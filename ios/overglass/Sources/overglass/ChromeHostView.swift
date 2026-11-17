import UIKit

/// Holds the real system bars. Touches outside them fall through to Flutter.
final class ChromeHostView: UIView, UITabBarDelegate, UINavigationBarDelegate, UISearchBarDelegate {
  /// Parent for the system tab controller.
  weak var owner: UIViewController?
  /// The FlutterView beside this host, whose touches scroll the body.
  weak var flutterView: UIView?
  var onEvent: ((String, [String: Any]) -> Void)?
  var imageLoader: ((String) -> UIImage?)?

  /// The session whose description is on screen and receives the events.
  var session: Int? {
    didSet {
      guard session != oldValue else { return }
      bottomSearchBar?.text = ""
      bottomSearchBar?.resignFirstResponder()
      lastMetrics = nil
      frozenTabBottom = 0
      setNeedsLayout()
    }
  }

  private(set) var navigationBar: UINavigationBar?
  private(set) var tabBar: UITabBar?
  private var navigationItems: [Int: UINavigationItem] = [:]
  private var navigationSignatures: [Int: String] = [:]
  private lazy var backPlaceholder = UINavigationItem(title: "")
  private var presented = true
  private var toolbar: UIToolbar?
  private var toolbarSignature: String?
  private var systemTabs: SystemTabHosting?
  private var navigationLeading: NSLayoutConstraint?
  /// While the tab bar can minimize, the body keeps the room of the full bar
  /// so that the list does not jump under the finger.
  private var frozenTabBottom: CGFloat = 0
  private var hasTabAccessory = false
  private var bottomSearch: UIView?
  private var bottomSearchBar: UISearchBar?
  private var bottomSearchAboveTabs: NSLayoutConstraint?
  private var tabSignature: String?
  private var lastMetrics: [String: AnyHashable]?
  private var tapSequences: [Int: Int] = [:]

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard var hit = super.hitTest(point, with: event), hit !== self else { return nil }
    // iPad's top tabs share the row of the navigation bar, which lies above them
    // and would take every touch that does not land on one of its own buttons.
    if usesTopTabs, let navigationBar, let tabs = systemTabs, hit.isDescendant(of: navigationBar), !Self.isControl(hit, in: navigationBar),
      let tabHit = tabs.view.hitTest(convert(point, to: tabs.view), with: event)
    {
      hit = tabHit
    }
    // The tab controller's containers and pages are empty: Flutter is below.
    if let page = systemTabs?.selectedPageView, page.isDescendant(of: hit) || hit.isDescendant(of: page) {
      return nil
    }
    return hit
  }

  private static func isControl(_ view: UIView, in container: UIView) -> Bool {
    var current: UIView? = view
    while let candidate = current, candidate !== container {
      if candidate is UIControl { return true }
      current = candidate.superview
    }
    return false
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    reportMetrics()
  }

  func forget(session: Int) {
    tapSequences[session] = nil
    navigationItems[session] = nil
    navigationSignatures[session] = nil
  }

  /// Fades the whole host. Native bars never move with a Flutter page.
  func setPresented(_ value: Bool, duration: TimeInterval) {
    isUserInteractionEnabled = value
    accessibilityElementsHidden = !value
    guard value != presented else { return }
    presented = value
    if value { isHidden = false }
    let finish: () -> Void = { [weak self] in
      guard let self, !self.presented else { return }
      self.isHidden = true
    }
    guard duration > 0, window != nil else {
      alpha = value ? 1 : 0
      finish()
      return
    }
    UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState]) {
      self.alpha = value ? 1 : 0
    } completion: { _ in
      finish()
    }
  }

  func apply(_ spec: [String: Any], previousSession: Int? = nil, animated: Bool = false) {
    setPresented((spec["visible"] as? Bool) != false, duration: Double(spec["fadeMs"] as? Int ?? 0) / 1000)
    let interactive = (spec["interactive"] as? Bool) != false
    isUserInteractionEnabled = interactive
    accessibilityElementsHidden = !interactive
    overrideUserInterfaceStyle = (spec["style"] as? String) == "dark" ? .dark : .light
    tintColor = (spec["tint"] as? Int).map(Self.color(argb:))
    applyTopBar(spec["topBar"] as? [String: Any], previousSession: previousSession, animated: animated)
    applyTabs(spec["tabBar"] as? [String: Any], ack: spec["ackTap"] as? Int ?? 0, animated: animated)
    applyToolbar(spec["toolbar"] as? [String: Any], animated: animated)
    applyBottomSearch((spec["topBar"] as? [String: Any])?["search"] as? [String: Any], animated: animated)
    applyScrim(spec["scrim"] as? [String: Any])
    setNeedsLayout()
  }

  // MARK: Scrim

  /// Fading the bars toward the content that Flutter's barrier already dims
  /// gives the barrier's look without a shape to match, and without dimming
  /// that content a second time.
  private func applyScrim(_ scrim: [String: Any]?) {
    let barrierAlpha = (scrim?["color"] as? Int).map { CGFloat(($0 >> 24) & 0xFF) / 255 } ?? 0
    let duration = Double(scrim?["durationMs"] as? Int ?? 150) / 1000
    let bars = [navigationBar as UIView?, tabBar, toolbar, systemTabs?.tabBarView, bottomSearch].compactMap { $0 }
    let alpha = 1 - barrierAlpha
    guard bars.contains(where: { $0.alpha != alpha }) else { return }
    UIView.animate(withDuration: duration) { bars.forEach { $0.alpha = alpha } }
  }

  // MARK: Top bar

  private func applyTopBar(_ spec: [String: Any]?, previousSession: Int?, animated: Bool) {
    guard let spec else {
      retire(navigationBar, animated: animated)
      navigationBar = nil
      // An item cannot belong to the bar being retired and to a new one.
      navigationItems.removeAll()
      navigationSignatures.removeAll()
      return
    }
    let isNew = navigationBar == nil
    let bar = navigationBar ?? makeNavigationBar()
    if isNew && animated { bar.alpha = 0 }
    bar.prefersLargeTitles = (spec["largeTitle"] as? Bool) == true

    let id = session ?? -1
    let item = navigationItems[id] ?? UINavigationItem()
    navigationItems[id] = item
    let tabsOnTop = usesTopTabs
    let signature = Self.signature(spec) + "\(tabsOnTop)"
    if signature != navigationSignatures[id] {
      navigationSignatures[id] = signature
      configure(item, with: spec, largeTitle: bar.prefersLargeTitles, hideTitle: tabsOnTop)
    }
    if let control = item.titleView as? UISegmentedControl,
      let selected = (spec["segments"] as? [String: Any])?["selected"] as? Int
    {
      control.selectedSegmentIndex = selected
    }

    // A real item stack lets UIKit animate the change the way a push or a pop
    // looks in a native app, including the back button.
    var stack = [item]
    if (spec["back"] as? Bool) == true {
      let below = previousSession.flatMap { navigationItems[$0] } ?? backPlaceholder
      if #available(iOS 14.0, *) { below.backButtonDisplayMode = .minimal }
      stack.insert(below, at: 0)
    }
    if !(bar.items ?? []).elementsEqual(stack, by: ===) {
      bar.setItems(stack, animated: animated && !isNew)
    }
  }

  /// iPad shows system tabs centered in the top row, where a title would be.
  private var usesTopTabs: Bool { systemTabs != nil && traitCollection.horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad }

  private func configure(_ item: UINavigationItem, with spec: [String: Any], largeTitle: Bool, hideTitle: Bool) {
    item.title = hideTitle ? "" : spec["title"] as? String ?? ""
    item.leftBarButtonItems = barItems(spec["leading"])
    item.rightBarButtonItems = barItems(spec["trailing"])
    item.leftItemsSupplementBackButton = true
    item.largeTitleDisplayMode = largeTitle ? .always : .never
    if let search = spec["search"] as? [String: Any], (search["placement"] as? String) != "bottom" {
      let title = item.titleView as? SearchTitleView ?? SearchTitleView()
      title.field.delegate = self
      title.field.placeholder = search["placeholder"] as? String
      item.titleView = title
    } else if let segments = spec["segments"] as? [String: Any], let labels = segments["labels"] as? [String] {
      let control = UISegmentedControl(items: labels)
      control.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
      item.titleView = control
    } else {
      item.titleView = nil
    }
  }

  private func retire(_ bar: UIView?, animated: Bool) {
    guard let bar else { return }
    guard animated else {
      bar.removeFromSuperview()
      return
    }
    UIView.animate(withDuration: 0.2) {
      bar.alpha = 0
    } completion: { _ in
      bar.removeFromSuperview()
    }
  }

  // MARK: Bottom search

  private func applyBottomSearch(_ search: [String: Any]?, animated: Bool) {
    guard let search, (search["placement"] as? String) == "bottom" else {
      retire(bottomSearch, animated: animated)
      bottomSearch = nil
      bottomSearchBar = nil
      bottomSearchAboveTabs = nil
      return
    }
    if bottomSearch == nil {
      makeBottomSearch(fadingIn: animated)
      if (search["autofocus"] as? Bool) == true {
        DispatchQueue.main.async { [weak self] in self?.bottomSearchBar?.becomeFirstResponder() }
      }
    }
    bottomSearchBar?.placeholder = search["placeholder"] as? String

    bottomSearchAboveTabs?.isActive = false
    if let below = usesTopTabs ? toolbar : (toolbar ?? tabBar ?? systemTabs?.tabBarView), let bottomSearch {
      // UIKit does not restore an accessory removed and set again, so it stays
      // and the field clears it. Its frame has no public anchor to pin to.
      let clearance: CGFloat = hasTabAccessory && !usesTopTabs ? 62 : 6
      let constraint = bottomSearch.bottomAnchor.constraint(lessThanOrEqualTo: below.topAnchor, constant: -clearance)
      constraint.isActive = true
      bottomSearchAboveTabs = constraint
    }
  }

  private func makeBottomSearch(fadingIn: Bool) {
    let field = UISearchBar()
    field.delegate = self
    let surface = ChromeHostView.makeSearchSurface(for: field)
    addSubview(surface.view)
    if fadingIn {
      surface.view.alpha = 0
      UIView.animate(withDuration: 0.2) { surface.view.alpha = 1 }
    }

    var constraints = [
      surface.view.heightAnchor.constraint(equalToConstant: 52),
      surface.view.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
      surface.view.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
    ]
    // Rests as low as the keyboard and the tab bar allow. The pull is weak so
    // that it can never compress the tab bar.
    let resting = surface.view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8)
    resting.priority = .defaultLow
    constraints.append(resting)
    if #available(iOS 15.0, *) {
      constraints.append(surface.view.bottomAnchor.constraint(lessThanOrEqualTo: keyboardLayoutGuide.topAnchor, constant: -8))
    }
    NSLayoutConstraint.activate(constraints)
    bottomSearch = surface.view
    bottomSearchBar = field
  }

  /// A single glass capsule around a search field whose own chrome is cleared.
  static func makeSearchSurface(for field: UISearchBar) -> (view: UIView, content: UIView) {
    field.searchBarStyle = .minimal
    field.searchTextField.borderStyle = .none
    field.searchTextField.backgroundColor = .clear
    field.translatesAutoresizingMaskIntoConstraints = false

    let surface = glassSurface()
    surface.view.translatesAutoresizingMaskIntoConstraints = false
    surface.content.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor, constant: 4),
      field.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor, constant: -4),
      field.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor),
    ])
    return surface
  }

  static func glassSurface() -> (view: UIView, content: UIView) {
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.cornerConfiguration = .capsule()
        return (glass, glass.contentView)
      }
    #endif
    let plain = UIView()
    return (plain, plain)
  }

  private func makeNavigationBar() -> UINavigationBar {
    let bar = UINavigationBar()
    bar.delegate = self
    bar.translatesAutoresizingMaskIntoConstraints = false
    addSubview(bar)
    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      // A standalone bar gets no margins from a navigation controller.
      bar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
    ])
    let leading = bar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16)
    leading.isActive = true
    navigationLeading = leading
    navigationBar = bar
    return bar
  }

  /// Flutter owns navigation, so the bar reports the tap and never pops itself.
  func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
    onEvent?("backPressed", [:])
    return false
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    onEvent?("searchChanged", ["text": searchText])
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    if searchBar === bottomSearchBar { searchBar.setShowsCancelButton(true, animated: true) }
  }

  func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
    if searchBar === bottomSearchBar { searchBar.setShowsCancelButton(false, animated: true) }
  }

  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
    searchBar.text = ""
    onEvent?("searchChanged", ["text": ""])
    searchBar.resignFirstResponder()
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    onEvent?("searchSubmitted", ["text": searchBar.text ?? ""])
    searchBar.resignFirstResponder()
  }

  @objc private func segmentChanged(_ control: UISegmentedControl) {
    onEvent?("segmentSelected", ["index": control.selectedSegmentIndex])
  }

  private func picture(_ entry: [String: Any]) -> UIImage? {
    if let key = entry["image"] as? String, let image = imageLoader?(key) { return image }
    return (entry["symbol"] as? String).flatMap { UIImage(systemName: $0) }
  }

  private func barItems(_ value: Any?) -> [UIBarButtonItem] {
    // The host only runs where system glass exists; this satisfies the iOS 13 floor.
    guard #available(iOS 14.0, *), let actions = value as? [[String: Any]] else { return [] }
    return actions.compactMap { action in
      if (action["space"] as? Bool) == true { return .flexibleSpace() }
      guard let id = action["id"] as? String else { return nil }
      let image = picture(action)
      let label = action["label"] as? String
      let title = image == nil ? label : nil
      let item: UIBarButtonItem
      if let menu = action["menu"] as? [String: Any] {
        item = UIBarButtonItem(title: title, image: image, primaryAction: nil, menu: makeMenu(menu, action: id))
      } else {
        let handler = UIAction { [weak self] _ in self?.onEvent?("actionPressed", ["id": id]) }
        item = UIBarButtonItem(title: title, image: image, primaryAction: handler, menu: nil)
      }
      item.accessibilityLabel = label
      return item
    }
  }

  @available(iOS 14.0, *)
  private func makeMenu(_ menu: [String: Any], action: String) -> UIMenu {
    let entries = menu["items"] as? [[String: Any]] ?? []
    let children = entries.enumerated().map { index, entry -> UIAction in
      let selected = UIAction(
        title: entry["label"] as? String ?? "",
        image: (entry["symbol"] as? String).flatMap { UIImage(systemName: $0) },
        attributes: (entry["destructive"] as? Bool) == true ? .destructive : []
      ) { [weak self] _ in
        self?.onEvent?("menuSelected", ["action": action, "item": index])
      }
      return selected
    }
    return UIMenu(title: menu["title"] as? String ?? "", children: children)
  }

  // MARK: Tab bar

  // MARK: Toolbar

  private func applyToolbar(_ spec: [String: Any]?, animated: Bool) {
    guard let spec else {
      retire(toolbar, animated: animated)
      toolbar = nil
      toolbarSignature = nil
      return
    }
    let isNew = toolbar == nil
    let bar = toolbar ?? makeToolbar()
    if isNew && animated { bar.alpha = 0 }
    let signature = Self.signature(spec)
    guard signature != toolbarSignature else { return }
    toolbarSignature = signature
    bar.setItems(barItems(spec["items"]), animated: animated && !isNew)
  }

  private func makeToolbar() -> UIToolbar {
    let bar = UIToolbar()
    bar.translatesAutoresizingMaskIntoConstraints = false
    addSubview(bar)
    NSLayoutConstraint.activate([
      bar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
      bar.leadingAnchor.constraint(equalTo: leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    toolbar = bar
    return bar
  }

  // MARK: Tabs

  private func applyTabs(_ spec: [String: Any]?, ack: Int, animated: Bool) {
    let items = spec?["items"] as? [[String: Any]] ?? []
    hasTabAccessory = spec?["accessory"] is [String: Any]
    let wantsSystem =
      spec != nil && owner != nil
      && (spec?["accessory"] is [String: Any] || (spec?["minimize"] as? Bool) == true
        || (spec?["sidebar"] as? Bool) == true
        || items.contains { ($0["isSearch"] as? Bool) == true } || UIDevice.current.userInterfaceIdiom == .pad)
    guard wantsSystem, let host = systemTabs ?? installSystemTabs() else {
      removeSystemTabs()
      applyTabBar(spec, ack: ack, animated: animated)
      return
    }
    applyTabBar(nil, ack: ack, animated: false)
    let selected = ack >= tapSequences[session ?? -1, default: 0] ? spec?["selected"] as? Int : nil
    host.apply(
      items: items,
      selected: selected,
      accessory: spec?["accessory"] as? [String: Any],
      scroll: SystemTabScroll(
        minimize: (spec?["minimize"] as? Bool) == true,
        scrollable: (spec?["scrollable"] as? Bool) == true,
        atTop: (spec?["atTop"] as? Bool) ?? true,
        touchSurface: flutterView
      ),
      sidebar: (spec?["sidebar"] as? Bool) == true,
      picture: { [weak self] in self?.picture($0) },
      animated: animated
    )
  }

  private func installSystemTabs() -> SystemTabHosting? {
    guard let owner, let tabs = makeSystemTabs() else { return nil }
    tabs.onSelect = { [weak self] index in self?.tabTapped(index) }
    tabs.onAccessory = { [weak self] in self?.onEvent?("accessoryPressed", [:]) }
    tabs.onLayout = { [weak self] in
      DispatchQueue.main.async { self?.reportMetrics() }
    }
    owner.addChild(tabs)
    tabs.view.translatesAutoresizingMaskIntoConstraints = false
    insertSubview(tabs.view, at: 0)
    NSLayoutConstraint.activate([
      tabs.view.topAnchor.constraint(equalTo: topAnchor),
      tabs.view.bottomAnchor.constraint(equalTo: bottomAnchor),
      tabs.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      tabs.view.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    tabs.didMove(toParent: owner)
    systemTabs = tabs
    return tabs
  }

  private func removeSystemTabs() {
    guard let tabs = systemTabs else { return }
    tabs.detach()
    tabs.willMove(toParent: nil)
    tabs.view.removeFromSuperview()
    tabs.removeFromParent()
    systemTabs = nil
  }

  private func tabTapped(_ index: Int) {
    guard let session else { return }
    let sequence = tapSequences[session, default: 0] + 1
    tapSequences[session] = sequence
    onEvent?("tabSelected", ["index": index, "tapSeq": sequence])
  }

  private func applyTabBar(_ spec: [String: Any]?, ack: Int, animated: Bool) {
    guard let spec, let items = spec["items"] as? [[String: Any]] else {
      retire(tabBar, animated: animated)
      tabBar = nil
      tabSignature = nil
      return
    }
    let isNew = tabBar == nil
    let bar = tabBar ?? makeTabBar()
    if isNew && animated { bar.alpha = 0 }
    let signature = Self.signature(items)
    if signature != tabSignature {
      tabSignature = signature
      let tabs = items.enumerated().map { index, entry -> UITabBarItem in
        let item = UITabBarItem(title: entry["label"] as? String, image: picture(entry), tag: index)
        item.badgeValue = entry["badge"] as? String
        return item
      }
      bar.setItems(tabs, animated: animated && !isNew)
    }
    // A description older than the latest tap must not undo that tap.
    guard ack >= tapSequences[session ?? -1, default: 0] else { return }
    if let selected = spec["selected"] as? Int, let tabItems = bar.items, tabItems.indices.contains(selected),
      bar.selectedItem !== tabItems[selected]
    {
      bar.selectedItem = tabItems[selected]
    }
  }

  private func makeTabBar() -> UITabBar {
    let bar = UITabBar()
    bar.delegate = self
    bar.translatesAutoresizingMaskIntoConstraints = false
    addSubview(bar)
    NSLayoutConstraint.activate([
      bar.bottomAnchor.constraint(equalTo: bottomAnchor),
      bar.leadingAnchor.constraint(equalTo: leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    tabBar = bar
    return bar
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    tabTapped(item.tag)
  }

  // MARK: Helpers

  private func reportMetrics() {
    let tabView = tabBar ?? systemTabs?.tabBarView
    tabView?.layoutIfNeeded()
    let tabsAtTop = tabView.map { $0.frame.midY < bounds.midY } ?? false
    var tabBottom = tabsAtTop ? 0 : tabView.map { bounds.height - $0.frame.minY } ?? 0
    if systemTabs?.minimizes == true {
      frozenTabBottom = max(frozenTabBottom, tabBottom)
      tabBottom = frozenTabBottom
    } else {
      frozenTabBottom = 0
    }
    let leading = systemTabs?.contentInsetLeading ?? 0
    if let navigationLeading, navigationLeading.constant != 16 + leading {
      navigationLeading.constant = 16 + leading
    }
    var metrics: [String: AnyHashable] = [
      "top": max(navigationBar?.frame.maxY ?? 0, tabsAtTop ? (tabView?.frame.maxY ?? 0) : 0),
      "bottom": max(
        tabBottom,
        toolbar.map { bounds.height - $0.frame.minY } ?? 0,
        bottomSearch.map { bounds.height - $0.frame.minY } ?? 0
      ),
      "left": leading,
    ]
    if !tabsAtTop, let capsule = tabView.flatMap(capsuleFrame) {
      metrics["tabCapsule"] = [
        "x": capsule.minX, "y": capsule.minY, "width": capsule.width, "height": capsule.height,
      ]
    }
    guard metrics != lastMetrics, session != nil else { return }
    lastMetrics = metrics
    onEvent?("metrics", metrics)
  }

  /// The iOS 26 tab bar floats inside its frame. Its capsule has no public
  /// API, so the largest control-sized descendant stands in for it. The result
  /// only shapes the Flutter twin.
  private func capsuleFrame(of bar: UITabBar) -> CGRect? {
    guard #available(iOS 26.0, *) else { return nil }
    var best: UIView?
    var queue = bar.subviews
    while !queue.isEmpty {
      let view = queue.removeFirst()
      queue += view.subviews
      let size = view.bounds.size
      guard !view.isHidden, size.width < bar.bounds.width - 1, size.width >= 120, (44...90).contains(size.height)
      else { continue }
      if size.width * size.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) { best = view }
    }
    return best.map { $0.convert($0.bounds, to: self) }
  }

  private static func signature(_ value: Any) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? UUID().uuidString
  }

  private static func color(argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

/// Glass search capsule used as a navigation item's title view.
private final class SearchTitleView: UIView {
  let field = UISearchBar()

  override init(frame: CGRect) {
    super.init(frame: frame)
    let surface = ChromeHostView.makeSearchSurface(for: field)
    addSubview(surface.view)
    NSLayoutConstraint.activate([
      surface.view.topAnchor.constraint(equalTo: topAnchor),
      surface.view.bottomAnchor.constraint(equalTo: bottomAnchor),
      surface.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      surface.view.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("Not used") }

  /// Takes all the width the bar offers, at its standard control height.
  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)
  }
}

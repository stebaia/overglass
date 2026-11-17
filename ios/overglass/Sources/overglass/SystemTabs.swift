import UIKit

/// A real tab bar controller, for features UIKit offers nowhere else: the bottom
/// accessory, the search tab, minimize on scroll, iPad's top tabs and sidebar.
protocol SystemTabHosting: UIViewController {
  var tabBarView: UITabBar { get }
  var selectedPageView: UIView? { get }
  var onSelect: ((Int) -> Void)? { get set }
  var onAccessory: (() -> Void)? { get set }
  /// Called after the controller lays out, for example when the sidebar moves.
  var onLayout: (() -> Void)? { get set }
  /// Width the sidebar takes from the leading edge of the content.
  var contentInsetLeading: CGFloat { get }
  var minimizes: Bool { get }
  func apply(
    items: [[String: Any]],
    selected: Int?,
    accessory: [String: Any]?,
    scroll: SystemTabScroll,
    sidebar: Bool,
    picture: ([String: Any]) -> UIImage?,
    animated: Bool
  )
  /// Gives the scroll proxy's gesture back before the controller goes away.
  func detach()
}

/// What minimize on scroll needs to know about the Flutter body.
struct SystemTabScroll {
  var minimize = false
  var scrollable = false
  var atTop = true
  /// The view whose touches scroll Flutter: the proxy watches the same touches.
  weak var touchSurface: UIView?
}

func makeSystemTabs() -> SystemTabHosting? {
  #if compiler(>=6.2)
    if #available(iOS 26.0, *) { return ChromeTabController() }
  #endif
  return nil
}

#if compiler(>=6.2)
  /// Empty page: Flutter is visible through it.
  @available(iOS 26.0, *)
  private final class ChromeClearPage: UIViewController {
    var onLayout: (() -> Void)?

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      onLayout?()
    }
  }

  /// UIKit minimizes the tab bar only for a scroll view the user is dragging.
  /// This one is never seen: its pan recognizer moves onto the FlutterView, so
  /// the finger that scrolls Flutter scrolls it too, and UIKit reacts.
  @available(iOS 26.0, *)
  private final class ScrollProxy: UIScrollView {
    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      showsVerticalScrollIndicator = false
      showsHorizontalScrollIndicator = false
      alwaysBounceVertical = true
      contentInsetAdjustmentBehavior = .never
      isAccessibilityElement = false
      accessibilityElementsHidden = true
      // Flutter must keep receiving every touch the proxy also follows.
      panGestureRecognizer.cancelsTouchesInView = false
      panGestureRecognizer.delaysTouchesBegan = false
      panGestureRecognizer.delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func layoutSubviews() {
      super.layoutSubviews()
      let size = CGSize(width: bounds.width, height: 10_000_000)
      if contentSize != size { contentSize = size }
    }
  }

  @available(iOS 26.0, *)
  final class ChromeTabController: UITabBarController, UITabBarControllerDelegate, SystemTabHosting {
    var onSelect: ((Int) -> Void)?
    var onAccessory: (() -> Void)?
    var onLayout: (() -> Void)?
    private let proxy = ScrollProxy()
    private var scroll = SystemTabScroll()
    private var tabsSignature: String?
    private var accessorySignature: String?
    private var applying = false

    var tabBarView: UITabBar { tabBar }
    var selectedPageView: UIView? { selectedViewController?.viewIfLoaded }
    var minimizes: Bool { scroll.minimize }

    var contentInsetLeading: CGFloat {
      guard mode == .tabSidebar, !sidebar.isHidden, let page = selectedPageView else { return 0 }
      let frame = page.convert(page.bounds, to: view)
      return max(0, frame.minX) + max(0, page.safeAreaInsets.left - view.safeAreaInsets.left)
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      delegate = self
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      onLayout?()
    }

    private func makePage() -> UIViewController {
      let page = ChromeClearPage()
      page.onLayout = { [weak self] in self?.onLayout?() }
      return page
    }

    func apply(
      items: [[String: Any]],
      selected: Int?,
      accessory: [String: Any]?,
      scroll: SystemTabScroll,
      sidebar: Bool,
      picture: ([String: Any]) -> UIImage?,
      animated: Bool
    ) {
      applying = true
      defer { applying = false }
      loadViewIfNeeded()
      let wanted: UITabBarController.Mode = sidebar ? .tabSidebar : .automatic
      if mode != wanted { mode = wanted }

      let signature = String(describing: items.map { $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } })
      if signature != tabsSignature {
        tabsSignature = signature
        let built: [UITab] = items.enumerated().map { index, entry in
          let tab: UITab
          if (entry["isSearch"] as? Bool) == true {
            tab = UISearchTab { [weak self] _ in self?.makePage() ?? ChromeClearPage() }
          } else {
            tab = UITab(
              title: entry["label"] as? String ?? "",
              image: picture(entry),
              identifier: "\(index)"
            ) { [weak self] _ in self?.makePage() ?? ChromeClearPage() }
          }
          tab.badgeValue = entry["badge"] as? String
          tab.userInfo = index as NSNumber
          return tab
        }
        setTabs(built, animated: animated)
      }
      if let selected, tabs.indices.contains(selected), selectedTab !== tabs[selected] {
        selectedTab = tabs[selected]
      }
      applyAccessory(accessory, animated: animated)
      applyScroll(scroll)
    }

    // MARK: Minimize on scroll

    private func applyScroll(_ next: SystemTabScroll) {
      let wasMinimizing = scroll.minimize
      scroll = next
      tabBarMinimizeBehavior = next.minimize ? .onScrollDown : .never
      guard next.minimize, let surface = next.touchSurface else {
        detach()
        return
      }
      placeProxy()
      proxy.isScrollEnabled = next.scrollable
      if proxy.panGestureRecognizer.view !== surface {
        surface.addGestureRecognizer(proxy.panGestureRecognizer)
      }
      // Back at the top of Flutter's list, the bar opens even when the
      // finger never scrolled the proxy up, after a fling for example.
      let idle = !proxy.isDragging && !proxy.isDecelerating
      if next.atTop, idle, proxy.contentOffset.y > 0 || !wasMinimizing {
        proxy.setContentOffset(.zero, animated: false)
        tabBarMinimizeBehavior = .never
        tabBarMinimizeBehavior = .onScrollDown
      }
    }

    private func placeProxy() {
      guard let page = selectedViewController else { return }
      page.loadViewIfNeeded()
      if proxy.superview !== page.view {
        proxy.frame = page.view.bounds
        proxy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        page.view.addSubview(proxy)
      }
      page.setContentScrollView(proxy, for: .bottom)
    }

    func detach() {
      if proxy.panGestureRecognizer.view !== proxy {
        proxy.addGestureRecognizer(proxy.panGestureRecognizer)
      }
      proxy.removeFromSuperview()
    }

    private func applyAccessory(_ accessory: [String: Any]?, animated: Bool) {
      let signature = accessory.map { String(describing: $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }) }
      guard signature != accessorySignature else { return }
      accessorySignature = signature
      guard let accessory else {
        setBottomAccessory(nil, animated: animated)
        return
      }
      let content = AccessoryContentView(spec: accessory) { [weak self] in self?.onAccessory?() }
      setBottomAccessory(UITabAccessory(contentView: content), animated: animated)
    }

    func tabBarController(_ controller: UITabBarController, didSelectTab selected: UITab, previousTab: UITab?) {
      if scroll.minimize {
        // Each tab's Flutter body starts at its own position.
        proxy.setContentOffset(.zero, animated: false)
        placeProxy()
      }
      guard !applying, let index = (selected.userInfo as? NSNumber)?.intValue else { return }
      onSelect?(index)
    }
  }

  @available(iOS 26.0, *)
  private final class AccessoryContentView: UIControl {
    private let tapped: () -> Void

    init(spec: [String: Any], tapped: @escaping () -> Void) {
      self.tapped = tapped
      super.init(frame: .zero)
      let title = UILabel()
      title.text = spec["title"] as? String
      title.font = .preferredFont(forTextStyle: .subheadline)
      let subtitle = UILabel()
      subtitle.text = spec["subtitle"] as? String
      subtitle.font = .preferredFont(forTextStyle: .caption1)
      subtitle.textColor = .secondaryLabel
      subtitle.isHidden = subtitle.text == nil
      let labels = UIStackView(arrangedSubviews: [title, subtitle])
      labels.axis = .vertical
      let image = UIImageView(image: (spec["symbol"] as? String).flatMap { UIImage(systemName: $0) })
      image.isHidden = image.image == nil
      image.setContentHuggingPriority(.required, for: .horizontal)
      let row = UIStackView(arrangedSubviews: [image, labels])
      row.spacing = 10
      row.alignment = .center
      row.isUserInteractionEnabled = false
      row.translatesAutoresizingMaskIntoConstraints = false
      addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        row.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
      isAccessibilityElement = true
      accessibilityTraits = .button
      accessibilityLabel = [title.text, subtitle.text].compactMap { $0 }.joined(separator: ", ")
      addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    @objc private func handleTap() { tapped() }
  }
#endif

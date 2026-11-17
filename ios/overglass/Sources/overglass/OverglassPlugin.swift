import Flutter
import UIKit

/// Declarative bridge: each Dart scaffold owns a session holding one full
/// description of its chrome, and the newest visible session is what shows.
public final class OverglassPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var host: ChromeHostView?
  private var hostController: UIViewController?
  private var sessions: [(id: Int, spec: [String: Any])] = []
  private var retryTimer: Timer?
  private var sentinel: WindowSentinel?

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.overglass/chrome", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(OverglassPlugin(channel: channel, registrar: registrar), channel: channel)
    registrar.register(ControlFactory(messenger: registrar.messenger()), withId: "dev.overglass/control")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "capabilities":
      result(["nativeGlass": Self.hasSystemGlass])
    case "reset":
      sessions.removeAll()
      teardown()
      result(nil)
    case "apply":
      guard let id = arguments["session"] as? Int else {
        result(FlutterError(code: "bad_spec", message: "Expected a session", details: nil))
        return
      }
      result(["attached": apply(id: id, spec: arguments)])
    case "release":
      if let id = arguments["session"] as? Int { release(id: id) }
      result(nil)
    case "alert":
      presentAlert(arguments, result: result)
    case "contextMenu":
      presentContextMenu(arguments, result: result)
    case "popover":
      presentPopover(arguments, result: result)
    case "sheet":
      presentSheet(arguments, result: result)
    case "choiceSheet", "dateSheet":
      presentDescribedSheet(call.method, arguments, result: result)
    case "toast":
      if let window = findFlutterView()?.window {
        ToastPresenter.show(arguments, in: window)
        result(true)
      } else {
        result(false)
      }
    case "sheetClose":
      result(SheetSession.closeCurrent(with: arguments["result"] as? String))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var hasSystemGlass: Bool {
    guard #available(iOS 26.0, *) else { return false }
    let optedOut = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool
    return optedOut != true
  }

  // MARK: Sessions

  private func apply(id: Int, spec: [String: Any]) -> Bool {
    if let index = sessions.firstIndex(where: { $0.id == id }) {
      sessions[index].spec = spec
    } else {
      sessions.append((id, spec))
    }
    return render()
  }

  private func release(id: Int) {
    sessions.removeAll { $0.id == id }
    host?.forget(session: id)
    render()
  }

  @discardableResult
  private func render() -> Bool {
    guard !sessions.isEmpty else {
      teardown()
      return true
    }
    guard let host = resolveHost() else {
      scheduleRetry()
      return false
    }
    guard let active = sessions.last(where: { ($0.spec["visible"] as? Bool) != false }) else {
      let fade = sessions.last?.spec["fadeMs"] as? Int ?? 0
      host.setPresented(false, duration: Double(fade) / 1000)
      return true
    }
    let index = sessions.firstIndex { $0.id == active.id } ?? 0
    let animated = host.session != nil && host.session != active.id
    host.session = active.id
    host.apply(active.spec, previousSession: index > 0 ? sessions[index - 1].id : nil, animated: animated)
    return true
  }

  private func teardown() {
    stopRetry()
    sentinel?.removeFromSuperview()
    sentinel = nil
    removeHost()
  }

  private func removeHost() {
    hostController?.willMove(toParent: nil)
    host?.removeFromSuperview()
    hostController?.removeFromParent()
    hostController = nil
    host = nil
  }

  /// A view controller can enter an already visible window, which posts no
  /// notification, so attachment is polled until it succeeds.
  private func scheduleRetry() {
    guard retryTimer == nil else { return }
    retryTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self, self.render(), self.host != nil else { return }
      self.stopRetry()
      for session in self.sessions {
        self.channel.invokeMethod("attached", arguments: ["session": session.id])
      }
    }
  }

  /// A full-screen modal takes the FlutterView out of the window and puts it
  /// back on top of everything, with no callback a plugin can observe.
  private func watchWindow(of flutterView: UIView) {
    guard sentinel?.superview !== flutterView else { return }
    sentinel?.removeFromSuperview()
    let watcher = WindowSentinel()
    watcher.onWindowChange = { [weak self] in
      DispatchQueue.main.async { self?.flutterViewMoved() }
    }
    flutterView.insertSubview(watcher, at: 0)
    sentinel = watcher
  }

  private func flutterViewMoved() {
    guard !sessions.isEmpty else { return }
    let wasDetached = retryTimer != nil
    guard render(), wasDetached, host != nil else { return }
    stopRetry()
    for session in sessions {
      channel.invokeMethod("attached", arguments: ["session": session.id])
    }
  }

  private func stopRetry() {
    retryTimer?.invalidate()
    retryTimer = nil
  }

  // MARK: Hosting

  /// The host is a sibling above the FlutterView, not a child. Flutter assigns
  /// its own `accessibilityElements`, which would hide any native subview from
  /// VoiceOver.
  private func resolveHost() -> ChromeHostView? {
    guard let flutterView = findFlutterView() else { return nil }
    watchWindow(of: flutterView)
    guard let parent = flutterView.superview else { return nil }
    // UIKit requires a view's controller to be a child of the controller that
    // owns its superview. A window owns none, so the host's controller is then
    // parentless; adding it to the Flutter controller would abort the app.
    let owner = sequence(first: parent as UIResponder, next: \.next).lazy.compactMap { $0 as? UIViewController }.first
    if let host, host.superview === parent, hostController?.parent === owner {
      let views = parent.subviews
      if let hostIndex = views.firstIndex(of: host), let flutterIndex = views.firstIndex(of: flutterView),
        hostIndex < flutterIndex
      {
        parent.insertSubview(host, aboveSubview: flutterView)
      }
      return host
    }
    removeHost()

    let created = ChromeHostView()
    created.onEvent = { [channel, weak created] method, arguments in
      guard let session = created?.session else { return }
      var payload = arguments
      payload["session"] = session
      channel.invokeMethod(method, arguments: payload)
    }
    created.imageLoader = { [weak registrar] key in
      guard let registrar else { return nil }
      let path = Bundle.main.path(forResource: registrar.lookupKey(forAsset: key), ofType: nil)
      return path.flatMap { UIImage(contentsOfFile: $0) }?.withRenderingMode(.alwaysTemplate)
    }
    created.translatesAutoresizingMaskIntoConstraints = false

    // UIKit looks for a controller among a bar button's ancestors to present
    // its menu, and a sibling of the FlutterView has none of its own.
    let controller = UIViewController()
    controller.view = created
    created.owner = controller
    created.flutterView = flutterView
    owner?.addChild(controller)
    parent.insertSubview(created, aboveSubview: flutterView)
    controller.didMove(toParent: owner)
    hostController = controller
    NSLayoutConstraint.activate([
      created.topAnchor.constraint(equalTo: flutterView.topAnchor),
      created.bottomAnchor.constraint(equalTo: flutterView.bottomAnchor),
      created.leadingAnchor.constraint(equalTo: flutterView.leadingAnchor),
      created.trailingAnchor.constraint(equalTo: flutterView.trailingAnchor),
    ])
    host = created
    return created
  }

  private func findFlutterView() -> UIView? {
    if let view = registrar?.viewController?.viewIfLoaded { return view }
    return Self.firstFlutterController()?.viewIfLoaded
  }

  private static func firstFlutterController() -> FlutterViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    for window in windows where !window.isHidden {
      if let root = window.rootViewController, let controller = findFlutterController(root) {
        return controller
      }
    }
    return nil
  }

  private static func findFlutterController(_ controller: UIViewController) -> FlutterViewController? {
    if let flutter = controller as? FlutterViewController { return flutter }
    for child in controller.children {
      if let found = findFlutterController(child) { return found }
    }
    return controller.presentedViewController.flatMap(findFlutterController)
  }

  // MARK: Presented surfaces

  private func presenterController() -> UIViewController? {
    guard var presenter = registrar?.viewController ?? Self.firstFlutterController() else { return nil }
    while let presented = presenter.presentedViewController { presenter = presented }
    return presenter
  }

  private func presentContextMenu(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *), let view = findFlutterView() else {
      result(FlutterError(code: "no_view", message: "Nothing to present from", details: nil))
      return
    }
    let point = CGPoint(x: arguments["x"] as? Double ?? 0, y: arguments["y"] as? Double ?? 0)
    EditMenuPresenter.present(
      entries: arguments["items"] as? [[String: Any]] ?? [], title: arguments["title"] as? String, in: view, at: point,
      result: result)
  }

  private func presentPopover(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let presenter = presenterController() else {
      result(FlutterError(code: "no_view", message: "Nothing to present from", details: nil))
      return
    }
    let popover = PopoverController(spec: arguments, result: result)
    popover.modalPresentationStyle = .popover
    popover.popoverPresentationController?.delegate = popover
    popover.popoverPresentationController?.sourceView = presenter.view
    if let anchor = arguments["anchor"] as? [String: Double] {
      popover.popoverPresentationController?.sourceRect = CGRect(
        x: anchor["x"] ?? 0, y: anchor["y"] ?? 0, width: anchor["width"] ?? 0, height: anchor["height"] ?? 0)
    }
    presenter.present(popover, animated: true)
  }

  private func presentSheet(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let presenter = presenterController() else {
      result(FlutterError(code: "no_view", message: "Nothing to present from", details: nil))
      return
    }
    SheetSession.present(arguments, from: presenter, result: result)
  }

  private func presentDescribedSheet(_ kind: String, _ arguments: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result(FlutterError(code: "unsupported", message: "Needs iOS 15", details: nil))
      return
    }
    guard let presenter = presenterController() else {
      result(FlutterError(code: "no_view", message: "Nothing to present from", details: nil))
      return
    }
    let sheet: DescribedSheetController =
      kind == "dateSheet"
      ? DateSheetController(spec: arguments, result: result) : ChoiceSheetController(spec: arguments, result: result)
    DescribedSheetController.present(sheet, from: presenter)
  }

  // MARK: Alerts

  private func presentAlert(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard var presenter = registrar?.viewController ?? Self.firstFlutterController() else {
      result(FlutterError(code: "no_view", message: "Nothing to present from", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }

    let isSheet = (arguments["style"] as? String) == "sheet"
    let alert = UIAlertController(
      title: arguments["title"] as? String,
      message: arguments["message"] as? String,
      preferredStyle: isSheet ? .actionSheet : .alert
    )
    var hasCancel = false
    for action in arguments["actions"] as? [[String: Any]] ?? [] {
      let id = action["id"] as? String
      let style: UIAlertAction.Style
      switch action["style"] as? String {
      case "cancel":
        style = .cancel
        hasCancel = true
      case "destructive":
        style = .destructive
      default:
        style = .default
      }
      alert.addAction(UIAlertAction(title: action["label"] as? String, style: style) { _ in result(id) })
    }
    // An iPad popover closes on an outside tap and only reports it to a cancel
    // action, which it does not display.
    if isSheet, !hasCancel, UIDevice.current.userInterfaceIdiom == .pad {
      alert.addAction(UIAlertAction(title: nil, style: .cancel) { _ in result(nil) })
    }
    if let popover = alert.popoverPresentationController {
      let view = presenter.view!
      popover.sourceView = view
      if let anchor = arguments["anchor"] as? [String: Double] {
        popover.sourceRect = CGRect(
          x: anchor["x"] ?? 0, y: anchor["y"] ?? 0, width: anchor["width"] ?? 0, height: anchor["height"] ?? 0)
      } else {
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
      }
    }
    presenter.present(alert, animated: true)
  }
}

/// Zero-sized child of the FlutterView that reports window changes.
private final class WindowSentinel: UIView {
  var onWindowChange: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onWindowChange?()
  }
}

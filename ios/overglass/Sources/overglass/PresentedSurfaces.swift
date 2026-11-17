import Flutter
import UIKit

/// Shows a system menu at a point chosen by Flutter.
@available(iOS 16.0, *)
final class EditMenuPresenter: NSObject, UIEditMenuInteractionDelegate {
  private static var active: EditMenuPresenter?

  private var menu = UIMenu(children: [])
  private var selected: Int?
  private let result: FlutterResult
  private weak var view: UIView?
  private var interaction: UIEditMenuInteraction?

  private init(result: @escaping FlutterResult) {
    self.result = result
  }

  static func present(
    entries: [[String: Any]], title: String?, in view: UIView, at point: CGPoint, result: @escaping FlutterResult
  ) {
    active?.finish()
    let presenter = EditMenuPresenter(result: result)
    let children = entries.enumerated().map { index, entry in
      UIAction(
        title: entry["label"] as? String ?? "",
        image: (entry["symbol"] as? String).flatMap { UIImage(systemName: $0) },
        attributes: (entry["destructive"] as? Bool) == true ? .destructive : []
      ) { [weak presenter] _ in presenter?.selected = index }
    }
    presenter.menu = UIMenu(title: title ?? "", children: children)
    presenter.view = view
    let interaction = UIEditMenuInteraction(delegate: presenter)
    presenter.interaction = interaction
    view.addInteraction(interaction)
    active = presenter
    interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
  }

  func editMenuInteraction(
    _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
    suggestedActions: [UIMenuElement]
  ) -> UIMenu? {
    menu
  }

  func editMenuInteraction(
    _ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
    animator: UIEditMenuInteractionAnimating
  ) {
    animator.addCompletion { [weak self] in self?.finish() }
  }

  private var finished = false

  private func finish() {
    guard !finished else { return }
    finished = true
    if let interaction { view?.removeInteraction(interaction) }
    result(selected)
    if EditMenuPresenter.active === self { EditMenuPresenter.active = nil }
  }
}

/// A native popover holding text and buttons described by Dart.
final class PopoverController: UIViewController, UIPopoverPresentationControllerDelegate {
  private let spec: [String: Any]
  private var result: FlutterResult?

  init(spec: [String: Any], result: @escaping FlutterResult) {
    self.spec = spec
    self.result = result
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    if let title = spec["title"] as? String {
      let label = UILabel()
      label.text = title
      label.font = .preferredFont(forTextStyle: .headline)
      label.numberOfLines = 0
      stack.addArrangedSubview(label)
    }
    if let message = spec["message"] as? String {
      let label = UILabel()
      label.text = message
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.numberOfLines = 0
      stack.addArrangedSubview(label)
    }
    for (index, action) in (spec["actions"] as? [[String: Any]] ?? []).enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(action["label"] as? String, for: .normal)
      button.tag = index
      button.contentHorizontalAlignment = .leading
      if (action["style"] as? String) == "destructive" { button.tintColor = .systemRed }
      button.addTarget(self, action: #selector(choose(_:)), for: .touchUpInside)
      stack.addArrangedSubview(button)
    }
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
    ])
    let width: CGFloat = 280
    let fitting = stack.systemLayoutSizeFitting(
      CGSize(width: width - 36, height: 0), withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel)
    preferredContentSize = CGSize(width: width, height: fitting.height + 32)
  }

  @objc private func choose(_ sender: UIButton) {
    let actions = spec["actions"] as? [[String: Any]] ?? []
    let id = actions[sender.tag]["id"]
    dismiss(animated: true) { [self] in finish(id) }
  }

  private func finish(_ value: Any?) {
    result?(value)
    result = nil
  }

  func adaptivePresentationStyle(
    for controller: UIPresentationController, traitCollection: UITraitCollection
  ) -> UIModalPresentationStyle {
    .none
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }
}

/// A system sheet whose content is Flutter. iOS runs one FlutterView per
/// engine here, so the sheet gets its own engine and isolate.
final class SheetSession: NSObject, UIAdaptivePresentationControllerDelegate {
  private static let group = FlutterEngineGroup(name: "overglass.sheets", project: nil)
  private static var current: SheetSession?

  private let engine: FlutterEngine
  private let controller: FlutterViewController
  private var result: FlutterResult?

  private init(engine: FlutterEngine, controller: FlutterViewController, result: @escaping FlutterResult) {
    self.engine = engine
    self.controller = controller
    self.result = result
  }

  static func present(_ arguments: [String: Any], from presenter: UIViewController, result: @escaping FlutterResult) {
    guard current == nil else {
      result(FlutterError(code: "busy", message: "A sheet is already open", details: nil))
      return
    }
    let options = FlutterEngineGroupOptions()
    options.entrypoint = arguments["entrypoint"] as? String
    options.entrypointArgs = arguments["arguments"] as? [String]
    let engine = group.makeEngine(with: options)
    (NSClassFromString("GeneratedPluginRegistrant") as AnyObject?)?
      .perform(NSSelectorFromString("registerWithRegistry:"), with: engine)

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.isViewOpaque = false
    controller.view.backgroundColor = .clear
    controller.modalPresentationStyle = .pageSheet
    if #available(iOS 15.0, *), let sheet = controller.sheetPresentationController {
      let names = arguments["detents"] as? [String] ?? ["medium", "large"]
      sheet.detents = names.map { $0 == "large" ? .large() : .medium() }
      sheet.prefersGrabberVisible = true
    }
    let session = SheetSession(engine: engine, controller: controller, result: result)
    controller.presentationController?.delegate = session
    current = session
    presenter.present(controller, animated: true)
  }

  /// Returns false when no native sheet is open, so Dart pops its own route.
  static func closeCurrent(with value: String?) -> Bool {
    guard let session = current else { return false }
    session.controller.dismiss(animated: true) { session.finish(value) }
    return true
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }

  private func finish(_ value: String?) {
    result?(value)
    result = nil
    engine.destroyContext()
    if SheetSession.current === self { SheetSession.current = nil }
  }
}

import Flutter
import SwiftUI
import UIKit

/// Creates the system controls that sit inside Flutter content. Unlike the
/// bars, these are platform views: they scroll and lay out with Flutter.
final class ControlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    NativeControl(id: viewId, params: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

/// One control. Dart sends its whole description with `update` and gets back
/// the size the control needs; the control reports changes with `changed`.
final class NativeControl: NSObject, FlutterPlatformView {
  private let container = UIView()
  private let channel: FlutterMethodChannel
  private let kind: String
  private var params: [String: Any]
  private var control: UIView?
  private var gauge: AnyObject?
  private var hosting: UIViewController?
  private var fitHosting: ((CGSize) -> CGSize)?

  init(id: Int64, params: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.overglass/control/\(id)", binaryMessenger: messenger)
    kind = params["kind"] as? String ?? ""
    self.params = params
    super.init()
    container.backgroundColor = .clear
    build()
    update()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == "update", let next = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.params = next
      self.update()
      result(self.measure())
    }
  }

  func view() -> UIView { container }

  private var tint: UIColor? { DescribedSheetController.color(params["tint"]) }
  private var enabled: Bool { params["enabled"] as? Bool ?? true }

  // MARK: Building

  private func build() {
    switch kind {
    case "button":
      let button = UIButton(type: .system)
      button.addTarget(self, action: #selector(pressed), for: .touchUpInside)
      place(button, expand: true)
    case "switch":
      let toggle = UISwitch()
      toggle.addTarget(self, action: #selector(switched(_:)), for: .valueChanged)
      // Dart makes this view larger than the switch, so that the glass thumb
      // has room to grow while it moves instead of being cut at the edges.
      toggle.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(toggle)
      NSLayoutConstraint.activate([
        toggle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      ])
      control = toggle
    case "slider":
      let slider = UISlider()
      slider.isContinuous = true
      slider.addTarget(self, action: #selector(slid(_:)), for: .valueChanged)
      slider.addTarget(self, action: #selector(slideEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
      place(slider, expand: true)
    case "date":
      let picker = UIDatePicker()
      if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .compact }
      picker.addTarget(self, action: #selector(picked(_:)), for: .valueChanged)
      place(picker, expand: false)
    case "gauge":
      buildGauge()
    default:
      break
    }
  }

  private func place(_ view: UIView, expand: Bool) {
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    var constraints = [
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ]
    constraints.append(
      expand
        ? view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        : view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor))
    NSLayoutConstraint.activate(constraints)
    control = view
  }

  private func buildGauge() {
    if #available(iOS 16.0, *) {
      let model = GaugeModel()
      let controller = UIHostingController(rootView: GaugeContent(model: model))
      controller.view.backgroundColor = .clear
      controller.view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(controller.view)
      NSLayoutConstraint.activate([
        controller.view.topAnchor.constraint(equalTo: container.topAnchor),
        controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ])
      gauge = model
      hosting = controller
      fitHosting = { [weak controller] size in controller?.sizeThatFits(in: size) ?? .zero }
      control = controller.view
    } else {
      place(UIProgressView(progressViewStyle: .default), expand: true)
    }
  }

  // MARK: Updating

  private func update() {
    switch control {
    case let button as UIButton: updateButton(button)
    case let toggle as UISwitch:
      if toggle.isOn != (params["value"] as? Bool ?? false) {
        toggle.setOn(params["value"] as? Bool ?? false, animated: true)
      }
      toggle.onTintColor = tint
      toggle.isEnabled = enabled
      toggle.accessibilityLabel = params["semanticLabel"] as? String
    case let slider as UISlider:
      slider.minimumValue = Float(number("min") ?? 0)
      slider.maximumValue = Float(number("max") ?? 1)
      // Never move the thumb away from the finger.
      if !slider.isTracking { slider.value = Float(number("value") ?? 0) }
      slider.minimumTrackTintColor = tint
      slider.isEnabled = enabled
      slider.accessibilityLabel = params["semanticLabel"] as? String
    case let picker as UIDatePicker:
      switch params["mode"] as? String {
      case "time": picker.datePickerMode = .time
      case "dateAndTime": picker.datePickerMode = .dateAndTime
      default: picker.datePickerMode = .date
      }
      if let locale = params["locale"] as? String { picker.locale = Locale(identifier: locale) }
      picker.minimumDate = date("minimum")
      picker.maximumDate = date("maximum")
      if let value = date("value"), value != picker.date { picker.date = value }
      picker.tintColor = tint
      picker.isEnabled = enabled
    case let progress as UIProgressView:
      progress.progress = Float(fraction)
      progress.progressTintColor = tint
    default:
      if #available(iOS 16.0, *), let model = gauge as? GaugeModel {
        model.value = number("value") ?? 0
        model.minimum = number("min") ?? 0
        model.maximum = max(number("max") ?? 1, model.minimum + .ulpOfOne)
        model.circular = (params["style"] as? String) != "linear"
        model.label = params["label"] as? String
        model.valueLabel = params["valueLabel"] as? String
        model.tint = tint.map(Color.init)
      }
    }
  }

  private func updateButton(_ button: UIButton) {
    let label = params["label"] as? String
    let image = (params["symbol"] as? String).flatMap { UIImage(systemName: $0) }
    let style = params["style"] as? String
    let destructive = (params["destructive"] as? Bool) == true
    if #available(iOS 15.0, *) {
      var configuration = Self.buttonConfiguration(style)
      configuration.title = label
      configuration.image = image
      configuration.imagePadding = 6
      switch params["size"] as? String {
      case "small": configuration.buttonSize = .small
      case "large": configuration.buttonSize = .large
      default: configuration.buttonSize = .medium
      }
      let color = destructive ? UIColor.systemRed : tint
      if style == "prominent" {
        configuration.baseBackgroundColor = color
      } else if let color {
        configuration.baseForegroundColor = color
      }
      button.configuration = configuration
    } else {
      button.setTitle(label, for: .normal)
      button.setImage(image, for: .normal)
      if destructive { button.tintColor = .systemRed } else if let tint { button.tintColor = tint }
    }
    button.isEnabled = enabled
    button.accessibilityLabel = params["semanticLabel"] as? String ?? label
  }

  @available(iOS 15.0, *)
  private static func buttonConfiguration(_ style: String?) -> UIButton.Configuration {
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        switch style {
        case "prominent": return .prominentGlass()
        case "plain": return .plain()
        default: return .glass()
        }
      }
    #endif
    var configuration: UIButton.Configuration
    switch style {
    case "prominent": configuration = .filled()
    case "plain": configuration = .plain()
    default: configuration = .gray()
    }
    configuration.cornerStyle = .capsule
    return configuration
  }

  /// The size Dart should give the platform view. A width of 0 means "as
  /// wide as the layout allows".
  private func measure() -> [String: Double] {
    guard let control else { return [:] }
    var size: CGSize
    if let fitHosting {
      let circular = (params["style"] as? String) != "linear"
      size = fitHosting(CGSize(width: circular ? 300 : 320, height: 300))
      if !circular { size.width = 0 }
    } else {
      size = control.intrinsicContentSize
      if control is UISlider || control is UIProgressView { size.width = 0 }
    }
    if control is UIProgressView { size.height = max(size.height, 4) }
    return ["width": Double(max(0, size.width)), "height": Double(max(0, size.height))]
  }

  private func number(_ key: String) -> Double? { (params[key] as? NSNumber)?.doubleValue }

  private func date(_ key: String) -> Date? {
    number(key).map { Date(timeIntervalSince1970: $0 / 1000) }
  }

  private var fraction: Double {
    let low = number("min") ?? 0
    let high = number("max") ?? 1
    guard high > low else { return 0 }
    return min(1, max(0, ((number("value") ?? 0) - low) / (high - low)))
  }

  // MARK: Events

  @objc private func pressed() { channel.invokeMethod("pressed", arguments: nil) }

  @objc private func switched(_ toggle: UISwitch) {
    channel.invokeMethod("changed", arguments: ["value": toggle.isOn])
  }

  @objc private func slid(_ slider: UISlider) {
    channel.invokeMethod("changed", arguments: ["value": Double(slider.value)])
  }

  @objc private func slideEnded(_ slider: UISlider) {
    channel.invokeMethod("ended", arguments: ["value": Double(slider.value)])
  }

  @objc private func picked(_ picker: UIDatePicker) {
    channel.invokeMethod("changed", arguments: ["millis": Int64(picker.date.timeIntervalSince1970 * 1000)])
  }
}

@available(iOS 16.0, *)
private final class GaugeModel: ObservableObject {
  @Published var value: Double = 0
  @Published var minimum: Double = 0
  @Published var maximum: Double = 1
  @Published var circular = true
  @Published var label: String?
  @Published var valueLabel: String?
  @Published var tint: Color?
}

@available(iOS 16.0, *)
private struct GaugeContent: View {
  @ObservedObject var model: GaugeModel

  var body: some View {
    let gauge = Gauge(value: min(max(model.value, model.minimum), model.maximum), in: model.minimum...model.maximum) {
      Text(model.label ?? "")
    } currentValueLabel: {
      Text(model.valueLabel ?? "")
    }
    Group {
      if model.circular {
        gauge.gaugeStyle(.accessoryCircular)
      } else {
        gauge.gaugeStyle(.linearCapacity)
      }
    }
    .tint(model.tint ?? .accentColor)
  }
}

/// A short message in a glass capsule at the top of the window. iOS has no
/// toast of its own; this keeps the system's material and announces the
/// message to VoiceOver.
enum ToastPresenter {
  private static weak var current: UIView?

  static func show(_ spec: [String: Any], in window: UIWindow) {
    current?.removeFromSuperview()
    let surface = ChromeHostView.glassSurface()
    let capsule = surface.view
    if !(capsule is UIVisualEffectView) {
      capsule.backgroundColor = .secondarySystemBackground
      capsule.layer.cornerRadius = 24
      capsule.layer.shadowColor = UIColor.black.cgColor
      capsule.layer.shadowOpacity = 0.15
      capsule.layer.shadowRadius = 12
      capsule.layer.shadowOffset = CGSize(width: 0, height: 4)
    }
    capsule.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = spec["message"] as? String
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 2
    let row = UIStackView(arrangedSubviews: [label])
    if let symbol = (spec["symbol"] as? String).flatMap({ UIImage(systemName: $0) }) {
      let image = UIImageView(image: symbol)
      image.tintColor = DescribedSheetController.color(spec["tint"]) ?? .label
      image.setContentHuggingPriority(.required, for: .horizontal)
      row.insertArrangedSubview(image, at: 0)
    }
    row.spacing = 8
    row.alignment = .center
    row.translatesAutoresizingMaskIntoConstraints = false
    surface.content.addSubview(row)
    window.addSubview(capsule)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: surface.content.topAnchor, constant: 12),
      row.bottomAnchor.constraint(equalTo: surface.content.bottomAnchor, constant: -12),
      row.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor, constant: 18),
      row.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor, constant: -18),
      capsule.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
      capsule.centerXAnchor.constraint(equalTo: window.centerXAnchor),
      capsule.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
    ])
    current = capsule

    let tap = UITapGestureRecognizer(target: ToastDismissal.shared, action: #selector(ToastDismissal.dismiss(_:)))
    capsule.addGestureRecognizer(tap)
    capsule.isAccessibilityElement = true
    capsule.accessibilityLabel = label.text

    capsule.alpha = 0
    capsule.transform = CGAffineTransform(translationX: 0, y: -24)
    UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
      capsule.alpha = 1
      capsule.transform = .identity
    }
    UIAccessibility.post(notification: .announcement, argument: label.text)

    let milliseconds = spec["durationMs"] as? Int ?? 2000
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak capsule] in
      if let capsule { hide(capsule) }
    }
  }

  static func hide(_ capsule: UIView) {
    UIView.animate(
      withDuration: 0.25,
      animations: {
        capsule.alpha = 0
        capsule.transform = CGAffineTransform(translationX: 0, y: -24)
      },
      completion: { _ in capsule.removeFromSuperview() })
  }
}

private final class ToastDismissal: NSObject {
  static let shared = ToastDismissal()

  @objc func dismiss(_ recognizer: UITapGestureRecognizer) {
    if let capsule = recognizer.view { ToastPresenter.hide(capsule) }
  }
}

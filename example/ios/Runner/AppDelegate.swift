import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var modalChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExampleModal") else { return }
    let channel = FlutterMethodChannel(name: "overglass_example/modal", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak registrar] _, result in
      registrar?.viewController?.present(ExampleModalController(), animated: true)
      result(nil)
    }
    modalChannel = channel
  }
}

/// A full-screen UIKit screen, to exercise view ordering after it closes.
final class ExampleModalController: UIViewController {
  init() {
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) { fatalError("Not used") }

  @objc private func close() {
    dismiss(animated: true)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let button = UIButton(type: .system)
    button.setTitle("Dismiss modal", for: .normal)
    button.addTarget(self, action: #selector(close), for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }
}

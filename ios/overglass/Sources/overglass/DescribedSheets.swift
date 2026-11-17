import Flutter
import UIKit

/// A system sheet built from a Dart description: the title in a navigation
/// bar with a close button, a height that fits the content, one result.
/// On iOS 26 the sheet keeps the system's Liquid Glass background.
class DescribedSheetController: UIViewController, UIAdaptivePresentationControllerDelegate {
  let spec: [String: Any]
  private var result: FlutterResult?

  init(spec: [String: Any], result: @escaping FlutterResult) {
    self.spec = spec
    self.result = result
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Not used") }

  /// Glass shows through only where the content leaves the background clear.
  static var clearBackground: Bool {
    guard #available(iOS 26.0, *) else { return false }
    return Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool != true
  }

  /// The height the content needs below the navigation bar.
  func contentHeight(width: CGFloat) -> CGFloat { 0 }

  func close(with value: Any?) {
    dismiss(animated: true) { [self] in finish(value) }
  }

  @objc private func cancel() {
    close(with: nil)
  }

  private func finish(_ value: Any?) {
    result?(value)
    result = nil
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }

  static func present(_ sheet: DescribedSheetController, from presenter: UIViewController) {
    sheet.title = sheet.spec["title"] as? String
    sheet.navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .close, target: sheet, action: #selector(cancel))
    let navigation = UINavigationController(rootViewController: sheet)
    navigation.view.backgroundColor = clearBackground ? .clear : .systemGroupedBackground
    navigation.modalPresentationStyle = .pageSheet
    navigation.presentationController?.delegate = sheet
    if #available(iOS 15.0, *), let controller = navigation.sheetPresentationController {
      if #available(iOS 16.0, *) {
        controller.detents = [
          .custom { [weak sheet, weak navigation] context in
            guard let sheet, let navigation else { return nil }
            let bar = navigation.navigationBar.frame.height > 0 ? navigation.navigationBar.frame.height : 56
            let width = navigation.view.bounds.width > 0 ? navigation.view.bounds.width : presenter.view.bounds.width
            return min(context.maximumDetentValue, bar + sheet.contentHeight(width: width))
          }
        ]
      } else {
        controller.detents = [.medium(), .large()]
      }
      controller.prefersGrabberVisible = false
    }
    presenter.present(navigation, animated: true)
  }

  static func color(_ value: Any?) -> UIColor? {
    guard let argb = (value as? NSNumber)?.uint32Value else { return nil }
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}

/// Large rows to pick one from: symbol, title, subtitle, a checkmark on the
/// current one. Returns the picked id.
@available(iOS 15.0, *)
final class ChoiceSheetController: DescribedSheetController, UITableViewDataSource, UITableViewDelegate {
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private var items: [[String: Any]] { spec["items"] as? [[String: Any]] ?? [] }

  override func viewDidLoad() {
    super.viewDidLoad()
    table.dataSource = self
    table.delegate = self
    table.alwaysBounceVertical = false
    table.backgroundColor = Self.clearBackground ? .clear : .systemGroupedBackground
    table.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(table)
    NSLayoutConstraint.activate([
      table.topAnchor.constraint(equalTo: view.topAnchor),
      table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  override func contentHeight(width: CGFloat) -> CGFloat {
    loadViewIfNeeded()
    if table.bounds.width != width {
      table.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
      table.reloadData()
    }
    table.layoutIfNeeded()
    return table.contentSize.height + 8
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    spec["message"] as? String
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let item = items[indexPath.row]
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = item["label"] as? String
    content.secondaryText = item["subtitle"] as? String
    content.secondaryTextProperties.color = .secondaryLabel
    if let symbol = item["symbol"] as? String {
      content.image = UIImage(systemName: symbol)
      content.imageProperties.tintColor = Self.color(item["color"]) ?? tableView.tintColor
    }
    cell.contentConfiguration = content
    cell.accessoryType = (item["selected"] as? Bool) == true ? .checkmark : .none
    cell.accessibilityTraits = (item["selected"] as? Bool) == true ? [.button, .selected] : .button
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    close(with: items[indexPath.row]["id"])
  }
}

/// The system date picker with a confirm button and an optional clear one.
/// Returns {"action": "confirm", "millis": …} or {"action": "clear"}.
@available(iOS 15.0, *)
final class DateSheetController: DescribedSheetController {
  private let picker = UIDatePicker()
  private let stack = UIStackView()
  private static let margin: CGFloat = 20

  override func viewDidLoad() {
    super.viewDidLoad()
    let mode = spec["mode"] as? String
    switch mode {
    case "time": picker.datePickerMode = .time
    case "date": picker.datePickerMode = .date
    default: picker.datePickerMode = .dateAndTime
    }
    picker.preferredDatePickerStyle = mode == "time" ? .wheels : .inline
    if let locale = spec["locale"] as? String { picker.locale = Locale(identifier: locale) }
    if let millis = (spec["initial"] as? NSNumber)?.doubleValue {
      picker.date = Date(timeIntervalSince1970: millis / 1000)
    }
    if let millis = (spec["minimum"] as? NSNumber)?.doubleValue {
      picker.minimumDate = Date(timeIntervalSince1970: millis / 1000)
    }

    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    if let message = spec["message"] as? String {
      let label = UILabel()
      label.text = message
      label.font = .preferredFont(forTextStyle: .footnote)
      label.textColor = .secondaryLabel
      label.textAlignment = .center
      label.numberOfLines = 0
      stack.addArrangedSubview(label)
    }
    stack.addArrangedSubview(picker)
    stack.setCustomSpacing(20, after: picker)
    stack.addArrangedSubview(button(spec["confirmLabel"] as? String, prominent: true, action: #selector(confirm)))
    if let clear = spec["clearLabel"] as? String {
      stack.addArrangedSubview(button(clear, prominent: false, action: #selector(clearDate)))
    }
    view.addSubview(stack)
    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Self.margin),
      stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Self.margin),
    ])
  }

  private func button(_ title: String?, prominent: Bool, action: Selector) -> UIButton {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = prominent ? .prominentGlass() : .glass()
    } else {
      configuration = prominent ? .filled() : .gray()
      configuration.cornerStyle = .capsule
    }
    configuration.title = title
    configuration.buttonSize = .large
    if !prominent { configuration.baseForegroundColor = .systemRed }
    let button = UIButton(configuration: configuration)
    button.addTarget(self, action: action, for: .touchUpInside)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    return button
  }

  override func contentHeight(width: CGFloat) -> CGFloat {
    loadViewIfNeeded()
    let fitting = stack.systemLayoutSizeFitting(
      CGSize(width: width - 2 * Self.margin, height: 0), withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel)
    return fitting.height + 8 + Self.margin
  }

  @objc private func confirm() {
    close(with: ["action": "confirm", "millis": Int64(picker.date.timeIntervalSince1970 * 1000)])
  }

  @objc private func clearDate() {
    close(with: ["action": "clear"])
  }
}

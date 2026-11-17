import XCTest

/// Runs against the real accessibility tree, the one VoiceOver consumes.
final class OverglassUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
    XCTAssertTrue(tab("Home").waitForExistence(timeout: 30), "native tab bar missing")
  }

  /// iPad shows system tabs in the top row, outside the `tabBars` query.
  private func tab(_ name: String) -> XCUIElement {
    guard UIDevice.current.userInterfaceIdiom == .pad else { return app.tabBars.buttons[name] }
    // The controller keeps a second, off-screen copy of each tab.
    let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
    return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
  }

  private func element(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
  }

  private func openMenuItem(_ label: String) {
    app.buttons["More"].tap()
    let item = app.buttons[label]
    XCTAssertTrue(item.waitForExistence(timeout: 5), "menu item \(label) missing")
    item.tap()
  }

  /// CI simulators are much slower than a local one, so this waits longer
  /// than the other checks.
  private func waitUntilGone(_ target: XCUIElement) {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: target)
    wait(for: [gone], timeout: 25)
  }

  private func assertTabsReachFlutter(file: StaticString = #filePath, line: UInt = #line) {
    tab("Search").tap()
    XCTAssertTrue(element("Search 1").waitForExistence(timeout: 10), "tab did not reach Flutter", file: file, line: line)
    tab("Home").tap()
    XCTAssertTrue(element("Home 1").waitForExistence(timeout: 10), "tab did not reach Flutter", file: file, line: line)
  }

  func testNativeChromeAndFlutterContentAreBothAccessible() {
    XCTAssertTrue(app.buttons["Show dialog"].exists)
    XCTAssertTrue(element("Home 1").waitForExistence(timeout: 10))
    assertTabsReachFlutter()
  }

  func testPlainPageHidesChrome() {
    openMenuItem("Plain page")
    XCTAssertTrue(element("Chrome hidden on this route").waitForExistence(timeout: 10))
    waitUntilGone(tab("Home"))
  }

  /// Correction 1: two scaffolds on two routes.
  func testSecondScaffoldThenBackKeepsFirstWorking() {
    openMenuItem("Open detail")
    let notes = tab("Notes")
    XCTAssertTrue(notes.waitForExistence(timeout: 10), "second scaffold has no native bar")
    notes.tap()
    XCTAssertTrue(element("Detail tab 1").waitForExistence(timeout: 10))

    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(tab("Home").waitForExistence(timeout: 10), "first scaffold did not return")
    assertTabsReachFlutter()
  }

  /// Correction 4: view order after a full-screen UIKit controller.
  func testFullScreenUIKitModalLeavesBarsWorking() {
    openMenuItem("UIKit modal")
    let dismiss = app.buttons["Dismiss modal"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    dismiss.tap()
    waitUntilGone(dismiss)
    XCTAssertTrue(tab("Search").waitForExistence(timeout: 10))
    XCTAssertTrue(tab("Search").isHittable, "tab bar is covered after the modal")
    assertTabsReachFlutter()
  }

  /// Dialog: native bars become inert, and the barrier still receives touches.
  func testDialogLeavesBarsInertThenRestoresThem() {
    app.buttons["Show dialog"].tap()
    XCTAssertTrue(element("Flutter dialog").waitForExistence(timeout: 10))
    waitUntilGone(tab("Home"))
    element("Close").tap()
    waitUntilGone(element("Flutter dialog"))
    XCTAssertTrue(tab("Home").waitForExistence(timeout: 10))
    assertTabsReachFlutter()
  }

  func testNativeSearchReachesFlutter() {
    openMenuItem("Open detail")
    let field = app.searchFields["Search notes"]
    XCTAssertTrue(field.waitForExistence(timeout: 10), "native search field missing")
    field.tap()
    field.typeText("abc")
    XCTAssertTrue(element("query abc").waitForExistence(timeout: 10), "search text did not reach Flutter")
  }

  /// Apple's automated audit, restricted to the controls the package owns.
  func testAccessibilityAuditOfNativeBars() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Audits need iOS 17") }
    var report: [String] = []
    try app.performAccessibilityAudit { issue in
      let label = issue.element?.label ?? "-"
      let type = issue.element?.elementType.rawValue ?? 0
      report.append("\(issue.auditType.rawValue) type=\(type) '\(label)': \(issue.compactDescription)")
      // Demo cards are Flutter content, outside this package.
      return issue.element?.elementType != .button && issue.element?.elementType != .tabBar
    }
    print("OVERGLASS_AUDIT\n" + report.joined(separator: "\n"))
  }

  func testBottomSearchFiltersFlutterContentAndClearsOnCancel() {
    tab("Search").tap()
    let field = app.searchFields["Search items"]
    XCTAssertTrue(field.waitForExistence(timeout: 10), "bottom search field missing")
    if UIDevice.current.userInterfaceIdiom != .pad {
      XCTAssertLessThan(field.frame.maxY, app.tabBars.firstMatch.frame.maxY)
    }

    field.tap()
    field.typeText("37")
    XCTAssertTrue(element("Search 37").waitForExistence(timeout: 10), "search text did not reach Flutter")
    waitUntilGone(element("Search 12"))
    if app.keyboards.firstMatch.exists {
      XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY, "field is behind the keyboard")
    }

    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(element("Search 1").waitForExistence(timeout: 10), "cancel did not clear the filter")
  }

  func testToolbarAndSegmentsReachFlutter() {
    openMenuItem("Toolbar page")
    let trash = app.buttons["Trash"]
    XCTAssertTrue(trash.waitForExistence(timeout: 10), "toolbar action missing")
    trash.tap()
    XCTAssertTrue(element("action Trash").waitForExistence(timeout: 10))
    let week = app.buttons["Week"]
    XCTAssertTrue(week.exists, "segment missing")
    week.tap()
    XCTAssertTrue(element("Segment 1").waitForExistence(timeout: 10))
  }

  func testContextMenuRunsTheChosenItem() {
    element("Home 3").press(forDuration: 1.2)
    let pin = element("Pin screen")
    XCTAssertTrue(pin.waitForExistence(timeout: 10), "context menu did not open")
    pin.tap()
    XCTAssertTrue(element("Last: Pinned").waitForExistence(timeout: 10))
  }

  func testPopoverReturnsChoice() {
    openMenuItem("Popover")
    let choose = app.buttons["Choose me"]
    XCTAssertTrue(choose.waitForExistence(timeout: 10))
    choose.tap()
    XCTAssertTrue(element("Last: Popover yes").waitForExistence(timeout: 10))
  }

  func testFlutterSheetShowsContentAndReturnsResult() {
    openMenuItem("Flutter sheet")
    XCTAssertTrue(element("Sheet says: Hello from the app").waitForExistence(timeout: 20), "sheet content missing")
    element("Close sheet").tap()
    XCTAssertTrue(element("Last: Sheet page done").waitForExistence(timeout: 15))
  }

  func testSystemTabsAccessoryAndPassThrough() {
    openMenuItem("System tabs")
    let radio = tab("Radio")
    XCTAssertTrue(radio.waitForExistence(timeout: 15), "system tab missing")
    radio.tap()
    XCTAssertTrue(element("System tab 1").waitForExistence(timeout: 10), "tab did not reach Flutter")
    element("Now playing").tap()
    XCTAssertTrue(element("accessory 1").waitForExistence(timeout: 10), "accessory did not reach Flutter")

    let list = app.scrollViews.firstMatch
    list.swipeUp()
    XCTAssertTrue(element("row 8").waitForExistence(timeout: 10), "scrolling did not pass through the tab host")
  }

  func testSearchTabOpensTheFieldAndFiltersFlutter() throws {
    guard UIDevice.current.userInterfaceIdiom != .pad else { throw XCTSkip("iPhone layout") }
    openMenuItem("System tabs")
    let lens = app.tabBars.buttons.element(boundBy: 2)
    XCTAssertTrue(lens.waitForExistence(timeout: 15), "search tab missing")
    lens.tap()
    let field = app.searchFields["Find rows"]
    XCTAssertTrue(field.waitForExistence(timeout: 10), "the search tab did not open a field")
    field.tap()
    field.typeText("37")
    XCTAssertTrue(element("row 37").waitForExistence(timeout: 10), "search did not reach Flutter")
    waitUntilGone(element("row 12"))
  }

  func testNativeAlertReturnsChoice() {
    openMenuItem("Native alert")
    let confirm = app.alerts.buttons["Confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    confirm.tap()
    XCTAssertTrue(element("Last: Alert ok").waitForExistence(timeout: 10))
  }

  func testNativeSheetReturnsChoice() {
    openMenuItem("Native sheet")
    let delete = app.buttons["Delete"]
    XCTAssertTrue(delete.waitForExistence(timeout: 10))
    delete.tap()
    XCTAssertTrue(element("Last: Sheet delete").waitForExistence(timeout: 10))
  }

  func testBackgroundAndReturn() {
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(tab("Home").waitForExistence(timeout: 10))
    assertTabsReachFlutter()
  }

  func testRotation() {
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    XCTAssertTrue(tab("Home").waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Show dialog"].isHittable)
    assertTabsReachFlutter()
  }
}

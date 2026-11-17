import UIKit
import XCTest

@testable import overglass

final class ChromeHostViewTests: XCTestCase {
  private func spec(selected: Int, ack: Int) -> [String: Any] {
    [
      "visible": true,
      "ackTap": ack,
      "tabBar": [
        "selected": selected,
        "items": [["label": "A"], ["label": "B"], ["label": "C"]],
      ],
    ]
  }

  /// Correction 10: an old description cannot undo a newer tap.
  func testStaleDescriptionDoesNotMoveSelection() throws {
    let host = ChromeHostView()
    host.session = 1
    host.apply(spec(selected: 0, ack: 0))
    let bar = try XCTUnwrap(host.tabBar)
    let items = try XCTUnwrap(bar.items)

    bar.selectedItem = items[1]
    host.tabBar(bar, didSelect: items[1])
    bar.selectedItem = items[2]
    host.tabBar(bar, didSelect: items[2])

    host.apply(spec(selected: 1, ack: 1))
    XCTAssertTrue(bar.selectedItem === items[2])

    host.apply(spec(selected: 0, ack: 2))
    XCTAssertTrue(bar.selectedItem === items[0], "a current description must still apply")
  }

  private func barSpec(title: String, back: Bool) -> [String: Any] {
    ["visible": true, "topBar": ["title": title, "back": back]]
  }

  /// Page changes: the same items form a real stack, so UIKit animates them.
  func testPushAndPopReuseTheSameNavigationItems() throws {
    let host = ChromeHostView()
    host.session = 1
    host.apply(barSpec(title: "A", back: false))
    let bar = try XCTUnwrap(host.navigationBar)
    let first = try XCTUnwrap(bar.topItem)

    host.session = 2
    host.apply(barSpec(title: "B", back: true), previousSession: 1)
    XCTAssertEqual(bar.items?.count, 2)
    XCTAssertTrue(bar.items?.first === first)
    XCTAssertEqual(bar.topItem?.title, "B")

    host.session = 1
    host.apply(barSpec(title: "A", back: false))
    XCTAssertEqual(bar.items?.count, 1)
    XCTAssertTrue(bar.topItem === first)
    XCTAssertTrue(host.navigationBar === bar, "the bar must stay in place across pages")
  }

  func testTapSequencesAreIndependentPerSession() throws {
    let host = ChromeHostView()
    host.session = 1
    host.apply(spec(selected: 0, ack: 0))
    let bar = try XCTUnwrap(host.tabBar)
    let items = try XCTUnwrap(bar.items)
    host.tabBar(bar, didSelect: items[1])

    host.session = 2
    host.apply(spec(selected: 2, ack: 0))
    XCTAssertTrue(bar.selectedItem === items[2])
  }
}

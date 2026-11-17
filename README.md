# overglass

Real iOS system bars (Liquid Glass on iOS 26+) for Flutter, with **no platform views and no shader imitation**.
The bars, sheets, menus, alerts and toasts float above Flutter as system views. Optional controls inside your
content, such as buttons and switches, live in a separate import because they need platform views.

```dart
OverglassScaffold(
  topBar: OverglassTopBar(
    title: 'Home',
    trailing: [OverglassAction.add(onPressed: add)],
  ),
  tabBar: OverglassTabBar(
    currentIndex: tab,
    onChanged: (i) => setState(() => tab = i),
    items: const [
      OverglassTab(label: 'Home', sfSymbol: 'house.fill', icon: myHomeIcon),
      OverglassTab(label: 'Search', sfSymbol: 'magnifyingglass', icon: mySearchIcon, badge: '3'),
    ],
  ),
  body: ListView(children: items), // MediaQuery.padding already includes the bars
);
```

## What you get

| Feature | API | Native control |
| --- | --- | --- |
| Top bar | `OverglassTopBar` | `UINavigationBar` |
| Tab bar and badges | `OverglassTabBar`, `OverglassTab.badge` | `UITabBar` |
| Back button | `OverglassTopBar.showBack` (defaults to whether the route can pop) | `UINavigationItem` |
| Large title | `OverglassTopBar.largeTitle` | `prefersLargeTitles` |
| Search, in the top bar or floating above the tab bar | `OverglassTopBar.search` | `UISearchBar` |
| Menus | `OverglassAction.menu` | `UIMenu` |
| Bottom toolbar | `OverglassScaffold.toolbar` | `UIToolbar` |
| Segmented control | `OverglassTopBar.segments` | `UISegmentedControl` |
| Search tab and accessory above the tabs | `OverglassTab.isSearch`, `OverglassTabBar.accessory` | `UITabBarController` |
| Tab bar that shrinks while scrolling | `OverglassTabBar.minimizeOnScroll` | `tabBarMinimizeBehavior` |
| iPad sidebar | `OverglassTabBar.sidebar` | `UITabBarController` sidebar |
| Context menu on Flutter content | `OverglassContextMenu`, `Overglass.showContextMenu` | `UIEditMenuInteraction` |
| Popover with text and buttons | `Overglass.showPopover` | `UIPopoverPresentationController` |
| Sheet with Flutter content | `Overglass.showSheet` | `UISheetPresentationController` |
| Alerts | `Overglass.showAlert` | `UIAlertController` |
| Action sheets | `Overglass.showActionSheet` | `UIAlertController` |
| Sheet with a list to pick from | `Overglass.showChoiceSheet` | `UITableView` in a sheet |
| Sheet with a date picker | `Overglass.showDateSheet` | `UIDatePicker` in a sheet |
| Toast | `Overglass.showToast` | Glass capsule; iOS has no toast of its own |

### Controls inside your content

These sit in the widget tree like any widget, so on iOS each one is a platform view holding the system control;
elsewhere Flutter draws a simple stand-in. They come from their own import, and an app that imports only
`package:overglass/overglass.dart` creates no platform views.

```dart
import 'package:overglass/controls.dart';
```

| Control | Widget | Native control |
| --- | --- | --- |
| Button, glass or prominent | `OverglassButton` | `UIButton` with the glass configurations |
| Switch | `OverglassSwitch` | `UISwitch` |
| Slider | `OverglassSlider` | `UISlider` |
| Date picker | `OverglassDatePicker` | Compact `UIDatePicker` |
| Gauge, circular or linear | `OverglassGauge` | SwiftUI `Gauge`, a progress bar before iOS 16 |

```dart
OverglassSwitch(value: wifi, onChanged: (on) => setState(() => wifi = on), semanticLabel: 'Wi-Fi'),
OverglassSlider(value: volume, onChanged: (v) => setState(() => volume = v)),
OverglassButton(label: 'Save', style: OverglassButtonStyle.prominent, onPressed: save),
```

Build with Xcode 26 to get Liquid Glass.

Requires Flutter 3.38.1 or later. CocoaPods works from that version. Swift Package Manager needs Flutter 3.44 or later.

## How it works

Liquid Glass belongs to the navigation layer that floats above content. That layer is small and fixed,
so it does not have to live inside the Flutter tree.

- The system bars sit in a host view that is a **sibling above the FlutterView**.
- On iOS 26.5 simulators the system glass refracts Flutter's rendered content. This is observed behavior,
  not something Apple documents, and physical devices are still to be verified.
- Touches outside the bars fall through to Flutter.
- Each scaffold is a session that sends one declarative description of its bars. The newest visible session
  is what shows, and native code applies only what changed.

| Environment or state | Bars |
| --- | --- |
| iOS 26+ built with Xcode 26 | Real system controls |
| A Flutter dialog covers the scaffold | Real system controls, dimmed and inert |
| A popup with no barrier covers the scaffold | Real system controls, inert |
| A page replaces the scaffold | Real system controls stay in place; a page with its own scaffold changes their content, any other page fades them out |
| A bottom sheet covers the scaffold | Flutter twin with the iOS 26 geometry |
| Native attachment failed | Flutter-drawn, until it succeeds |
| iOS 26+ with `UIDesignRequiresCompatibility`, older iOS, Android, web, desktop | Flutter-drawn, or yours through `fallbackTopBarBuilder` and `fallbackTabBarBuilder` |

There is no observer to install. Override the table with `coverPolicy`. The package imports only
`package:flutter/widgets.dart`, so the `material_ui` / `cupertino_ui` migration does not affect it.

## Limits

- A route can show one `OverglassScaffold` at a time. Two visible ones fail an assert in debug.
- Glass that scrolls with content is out of scope.
- Flutter cannot paint above native bars. `OverlayEntry`s are drawn underneath them, and a dialog or popup
  tall enough to reach a bar is overlapped by it.
- A scaffold inside a nested `Navigator` does not notice routes pushed on the root navigator above it.
- If a covering route pushes another route, the bars keep the reaction chosen for the first one.
- A Flutter body has no `UIScrollView`, so the system scroll edge effect is approximated with a gradient.
- Minimize on scroll works through an invisible scroll view that follows the same finger as Flutter. A fling that
  stops at the top of the list opens the bar again when Flutter reports the top. The body keeps the room of the full bar
  while it is minimized, so content does not jump.
- Controls inside content are platform views, with their usual cost: each one adds work to every frame it is on
  screen. Use them where the system look matters, not for long lists of rows.
- `OverglassDatePicker` has no Flutter stand-in: pass your own with `fallback`.
- The toast is the package's own design, since iOS has none. It is placed at the top of the window.
- `Overglass.showSheet` runs its content in a separate Flutter engine and isolate. It shares no state with the app, receives only string arguments and takes extra memory and startup time.
- The context menu uses the system's compact menu, without the lifted preview of a full context menu.
- A native popover holds text and buttons, not Flutter widgets.
- A tab accessory is drawn by the system from a title, subtitle and symbol.
- On iPad the system tab controller is used and the title is hidden while tabs sit in the top row. With `sidebar`, the body
  is inset by the width of the open sidebar.
- The twin finds the tab bar capsule by inspecting UIKit's view tree. If that changes, it falls back to a full-width bar.

## Status

Pre-release. Minimize on scroll, the toast and the controls inside content were tried by hand on an iPhone 15 Pro; the iPad sidebar has not been run yet
and none of them has automated UI tests.
The native test suite passes on an iPhone iOS 26.5 simulator with Flutter 3.44.5.
On an iPad iOS 26.5 simulator 15 of 17 UI tests pass: the second scaffold's tabs and the search cancel button still need work.
Earlier versions also passed on Flutter 3.47.9 and built with CocoaPods on 3.38.1. The system tabs, popover, context menu and sheets have not been run on those.
The example was run in profile mode on an iPhone 15 Pro with iOS 26.1.
Not yet tested with a live VoiceOver session or with two iPad windows.

Performance data is preliminary. On that iPhone at 120 Hz, Flutter's raster time with `overglass` matched a list with no bars
(0.52 ms against 0.57 ms on average, one run). Two 20-second Instruments runs showed 6 and 3 hitches, against 0 and 3 without bars.
That is too little data to compare it with other approaches.

<p align="center">
  <a href="https://stebaia.github.io/overglass/">
    <img src="https://stebaia.github.io/overglass/readme/banner.jpg" alt="A clear glass capsule bending a stack of coloured tiles" width="100%">
  </a>
</p>

<h1 align="center">overglass</h1>

<p align="center">
  <strong>Liquid Glass for Flutter. The real one.</strong><br>
  Real iOS system bars, sheets, menus and alerts floating above your Flutter app.<br>
  No platform views. No shader imitation.
</p>

<p align="center">
  <a href="https://pub.dev/packages/overglass"><img src="https://img.shields.io/pub/v/overglass?include_prereleases&label=pub.dev&color=2997ff" alt="pub.dev version"></a>
  <img src="https://img.shields.io/badge/iOS-26%2B-000000?logo=apple" alt="iOS 26 and later">
  <img src="https://img.shields.io/badge/Flutter-3.38.1%2B-02569B?logo=flutter" alt="Flutter 3.38.1 and later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://stebaia.github.io/overglass/"><strong>Website</strong></a> ·
  <a href="https://pub.dev/packages/overglass">pub.dev</a> ·
  <a href="example/lib/main.dart">Example app</a> ·
  <a href="https://github.com/stebaia/overglass/issues">Issues</a>
</p>

<table align="center">
  <tr>
    <td align="center" width="50%">
      <img src="https://stebaia.github.io/overglass/readme/surfaces.gif" alt="Scrolling a Flutter list under the system bars, then a native menu, a native alert and a Flutter dialog that dims the bars" width="280"><br>
      <sub><b>System bars, menus and alerts over a plain <code>ListView</code></b></sub>
    </td>
    <td align="center" width="50%">
      <img src="https://stebaia.github.io/overglass/readme/systabs.gif" alt="A system tab bar with an accessory that shrinks while scrolling down and grows back when scrolling up" width="280"><br>
      <sub><b>System tabs that minimize while you scroll</b></sub>
    </td>
  </tr>
</table>

<p align="center"><sub>Unretouched recordings of the example app on an iOS 26.5 simulator.</sub></p>

---

## Why overglass

Most "liquid glass" packages redraw the effect with blurs and shaders. overglass doesn't draw it at all.
The bars are `UINavigationBar`, `UITabBar` and `UIMenu`, hosted in a view **beside** the FlutterView, so
iOS renders the glass, the animations and the behaviour, and they bend the pixels Flutter draws underneath.

- 🪟 **The system's own glass**: it looks right because it is the real control, drawn and animated by iOS.
- 🧩 **No platform views** in the main library: the bars live outside the Flutter tree, not inside it.
- 📐 **Reads like a `Scaffold`**: describe the bars, and `MediaQuery.padding` already includes them.
- 🛟 **Falls back on its own**: Flutter-drawn bars on older iOS, Android, web and desktop, or your own builders.

## Install

```sh
flutter pub add overglass
```

Build with **Xcode 26** to get Liquid Glass. Requires Flutter 3.38.1 or later. CocoaPods works from that version.
Swift Package Manager needs Flutter 3.44 or later.

## Quick start

```dart
import 'package:overglass/overglass.dart';

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

Menus, alerts and sheets are one call away:

```dart
final choice = await Overglass.showAlert(
  context,
  title: 'Native alert',
  message: 'Presented by UIKit.',
  actions: const [
    OverglassAlertAction(id: 'cancel', label: 'Cancel', style: OverglassAlertActionStyle.cancel),
    OverglassAlertAction(id: 'ok', label: 'Confirm'),
  ],
);
```

## What you get

<table>
  <tr>
    <td align="center" width="25%"><img src="https://stebaia.github.io/overglass/readme/ex-menu.png" alt="A native menu open over a colourful Flutter list" width="160"><br><sub><b>Menus</b><br><code>UIMenu</code></sub></td>
    <td align="center" width="25%"><img src="https://stebaia.github.io/overglass/readme/ex-alert.png" alt="A native alert with Cancel and Confirm" width="160"><br><sub><b>Alerts</b><br><code>UIAlertController</code></sub></td>
    <td align="center" width="25%"><img src="https://stebaia.github.io/overglass/readme/ex-systabs.png" alt="A minimized system tab bar with a Now playing accessory" width="160"><br><sub><b>Tabs and accessory</b><br><code>UITabBarController</code></sub></td>
    <td align="center" width="25%"><img src="https://stebaia.github.io/overglass/readme/ex-controls.png" alt="System buttons, switch, slider, gauges and date picker" width="160"><br><sub><b>Controls</b><br><code>controls.dart</code></sub></td>
  </tr>
</table>

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

OverglassSwitch(value: wifi, onChanged: (on) => setState(() => wifi = on), semanticLabel: 'Wi-Fi'),
OverglassSlider(value: volume, onChanged: (v) => setState(() => volume = v)),
OverglassButton(label: 'Save', style: OverglassButtonStyle.prominent, onPressed: save),
```

| Control | Widget | Native control |
| --- | --- | --- |
| Button, glass or prominent | `OverglassButton` | `UIButton` with the glass configurations |
| Switch | `OverglassSwitch` | `UISwitch` |
| Slider | `OverglassSlider` | `UISlider` |
| Date picker | `OverglassDatePicker` | Compact `UIDatePicker` |
| Gauge, circular or linear | `OverglassGauge` | SwiftUI `Gauge`, a progress bar before iOS 16 |

## How it works

Liquid Glass belongs to the navigation layer that floats above content. That layer is small and fixed,
so it does not have to live inside the Flutter tree.

```text
┌──────────────────────────────┐
│  overglass host view         │  UINavigationBar · UITabBar · UIMenu …
│  (sibling above Flutter)     │  touches outside the bars fall through ↓
├──────────────────────────────┤
│  FlutterView                 │  your widgets, refracted by the glass above
└──────────────────────────────┘
```

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

## Brand inside, system outside

<img align="right" src="https://stebaia.github.io/overglass/readme/sat-collection.png" alt="A Saturn collection page with glass back and action buttons tinted by the page colour" width="200">

Your screens stay entirely yours. In **Saturn**, an app built on overglass, every page is Flutter with its own
type and colour, while the tab bar, the search button and the navigation actions are the system's,
tinted by the content underneath.

<br clear="right">

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

> **Pre-release.** The API may still change before 1.0.

Minimize on scroll, the toast and the controls inside content were tried by hand on an iPhone 15 Pro; the iPad sidebar has not been run yet
and none of them has automated UI tests.
The native test suite passes on an iPhone iOS 26.5 simulator with Flutter 3.44.5.
On an iPad iOS 26.5 simulator 15 of 17 UI tests pass: the second scaffold's tabs and the search cancel button still need work.
Earlier versions also passed on Flutter 3.47.9 and built with CocoaPods on 3.38.1. The system tabs, popover, context menu and sheets have not been run on those.
The example was run in profile mode on an iPhone 15 Pro with iOS 26.1.
Not yet tested with a live VoiceOver session or with two iPad windows.

Performance data is preliminary. On that iPhone at 120 Hz, Flutter's raster time with `overglass` matched a list with no bars
(0.52 ms against 0.57 ms on average, one run). Two 20-second Instruments runs showed 6 and 3 hitches, against 0 and 3 without bars.
That is too little data to compare it with other approaches.

## License

MIT. See [LICENSE](LICENSE).

<sub>overglass is an independent open-source project, not affiliated with or endorsed by Apple Inc.
iOS, UIKit and Liquid Glass are trademarks of Apple Inc. Flutter is a trademark of Google LLC.</sub>

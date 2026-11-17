## 0.3.0-dev.1

- Sessions: several `OverglassScaffold`s on different routes no longer interfere.
- Flutter-drawn bars appear when native attachment fails, and native bars return when it succeeds.
- Native bars stay under dialogs, dimmed and inert. A `coverPolicy` can change this.
- Page changes keep the native bars in place and animate their content, with no Flutter stand-in.
- For bottom sheets, the Flutter twin keeps the iOS 26 geometry.
- Native menus, alerts, action sheets, back button, tab badges, large titles and search, with a field in the top bar or floating above the tab bar.
- Symbols and icons are optional. Named `OverglassAction.add` and `OverglassAction.close`.
- Bottom toolbar, segmented control, system search tab, tab accessory, context menu, popover and sheets with Flutter content.
- Tab bar minimize on scroll, driven by Flutter's scrolling.
- iPad sidebar for system tabs.
- Toasts in a glass capsule.
- Choice and date sheets.
- System controls inside content, from `package:overglass/controls.dart`: buttons, switches, sliders, compact date pickers and gauges. They are platform views, so the main library does not export them.
- Replaceable fallback bars.
- Requires Flutter 3.38.1.

## 0.1.0-dev.1

- `OverglassScaffold` with native top bar and tab bar on iOS 26+, and Flutter-drawn bars elsewhere.

import 'package:flutter/widgets.dart';

import 'glyph.dart';

/// One entry of an [OverglassMenu].
@immutable
class OverglassMenuItem {
  const OverglassMenuItem({required this.label, required this.onSelected, this.sfSymbol, this.destructive = false});

  final String label;
  final String? sfSymbol;
  final bool destructive;
  final VoidCallback onSelected;

  Map<String, Object?> toSpec() => {'label': label, 'symbol': sfSymbol, 'destructive': destructive};
}

/// A menu opened by an [OverglassAction]. It is a system `UIMenu` where bars
/// are native.
@immutable
class OverglassMenu {
  const OverglassMenu({required this.items, this.title});

  final String? title;
  final List<OverglassMenuItem> items;

  Map<String, Object?> toSpec() => {
    'title': title,
    'items': [for (final item in items) item.toSpec()],
  };
}

/// A bar item, described by intent rather than by appearance.
///
/// With neither a symbol nor an icon it is a text button using [label].
@immutable
class OverglassAction {
  const OverglassAction({
    required this.id,
    required this.label,
    this.sfSymbol,
    this.icon,
    this.image,
    this.onPressed,
    this.menu,
  }) : glyph = null,
       assert(onPressed != null || menu != null, 'An action needs onPressed or menu.');

  /// A standard add action that needs no icon of its own.
  const OverglassAction.add({this.id = 'add', this.label = 'Add', required VoidCallback this.onPressed})
    : sfSymbol = 'plus',
      icon = null,
      image = null,
      menu = null,
      glyph = OverglassGlyph.add;

  /// A standard close action that needs no icon of its own.
  const OverglassAction.close({this.id = 'close', this.label = 'Close', required VoidCallback this.onPressed})
    : sfSymbol = 'xmark',
      icon = null,
      image = null,
      menu = null,
      glyph = OverglassGlyph.close;

  /// Stable identifier, unique within the top bar.
  final String id;

  /// Accessibility label, and the visible text of a text button.
  final String label;

  /// SF Symbol name used by the native bar.
  final String? sfSymbol;

  /// Icon used by the Flutter-drawn bar.
  final IconData? icon;

  /// App image used as a silhouette, for icons that are not SF Symbols.
  final AssetImage? image;

  final VoidCallback? onPressed;
  final OverglassMenu? menu;

  /// Built-in shape for the Flutter-drawn bar.
  final OverglassGlyph? glyph;

  Map<String, Object?> toSpec() => {
    'id': id,
    'label': label,
    'symbol': sfSymbol,
    'image': image?.keyName,
    'menu': menu?.toSpec(),
  };
}

@immutable
class OverglassTab {
  const OverglassTab({required this.label, this.sfSymbol, this.icon, this.image, this.badge, this.isSearch = false});

  /// Shows this as the system's detached search tab where bars are native.
  final bool isSearch;

  final String label;
  final String? sfSymbol;
  final IconData? icon;
  final AssetImage? image;

  /// Short text in the tab's badge.
  final String? badge;

  Map<String, Object?> toSpec() => {
    'label': label,
    'symbol': sfSymbol,
    'image': image?.keyName,
    'badge': badge,
    'isSearch': isSearch,
  };
}

/// Where a native search field sits.
enum OverglassSearchPlacement {
  /// In the top bar, in place of the title.
  top,

  /// Floating above the tab bar, and above the keyboard while typing.
  bottom,
}

/// A system search field. Where bars are Flutter-drawn it is in the top bar.
@immutable
class OverglassSearch {
  const OverglassSearch({
    this.placeholder,
    this.placement = OverglassSearchPlacement.top,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final String? placeholder;
  final OverglassSearchPlacement placement;

  /// Opens the keyboard when a bottom field appears, as a search tab does.
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
}

@immutable
class OverglassTopBar {
  const OverglassTopBar({
    this.title,
    this.leading = const [],
    this.trailing = const [],
    this.showBack,
    this.onBack,
    this.largeTitle = false,
    this.segments,
    this.search,
  });

  final String? title;
  final List<OverglassAction> leading;
  final List<OverglassAction> trailing;

  /// Defaults to whether the enclosing route can pop.
  final bool? showBack;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Shows a large title that collapses when the body scrolls. Only native
  /// bars have one.
  final bool largeTitle;

  /// Shown in place of the title. A [search] field takes precedence.
  final OverglassSegments? segments;

  final OverglassSearch? search;

  Iterable<OverglassAction> get actions => [...leading, ...trailing];

  Map<String, Object?> toSpec({required bool back, required bool collapsed}) => {
    'title': title,
    'back': back,
    'largeTitle': largeTitle && !collapsed,
    'segments': segments?.toSpec(),
    'search': search == null
        ? null
        : {'placeholder': search!.placeholder, 'placement': search!.placement.name, 'autofocus': search!.autofocus},
    'leading': [for (final a in leading) a.toSpec()],
    'trailing': [for (final a in trailing) a.toSpec()],
  };
}

@immutable
class OverglassTabBar {
  const OverglassTabBar({
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.accessory,
    this.minimizeOnScroll = false,
    this.sidebar = false,
  }) : assert(items.length >= 2);

  /// Shrinks the tab bar while the body scrolls down and brings it back when
  /// it scrolls up, as iOS 26 apps do. Only native bars do this.
  final bool minimizeOnScroll;

  /// On iPad, lets the tabs open as the system sidebar. iPhone ignores it.
  final bool sidebar;

  /// A system view above the tab bar. Only native bars have one.
  final OverglassTabAccessory? accessory;

  final List<OverglassTab> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  Map<String, Object?> toSpec() => {
    'items': [for (final t in items) t.toSpec()],
    'selected': currentIndex,
    'accessory': accessory?.toSpec(),
    'minimize': minimizeOnScroll,
    'sidebar': sidebar,
  };
}

/// A compact system view above the tab bar, such as a mini player.
@immutable
class OverglassTabAccessory {
  const OverglassTabAccessory({required this.title, this.subtitle, this.sfSymbol, this.onPressed});

  final String title;
  final String? subtitle;
  final String? sfSymbol;
  final VoidCallback? onPressed;

  Map<String, Object?> toSpec() => {'title': title, 'subtitle': subtitle, 'symbol': sfSymbol};
}

/// A segmented control shown in the top bar.
@immutable
class OverglassSegments {
  const OverglassSegments({required this.labels, required this.selectedIndex, required this.onChanged})
    : assert(labels.length >= 2);

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  Map<String, Object?> toSpec() => {'labels': labels, 'selected': selectedIndex};
}

/// One slot of an [OverglassToolbar].
@immutable
class OverglassToolbarItem {
  const OverglassToolbarItem.action(OverglassAction this.action);

  /// Takes the free space between the items around it.
  const OverglassToolbarItem.flexibleSpace() : action = null;

  final OverglassAction? action;

  Map<String, Object?> toSpec() => action?.toSpec() ?? {'space': true};
}

/// A bottom toolbar, for screens without a tab bar.
@immutable
class OverglassToolbar {
  const OverglassToolbar({required this.items});

  final List<OverglassToolbarItem> items;

  Iterable<OverglassAction> get actions => items.map((item) => item.action).whereType<OverglassAction>();

  Map<String, Object?> toSpec() => {
    'items': [for (final item in items) item.toSpec()],
  };
}

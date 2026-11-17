import 'package:flutter/widgets.dart';

/// What the bars do while a Flutter route sits above the scaffold.
enum OverglassCover {
  /// Native bars stay, dimmed like the route's barrier and not tappable.
  scrim,

  /// Native bars stay as they are, but not tappable.
  passive,

  /// Native bars fade out in place during the route's transition.
  fade,

  /// A Flutter-drawn twin replaces them, so the route can paint over it.
  twin,
}

/// Chooses how the bars react to the route covering the scaffold.
typedef OverglassCoverPolicy = OverglassCover Function(Route<Object?> covering);

/// Pages replace the bars in place, as on iOS. Dialogs keep them, barrier-less
/// popups leave them inert, and anything else needs the twin because Flutter
/// cannot paint over native views.
OverglassCover defaultCoverPolicy(Route<Object?> route) {
  if (route is ModalRoute && route.opaque) return OverglassCover.fade;
  if (route is RawDialogRoute) return OverglassCover.scrim;
  if (route is PopupRoute && (route.barrierColor?.a ?? 0) == 0) {
    return OverglassCover.passive;
  }
  return OverglassCover.twin;
}

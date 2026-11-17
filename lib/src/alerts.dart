import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'channel.dart';
import 'fallback.dart';
import 'spec.dart';

enum OverglassAlertActionStyle { normal, cancel, destructive }

/// One button of an alert or action sheet.
@immutable
class OverglassAlertAction {
  const OverglassAlertAction({required this.id, required this.label, this.style = OverglassAlertActionStyle.normal});

  final String id;
  final String label;
  final OverglassAlertActionStyle style;

  Map<String, Object?> toSpec() => {'id': id, 'label': label, 'style': style.name};
}

enum OverglassSheetDetent { medium, large }

/// One row of [Overglass.showChoiceSheet].
@immutable
class OverglassSheetChoice {
  const OverglassSheetChoice({
    required this.id,
    required this.label,
    this.subtitle,
    this.sfSymbol,
    this.symbolColor,
    this.selected = false,
  });

  final String id;
  final String label;
  final String? subtitle;
  final String? sfSymbol;
  final Color? symbolColor;

  /// The current choice: shown with a checkmark.
  final bool selected;

  Map<String, Object?> toSpec() => {
    'id': id,
    'label': label,
    'subtitle': subtitle,
    'symbol': sfSymbol,
    'color': symbolColor?.toARGB32(),
    'selected': selected,
  };
}

enum OverglassDateMode { time, date, dateAndTime }

/// What [Overglass.showDateSheet] returns: the picked [date], or null when
/// the clear button was used.
@immutable
class OverglassDatePick {
  const OverglassDatePick(this.date);

  final DateTime? date;
}

/// Closes the sheet this code is running in, from a sheet's own entrypoint or
/// from the Flutter fallback.
abstract final class OverglassSheet {
  static Future<void> close(BuildContext context, {String? result}) async {
    final closed = await OverglassChannel.instance.closeSheet(result);
    if (!closed && context.mounted) Navigator.of(context, rootNavigator: true).pop(result);
  }
}

/// Opens a system menu when its child is long pressed.
class OverglassContextMenu extends StatelessWidget {
  const OverglassContextMenu({super.key, required this.menu, required this.child});

  final OverglassMenu menu;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: (details) => Overglass.showContextMenu(context, position: details.globalPosition, menu: menu),
    child: child,
  );
}

/// System surfaces that UIKit presents above the whole app.
abstract final class Overglass {
  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Shows the system's menu at a global [position] and runs the chosen item.
  static Future<void> showContextMenu(
    BuildContext context, {
    required Offset position,
    required OverglassMenu menu,
  }) async {
    if (_isIOS) {
      try {
        final index = await OverglassChannel.instance.presentContextMenu({
          'x': position.dx,
          'y': position.dy,
          ...menu.toSpec(),
        });
        if (index != null) menu.items[index].onSelected();
        return;
      } on MissingPluginException {
        // No native side: use the Flutter dialog below.
      } on PlatformException {
        // Nothing to present from: use the Flutter dialog below.
      }
    }
    if (!context.mounted) return;
    final item = await showFallbackChoice<OverglassMenuItem>(
      context,
      palette: BarPalette(MediaQuery.platformBrightnessOf(context), null),
      title: menu.title,
      choices: [
        for (final item in menu.items) FallbackChoice(value: item, label: item.label, destructive: item.destructive),
      ],
    );
    item?.onSelected();
  }

  /// Shows a system popover with text and buttons, pointing at [anchor].
  ///
  /// Returns the chosen action id, or null if dismissed. A native popover
  /// cannot hold Flutter widgets.
  static Future<String?> showPopover(
    BuildContext context, {
    required Rect anchor,
    String? title,
    String? message,
    required List<OverglassAlertAction> actions,
  }) async {
    if (_isIOS) {
      try {
        return await OverglassChannel.instance.presentPopover({
          'title': title,
          'message': message,
          'actions': [for (final action in actions) action.toSpec()],
          'anchor': {'x': anchor.left, 'y': anchor.top, 'width': anchor.width, 'height': anchor.height},
        });
      } on MissingPluginException {
        // No native side: use the Flutter dialog below.
      } on PlatformException {
        // Nothing to present from: use the Flutter dialog below.
      }
    }
    if (!context.mounted) return null;
    return showFallbackChoice<String>(
      context,
      palette: BarPalette(MediaQuery.platformBrightnessOf(context), null),
      title: title,
      message: message,
      choices: [for (final action in actions) FallbackChoice(value: action.id, label: action.label)],
    );
  }

  /// Shows a system sheet whose content is Flutter.
  ///
  /// [entrypoint] names a top-level function in the app's main library, marked
  /// `@pragma('vm:entry-point')`. It runs in its own engine and isolate, so it
  /// receives only [arguments] and shares no state with the app. Call
  /// [OverglassSheet.close] to return a result.
  ///
  /// [fallback] builds the content where the native sheet is not available.
  static Future<String?> showSheet(
    BuildContext context, {
    required String entrypoint,
    List<String> arguments = const [],
    List<OverglassSheetDetent> detents = const [OverglassSheetDetent.medium, OverglassSheetDetent.large],
    required WidgetBuilder fallback,
  }) async {
    if (_isIOS && (await OverglassChannel.instance.resolveNativeGlass())) {
      try {
        return await OverglassChannel.instance.presentSheet({
          'entrypoint': entrypoint,
          'arguments': arguments,
          'detents': [for (final detent in detents) detent.name],
        });
      } on MissingPluginException {
        // No native side: use the Flutter sheet below.
      } on PlatformException {
        // Nothing to present from: use the Flutter sheet below.
      }
    }
    if (!context.mounted) return null;
    final palette = BarPalette(MediaQuery.platformBrightnessOf(context), null);
    return Navigator.of(context, rootNavigator: true).push<String>(
      RawDialogRoute<String>(
        barrierDismissible: true,
        barrierColor: const Color(0x66000000),
        barrierLabel: 'Dismiss',
        pageBuilder: (context, _, _) => Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.6,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: ColoredBox(
                color: palette.solid,
                child: Builder(builder: fallback),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A system sheet of large rows to pick one from, sized to fit, with the
  /// system's Liquid Glass on iOS 26. Returns the picked id, or null when
  /// dismissed.
  ///
  /// [fallback] shows the app's own sheet where UIKit is not available.
  static Future<String?> showChoiceSheet(
    BuildContext context, {
    required String title,
    String? message,
    required List<OverglassSheetChoice> choices,
    required Future<String?> Function() fallback,
  }) async {
    if (_isIOS) {
      try {
        return await OverglassChannel.instance.presentChoiceSheet({
          'title': title,
          'message': message,
          'items': [for (final choice in choices) choice.toSpec()],
        });
      } on MissingPluginException {
        // No native side: use the fallback below.
      } on PlatformException {
        // Nothing to present from: use the fallback below.
      }
    }
    if (!context.mounted) return null;
    return fallback();
  }

  /// A system sheet with the date picker, a confirm button and, with
  /// [clearLabel], a button that clears the date. Null when dismissed.
  ///
  /// [locale] is a language tag such as `it` for the picker's labels.
  static Future<OverglassDatePick?> showDateSheet(
    BuildContext context, {
    required String title,
    String? message,
    required String confirmLabel,
    String? clearLabel,
    required DateTime initial,
    DateTime? minimum,
    OverglassDateMode mode = OverglassDateMode.dateAndTime,
    String? locale,
    required Future<OverglassDatePick?> Function() fallback,
  }) async {
    if (_isIOS) {
      try {
        final reply = await OverglassChannel.instance.presentDateSheet({
          'title': title,
          'message': message,
          'confirmLabel': confirmLabel,
          'clearLabel': clearLabel,
          'initial': initial.millisecondsSinceEpoch,
          'minimum': minimum?.millisecondsSinceEpoch,
          'mode': mode.name,
          'locale': locale,
        });
        return switch (reply?['action']) {
          'confirm' => OverglassDatePick(DateTime.fromMillisecondsSinceEpoch((reply!['millis']! as num).toInt())),
          'clear' => const OverglassDatePick(null),
          _ => null,
        };
      } on MissingPluginException {
        // No native side: use the fallback below.
      } on PlatformException {
        // Nothing to present from: use the fallback below.
      }
    }
    if (!context.mounted) return null;
    return fallback();
  }

  /// Shows a short message in a capsule at the top of the screen, which goes
  /// away by itself after [duration] or when tapped. On iOS 26 the capsule is
  /// Liquid Glass. iOS has no toast of its own, so this is the package's.
  static Future<void> showToast(
    BuildContext context, {
    required String message,
    String? sfSymbol,
    IconData? icon,
    Color? tint,
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (_isIOS) {
      try {
        final shown = await OverglassChannel.instance.presentToast({
          'message': message,
          'symbol': sfSymbol,
          'tint': tint?.toARGB32(),
          'durationMs': duration.inMilliseconds,
        });
        if (shown) return;
      } on MissingPluginException {
        // No native side: use the Flutter toast below.
      } on PlatformException {
        // Same.
      }
    }
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) =>
          _FallbackToast(message: message, icon: icon, tint: tint, duration: duration, onDone: entry.remove),
    );
    overlay.insert(entry);
  }

  /// Returns the chosen action id, or null if dismissed.
  ///
  /// [fallback] replaces the built-in dialog where UIKit is not available.
  static Future<String?> showAlert(
    BuildContext context, {
    String? title,
    String? message,
    required List<OverglassAlertAction> actions,
    WidgetBuilder? fallback,
  }) => _present(context, style: 'alert', title: title, message: message, actions: actions, fallback: fallback);

  /// Returns the chosen action id, or null if dismissed.
  ///
  /// [anchor] is the point of origin on iPad, in global coordinates.
  static Future<String?> showActionSheet(
    BuildContext context, {
    String? title,
    String? message,
    required List<OverglassAlertAction> actions,
    Rect? anchor,
    WidgetBuilder? fallback,
  }) => _present(
    context,
    style: 'sheet',
    title: title,
    message: message,
    actions: actions,
    anchor: anchor,
    fallback: fallback,
  );

  static Future<String?> _present(
    BuildContext context, {
    required String style,
    String? title,
    String? message,
    required List<OverglassAlertAction> actions,
    Rect? anchor,
    WidgetBuilder? fallback,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        return await OverglassChannel.instance.presentAlert({
          'style': style,
          'title': title,
          'message': message,
          'actions': [for (final action in actions) action.toSpec()],
          if (anchor != null)
            'anchor': {'x': anchor.left, 'y': anchor.top, 'width': anchor.width, 'height': anchor.height},
        });
      } on MissingPluginException {
        // No native side: use the Flutter dialog below.
      } on PlatformException {
        // Nothing to present from: use the Flutter dialog below.
      }
    }
    if (!context.mounted) return null;
    if (fallback != null) {
      return Navigator.of(context, rootNavigator: true).push<String>(
        RawDialogRoute<String>(
          barrierDismissible: false,
          barrierColor: const Color(0x66000000),
          pageBuilder: (context, _, _) => fallback(context),
        ),
      );
    }
    final hasCancel = actions.any((action) => action.style == OverglassAlertActionStyle.cancel);
    return showFallbackChoice<String>(
      context,
      palette: BarPalette(MediaQuery.platformBrightnessOf(context), null),
      title: title,
      message: message,
      barrierDismissible: hasCancel || style == 'sheet',
      choices: [
        for (final action in actions)
          FallbackChoice(
            value: action.id,
            label: action.label,
            destructive: action.style == OverglassAlertActionStyle.destructive,
            cancel: action.style == OverglassAlertActionStyle.cancel,
          ),
      ],
    );
  }
}

class _FallbackToast extends StatefulWidget {
  const _FallbackToast({
    required this.message,
    required this.icon,
    required this.tint,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final IconData? icon;
  final Color? tint;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_FallbackToast> createState() => _FallbackToastState();
}

class _FallbackToastState extends State<_FallbackToast> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    Future<void>.delayed(widget.duration, _hide);
  }

  void _hide() {
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BarPalette(MediaQuery.platformBrightnessOf(context), widget.tint);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          onEnd: () {
            if (!_visible) widget.onDone();
          },
          child: GestureDetector(
            onTap: _hide,
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.solid,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18, color: widget.tint ?? palette.foreground),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.foreground, fontSize: 15, decoration: TextDecoration.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

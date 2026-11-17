import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glyph.dart';
import 'spec.dart';

/// Colors of the Flutter-drawn bars.
class BarPalette {
  BarPalette(Brightness brightness, Color? tint)
    : foreground = brightness == Brightness.dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      muted = brightness == Brightness.dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43),
      fill = brightness == Brightness.dark ? const Color(0xB31C1C1E) : const Color(0xCCF9F9F9),
      solid = brightness == Brightness.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9),
      accent = tint ?? const Color(0xFF007AFF),
      destructive = const Color(0xFFFF3B30);

  final Color foreground;
  final Color muted;
  final Color fill;
  final Color solid;
  final Color accent;
  final Color destructive;
}

class _Frosted extends StatelessWidget {
  const _Frosted({required this.palette, required this.child});

  final BarPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return ColoredBox(color: palette.solid, child: child);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: ColoredBox(color: palette.fill, child: child),
      ),
    );
  }
}

Widget _picture({
  required Color color,
  IconData? icon,
  AssetImage? image,
  OverglassGlyph? glyph,
  required Widget otherwise,
}) {
  if (image != null) return Image(image: image, width: 24, height: 24, color: color);
  if (icon != null) return Icon(icon, color: color, size: 24);
  if (glyph != null) return GlyphIcon(glyph, color: color);
  return otherwise;
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.onTap,
    required this.round,
    required this.palette,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final bool round;
  final BarPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      widthFactor: 1,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: child),
    );
    content = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44, maxHeight: 44),
      child: content,
    );
    if (round) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _Frosted(palette: palette, child: content),
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: content),
    );
  }
}

/// Flutter version of the native top bar. It is used where system glass does
/// not exist, and as a twin while a route covers the scaffold.
class FallbackTopBar extends StatelessWidget {
  const FallbackTopBar({
    super.key,
    required this.bar,
    required this.palette,
    required this.safeTop,
    required this.showBack,
    required this.onBack,
    this.glassLook = false,
  });

  final OverglassTopBar bar;
  final BarPalette palette;
  final double safeTop;
  final bool showBack;
  final VoidCallback onBack;

  /// Keeps the geometry of the iOS 26 bar: floating round buttons, no band.
  final bool glassLook;

  void _press(BuildContext context, OverglassAction action) => pressAction(context, action, palette);

  Widget _action(BuildContext context, OverglassAction action) => _BarButton(
    label: action.label,
    round: glassLook,
    palette: palette,
    onTap: () => _press(context, action),
    child: _picture(
      color: glassLook ? palette.foreground : palette.accent,
      icon: action.icon,
      image: action.image,
      glyph: action.glyph,
      otherwise: Text(
        action.label,
        style: TextStyle(color: glassLook ? palette.foreground : palette.accent, fontSize: 17),
      ),
    ),
  );

  Widget _row(BuildContext context, List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, spacing: glassLook ? 8 : 0, children: children);

  @override
  Widget build(BuildContext context) {
    final leading = [
      if (showBack)
        _BarButton(
          label: 'Back',
          round: glassLook,
          palette: palette,
          onTap: onBack,
          child: GlyphIcon(OverglassGlyph.back, color: glassLook ? palette.foreground : palette.accent),
        ),
      for (final action in bar.leading) _action(context, action),
    ];
    final content = Padding(
      padding: EdgeInsets.only(top: safeTop, left: glassLook ? 16 : 8, right: glassLook ? 16 : 8),
      child: NavigationToolbar(
        leading: _row(context, leading),
        middle: bar.search == null && bar.segments != null
            ? _FallbackSegments(segments: bar.segments!, palette: palette)
            : bar.search != null
            ? _FallbackSearchField(search: bar.search!, palette: palette)
            : bar.title == null
            ? null
            : Text(
                bar.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.foreground, fontSize: 17, fontWeight: FontWeight.w600),
              ),
        trailing: _row(context, [for (final action in bar.trailing) _action(context, action)]),
      ),
    );
    return glassLook ? content : _Frosted(palette: palette, child: content);
  }
}

class _FallbackSegments extends StatelessWidget {
  const _FallbackSegments({required this.segments, required this.palette});

  final OverglassSegments segments;
  final BarPalette palette;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, label) in segments.labels.indexed)
        Semantics(
          button: true,
          selected: index == segments.selectedIndex,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => segments.onChanged(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: index == segments.selectedIndex ? palette.accent : palette.muted,
                  fontWeight: index == segments.selectedIndex ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Flutter version of the native toolbar.
class FallbackToolbar extends StatelessWidget {
  const FallbackToolbar({super.key, required this.toolbar, required this.palette, required this.safeBottom});

  final OverglassToolbar toolbar;
  final BarPalette palette;
  final double safeBottom;

  @override
  Widget build(BuildContext context) => _Frosted(
    palette: palette,
    child: Padding(
      padding: EdgeInsets.only(left: 8, right: 8, bottom: safeBottom),
      child: Row(
        children: [
          for (final item in toolbar.items)
            if (item.action case final action?)
              _BarButton(
                label: action.label,
                round: false,
                palette: palette,
                onTap: () => pressAction(context, action, palette),
                child: _picture(
                  color: palette.accent,
                  icon: action.icon,
                  image: action.image,
                  glyph: action.glyph,
                  otherwise: Text(action.label, style: TextStyle(color: palette.accent, fontSize: 17)),
                ),
              )
            else
              const Spacer(),
        ],
      ),
    ),
  );
}

class _FallbackSearchField extends StatefulWidget {
  const _FallbackSearchField({required this.search, required this.palette});

  final OverglassSearch search;
  final BarPalette palette;

  @override
  State<_FallbackSearchField> createState() => _FallbackSearchFieldState();
}

class _FallbackSearchFieldState extends State<_FallbackSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = TextStyle(color: palette.foreground, fontSize: 16);
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: palette.muted.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) => value.text.isEmpty
                ? ExcludeSemantics(
                    child: Text(widget.search.placeholder ?? '', style: style.copyWith(color: palette.muted)),
                  )
                : const SizedBox.shrink(),
          ),
          Semantics(
            textField: true,
            label: widget.search.placeholder,
            child: EditableText(
              controller: _controller,
              focusNode: _focus,
              style: style,
              cursorColor: palette.accent,
              backgroundCursorColor: palette.muted,
              textInputAction: TextInputAction.search,
              onChanged: widget.search.onChanged,
              onSubmitted: widget.search.onSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flutter version of the native tab bar.
class FallbackTabBar extends StatelessWidget {
  const FallbackTabBar({
    super.key,
    required this.bar,
    required this.palette,
    required this.safeBottom,
    this.capsule = false,
  });

  final OverglassTabBar bar;
  final BarPalette palette;
  final double safeBottom;

  /// Draws the floating iOS 26 capsule; the parent sizes it.
  final bool capsule;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.only(bottom: capsule ? 0 : safeBottom),
      child: Row(children: [for (final (index, tab) in bar.items.indexed) Expanded(child: _tab(index, tab))]),
    );
    if (!capsule) return _Frosted(palette: palette, child: row);
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: _Frosted(palette: palette, child: row),
    );
  }

  Widget _tab(int index, OverglassTab tab) {
    final selected = index == bar.currentIndex;
    final color = selected ? palette.accent : palette.muted;
    final badge = tab.badge;
    Widget picture = _picture(color: color, icon: tab.icon, image: tab.image, otherwise: const SizedBox(height: 24));
    if (badge != null) {
      picture = Stack(
        clipBehavior: Clip.none,
        children: [
          picture,
          Positioned(
            top: -4,
            left: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(color: palette.destructive, borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Text(badge, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 10)),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? tab.label : '${tab.label}, $badge',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => bar.onChanged(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            picture,
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs an action, opening its menu with the Flutter dialog when it has one.
void pressAction(BuildContext context, OverglassAction action, BarPalette palette) {
  final menu = action.menu;
  if (menu == null) {
    action.onPressed?.call();
    return;
  }
  showFallbackChoice<OverglassMenuItem>(
    context,
    palette: palette,
    title: menu.title,
    choices: [
      for (final item in menu.items) FallbackChoice(value: item, label: item.label, destructive: item.destructive),
    ],
  ).then((item) => item?.onSelected());
}

/// One option of [showFallbackChoice].
class FallbackChoice<T> {
  const FallbackChoice({required this.value, required this.label, this.destructive = false, this.cancel = false});

  final T value;
  final String label;
  final bool destructive;
  final bool cancel;
}

/// Minimal Flutter-drawn dialog behind menus, alerts and action sheets.
Future<T?> showFallbackChoice<T>(
  BuildContext context, {
  required BarPalette palette,
  required List<FallbackChoice<T>> choices,
  String? title,
  String? message,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    RawDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierColor: const Color(0x66000000),
      barrierLabel: 'Dismiss',
      pageBuilder: (context, _, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: palette.solid,
              child: DefaultTextStyle(
                style: TextStyle(color: palette.foreground, fontSize: 15, decoration: TextDecoration.none),
                textAlign: TextAlign.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    if (message != null)
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(message)),
                    for (final choice in choices)
                      Semantics(
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(choice.cancel ? null : choice.value),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              choice.label,
                              style: TextStyle(
                                fontSize: 17,
                                color: choice.destructive ? palette.destructive : palette.accent,
                                fontWeight: choice.cancel ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'alerts.dart';
import 'fallback.dart';

/// System controls placed inside Flutter content.
///
/// Unlike the bars, these are platform views on iOS: each one is a real UIKit
/// control laid out by Flutter. Elsewhere they are drawn by Flutter.
bool get _useNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

const _viewType = 'dev.overglass/control';

/// How an [OverglassButton] is filled.
enum OverglassButtonStyle {
  /// Liquid Glass on iOS 26, gray capsule before.
  glass,

  /// Tinted glass on iOS 26, filled capsule before.
  prominent,

  /// Text and symbol only.
  plain,
}

/// Size of an [OverglassButton], as UIKit defines it.
enum OverglassButtonSize { small, medium, large }

/// A system button: `UIButton` with the glass configurations on iOS 26.
class OverglassButton extends StatelessWidget {
  const OverglassButton({
    super.key,
    required this.label,
    this.sfSymbol,
    this.icon,
    this.style = OverglassButtonStyle.glass,
    this.size = OverglassButtonSize.medium,
    this.destructive = false,
    this.tint,
    this.expand = false,
    required this.onPressed,
  });

  final String label;
  final String? sfSymbol;

  /// Used where the button is drawn by Flutter.
  final IconData? icon;
  final OverglassButtonStyle style;
  final OverglassButtonSize size;
  final bool destructive;
  final Color? tint;

  /// Takes all the width the layout offers.
  final bool expand;

  /// Null disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (_useNative) {
      return _NativeControl(
        kind: 'button',
        params: {
          'label': label,
          'symbol': sfSymbol,
          'style': style.name,
          'size': size.name,
          'destructive': destructive,
          'tint': tint?.toARGB32(),
          'enabled': onPressed != null,
        },
        // A guess until UIKit measures the button, so that a Row can lay it out.
        fallbackSize: Size(expand ? 0 : label.length * 9.0 + (sfSymbol == null ? 40 : 64), _heights[size]!),
        expand: expand,
        onEvent: (method, _) {
          if (method == 'pressed') onPressed?.call();
        },
      );
    }
    final palette = BarPalette(MediaQuery.platformBrightnessOf(context), tint);
    final color = destructive ? palette.destructive : palette.accent;
    final filled = style == OverglassButtonStyle.prominent;
    final foreground = filled ? const Color(0xFFFFFFFF) : color;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: foreground), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: Container(
            height: _heights[size],
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: switch (style) {
                OverglassButtonStyle.prominent => color,
                OverglassButtonStyle.glass => palette.fill,
                OverglassButtonStyle.plain => const Color(0x00000000),
              },
              borderRadius: BorderRadius.circular(_heights[size]! / 2),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  static const _heights = {
    OverglassButtonSize.small: 34.0,
    OverglassButtonSize.medium: 44.0,
    OverglassButtonSize.large: 52.0,
  };
}

/// A system switch: `UISwitch`.
class OverglassSwitch extends StatelessWidget {
  const OverglassSwitch({super.key, required this.value, required this.onChanged, this.tint, this.semanticLabel});

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Color of the track when on.
  final Color? tint;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (_useNative) {
      return _NativeControl(
        kind: 'switch',
        params: {
          'value': value,
          'tint': tint?.toARGB32(),
          'enabled': onChanged != null,
          'semanticLabel': semanticLabel,
        },
        fallbackSize: const Size(51, 31),
        bleed: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        // Hands the touch to UIKit at once, so the thumb follows the finger
        // instead of waiting for Flutter to give up the gesture on release.
        gestures: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
        onEvent: (method, args) {
          if (method == 'changed') onChanged?.call(args['value']! as bool);
        },
      );
    }
    final on = tint ?? const Color(0xFF34C759);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Opacity(
          opacity: onChanged == null ? 0.4 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 51,
            height: 31,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? on : const Color(0x29787880),
              borderRadius: BorderRadius.circular(15.5),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: const _Thumb(size: 27),
            ),
          ),
        ),
      ),
    );
  }
}

/// A system slider: `UISlider`. It takes all the width the layout offers.
class OverglassSlider extends StatelessWidget {
  const OverglassSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onChanged,
    this.onChangeEnd,
    this.tint,
    this.semanticLabel,
  }) : assert(min < max);

  final double value;
  final double min;
  final double max;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? tint;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (_useNative) {
      return _NativeControl(
        kind: 'slider',
        params: {
          'value': value,
          'min': min,
          'max': max,
          'tint': tint?.toARGB32(),
          'enabled': onChanged != null,
          'semanticLabel': semanticLabel,
        },
        fallbackSize: const Size(0, 34),
        expand: true,
        // Horizontal drags move the thumb; vertical ones still scroll.
        gestures: {Factory<OneSequenceGestureRecognizer>(HorizontalDragGestureRecognizer.new)},
        onEvent: (method, args) {
          final next = (args['value']! as num).toDouble();
          if (method == 'changed') onChanged?.call(next);
          if (method == 'ended') onChangeEnd?.call(next);
        },
      );
    }
    final palette = BarPalette(MediaQuery.platformBrightnessOf(context), tint);
    final step = (max - min) / 10;
    double clamp(double next) => next.clamp(min, max).toDouble();
    return Semantics(
      slider: true,
      enabled: onChanged != null,
      label: semanticLabel,
      value: '${((value - min) / (max - min) * 100).round()}%',
      onIncrease: onChanged == null ? null : () => onChanged!(clamp(value + step)),
      onDecrease: onChanged == null ? null : () => onChanged!(clamp(value - step)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const thumb = 28.0;
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
          final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
          double at(double dx) => clamp(min + (dx - thumb / 2) / (width - thumb) * (max - min));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onChanged == null ? null : (details) => onChanged!(at(details.localPosition.dx)),
            onHorizontalDragUpdate: onChanged == null ? null : (details) => onChanged!(at(details.localPosition.dx)),
            onHorizontalDragEnd: onChangeEnd == null ? null : (_) => onChangeEnd!(value),
            child: SizedBox(
              width: width,
              height: 34,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: thumb / 2),
                    decoration: BoxDecoration(color: const Color(0x29787880), borderRadius: BorderRadius.circular(2)),
                  ),
                  Container(
                    height: 4,
                    width: thumb / 2 + fraction * (width - thumb),
                    margin: const EdgeInsets.only(left: thumb / 2),
                    decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                  Positioned(
                    left: fraction * (width - thumb),
                    child: const _Thumb(size: thumb),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The system's compact date picker: `UIDatePicker`. Tapping it opens the
/// calendar or the time wheels in a system popover.
class OverglassDatePicker extends StatelessWidget {
  const OverglassDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.mode = OverglassDateMode.date,
    this.minimum,
    this.maximum,
    this.locale,
    this.tint,
    required this.fallback,
  });

  final DateTime value;

  /// Null disables the picker.
  final ValueChanged<DateTime>? onChanged;
  final OverglassDateMode mode;
  final DateTime? minimum;
  final DateTime? maximum;

  /// A language tag such as `it` for the picker's labels.
  final String? locale;
  final Color? tint;

  /// The app's own picker where UIKit is not available.
  final WidgetBuilder fallback;

  @override
  Widget build(BuildContext context) {
    if (!_useNative) return fallback(context);
    return _NativeControl(
      kind: 'date',
      params: {
        'value': value.millisecondsSinceEpoch,
        'mode': mode.name,
        'minimum': minimum?.millisecondsSinceEpoch,
        'maximum': maximum?.millisecondsSinceEpoch,
        'locale': locale,
        'tint': tint?.toARGB32(),
        'enabled': onChanged != null,
      },
      fallbackSize: const Size(120, 34),
      onEvent: (method, args) {
        if (method == 'changed') {
          onChanged?.call(DateTime.fromMillisecondsSinceEpoch((args['millis']! as num).toInt()));
        }
      },
    );
  }
}

/// Shape of an [OverglassGauge].
enum OverglassGaugeStyle {
  /// A small ring with the value in the middle.
  circular,

  /// A capacity bar as wide as the layout allows.
  linear,
}

/// The system gauge: SwiftUI `Gauge` on iOS 16 and later, a progress bar
/// before.
class OverglassGauge extends StatelessWidget {
  const OverglassGauge({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.style = OverglassGaugeStyle.circular,
    this.label,
    this.valueLabel,
    this.tint,
  }) : assert(min < max);

  final double value;
  final double min;
  final double max;
  final OverglassGaugeStyle style;

  /// What is measured, read by VoiceOver.
  final String? label;

  /// Text shown inside a circular gauge, such as `72%`.
  final String? valueLabel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final circular = style == OverglassGaugeStyle.circular;
    if (_useNative) {
      return _NativeControl(
        kind: 'gauge',
        params: {
          'value': value,
          'min': min,
          'max': max,
          'style': style.name,
          'label': label,
          'valueLabel': valueLabel,
          'tint': tint?.toARGB32(),
        },
        fallbackSize: circular ? const Size(58, 58) : const Size(0, 14),
        expand: !circular,
      );
    }
    final palette = BarPalette(MediaQuery.platformBrightnessOf(context), tint);
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: valueLabel ?? '${(fraction * 100).round()}%',
      child: circular
          ? SizedBox.square(
              dimension: 58,
              child: CustomPaint(
                painter: _RingPainter(fraction: fraction, color: palette.accent),
                child: Center(
                  child: Text(
                    valueLabel ?? '',
                    style: TextStyle(color: palette.foreground, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 14,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: const Color(0x29787880), borderRadius: BorderRadius.circular(3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0xFFFFFFFF),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 4, offset: Offset(0, 2))],
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    const sweep = 1.5 * math.pi;
    const start = 0.75 * math.pi;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, paint..color = const Color(0x29787880));
    if (fraction > 0) canvas.drawArc(rect, start, sweep * fraction, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}

/// Hosts one native control and keeps it in sync with its description.
class _NativeControl extends StatefulWidget {
  const _NativeControl({
    required this.kind,
    required this.params,
    required this.fallbackSize,
    this.expand = false,
    this.gestures = const <Factory<OneSequenceGestureRecognizer>>{},
    this.onEvent,
    this.bleed = EdgeInsets.zero,
  });

  /// Room around the control that its native view may draw into without
  /// taking space in the layout or receiving touches.
  final EdgeInsets bleed;

  final String kind;
  final Map<String, Object?> params;

  /// Used until the control reports the size it needs. A width of 0 expands.
  final Size fallbackSize;
  final bool expand;
  final Set<Factory<OneSequenceGestureRecognizer>> gestures;
  final void Function(String method, Map<String, Object?> args)? onEvent;

  @override
  State<_NativeControl> createState() => _NativeControlState();
}

class _NativeControlState extends State<_NativeControl> {
  MethodChannel? _channel;
  Size? _size;

  Map<String, Object?> get _payload => {'kind': widget.kind, ...widget.params};

  void _created(int id) {
    _channel = MethodChannel('$_viewType/$id')..setMethodCallHandler(_handle);
    _push();
  }

  Future<void> _push() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      final reply = await channel.invokeMapMethod<String, Object?>('update', _payload);
      if (!mounted || reply == null || reply.isEmpty) return;
      final size = Size((reply['width']! as num).toDouble(), (reply['height']! as num).toDouble());
      if (size != _size) setState(() => _size = size);
    } on MissingPluginException {
      // The view went away before the reply.
    } on PlatformException {
      // Same.
    }
  }

  Future<void> _handle(MethodCall call) async {
    final before = widget.params;
    widget.onEvent?.call(call.method, (call.arguments as Map?)?.cast<String, Object?>() ?? const {});
    // A control the app does not update must go back to the app's value. When
    // the app did update it, didUpdateWidget has already sent the new value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && mapEquals(before, widget.params)) _push();
    });
  }

  @override
  void didUpdateWidget(_NativeControl old) {
    super.didUpdateWidget(old);
    if (!mapEquals(old.params, widget.params)) _push();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size ?? widget.fallbackSize;
    final height = size.height > 0 ? size.height : widget.fallbackSize.height;
    final width = widget.expand
        ? double.infinity
        : size.width > 0
        ? size.width
        : widget.fallbackSize.width > 0
        ? widget.fallbackSize.width
        : double.infinity;
    final view = UiKitView(
      viewType: _viewType,
      creationParams: _payload,
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: widget.gestures,
      onPlatformViewCreated: _created,
    );
    if (widget.bleed == EdgeInsets.zero) return SizedBox(width: width, height: height, child: view);
    // The native view is larger than the layout slot and centered on it.
    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        maxWidth: width + widget.bleed.horizontal,
        maxHeight: height + widget.bleed.vertical,
        child: SizedBox(width: width + widget.bleed.horizontal, height: height + widget.bleed.vertical, child: view),
      ),
    );
  }
}

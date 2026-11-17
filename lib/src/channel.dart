import 'dart:async';
import 'dart:ui' show PlatformDispatcher, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Route;

/// Height of the native bars measured from the window edges.
class OverglassMetrics {
  const OverglassMetrics(this.top, this.bottom, this.tabCapsule, {this.left = 0});

  final double top;
  final double bottom;

  /// Room taken by the iPad sidebar on the leading edge.
  final double left;

  /// Frame of the floating tab bar capsule, in window coordinates.
  final Rect? tabCapsule;
}

/// Callbacks delivered from the native chrome host to one scaffold.
abstract class OverglassEvents {
  void onTabSelected(int index, int tapSeq);
  void onActionPressed(String id);
  void onMenuSelected(String actionId, int item);
  void onBackPressed();
  void onSegmentSelected(int index);
  void onAccessoryPressed();
  void onSearchChanged(String text);
  void onSearchSubmitted(String text);
  void onMetrics(OverglassMetrics metrics);
  void onAttached();
}

/// Native contract, keyed by session so scaffolds cannot disturb each other.
class OverglassChannel {
  OverglassChannel._() {
    _channel.setMethodCallHandler(_handle);
  }

  static final OverglassChannel instance = OverglassChannel._();
  static const String _name = 'dev.overglass/chrome';
  static const MethodChannel _channel = MethodChannel(_name);

  final Map<int, OverglassEvents> _sessions = {};
  final Map<int, Route<Object?>> _visibleRoutes = {};
  int _nextId = 0;
  bool? _knownGlass;

  /// Lets a new scaffold lay out its body before its own metrics arrive.
  OverglassMetrics? lastMetrics;

  /// Runs before `main`, on every start and hot restart, and discards bars
  /// left by a previous run. It needs no binding, unlike [MethodChannel].
  static void sendReset() {
    PlatformDispatcher.instance.sendPlatformMessage(
      _name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('reset')),
      null,
    );
  }

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The answer, if it is available without asking the platform.
  bool? get knownNativeGlass => _isIOS ? _knownGlass : false;

  Future<bool> resolveNativeGlass() async {
    final known = knownNativeGlass;
    if (known != null) return known;
    var supported = false;
    try {
      final caps = await _channel.invokeMapMethod<String, Object?>('capabilities');
      supported = caps?['nativeGlass'] == true;
    } on MissingPluginException {
      supported = false;
    } on PlatformException {
      supported = false;
    }
    return _knownGlass = supported;
  }

  int register(OverglassEvents owner) {
    final id = _nextId++;
    _sessions[id] = owner;
    return id;
  }

  void release(int id, {required bool notifyNative}) {
    _sessions.remove(id);
    _visibleRoutes.remove(id);
    if (notifyNative) _safe(_channel.invokeMethod<void>('release', {'session': id}));
  }

  /// Returns whether the native bars are attached to a view.
  Future<bool> apply(int id, Map<String, Object?> spec) async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('apply', {'session': id, ...spec});
      return reply?['attached'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns the chosen action id, or null when dismissed.
  /// Throws [MissingPluginException] where there is no native side.
  Future<String?> presentAlert(Map<String, Object?> spec) => _channel.invokeMethod<String>('alert', spec);

  /// Returns the index of the chosen item, or null when dismissed.
  Future<int?> presentContextMenu(Map<String, Object?> spec) => _channel.invokeMethod<int>('contextMenu', spec);

  /// Returns the chosen action id, or null when dismissed.
  Future<String?> presentPopover(Map<String, Object?> spec) => _channel.invokeMethod<String>('popover', spec);

  /// Returns the result given to the sheet's close, or null when swiped away.
  Future<String?> presentSheet(Map<String, Object?> spec) => _channel.invokeMethod<String>('sheet', spec);

  /// Returns the picked item id, or null when dismissed.
  Future<String?> presentChoiceSheet(Map<String, Object?> spec) => _channel.invokeMethod<String>('choiceSheet', spec);

  /// Returns {action: confirm, millis} or {action: clear}, or null when dismissed.
  Future<Map<String, Object?>?> presentDateSheet(Map<String, Object?> spec) =>
      _channel.invokeMapMethod<String, Object?>('dateSheet', spec);

  /// Returns whether the native toast was shown.
  Future<bool> presentToast(Map<String, Object?> spec) async =>
      await _channel.invokeMethod<bool>('toast', spec) ?? false;

  /// Returns whether a native sheet was closed.
  Future<bool> closeSheet(String? result) async {
    try {
      return await _channel.invokeMethod<bool>('sheetClose', {'result': result}) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Debug check of the one-visible-scaffold-per-route rule.
  bool debugClaimRoute(int id, Route<Object?>? route, {required bool visible}) {
    _visibleRoutes.remove(id);
    if (route == null || !visible) return true;
    final clash = _visibleRoutes.values.any((other) => identical(other, route));
    _visibleRoutes[id] = route;
    return !clash;
  }

  /// Drops a scaffold's claim as soon as it leaves the tree: it is disposed
  /// only at the end of the frame, after its replacement has already built.
  void debugReleaseRoute(int id) => _visibleRoutes.remove(id);

  @visibleForTesting
  void debugReset() {
    _sessions.clear();
    _visibleRoutes.clear();
    _knownGlass = null;
    lastMetrics = null;
  }

  Future<void> _handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final owner = _sessions[args['session']];
    if (owner == null) return;
    switch (call.method) {
      case 'tabSelected':
        owner.onTabSelected(args['index']! as int, args['tapSeq']! as int);
      case 'actionPressed':
        owner.onActionPressed(args['id']! as String);
      case 'menuSelected':
        owner.onMenuSelected(args['action']! as String, args['item']! as int);
      case 'backPressed':
        owner.onBackPressed();
      case 'segmentSelected':
        owner.onSegmentSelected(args['index']! as int);
      case 'accessoryPressed':
        owner.onAccessoryPressed();
      case 'searchChanged':
        owner.onSearchChanged(args['text']! as String);
      case 'searchSubmitted':
        owner.onSearchSubmitted(args['text']! as String);
      case 'attached':
        owner.onAttached();
      case 'metrics':
        final capsule = (args['tabCapsule'] as Map?)?.cast<String, Object?>();
        final metrics = OverglassMetrics(
          (args['top']! as num).toDouble(),
          (args['bottom']! as num).toDouble(),
          capsule == null
              ? null
              : Rect.fromLTWH(
                  (capsule['x']! as num).toDouble(),
                  (capsule['y']! as num).toDouble(),
                  (capsule['width']! as num).toDouble(),
                  (capsule['height']! as num).toDouble(),
                ),
          left: (args['left'] as num?)?.toDouble() ?? 0,
        );
        lastMetrics = metrics;
        owner.onMetrics(metrics);
    }
  }

  static void _safe(Future<void> call) {
    unawaited(call.catchError((Object _) {}));
  }
}

/// Entry point the Flutter tool runs before `main` on iOS.
class OverglassDartPlugin {
  static void registerWith() => OverglassChannel.sendReset();
}

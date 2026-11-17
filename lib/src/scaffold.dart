import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'channel.dart';
import 'cover.dart';
import 'fallback.dart';
import 'spec.dart';

/// Builds an app-provided bar where system glass does not exist.
typedef OverglassFallbackBuilder<B> = Widget Function(BuildContext context, B bar);

enum _Presentation { native, scrim, passive, fade, twin }

/// Screen structure whose bars are real system controls where the OS has
/// Liquid Glass, and Flutter-drawn everywhere else.
///
/// [body] receives the bar heights through `MediaQuery.padding`, so scrolling
/// content runs underneath the glass. A route may show one scaffold at a time.
class OverglassScaffold extends StatefulWidget {
  const OverglassScaffold({
    super.key,
    required this.body,
    this.topBar,
    this.tabBar,
    this.brightness,
    this.tint,
    this.backgroundColor,
    this.coverPolicy = defaultCoverPolicy,
    this.fallbackTopBarBuilder,
    this.fallbackTopBarHeight,
    this.fallbackTabBarBuilder,
    this.fallbackTabBarHeight,
    this.toolbar,
  }) : assert(toolbar == null || tabBar == null, 'A screen has a tab bar or a toolbar, not both.');

  /// A bottom toolbar, for screens without a tab bar.
  final OverglassToolbar? toolbar;

  final Widget body;
  final OverglassTopBar? topBar;
  final OverglassTabBar? tabBar;

  /// Defaults to the platform brightness.
  final Brightness? brightness;

  /// Accent of selected and interactive bar items.
  final Color? tint;

  final Color? backgroundColor;

  /// What the bars do while another route covers this scaffold.
  final OverglassCoverPolicy coverPolicy;

  /// Replaces the built-in top bar where system glass does not exist.
  final OverglassFallbackBuilder<OverglassTopBar>? fallbackTopBarBuilder;

  /// Height below the safe area taken by [fallbackTopBarBuilder].
  final double? fallbackTopBarHeight;

  /// Replaces the built-in tab bar where system glass does not exist.
  final OverglassFallbackBuilder<OverglassTabBar>? fallbackTabBarBuilder;

  /// Height above the safe area taken by [fallbackTabBarBuilder].
  final double? fallbackTabBarHeight;

  @override
  State<OverglassScaffold> createState() => _OverglassScaffoldState();
}

class _OverglassScaffoldState extends State<OverglassScaffold> with WidgetsBindingObserver implements OverglassEvents {
  static const double _fallbackTopHeight = 44;
  static const double _fallbackTabHeight = 50;

  final OverglassChannel _channel = OverglassChannel.instance;
  late final int _session = _channel.register(this);

  bool? _nativeGlass;

  /// Null until the native side answers; false shows the Flutter bars.
  bool? _attached;
  OverglassMetrics? _metrics;
  String? _lastPayload;
  int _ackTap = 0;
  bool _bodyScrolled = false;
  bool _bodyScrollable = false;
  double _pinnedTop = 0;
  ModalRoute<Object?>? _route;
  int _fadeMs = 0;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session; // Registers before any native event can arrive.
    _nativeGlass = _channel.knownNativeGlass;
    if (_nativeGlass == null) unawaited(_resolveCapabilities());
  }

  Future<void> _resolveCapabilities() async {
    final supported = await _channel.resolveNativeGlass();
    if (mounted) setState(() => _nativeGlass = supported);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_onRouteStatus);
      _animation = animation?..addStatusListener(_onRouteStatus);
    }
  }

  /// A popped route is no longer told about changes to `isCurrent`, so its
  /// animation is the only early sign that it is leaving.
  void _onRouteStatus(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resync();
  }

  Route<Object?>? _topRoute(ModalRoute<Object?> route) {
    Route<Object?>? top;
    // The predicate accepts the first route it sees, so nothing is popped.
    route.navigator?.popUntil((candidate) {
      top = candidate;
      return true;
    });
    return top;
  }

  _Presentation get _presentation {
    final route = _route;
    // Native bars never travel with a page: as on iOS they stay in place and
    // only their content changes, so a page in transition needs no stand-in.
    if (route is TransitionRoute && _animation?.status == AnimationStatus.reverse) {
      _fadeMs = (route as TransitionRoute<Object?>).reverseTransitionDuration.inMilliseconds;
      return _Presentation.fade;
    }
    if (route == null || route.isCurrent) return _Presentation.native;
    final top = _topRoute(route);
    if (top == null || identical(top, route)) return _Presentation.fade;
    if (top is TransitionRoute) _fadeMs = top.transitionDuration.inMilliseconds;
    return switch (widget.coverPolicy(top)) {
      OverglassCover.scrim => _Presentation.scrim,
      OverglassCover.passive => _Presentation.passive,
      OverglassCover.fade => _Presentation.fade,
      OverglassCover.twin => _Presentation.twin,
    };
  }

  Brightness get _brightness => widget.brightness ?? MediaQuery.platformBrightnessOf(context);

  bool get _showBack => widget.topBar?.showBack ?? (_route?.canPop ?? false);

  Map<String, Object?>? _scrimSpec(_Presentation presentation) {
    if (presentation != _Presentation.scrim) return null;
    final covering = _route == null ? null : _topRoute(_route!);
    return {
      'color': (covering is ModalRoute ? covering.barrierColor : null)?.toARGB32() ?? 0x8A000000,
      'durationMs': (covering is TransitionRoute ? covering.transitionDuration : Duration.zero).inMilliseconds,
    };
  }

  void _scheduleSync(_Presentation presentation) {
    final visible = presentation != _Presentation.twin && presentation != _Presentation.fade;
    assert(
      _channel.debugClaimRoute(_session, _route, visible: visible),
      'Only one OverglassScaffold can be visible in a route.',
    );
    final payload = jsonEncode({
      'visible': visible,
      'interactive': presentation == _Presentation.native,
      'fadeMs': _fadeMs,
      'style': _brightness.name,
      'tint': widget.tint?.toARGB32(),
      'ackTap': _ackTap,
      'scrim': _scrimSpec(presentation),
      'topBar': widget.topBar?.toSpec(back: _showBack, collapsed: _bodyScrolled),
      'tabBar': widget.tabBar == null
          ? null
          : {...widget.tabBar!.toSpec(), 'scrollable': _bodyScrollable, 'atTop': !_bodyScrolled},
      'toolbar': widget.toolbar?.toSpec(),
      'width': MediaQuery.sizeOf(context).width.round(),
    });
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || payload != _lastPayload) return;
      final attached = await _channel.apply(_session, (jsonDecode(payload) as Map).cast<String, Object?>());
      if (mounted && attached != _attached) setState(() => _attached = attached);
    });
  }

  void _resync() {
    if (!mounted) return;
    _lastPayload = null;
    setState(() {});
  }

  void _goBack() {
    final onBack = widget.topBar?.onBack;
    if (onBack != null) {
      onBack();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  OverglassAction? _action(String id) {
    for (final action in [...?widget.topBar?.actions, ...?widget.toolbar?.actions]) {
      if (action.id == id) return action;
    }
    return null;
  }

  @override
  void onTabSelected(int index, int tapSeq) {
    _ackTap = tapSeq;
    widget.tabBar?.onChanged(index);
    // A parent may reject a selection, so the native bar must be re-asserted.
    _resync();
  }

  @override
  void onActionPressed(String id) => _action(id)?.onPressed?.call();

  @override
  void onMenuSelected(String actionId, int item) {
    final items = _action(actionId)?.menu?.items;
    if (items != null && item < items.length) items[item].onSelected();
  }

  @override
  void onBackPressed() => _goBack();

  @override
  void onSegmentSelected(int index) {
    widget.topBar?.segments?.onChanged(index);
    _resync();
  }

  @override
  void onAccessoryPressed() => widget.tabBar?.accessory?.onPressed?.call();

  @override
  void onSearchChanged(String text) => widget.topBar?.search?.onChanged?.call(text);

  @override
  void onSearchSubmitted(String text) => widget.topBar?.search?.onSubmitted?.call(text);

  @override
  void onMetrics(OverglassMetrics metrics) {
    if (mounted) setState(() => _metrics = metrics);
  }

  @override
  void onAttached() {
    if (!mounted) return;
    _lastPayload = null;
    setState(() => _attached = true);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.extentBefore > 0;
      if (scrolled != _bodyScrolled) setState(() => _bodyScrolled = scrolled);
      _noteScrollable(notification.metrics);
    }
    return false;
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) _noteScrollable(notification.metrics);
    return false;
  }

  /// Minimize on scroll follows the finger only where the body can scroll.
  void _noteScrollable(ScrollMetrics metrics) {
    final scrollable = metrics.maxScrollExtent > metrics.minScrollExtent;
    if (scrollable != _bodyScrollable && widget.tabBar?.minimizeOnScroll == true) {
      setState(() => _bodyScrollable = scrollable);
    }
  }

  @override
  void deactivate() {
    // A replacement scaffold may build in this same frame; if this one is
    // reinserted instead, its next build claims the route again.
    assert(() {
      _channel.debugReleaseRoute(_session);
      return true;
    }());
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation?.removeStatusListener(_onRouteStatus);
    _channel.release(_session, notifyNative: _nativeGlass == true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final presentation = _presentation;
    final glass = _nativeGlass == true;
    final native = glass && _attached != false;
    final showNative = native && presentation != _Presentation.twin;
    final showFlutter = _nativeGlass != null && !showNative;
    if (glass) _scheduleSync(presentation);

    final topBar = widget.topBar;
    final tabBar = widget.tabBar;
    final customTop = !glass ? widget.fallbackTopBarBuilder : null;
    final customTab = !glass ? widget.fallbackTabBarBuilder : null;
    final metrics = native ? (_metrics ?? _channel.lastMetrics) : null;
    // Collapsing a large title must not move content the user is scrolling.
    if (metrics != null && topBar?.largeTitle == true && metrics.top > _pinnedTop) _pinnedTop = metrics.top;
    final top = topBar?.largeTitle == true && native && _pinnedTop > 0
        ? _pinnedTop
        : topBar == null
        ? media.padding.top
        : ((metrics?.top ?? 0) > 0
              ? metrics!.top
              : media.padding.top + ((customTop != null ? widget.fallbackTopBarHeight : null) ?? _fallbackTopHeight));
    final nativeBottomSearch = native && topBar?.search?.placement == OverglassSearchPlacement.bottom;
    final bottom = tabBar == null && widget.toolbar == null && !nativeBottomSearch
        ? media.padding.bottom
        : ((metrics?.bottom ?? 0) > 0
              ? metrics!.bottom
              : media.padding.bottom +
                    ((customTab != null ? widget.fallbackTabBarHeight : null) ?? _fallbackTabHeight));

    // With the keyboard up the tab bar is hidden behind it, and Flutter
    // already reports the bottom inset through viewInsets.
    final keyboardUp = media.viewInsets.bottom > 0;
    // A bottom search field rises with the keyboard, and its metrics say so.
    final bodyBottom = keyboardUp && !nativeBottomSearch ? media.padding.bottom : bottom;

    // The iPad sidebar covers the leading edge of the body.
    final left = math.max(media.padding.left, metrics?.left ?? 0);

    final dark = _brightness == Brightness.dark;
    final background = widget.backgroundColor ?? (dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7));
    final palette = BarPalette(_brightness, widget.tint);
    final capsule = metrics?.tabCapsule;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(top: top, bottom: bodyBottom, left: left),
                viewPadding: media.viewPadding.copyWith(top: top, bottom: bottom, left: left),
              ),
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onScrollMetrics,
                child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
              ),
            ),
            // A Flutter body has no UIScrollView, so UIKit cannot draw its scroll
            // edge effect. This keeps a bare native title legible over content.
            if (glass && topBar != null && _bodyScrolled)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top + 16,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          background.withValues(alpha: 0.94),
                          background.withValues(alpha: 0.86),
                          background.withValues(alpha: 0.62),
                          background.withValues(alpha: 0.24),
                          background.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.45, 0.7, 0.88, 1],
                      ),
                    ),
                  ),
                ),
              ),
            if (showFlutter && topBar != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top,
                child: customTop != null
                    ? customTop(context, topBar)
                    : FallbackTopBar(
                        bar: topBar,
                        palette: palette,
                        safeTop: media.padding.top,
                        showBack: _showBack,
                        onBack: _goBack,
                        glassLook: glass,
                      ),
              ),
            if (showFlutter && widget.toolbar != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: bottom,
                child: FallbackToolbar(toolbar: widget.toolbar!, palette: palette, safeBottom: media.padding.bottom),
              ),
            if (showFlutter && tabBar != null)
              if (capsule != null)
                Positioned.fromRect(
                  rect: capsule,
                  child: FallbackTabBar(bar: tabBar, palette: palette, safeBottom: 0, capsule: true),
                )
              else
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: bottom,
                  child: customTab != null
                      ? customTab(context, tabBar)
                      : FallbackTabBar(bar: tabBar, palette: palette, safeBottom: media.padding.bottom),
                ),
          ],
        ),
      ),
    );
  }
}

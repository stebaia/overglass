import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overglass/overglass.dart';
import 'package:overglass/src/channel.dart';

const _channel = MethodChannel('dev.overglass/chrome');
const _icon = IconData(0xe000);

class _Harness {
  final calls = <MethodCall>[];
  bool nativeGlass = true;
  bool attached = true;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'capabilities' => {'nativeGlass': nativeGlass},
        'apply' => {'attached': attached},
        'alert' => 'ok',
        'contextMenu' => 0,
        'popover' => 'yes',
        'sheet' => 'done',
        'sheetClose' => true,
        _ => null,
      };
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  }

  Iterable<Map<Object?, Object?>> get applies =>
      calls.where((c) => c.method == 'apply').map((c) => c.arguments as Map<Object?, Object?>);

  Map<Object?, Object?> get lastApply => applies.last;

  Future<void> send(WidgetTester tester, String method, Map<String, Object?> arguments) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await tester.pump();
  }
}

Widget _app(Widget home, {MediaQueryData? media}) => MediaQuery(
  data: media ?? const MediaQueryData(size: Size(400, 800)),
  child: WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(settings, builder) =>
        PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
    home: home,
  ),
);

OverglassScaffold _scaffold(
  ValueChanged<int> onChanged, {
  int index = 0,
  VoidCallback? onAction,
  String first = 'One',
  Widget body = const SizedBox.expand(),
  OverglassFallbackBuilder<OverglassTabBar>? tabBuilder,
  OverglassCoverPolicy coverPolicy = defaultCoverPolicy,
  OverglassMenu? menu,
  bool? showBack,
  VoidCallback? onBack,
}) => OverglassScaffold(
  coverPolicy: coverPolicy,
  fallbackTabBarBuilder: tabBuilder,
  fallbackTabBarHeight: tabBuilder == null ? null : 80,
  topBar: OverglassTopBar(
    title: 'Title',
    showBack: showBack,
    onBack: onBack,
    trailing: [
      if (menu != null)
        OverglassAction(id: 'menu', label: 'Menu', sfSymbol: 'ellipsis', icon: _icon, menu: menu)
      else
        OverglassAction(id: 'add', label: 'Add', sfSymbol: 'plus', icon: _icon, onPressed: onAction ?? () {}),
    ],
  ),
  tabBar: OverglassTabBar(
    currentIndex: index,
    onChanged: onChanged,
    items: [
      OverglassTab(label: first, sfSymbol: 'a', icon: _icon),
      const OverglassTab(label: 'Two', sfSymbol: 'b', icon: _icon),
    ],
  ),
  body: body,
);

void _onPlatform(String description, TargetPlatform platform, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<_Harness> _mount(WidgetTester tester, Widget home, {MediaQueryData? media, _Harness? harness}) async {
  final installed = (harness ?? _Harness())..install(tester);
  await tester.pumpWidget(_app(home, media: media));
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return installed;
}

Route<void> _page(Widget child) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => child);

void main() {
  tearDown(() => OverglassChannel.instance.debugReset());

  group('platform choice', () {
    _onPlatform('non-iOS draws Flutter bars and never calls native', TargetPlatform.android, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      expect(find.text('One'), findsOneWidget);
      expect(harness.calls, isEmpty);
    });

    _onPlatform('non-iOS bars appear on the first frame (8)', TargetPlatform.android, (tester) async {
      await tester.pumpWidget(_app(_scaffold((_) {})));
      expect(find.text('One'), findsOneWidget);
    });

    _onPlatform('iOS without system glass uses the Flutter bars', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}), harness: _Harness()..nativeGlass = false);
      expect(find.text('One'), findsOneWidget);
      expect(harness.applies, isEmpty);
    });

    _onPlatform('capabilities are asked once per process (8)', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpWidget(_app(_scaffold((_) {})));
      await tester.pump();
      expect(harness.calls.where((c) => c.method == 'capabilities').length, 1);
    });

    _onPlatform('system glass sends a spec and draws no Flutter bars', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      expect(find.text('One'), findsNothing);
      expect(harness.lastApply['visible'], isTrue);
      expect((harness.lastApply['tabBar']! as Map)['selected'], 0);
    });

    _onPlatform('an app can replace the fallback bars', TargetPlatform.android, (tester) async {
      await _mount(tester, _scaffold((_) {}, tabBuilder: (_, bar) => Text('custom ${bar.items.length}')));
      expect(find.text('custom 2'), findsOneWidget);
      expect(find.text('One'), findsNothing);
    });
  });

  group('sessions (1)', () {
    _onPlatform('events reach the first scaffold after the second pops', TargetPlatform.iOS, (tester) async {
      int? firstSelected;
      final harness = await _mount(tester, _scaffold((i) => firstSelected = i));
      final firstSession = harness.lastApply['session'];

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(_page(_scaffold((_) {}, first: 'Inner'))));
      await tester.pumpAndSettle();
      final secondSession = harness.applies.lastWhere((spec) => spec['session'] != firstSession)['session'];
      expect(secondSession, isNotNull);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(harness.calls.where((c) => c.method == 'clear'), isEmpty);
      expect(harness.calls.where((c) => c.method == 'release').map((c) => (c.arguments as Map)['session']), [
        secondSession,
      ]);
      await harness.send(tester, 'tabSelected', {'session': firstSession, 'index': 1, 'tapSeq': 1});
      expect(firstSelected, 1);
    });

    _onPlatform('events for a released session are ignored', TargetPlatform.iOS, (tester) async {
      int? selected;
      final harness = await _mount(tester, _scaffold((i) => selected = i));
      final session = harness.lastApply['session'];
      await tester.pumpWidget(_app(const SizedBox()));
      await harness.send(tester, 'tabSelected', {'session': session, 'index': 1, 'tapSeq': 1});
      expect(selected, isNull);
    });

    test('two visible scaffolds in one route are detected', () {
      final channel = OverglassChannel.instance;
      final route = _page(const SizedBox());
      expect(channel.debugClaimRoute(1, route, visible: true), isTrue);
      expect(channel.debugClaimRoute(1, route, visible: true), isTrue);
      expect(channel.debugClaimRoute(2, route, visible: false), isTrue);
      expect(channel.debugClaimRoute(2, route, visible: true), isFalse);
      expect(channel.debugClaimRoute(3, _page(const SizedBox()), visible: true), isTrue);
    });

    _onPlatform('replacing a scaffold in the same route is not a clash', TargetPlatform.iOS, (tester) async {
      await _mount(tester, _scaffold((_) {}));
      // A different parent forces a new element, built before the old one is disposed.
      await tester.pumpWidget(_app(KeyedSubtree(child: _scaffold((_) {}, first: 'Next'))));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('attachment (2, 9)', () {
    _onPlatform('a failed attach shows Flutter bars, then native on attached', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}), harness: _Harness()..attached = false);
      await tester.pump();
      expect(find.text('One'), findsOneWidget);

      final session = harness.lastApply['session'];
      harness.attached = true;
      await harness.send(tester, 'attached', {'session': session});
      await tester.pump();
      await tester.pump();
      expect(find.text('One'), findsNothing);
    });

    _onPlatform('a platform error counts as not attached', TargetPlatform.iOS, (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'capabilities') return {'nativeGlass': true};
        if (call.method == 'apply') throw PlatformException(code: 'boom');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
      await tester.pumpWidget(_app(_scaffold((_) {})));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('One'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('events', () {
    _onPlatform('native events reach the callbacks', TargetPlatform.iOS, (tester) async {
      int? selected;
      var pressed = false;
      final harness = await _mount(tester, _scaffold((i) => selected = i, onAction: () => pressed = true));
      final session = harness.lastApply['session'];
      await harness.send(tester, 'tabSelected', {'session': session, 'index': 1, 'tapSeq': 1});
      await harness.send(tester, 'actionPressed', {'session': session, 'id': 'add'});
      expect(selected, 1);
      expect(pressed, isTrue);
    });

    _onPlatform('a tap is acknowledged and a rejected one re-asserted (10)', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      final session = harness.lastApply['session'];
      await harness.send(tester, 'tabSelected', {'session': session, 'index': 1, 'tapSeq': 7});
      await tester.pump();
      expect(harness.lastApply['ackTap'], 7);
      expect((harness.lastApply['tabBar']! as Map)['selected'], 0);
    });

    _onPlatform('native menu selection runs the item', TargetPlatform.iOS, (tester) async {
      var chosen = false;
      final menu = OverglassMenu(
        items: [OverglassMenuItem(label: 'X', onSelected: () => chosen = true)],
      );
      final harness = await _mount(tester, _scaffold((_) {}, menu: menu));
      await harness.send(tester, 'menuSelected', {
        'session': harness.lastApply['session'],
        'action': 'menu',
        'item': 0,
      });
      expect(chosen, isTrue);
    });

    _onPlatform('back follows canPop and calls onBack', TargetPlatform.iOS, (tester) async {
      var backed = false;
      final harness = await _mount(tester, _scaffold((_) {}, showBack: true, onBack: () => backed = true));
      expect((harness.lastApply['topBar']! as Map)['back'], isTrue);
      await harness.send(tester, 'backPressed', {'session': harness.lastApply['session']});
      expect(backed, isTrue);
    });

    _onPlatform('native search events reach the callbacks', TargetPlatform.iOS, (tester) async {
      String? changed;
      String? submitted;
      final harness = await _mount(
        tester,
        OverglassScaffold(
          topBar: OverglassTopBar(
            search: OverglassSearch(
              placeholder: 'Find',
              onChanged: (t) => changed = t,
              onSubmitted: (t) => submitted = t,
            ),
          ),
          body: const SizedBox.expand(),
        ),
      );
      expect((harness.lastApply['topBar']! as Map)['search'], {
        'placeholder': 'Find',
        'placement': 'top',
        'autofocus': false,
      });
      final session = harness.lastApply['session'];
      await harness.send(tester, 'searchChanged', {'session': session, 'text': 'a'});
      await harness.send(tester, 'searchSubmitted', {'session': session, 'text': 'ab'});
      expect(changed, 'a');
      expect(submitted, 'ab');
    });

    _onPlatform('a large title collapses without moving content', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(
        tester,
        OverglassScaffold(
          topBar: const OverglassTopBar(title: 'T', largeTitle: true),
          body: ListView.builder(itemExtent: 100, itemCount: 50, itemBuilder: (_, i) => Text('r$i')),
        ),
      );
      final session = harness.lastApply['session'];
      expect((harness.lastApply['topBar']! as Map)['largeTitle'], isTrue);
      await harness.send(tester, 'metrics', {'session': session, 'top': 150.0, 'bottom': 0.0});
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      await tester.pump();
      expect((harness.lastApply['topBar']! as Map)['largeTitle'], isFalse);
      await harness.send(tester, 'metrics', {'session': session, 'top': 100.0, 'bottom': 0.0});
      expect(MediaQuery.of(tester.element(find.text('r5'))).padding.top, 0, reason: 'ListView consumes it');
      final scaffoldMedia = tester.widgetList<MediaQuery>(find.byType(MediaQuery)).map((m) => m.data.padding.top);
      expect(scaffoldMedia, contains(150));
    });

    _onPlatform('the fallback search field reports text', TargetPlatform.android, (tester) async {
      String? changed;
      await _mount(
        tester,
        OverglassScaffold(
          topBar: OverglassTopBar(
            search: OverglassSearch(placeholder: 'Find', onChanged: (t) => changed = t),
          ),
          body: const SizedBox.expand(),
        ),
      );
      await tester.enterText(find.byType(EditableText), 'hi');
      expect(changed, 'hi');
    });

    _onPlatform('toolbar and segments reach their callbacks', TargetPlatform.iOS, (tester) async {
      var pressed = false;
      int? segment;
      final harness = await _mount(
        tester,
        OverglassScaffold(
          topBar: OverglassTopBar(
            segments: OverglassSegments(labels: const ['A', 'B'], selectedIndex: 0, onChanged: (i) => segment = i),
          ),
          toolbar: OverglassToolbar(
            items: [
              const OverglassToolbarItem.flexibleSpace(),
              OverglassToolbarItem.action(OverglassAction.add(onPressed: () => pressed = true)),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      );
      final items = (harness.lastApply['toolbar']! as Map)['items']! as List;
      expect(items.first, {'space': true});
      final session = harness.lastApply['session'];
      await harness.send(tester, 'actionPressed', {'session': session, 'id': 'add'});
      await harness.send(tester, 'segmentSelected', {'session': session, 'index': 1});
      expect(pressed, isTrue);
      expect(segment, 1);
    });

    _onPlatform('the accessory fires and the search tab is marked', TargetPlatform.iOS, (tester) async {
      var tapped = false;
      final harness = await _mount(
        tester,
        OverglassScaffold(
          tabBar: OverglassTabBar(
            currentIndex: 0,
            onChanged: (_) {},
            accessory: OverglassTabAccessory(title: 'T', onPressed: () => tapped = true),
            items: const [
              OverglassTab(label: 'A'),
              OverglassTab(label: 'B', isSearch: true),
            ],
          ),
          body: ListView.builder(itemExtent: 100, itemCount: 50, itemBuilder: (_, i) => Text('r$i')),
        ),
      );
      final tabs = harness.lastApply['tabBar']! as Map;
      expect((tabs['items']! as List).last, containsPair('isSearch', true));
      await harness.send(tester, 'accessoryPressed', {'session': harness.lastApply['session']});
      expect(tapped, isTrue);
    });

    _onPlatform('context menu, popover and sheet use native results', TargetPlatform.iOS, (tester) async {
      await _mount(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      var chosen = false;
      await Overglass.showContextMenu(
        context,
        position: const Offset(10, 10),
        menu: OverglassMenu(
          items: [OverglassMenuItem(label: 'X', onSelected: () => chosen = true)],
        ),
      );
      expect(chosen, isTrue);
      expect(await Overglass.showPopover(context, anchor: Rect.zero, actions: const []), 'yes');
      expect(await Overglass.showSheet(context, entrypoint: 'e', fallback: (_) => const SizedBox()), 'done');
    });

    _onPlatform('the sheet falls back to Flutter off iOS', TargetPlatform.android, (tester) async {
      await _mount(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final result = Overglass.showSheet(context, entrypoint: 'e', fallback: (_) => const Text('fallback'));
      await tester.pumpAndSettle();
      expect(find.text('fallback'), findsOneWidget);
      Navigator.of(tester.element(find.text('fallback')), rootNavigator: true).pop('x');
      await tester.pumpAndSettle();
      expect(await result, 'x');
    });

    _onPlatform('the root route shows no back by default', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      expect((harness.lastApply['topBar']! as Map)['back'], isFalse);
    });

    _onPlatform('alerts return the native choice', TargetPlatform.iOS, (tester) async {
      await _mount(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final result = await Overglass.showAlert(
        context,
        actions: const [OverglassAlertAction(id: 'ok', label: 'OK')],
      );
      expect(result, 'ok');
    });

    _onPlatform('alerts use the Flutter dialog off iOS', TargetPlatform.android, (tester) async {
      await _mount(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final result = Overglass.showAlert(
        context,
        actions: const [OverglassAlertAction(id: 'ok', label: 'OK')],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await result, 'ok');
    });
  });

  group('layout', () {
    _onPlatform('native metrics become padding and viewPadding', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      await harness.send(tester, 'metrics', {'session': harness.lastApply['session'], 'top': 103.0, 'bottom': 83.0});
      final media = MediaQuery.of(tester.element(find.byType(SizedBox).last));
      expect(media.padding.top, 103);
      expect(media.padding.bottom, 83);
      expect(media.viewPadding.bottom, 83);
    });

    _onPlatform('a new scaffold uses the last known metrics', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      await harness.send(tester, 'metrics', {'session': harness.lastApply['session'], 'top': 103.0, 'bottom': 83.0});
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(_page(_scaffold((_) {}, body: const SizedBox.expand(key: Key('second'))))));
      await tester.pumpAndSettle();
      expect(MediaQuery.of(tester.element(find.byKey(const Key('second')))).padding.top, 103);
    });

    _onPlatform('a bottom search field keeps its inset above the keyboard', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(
        tester,
        OverglassScaffold(
          topBar: const OverglassTopBar(search: OverglassSearch(placement: OverglassSearchPlacement.bottom)),
          body: const SizedBox.expand(key: Key('body')),
        ),
        media: const MediaQueryData(size: Size(400, 800), viewInsets: EdgeInsets.only(bottom: 300)),
      );
      expect((harness.lastApply['topBar']! as Map)['search'], containsPair('placement', 'bottom'));
      await harness.send(tester, 'metrics', {'session': harness.lastApply['session'], 'top': 100.0, 'bottom': 366.0});
      expect(MediaQuery.of(tester.element(find.byKey(const Key('body')))).padding.bottom, 366);
    });

    _onPlatform('the keyboard removes the tab bar from padding (5)', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(
        tester,
        _scaffold((_) {}),
        media: const MediaQueryData(size: Size(400, 800), viewInsets: EdgeInsets.only(bottom: 300)),
      );
      await harness.send(tester, 'metrics', {'session': harness.lastApply['session'], 'top': 103.0, 'bottom': 83.0});
      final media = MediaQuery.of(tester.element(find.byType(SizedBox).last));
      expect(media.padding.bottom, 0);
      expect(media.viewPadding.bottom, 83);
    });

    _onPlatform('the title scrim appears only after scrolling', TargetPlatform.iOS, (tester) async {
      await _mount(
        tester,
        _scaffold((_) {}, body: ListView.builder(itemExtent: 100, itemCount: 50, itemBuilder: (_, i) => Text('r$i'))),
      );
      expect(find.byType(DecoratedBox), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  });

  group('covering routes', () {
    _onPlatform('a dialog keeps native bars, dimmed and inert', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      expect(harness.lastApply['interactive'], isTrue);
      expect(harness.lastApply['scrim'], isNull);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          RawDialogRoute<void>(barrierColor: const Color(0x8A000000), pageBuilder: (_, _, _) => const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.lastApply['visible'], isTrue);
      expect(harness.lastApply['interactive'], isFalse);
      expect((harness.lastApply['scrim']! as Map)['color'], 0x8A000000);
      expect(find.text('One'), findsNothing);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(harness.lastApply['interactive'], isTrue);
      expect(harness.lastApply['scrim'], isNull);
    });

    _onPlatform('a page hides native bars with no Flutter stand-in', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(_page(const SizedBox())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.lastApply['visible'], isFalse);
      expect(harness.lastApply['fadeMs'], 300);
      expect(find.text('One'), findsNothing);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.lastApply['visible'], isTrue);
      expect(find.text('One'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
    });

    _onPlatform('a popped scaffold gives up the bars when the pop starts', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(_page(_scaffold((_) {}, first: 'Inner'))));
      await tester.pumpAndSettle();
      final first = harness.applies.first['session'];
      final second = harness.applies.lastWhere((spec) => spec['session'] != first)['session'];

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final last = harness.applies.lastWhere((spec) => spec['session'] == second);
      expect(last['visible'], isFalse);
      expect(harness.calls.where((c) => c.method == 'release'), isEmpty);
      await tester.pumpAndSettle();
    });

    _onPlatform('an entering route shows native bars at once', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, const SizedBox());
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, _, _) => _scaffold((_) {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('One'), findsNothing);
      expect(harness.lastApply['visible'], isTrue);
      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
    });

    _onPlatform('coverPolicy can force the twin', TargetPlatform.iOS, (tester) async {
      final harness = await _mount(tester, _scaffold((_) {}, coverPolicy: (_) => OverglassCover.twin));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox())));
      await tester.pumpAndSettle();
      expect(harness.lastApply['visible'], isFalse);
      expect(find.text('One'), findsOneWidget);
    });

    test('default policy matches the table', () {
      expect(
        defaultCoverPolicy(RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox())),
        OverglassCover.scrim,
      );
      expect(defaultCoverPolicy(_page(const SizedBox())), OverglassCover.fade);
      expect(defaultCoverPolicy(_BarrierlessPopup()), OverglassCover.passive);
    });
  });
}

class _BarrierlessPopup extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      const SizedBox();
}

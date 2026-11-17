import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:overglass/overglass.dart';

/// `plain`, `overglass` or `lgr`. Every variant scrolls the same list.
const String variant = String.fromEnvironment('VARIANT', defaultValue: 'overglass');

/// Scrolls forever, so Instruments can record with no one touching the phone.
const bool autoScroll = bool.fromEnvironment('AUTOSCROLL');

final ScrollController benchController = ScrollController();

Future<void> scrollCycle() async {
  final end = benchController.position.maxScrollExtent;
  await benchController.animateTo(end, duration: const Duration(seconds: 8), curve: Curves.linear);
  await benchController.animateTo(0, duration: const Duration(seconds: 8), curve: Curves.linear);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (variant == 'lgr') await LiquidGlass.precache();
  runApp(const BenchApp());
}

class BenchApp extends StatefulWidget {
  const BenchApp({super.key});

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> {
  @override
  void initState() {
    super.initState();
    if (autoScroll) {
      Timer(const Duration(seconds: 3), () async {
        while (mounted) {
          await scrollCycle();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      type: MaterialType.transparency,
      child: switch (variant) {
        'plain' => const _Plain(),
        'lgr' => const _Renderer(),
        _ => const _Overglass(),
      },
    ),
  );
}

class _BenchList extends StatelessWidget {
  const _BenchList();

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: benchController,
    itemCount: 300,
    itemExtent: 132,
    itemBuilder: (context, index) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: HSLColor.fromAHSL(1, (index * 37) % 360.0, 0.75, 0.55).toColor(),
      ),
      alignment: Alignment.center,
      child: Text(
        'Item $index',
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

/// The same insets as the bars, so the list lays out identically.
const double _topInset = 116;
const double _bottomInset = 83;

Widget _insetList(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: const EdgeInsets.only(top: _topInset, bottom: _bottomInset),
  ),
  child: const _BenchList(),
);

class _Plain extends StatelessWidget {
  const _Plain();

  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xFFF2F2F7), child: _insetList(context));
}

class _Overglass extends StatelessWidget {
  const _Overglass();

  @override
  Widget build(BuildContext context) => OverglassScaffold(
    topBar: OverglassTopBar(
      title: 'Home',
      leading: [
        OverglassAction(id: 'menu', label: 'Menu', sfSymbol: 'ellipsis', icon: Icons.more_horiz, onPressed: () {}),
      ],
      trailing: [OverglassAction.add(onPressed: () {})],
    ),
    tabBar: OverglassTabBar(
      currentIndex: 0,
      onChanged: (_) {},
      items: const [
        OverglassTab(label: 'Home', sfSymbol: 'house.fill', icon: Icons.home),
        OverglassTab(label: 'Search', sfSymbol: 'magnifyingglass', icon: Icons.search),
        OverglassTab(label: 'Profile', sfSymbol: 'person.fill', icon: Icons.person),
      ],
    ),
    body: const _BenchList(),
  );
}

/// Shader glass with the geometry of the system bars: two buttons and a capsule.
class _Renderer extends StatelessWidget {
  const _Renderer();

  Widget _circle(IconData icon) => LiquidGlass(
    shape: const LiquidRoundedSuperellipse(borderRadius: 22),
    child: SizedBox.square(dimension: 44, child: Icon(icon, color: Colors.black87)),
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF2F2F7),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _insetList(context),
        LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27Regular(brightness: MediaQuery.platformBrightnessOf(context)),
          child: Stack(
            children: [
              Positioned(top: 62, left: 16, child: _circle(Icons.more_horiz)),
              Positioned(top: 62, right: 16, child: _circle(Icons.add)),
              const Positioned(
                bottom: 22,
                left: 64,
                right: 64,
                height: 60,
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [Icon(Icons.home), Icon(Icons.search), Icon(Icons.person)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

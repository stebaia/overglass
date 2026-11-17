// The example still supports Flutter 3.38, which has no material_ui package.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:overglass/controls.dart';
import 'package:overglass/overglass.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: DemoHome());
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  static const _titles = ['Home', 'Search', 'Profile'];
  static const _modal = MethodChannel('overglass_example/modal');
  int _tab = 0;
  String _last = 'None';
  String _query = '';

  List<int> get _visible => [
    for (var i = 0; i < 40; i++)
      if (_tab != 1 || _query.isEmpty || '$i'.contains(_query)) i,
  ];

  void _dialog() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Flutter dialog'),
      content: const Text('The native bars stay, dimmed like the barrier.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _popover() async {
    final choice = await Overglass.showPopover(
      context,
      anchor: const Rect.fromLTWH(180, 420, 40, 40),
      title: 'Native popover',
      message: 'Drawn by UIKit.',
      actions: const [OverglassAlertAction(id: 'yes', label: 'Choose me')],
    );
    if (mounted) setState(() => _last = 'Popover $choice');
  }

  Future<void> _sheetPage() async {
    final result = await Overglass.showSheet(
      context,
      entrypoint: 'sheetMain',
      arguments: const ['Hello from the app'],
      fallback: (_) => const SheetContent(message: 'Flutter fallback'),
    );
    if (mounted) setState(() => _last = 'Sheet page $result');
  }

  Future<void> _alert() async {
    final choice = await Overglass.showAlert(
      context,
      title: 'Native alert',
      message: 'Presented by UIKit.',
      actions: const [
        OverglassAlertAction(
          id: 'cancel',
          label: 'Cancel',
          style: OverglassAlertActionStyle.cancel,
        ),
        OverglassAlertAction(id: 'ok', label: 'Confirm'),
      ],
    );
    if (mounted) setState(() => _last = 'Alert $choice');
  }

  Future<void> _sheet() async {
    final choice = await Overglass.showActionSheet(
      context,
      title: 'Native sheet',
      actions: const [
        OverglassAlertAction(
          id: 'delete',
          label: 'Delete',
          style: OverglassAlertActionStyle.destructive,
        ),
        OverglassAlertAction(
          id: 'cancel',
          label: 'Cancel',
          style: OverglassAlertActionStyle.cancel,
        ),
      ],
    );
    if (mounted) setState(() => _last = 'Sheet $choice');
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: OverglassScaffold(
      topBar: OverglassTopBar(
        title: _titles[_tab],
        largeTitle: _tab == 2,
        search: _tab == 1
            ? OverglassSearch(
                placeholder: 'Search items',
                placement: OverglassSearchPlacement.bottom,
                onChanged: (text) => setState(() => _query = text),
              )
            : null,
        leading: [
          OverglassAction(
            id: 'more',
            label: 'More',
            sfSymbol: 'ellipsis',
            icon: Icons.more_horiz,
            menu: OverglassMenu(
              items: [
                OverglassMenuItem(
                  label: 'Open detail',
                  onSelected: () => _push(const DetailPage()),
                ),
                OverglassMenuItem(
                  label: 'Plain page',
                  onSelected: () => _push(const PlainPage()),
                ),
                OverglassMenuItem(
                  label: 'UIKit modal',
                  onSelected: () => _modal.invokeMethod<void>('present'),
                ),
                OverglassMenuItem(label: 'Native alert', onSelected: _alert),
                OverglassMenuItem(label: 'Popover', onSelected: _popover),
                OverglassMenuItem(
                  label: 'Flutter sheet',
                  onSelected: _sheetPage,
                ),
                OverglassMenuItem(
                  label: 'Toolbar page',
                  onSelected: () => _push(const ToolbarPage()),
                ),
                OverglassMenuItem(
                  label: 'System tabs',
                  onSelected: () => _push(const SystemTabsPage()),
                ),
                OverglassMenuItem(
                  label: 'Controls',
                  onSelected: () => _push(const ControlsPage()),
                ),
                OverglassMenuItem(
                  label: 'Native sheet',
                  onSelected: _sheet,
                  destructive: true,
                ),
              ],
            ),
          ),
        ],
        trailing: [
          OverglassAction.add(label: 'Show dialog', onPressed: _dialog),
        ],
      ),
      tabBar: OverglassTabBar(
        currentIndex: _tab,
        onChanged: (index) => setState(() {
          _tab = index;
          _query = '';
        }),
        items: const [
          OverglassTab(label: 'Home', sfSymbol: 'house.fill', icon: Icons.home),
          OverglassTab(
            label: 'Search',
            sfSymbol: 'magnifyingglass',
            icon: Icons.search,
            badge: '3',
          ),
          OverglassTab(
            label: 'Profile',
            sfSymbol: 'person.fill',
            icon: Icons.person,
          ),
        ],
      ),
      body: OverglassContextMenu(
        menu: OverglassMenu(
          items: [
            OverglassMenuItem(
              label: 'Pin screen',
              onSelected: () => setState(() => _last = 'Pinned'),
            ),
          ],
        ),
        child: ListView.builder(
          key: PageStorageKey<int>(_tab),
          itemCount: _visible.length,
          itemBuilder: (context, index) => Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: HSLColor.fromAHSL(
                1,
                (_visible[index] * 37 + _tab * 90) % 360.0,
                0.75,
                0.55,
              ).toColor(),
            ),
            alignment: Alignment.center,
            child: Text(
              _visible[index] == 0
                  ? 'Last: $_last'
                  : '${_titles[_tab]} ${_visible[index]}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A second route with its own scaffold.
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  int _tab = 0;
  String _query = '';

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: OverglassScaffold(
      topBar: OverglassTopBar(
        title: 'Detail',
        search: OverglassSearch(
          placeholder: 'Search notes',
          onChanged: (text) => setState(() => _query = text),
        ),
      ),
      tabBar: OverglassTabBar(
        currentIndex: _tab,
        onChanged: (index) => setState(() => _tab = index),
        items: const [
          OverglassTab(
            label: 'Info',
            sfSymbol: 'info.circle',
            icon: Icons.info,
          ),
          OverglassTab(
            label: 'Notes',
            sfSymbol: 'note.text',
            icon: Icons.notes,
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Detail tab $_tab query $_query',
          style: const TextStyle(fontSize: 22, color: Colors.grey),
        ),
      ),
    ),
  );
}

/// Runs in the sheet's own engine.
@pragma('vm:entry-point')
void sheetMain(List<String> arguments) => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
    home: Scaffold(body: SheetContent(message: arguments.first)),
  ),
);

class SheetContent extends StatelessWidget {
  const SheetContent({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sheet says: $message', style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => OverglassSheet.close(context, result: 'done'),
          child: const Text('Close sheet'),
        ),
      ],
    ),
  );
}

class ToolbarPage extends StatefulWidget {
  const ToolbarPage({super.key});

  @override
  State<ToolbarPage> createState() => _ToolbarPageState();
}

class _ToolbarPageState extends State<ToolbarPage> {
  int _segment = 0;
  String _action = 'none';

  OverglassToolbarItem _item(String id, String symbol, IconData icon) =>
      OverglassToolbarItem.action(
        OverglassAction(
          id: id,
          label: id,
          sfSymbol: symbol,
          icon: icon,
          onPressed: () => setState(() => _action = id),
        ),
      );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: OverglassScaffold(
      topBar: OverglassTopBar(
        segments: OverglassSegments(
          labels: const ['Day', 'Week'],
          selectedIndex: _segment,
          onChanged: (index) => setState(() => _segment = index),
        ),
      ),
      toolbar: OverglassToolbar(
        items: [
          _item('Share', 'square.and.arrow.up', Icons.share),
          const OverglassToolbarItem.flexibleSpace(),
          _item('Trash', 'trash', Icons.delete),
        ],
      ),
      body: Center(
        child: Text(
          'Segment $_segment action $_action',
          style: const TextStyle(fontSize: 22, color: Colors.grey),
        ),
      ),
    ),
  );
}

class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  bool _wifi = true;
  double _volume = 0.4;
  DateTime _date = DateTime(2026, 11, 17);
  int _presses = 0;

  bool get _dark => MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  TextStyle get _label => TextStyle(
    fontSize: 16,
    color: _dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43),
  );

  TextStyle get _value => TextStyle(
    fontSize: 16,
    color: _dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
  );

  Widget _row(String title, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Row(
      children: [
        SizedBox(width: 90, child: Text(title, style: _label)),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: control),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: OverglassScaffold(
      topBar: const OverglassTopBar(title: 'Controls'),
      body: ListView(
        children: [
          _row(
            'Buttons',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OverglassButton(
                  label: 'Glass',
                  onPressed: () => setState(() => _presses++),
                ),
                OverglassButton(
                  label: 'Prominent',
                  style: OverglassButtonStyle.prominent,
                  onPressed: () => setState(() => _presses++),
                ),
                OverglassButton(
                  label: 'Delete',
                  sfSymbol: 'trash',
                  icon: Icons.delete,
                  destructive: true,
                  onPressed: () => setState(() => _presses++),
                ),
              ],
            ),
          ),
          _row('Pressed', Text('Pressed $_presses', style: _value)),
          _row(
            'Wi-Fi',
            OverglassSwitch(
              value: _wifi,
              semanticLabel: 'Wi-Fi',
              onChanged: (value) => setState(() => _wifi = value),
            ),
          ),
          _row(
            'Wi-Fi is',
            Text(_wifi ? 'Wi-Fi on' : 'Wi-Fi off', style: _value),
          ),
          _row(
            'Volume',
            OverglassSlider(
              value: _volume,
              semanticLabel: 'Volume',
              onChanged: (value) => setState(() => _volume = value),
            ),
          ),
          _row(
            'Level',
            OverglassGauge(
              value: _volume,
              label: 'Volume',
              valueLabel: '${(_volume * 100).round()}',
            ),
          ),
          _row(
            'Bar',
            OverglassGauge(
              value: _volume,
              style: OverglassGaugeStyle.linear,
              label: 'Volume',
            ),
          ),
          _row(
            'Date',
            OverglassDatePicker(
              value: _date,
              onChanged: (value) => setState(() => _date = value),
              fallback: (_) =>
                  Text('${_date.year}-${_date.month}-${_date.day}'),
            ),
          ),
          _row(
            'Picked',
            Text(
              'Picked ${_date.year}-${_date.month}-${_date.day}',
              style: _value,
            ),
          ),
          _row(
            'Toast',
            OverglassButton(
              label: 'Show toast',
              sfSymbol: 'checkmark.circle.fill',
              icon: Icons.check_circle,
              onPressed: () => Overglass.showToast(
                context,
                message: 'Saved',
                sfSymbol: 'checkmark.circle.fill',
                icon: Icons.check_circle,
                tint: const Color(0xFF34C759),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SystemTabsPage extends StatefulWidget {
  const SystemTabsPage({super.key});

  @override
  State<SystemTabsPage> createState() => _SystemTabsPageState();
}

class _SystemTabsPageState extends State<SystemTabsPage> {
  int _tab = 0;
  int _accessory = 0;
  String _query = '';

  List<int> get _rows => [
    for (var i = 0; i < 60; i++)
      if (_tab != 2 || _query.isEmpty || '$i'.contains(_query)) i,
  ];

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: OverglassScaffold(
      topBar: OverglassTopBar(
        title: 'System tabs',
        search: _tab == 2
            ? OverglassSearch(
                placeholder: 'Find rows',
                placement: OverglassSearchPlacement.bottom,
                autofocus: true,
                onChanged: (text) => setState(() => _query = text),
              )
            : null,
      ),
      tabBar: OverglassTabBar(
        currentIndex: _tab,
        onChanged: (index) => setState(() {
          _tab = index;
          _query = '';
        }),
        minimizeOnScroll: true,
        sidebar: true,
        accessory: OverglassTabAccessory(
          title: 'Now playing',
          subtitle: 'Tapped $_accessory',
          sfSymbol: 'music.note',
          onPressed: () => setState(() => _accessory++),
        ),
        items: const [
          OverglassTab(
            label: 'Library',
            sfSymbol: 'books.vertical',
            icon: Icons.book,
          ),
          OverglassTab(
            label: 'Radio',
            sfSymbol: 'dot.radiowaves.left.and.right',
            icon: Icons.radio,
          ),
          OverglassTab(label: 'Find', icon: Icons.search, isSearch: true),
        ],
      ),
      body: ListView.builder(
        itemCount: _rows.length,
        itemBuilder: (context, index) => Container(
          height: 90,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: HSLColor.fromAHSL(1, (index * 29) % 360.0, 0.7, 0.6).toColor(),
          alignment: Alignment.center,
          child: Text(
            'System tab $_tab row ${_rows[index]} accessory $_accessory',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class PlainPage extends StatelessWidget {
  const PlainPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plain page')),
    body: const Center(child: Text('Chrome hidden on this route')),
  );
}

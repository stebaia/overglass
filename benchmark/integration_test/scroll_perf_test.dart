import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:overglass_benchmark/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('scrolls the list under the bars', (tester) async {
    await tester.pumpWidget(const BenchApp());
    await Future<void>.delayed(const Duration(seconds: 3));

    await binding.traceAction(() async {
      await scrollCycle();
    }, streams: const ['Dart', 'Embedder', 'GC'], reportKey: 'timeline');

    binding.reportData!['variant'] = variant;
  });
}

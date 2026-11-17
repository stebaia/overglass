import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final timeline = driver.Timeline.fromJson(data!['timeline'] as Map<String, dynamic>);
    await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(
      'scroll_${data['variant']}',
      destinationDirectory: 'build/perf',
      pretty: true,
      includeSummary: true,
    );
  },
);

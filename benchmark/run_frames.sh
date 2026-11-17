#!/usr/bin/env bash
# Flutter frame timings for the three variants, on a connected device.
# Usage: ./run_frames.sh "NOME_IPHONE"
# It measures Flutter's own work. Use run_instruments.sh for the system compositor.
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:?Pass the device name}"
MODE="${MODE:-profile}"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.9/bin/flutter}"
source ./signing.sh

"$FLUTTER" pub get >/dev/null
# A run that stops halfway must not show numbers from an earlier one.
rm -f build/perf/scroll_*
for variant in plain overglass lgr; do
  echo "== $variant"
  "$FLUTTER" drive --"$MODE" -d "$DEVICE" --endless-trace-buffer --no-dds \
    --driver=test_driver/perf_driver.dart \
    --target=integration_test/scroll_perf_test.dart \
    --dart-define=VARIANT="$variant"
done
python3 compare_frames.py build/perf

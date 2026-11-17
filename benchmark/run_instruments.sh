#!/usr/bin/env bash
# Records each variant with Instruments while the list scrolls by itself.
# Usage: ./run_instruments.sh "NOME_IPHONE" ["Animation Hitches"] [seconds]
# Set KEEP_TRACES=1 to keep hitch traces, which take about 500 MB each.
#
# WARNING: recording left several GB of system data on an iPhone 15 Pro, and
# that space was not released when the run ended. Set ACCEPT_DEVICE_STORAGE=1
# only on a phone with plenty of free space.
set -euo pipefail
if [ -z "${ACCEPT_DEVICE_STORAGE:-}" ]; then
  echo "Refusing to run: Instruments can fill the phone's storage with system data." >&2
  echo "See doc/verification/performance.md. Set ACCEPT_DEVICE_STORAGE=1 to run anyway." >&2
  exit 1
fi
cd "$(dirname "$0")"
DEVICE="${1:?Pass the device name}"
TEMPLATE="${2:-Animation Hitches}"
SECONDS_TO_RECORD="${3:-30}"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.9/bin/flutter}"
BUNDLE_ID="dev.overglass.overglassBenchmark"
source ./signing.sh

FREE_KB="$(df -k . | awk 'NR==2 {print $4}')"
if [ "$FREE_KB" -lt 2500000 ]; then
  echo "Need at least 2.5 GB free on this disk, found $((FREE_KB / 1024)) MB." >&2
  exit 1
fi

"$FLUTTER" pub get >/dev/null
mkdir -p build/perf
RESULTS=build/perf/hitches.md
rm -f "$RESULTS"
{
  echo "| Variant | Hitches | Total hitch time (ms) | Worst (ms) | When (s) |"
  echo "| --- | --- | --- | --- | --- |"
} > "$RESULTS"

FAILED=""
for variant in plain overglass lgr; do
  echo "== $variant"
  TRACE="build/perf/$variant.trace"
  "$FLUTTER" build ios --profile --dart-define=VARIANT="$variant" --dart-define=AUTOSCROLL=true
  xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app

  RECORDED=""
  for attempt in 1 2; do
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE" \
      --json-output build/perf/launch.json "$BUNDLE_ID"
    PID="$(python3 -c "import json; print(json.load(open('build/perf/launch.json'))['result']['process']['processIdentifier'])")"
    sleep 5
    rm -rf "$TRACE"
    if xcrun xctrace record --template "$TEMPLATE" --device "$DEVICE" --attach "$PID" \
      --time-limit "${SECONDS_TO_RECORD}s" --output "$TRACE"; then
      RECORDED=1
      break
    fi
    echo "Recording failed on attempt $attempt." >&2
  done

  if [ -z "$RECORDED" ]; then
    rm -rf "$TRACE"
    FAILED="$FAILED $variant"
    continue
  fi
  if [ "$TEMPLATE" = "Animation Hitches" ]; then
    python3 summarize_hitches.py "$TRACE" >> "$RESULTS"
    if [ -z "${KEEP_TRACES:-}" ]; then rm -rf "$TRACE"; fi
  fi
done

if [ "$TEMPLATE" = "Animation Hitches" ]; then cat "$RESULTS"; fi
if [ -n "$FAILED" ]; then
  echo "Not recorded:$FAILED" >&2
  exit 1
fi

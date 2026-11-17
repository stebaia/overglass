#!/usr/bin/env python3
"""Compares the Flutter frame timings written by run_frames.sh."""
import json
import pathlib
import sys

ROWS = [
    ("Frames", "frame_count", "{:.0f}"),
    ("Build avg (ms)", "average_frame_build_time_millis", "{:.2f}"),
    ("Build p90 (ms)", "90th_percentile_frame_build_time_millis", "{:.2f}"),
    ("Build p99 (ms)", "99th_percentile_frame_build_time_millis", "{:.2f}"),
    ("Build over budget", "missed_frame_build_budget_count", "{:.0f}"),
    ("Raster avg (ms)", "average_frame_rasterizer_time_millis", "{:.2f}"),
    ("Raster p90 (ms)", "90th_percentile_frame_rasterizer_time_millis", "{:.2f}"),
    ("Raster p99 (ms)", "99th_percentile_frame_rasterizer_time_millis", "{:.2f}"),
    ("Raster over budget", "missed_frame_rasterizer_budget_count", "{:.0f}"),
]
VARIANTS = ["plain", "overglass", "lgr"]

folder = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/perf")
data = {}
for variant in VARIANTS:
    path = folder / f"scroll_{variant}.timeline_summary.json"
    if path.exists():
        data[variant] = json.loads(path.read_text())
if not data:
    sys.exit(f"No summaries found in {folder}")

names = list(data)
print("| Metric | " + " | ".join(names) + " |")
print("| --- |" + " --- |" * len(names))
for title, key, fmt in ROWS:
    cells = [fmt.format(data[n][key]) if key in data[n] else "n/a" for n in names]
    print(f"| {title} | " + " | ".join(cells) + " |")

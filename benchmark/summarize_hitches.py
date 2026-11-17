#!/usr/bin/env python3
"""Prints one Markdown row per .trace file written by run_instruments.sh."""
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

XPATH = '/trace-toc/run/data/table[@schema="hitches"]'


def hitches(root):
    """Returns (start in s, duration in ms) per hitch.

    xctrace writes a repeated value once and points to it with `ref`.
    """
    known = {}
    result = []
    for row in root.iter("row"):
        fields = {}
        for cell in row:
            if "id" in cell.attrib and cell.text:
                known[cell.attrib["id"]] = cell.text
            if cell.tag in ("start-time", "duration"):
                fields[cell.tag] = int(cell.text or known.get(cell.attrib.get("ref", ""), "0"))
        result.append((fields.get("start-time", 0) / 1e9, fields.get("duration", 0) / 1e6))
    return result


# Exporting the table of contents crashes xctrace on these traces, so the
# table is requested directly.
for arg in sys.argv[1:]:
    trace = pathlib.Path(arg)
    done = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath", XPATH],
        capture_output=True, text=True,
    )
    if done.returncode != 0 or "<schema" not in done.stdout:
        print(f"| {trace.stem} | export failed | | | |")
        continue
    found = hitches(ET.fromstring(done.stdout))
    values = [duration for _, duration in found]
    when = ", ".join(f"{start:.1f}" for start, _ in found) or "-"
    print(f"| {trace.stem} | {len(values)} | {sum(values):.1f} | {max(values, default=0.0):.1f} | {when} |")

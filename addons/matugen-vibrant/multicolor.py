#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: multicolor.py IMAGE OUTPUT")

image, output = sys.argv[1:]
result = subprocess.run(
    ["matugen", "image", image, "--show-source-colors"],
    capture_output=True,
    text=True,
    check=True,
)
colors = [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("#")]
if len(colors) < 2:
    raise SystemExit("matugen returned fewer than two source colors")

path = Path(output)
data = json.loads(path.read_text(encoding="utf-8"))
accent_keys = ["mauve", "blue", "sapphire", "teal", "green", "yellow", "peach", "red", "pink"]
for index, key in enumerate(accent_keys):
    data[key] = colors[index % len(colors)]
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

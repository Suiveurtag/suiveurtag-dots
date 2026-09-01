#!/usr/bin/env python3
import colorsys
import json
import os
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: multicolor.py IMAGE OUTPUT")

image, output = sys.argv[1:]


def read_mode():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    settings_path = config_home / "serpantinum/settings.json"
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "normal"
    mode = str(settings.get("matugenColorMode", "")).lower()
    if mode in {"off", "normal", "vivid"}:
        return mode
    return "vivid" if settings.get("vibrantMatugenColors") is True else "normal"


def lift_dark_color(value):
    if not isinstance(value, str) or not value.startswith("#"):
        return value
    raw = value[1:]
    if len(raw) == 3:
        raw = "".join(char * 2 for char in raw)
    if len(raw) != 6:
        return value
    try:
        red, green, blue = (int(raw[index:index + 2], 16) / 255 for index in (0, 2, 4))
    except ValueError:
        return value
    hue, lightness, saturation = colorsys.rgb_to_hls(red, green, blue)
    if lightness >= 0.58:
        return value
    red, green, blue = colorsys.hls_to_rgb(hue, 0.58, saturation)
    return "#{:02x}{:02x}{:02x}".format(
        round(red * 255), round(green * 255), round(blue * 255)
    )


mode = read_mode()
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
    color = colors[index % len(colors)]
    data[key] = lift_dark_color(color) if mode == "vivid" else color
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

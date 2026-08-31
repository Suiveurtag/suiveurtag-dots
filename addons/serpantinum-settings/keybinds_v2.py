#!/usr/bin/env python3
"""Expose active Hyprland Lua bindings to the recovered legacy panel.

It also persists edits from the recovered panel while preserving generated
Lua loops (notably the workspace bindings).
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path


KEYBINDS = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hypr/config/keybinds.lua"
STRING = re.compile(r'"((?:\\.|[^"\\])*)"')
BIND = re.compile(r"hl\.bind\((.*?),\s*hl\.dsp\.([A-Za-z_][A-Za-z0-9_.]*)\((.*)\)")


def unquote(value: str) -> str:
    return bytes(value, "utf-8").decode("unicode_escape")


def parse_key(expression: str) -> dict[str, str] | None:
    literals = [unquote(match.group(1)) for match in STRING.finditer(expression)]
    if ".. key" in expression:
        return None
    value = ("SUPER" if "mainMod" in expression else "") + "".join(literals)
    parts = [part.strip() for part in value.split("+") if part.strip()]
    if not parts:
        return None
    return {"mods": " ".join(parts[:-1]), "key": parts[-1]}


def rows() -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    if not KEYBINDS.is_file():
        return result
    for line in KEYBINDS.read_text(encoding="utf-8").splitlines():
        match = BIND.search(line)
        if not match:
            continue
        key_data = parse_key(match.group(1))
        if key_data is None:
            continue
        dispatcher = match.group(2)
        args = match.group(3).strip()
        if dispatcher == "exec_cmd":
            command_match = STRING.search(args)
            dispatcher = "exec"
            args = unquote(command_match.group(1)) if command_match else args
        result.append({
            "type": "bind",
            "mods": key_data["mods"],
            "key": key_data["key"],
            "dispatcher": dispatcher,
            "command": args,
            "isEditing": False,
        })
    return result


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def save(rows_data: list[dict[str, object]]) -> None:
    original = KEYBINDS.read_text(encoding="utf-8")
    literal_lines = []
    for item in rows_data:
        mods = str(item.get("mods", "")).strip()
        key = str(item.get("key", "")).strip()
        dispatcher = str(item.get("dispatcher", "exec")).strip()
        command = str(item.get("command", "")).strip()
        if not key and not command:
            continue
        parts = [part for part in mods.split() if part] + ([key] if key else [])
        uses_main_mod = "$mainMod" in parts
        parts = [part for part in parts if part != "$mainMod"]
        parts = ["SHIFT" if part in ("SHIFT_L", "SHIFT_R") else part for part in parts]
        suffix = " + ".join(parts)
        chord = ("mainMod" + (f' .. " + {suffix}"' if suffix else "")) if uses_main_mod else json.dumps(" + ".join(parts), ensure_ascii=False)
        if dispatcher == "exec":
            rhs = f"hl.dsp.exec_cmd({lua_string(command)})"
        else:
            # Preserve structured Lua calls (resize/focus/mouse options).
            # The legacy editor exposes them, but cannot round-trip their
            # object arguments safely from its flat command field.
            literal_lines.append(None)
            continue
        literal_lines.append(f"hl.bind({chord}, {rhs})")

    lines = original.splitlines(keepends=True)
    # Keep generated workspace bindings (".. key") intact, but rewrite
    # ordinary bindings using mainMod as well as explicit modifier strings.
    bind_indexes = [i for i, line in enumerate(lines) if "hl.bind(" in line and ".. key" not in line]
    if len(bind_indexes) < len(literal_lines):
        raise RuntimeError("not enough literal bindings in the active Lua file")
    for index, replacement in zip(bind_indexes, literal_lines):
        if replacement is None:
            continue
        if "{ locked" in lines[index]:
            replacement = replacement[:-1] + ", { locked = true })"
        newline = "\n" if lines[index].endswith("\n") else ""
        lines[index] = replacement + newline
    temporary = KEYBINDS.with_suffix(KEYBINDS.suffix + ".tmp")
    temporary.write_text("".join(lines), encoding="utf-8")
    temporary.replace(KEYBINDS)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        print(json.dumps(rows(), ensure_ascii=False))
    elif sys.argv[1] == "save":
        save(json.loads(sys.argv[2]))
        print(json.dumps({"ok": True}))
    else:
        raise SystemExit("usage: keybinds_v2.py [list|save JSON]")

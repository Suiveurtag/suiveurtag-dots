#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from datetime import datetime
from pathlib import Path


HOME = Path.home()
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")).expanduser()
XDG_CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")).expanduser()
HYPR_BASE = Path(os.environ.get("HYPR_CONFIG_DIR", XDG_CONFIG_HOME / "hypr")).expanduser()
QS_DIR = Path(
    os.environ.get("HYPR_QUICKSHELL_DIR", HYPR_BASE / "scripts/quickshell")
).expanduser()
SETTINGS_POPUP = Path(
    os.environ.get(
        "MATUGEN_SETTINGS_POPUP",
        QS_DIR / "settings/SettingsPopup.qml",
    )
).expanduser()
SETTINGS = Path(os.environ.get("HYPR_SETTINGS", HYPR_BASE / "settings.json")).expanduser()
MATUGEN_BASE = Path(
    os.environ.get("MATUGEN_CONFIG_DIR", XDG_CONFIG_HOME / "matugen")
).expanduser()
MATUGEN_CONFIG = Path(
    os.environ.get("MATUGEN_CONFIG", MATUGEN_BASE / "config.toml")
).expanduser()
MATUGEN_TEMPLATE = Path(
    os.environ.get(
        "MATUGEN_QS_TEMPLATE",
        MATUGEN_BASE / "templates/qs_colors.json.template",
    )
).expanduser()
WALLPAPER_CACHE = Path(
    os.environ.get(
        "MATUGEN_WALLPAPER_CACHE",
        XDG_CACHE_HOME / "quickshell/wallpaper_picker/current_wallpaper.png",
    )
).expanduser()
RELOAD_SCRIPT = Path(
    os.environ.get(
        "MATUGEN_RELOAD_SCRIPT",
        QS_DIR / "wallpaper/matugen_reload.sh",
    )
).expanduser()
SHELL_QML = Path(os.environ.get("MATUGEN_SHELL_QML", QS_DIR / "Shell.qml")).expanduser()
ADDON_DIR = Path(
    os.environ.get("XDG_DATA_HOME", HOME / ".local/share")
).expanduser() / "quickshell-addons/matugen-vibrant"
STATE_DIR = ADDON_DIR / "state"
BACKUP_DIR = ADDON_DIR / "backups"
CARD_SOURCE = ADDON_DIR / "VibrantMatugenCard.qml"
CARD_TARGET = SETTINGS_POPUP.parent / "VibrantMatugenCard.qml"
VIBRANT_TEMPLATE = ADDON_DIR / "qs_colors.json.template"
STOCK_TEMPLATE = STATE_DIR / "upstream-qs_colors.json.template"
TYPE_STATE = STATE_DIR / "quickshell-type.json"
LOCK_FILE = STATE_DIR / "apply.lock"

TEMPLATE_MARKER = '"_matugenVibrantAddon": true'
TYPE_BEGIN = "# BEGIN user-addon: matugen-vibrant scheme"
TYPE_END = "# END user-addon: matugen-vibrant scheme"
TYPE_BLOCK = f'{TYPE_BEGIN}\ntype = "SchemeVibrant"\n{TYPE_END}\n'
TYPE_BLOCK_RE = re.compile(
    rf"^[ \t]*{re.escape(TYPE_BEGIN)}\n.*?^[ \t]*{re.escape(TYPE_END)}\n?",
    flags=re.MULTILINE | re.DOTALL,
)

QML_MARKERS = (
    "matugen-vibrant import",
    "matugen-vibrant max-index",
    "matugen-vibrant keyboard-toggle",
    "matugen-vibrant scroll-position",
    "matugen-vibrant general-toggle",
    "matugen-vibrant search-card",
    "matugen-vibrant card",
)


class PatchError(RuntimeError):
    pass


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def backup(path: Path) -> None:
    if not path.exists():
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    shutil.copy2(path, BACKUP_DIR / f"{path.name}.{timestamp}")


def find_matching_brace(text: str, opening: int) -> int:
    if opening < 0 or text[opening] != "{":
        raise PatchError("invalid QML brace anchor")

    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = opening
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""

        if line_comment:
            if char == "\n":
                line_comment = False
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char in ('"', "'"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1

    raise PatchError("unbalanced QML braces")


def replace_once(text: str, pattern: str, replacement: str, description: str) -> str:
    patched, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise PatchError(f"required SettingsPopup anchor not found: {description}")
    return patched


def patch_settings_popup(text: str) -> str:
    if "BEGIN user-addon: matugen-vibrant card" in text:
        if "BEGIN user-addon: matugen-vibrant import" not in text:
            import_match = re.search(r'(?m)^import "\.\./"\s*$', text)
            if not import_match:
                raise PatchError("SettingsPopup local import anchor not found")
            import_block = (
                "\n// BEGIN user-addon: matugen-vibrant import\n"
                'import "." as MatugenVibrant\n'
                "// END user-addon: matugen-vibrant import"
            )
            text = text[: import_match.end()] + import_block + text[import_match.end() :]
        text = re.sub(
            r"^(\s*)VibrantMatugenCard\s*\{",
            r"\1MatugenVibrant.VibrantMatugenCard {",
            text,
            count=1,
            flags=re.MULTILINE,
        )

    present_markers = [marker for marker in QML_MARKERS if f"BEGIN user-addon: {marker}" in text]
    if present_markers:
        if len(present_markers) != len(QML_MARKERS):
            raise PatchError("partial vibrant Matugen QML patch detected")
        return text

    card_matches = list(
        re.finditer(
            r"(?m)^(?P<indent>[ \t]*)\{\s*tab:\s*0,\s*boxIndex:\s*(?P<index>\d+).*?$",
            text,
        )
    )
    if not card_matches:
        raise PatchError("General settings search cards not found")

    max_line = re.search(r"(?m)^[ \t]*if \(tab === 0\) return (?P<index>\d+);\s*$", text)
    if not max_line:
        raise PatchError("General settings keyboard range not found")

    existing_max = max(
        max(int(match.group("index")) for match in card_matches),
        int(max_line.group("index")),
    )
    addon_index = existing_max + 1
    addon_scroll_y = max(0, addon_index * 120 - 200)

    import_match = re.search(r'(?m)^import "\.\./"\s*$', text)
    if not import_match:
        raise PatchError("SettingsPopup local import anchor not found")
    import_block = (
        "\n// BEGIN user-addon: matugen-vibrant import\n"
        'import "." as MatugenVibrant\n'
        "// END user-addon: matugen-vibrant import"
    )
    text = text[: import_match.end()] + import_block + text[import_match.end() :]

    max_indent = re.match(r"[ \t]*", max_line.group(0)).group(0)
    max_block = (
        f"{max_indent}// BEGIN user-addon: matugen-vibrant max-index\n"
        f"{max_indent}if (tab === 0) return {addon_index};\n"
        f"{max_indent}// END user-addon: matugen-vibrant max-index"
    )
    text = text[: max_line.start()] + max_block + text[max_line.end() :]

    keyboard_anchor = r"^(?P<indent>[ \t]*)\} else if \(root\.currentTab === 1\) \{$"
    keyboard_match = re.search(keyboard_anchor, text, flags=re.MULTILINE)
    if not keyboard_match:
        raise PatchError("General settings keyboard activation anchor not found")
    indent = keyboard_match.group("indent")
    keyboard_block = (
        f" else if (root.highlightedBox === {addon_index}) {{\n"
        f"{indent}    if (generalLoader.item) generalLoader.item.toggleVibrantMatugen();\n"
        f"{indent}}}\n"
        f"{indent}// END user-addon: matugen-vibrant keyboard-toggle\n"
        f"{indent}}} else if (root.currentTab === 1) {{"
    )
    text = (
        text[: keyboard_match.start()]
        + f"{indent}// BEGIN user-addon: matugen-vibrant keyboard-toggle\n{indent}"
        + keyboard_block
        + text[keyboard_match.end() :]
    )

    scroll_anchor = r"^(?P<indent>[ \t]*)generalLoader\.item\.scrollToBox\(approxY\);$"
    scroll_match = re.search(scroll_anchor, text, flags=re.MULTILINE)
    if not scroll_match:
        raise PatchError("General settings scroll anchor not found")
    indent = scroll_match.group("indent")
    scroll_block = (
        f"{indent}// BEGIN user-addon: matugen-vibrant scroll-position\n"
        f"{indent}else if (box === {addon_index}) approxY = root.s({addon_scroll_y});\n"
        f"{indent}// END user-addon: matugen-vibrant scroll-position\n"
        f"{indent}generalLoader.item.scrollToBox(approxY);"
    )
    text = text[: scroll_match.start()] + scroll_block + text[scroll_match.end() :]

    general_function_anchor = r"^(?P<indent>[ \t]*)function focusWpDirInput\(\) \{.*$"
    function_match = re.search(general_function_anchor, text, flags=re.MULTILINE)
    if not function_match:
        raise PatchError("General tab helper function anchor not found")
    line_end = text.find("\n", function_match.end())
    if line_end == -1:
        raise PatchError("invalid General tab helper function")
    indent = function_match.group("indent")
    function_block = (
        f"{indent}// BEGIN user-addon: matugen-vibrant general-toggle\n"
        f"{indent}function toggleVibrantMatugen() {{ vibrantMatugenCard.toggle(); }}\n"
        f"{indent}// END user-addon: matugen-vibrant general-toggle\n"
    )
    text = text[: line_end + 1] + function_block + text[line_end + 1 :]

    card_matches = list(
        re.finditer(
            r"(?m)^(?P<indent>[ \t]*)\{\s*tab:\s*0,\s*boxIndex:\s*(?P<index>\d+).*?$",
            text,
        )
    )
    search_anchor = max(card_matches, key=lambda match: int(match.group("index")))
    anchor_line = search_anchor.group(0).rstrip()
    if not anchor_line.endswith(","):
        anchor_line += ","
    search_block = (
        f"{anchor_line}\n"
        f"{search_anchor.group('indent')}// BEGIN user-addon: matugen-vibrant search-card\n"
        f'{search_anchor.group("indent")}{{ tab: 0, boxIndex: {addon_index}, label: "Vibrant Matugen colors", '
        f'desc: "Expanded wallpaper-matched palette", icon: "󰏘", color: "teal" }},\n'
        f"{search_anchor.group('indent')}// END user-addon: matugen-vibrant search-card"
    )
    text = text[: search_anchor.start()] + search_block + text[search_anchor.end() :]

    column_match = re.search(
        r"ColumnLayout\s*\{\s*\n\s*id:\s*settingsMainCol\b",
        text,
        flags=re.MULTILINE,
    )
    if not column_match:
        raise PatchError("General settings column not found")
    opening = text.find("{", column_match.start())
    closing = find_matching_brace(text, opening)
    closing_line_start = text.rfind("\n", 0, closing) + 1
    card_block = f'''                    // BEGIN user-addon: matugen-vibrant card
                    MatugenVibrant.VibrantMatugenCard {{
                        id: vibrantMatugenCard
                        uiScale: root.s(1)
                        highlighted: root.highlightedBox === {addon_index}
                        accentColor: root.teal
                        baseColor: root.base
                        textColor: root.text
                        subtextColor: root.subtext0
                        surface0Color: root.surface0
                        surface1Color: root.surface1
                        surface2Color: root.surface2
                        settingsPath: Config.settingsJsonPath
                        onSelected: root.highlightedBox = {addon_index}
                    }}
                    // END user-addon: matugen-vibrant card

'''
    text = text[:closing_line_start] + card_block + text[closing_line_start:]

    for marker in QML_MARKERS:
        if f"BEGIN user-addon: {marker}" not in text:
            raise PatchError(f"failed to add QML patch block: {marker}")
    return text


def section_bounds(text: str, section: str) -> tuple[int, int]:
    header = re.search(rf"(?m)^\[{re.escape(section)}\]\s*$", text)
    if not header:
        raise PatchError(f"Matugen config section not found: [{section}]")
    following = re.search(r"(?m)^\[[^\n]+\]\s*$", text[header.end() :])
    end = header.end() + following.start() if following else len(text)
    return header.end(), end


def save_type_state(present: bool, line: str = "", offset: int = 0) -> None:
    atomic_write(
        TYPE_STATE,
        json.dumps({"present": present, "line": line, "offset": offset}, indent=2) + "\n",
    )


def load_type_state() -> dict:
    if not TYPE_STATE.is_file():
        return {"present": False, "line": "", "offset": 0}
    try:
        data = json.loads(TYPE_STATE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid saved Matugen type state: {error}") from error
    return {
        "present": data.get("present") is True,
        "line": str(data.get("line", "")),
        "offset": int(data.get("offset", 0)),
    }


def patch_matugen_config(text: str, enabled: bool) -> str:
    has_marker = TYPE_BEGIN in text
    if enabled:
        if has_marker:
            return text
        section_start, section_end = section_bounds(text, "templates.quickshell")
        section = text[section_start:section_end]
        type_match = re.search(r"(?m)^[ \t]*type\s*=.*$", section)
        if type_match:
            original_line = type_match.group(0)
            absolute_start = section_start + type_match.start()
            absolute_end = section_start + type_match.end()
            if absolute_end < len(text) and text[absolute_end] == "\n":
                absolute_end += 1
            text = text[:absolute_start] + text[absolute_end:]
            save_type_state(True, original_line, type_match.start())
        else:
            save_type_state(False)

        section_start, section_end = section_bounds(text, "templates.quickshell")
        return text[:section_end] + TYPE_BLOCK + text[section_end:]

    if not has_marker:
        return text

    state = load_type_state()
    match = TYPE_BLOCK_RE.search(text)
    if not match:
        raise PatchError("invalid vibrant Matugen scheme block")
    restored = text[: match.start()] + text[match.end() :]
    if state["present"]:
        section_start, section_end = section_bounds(restored, "templates.quickshell")
        insertion = section_start + min(max(0, state["offset"]), section_end - section_start)
        restored = restored[:insertion] + state["line"] + "\n" + restored[insertion:]
    return restored


def validate_toml(text: str) -> None:
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise PatchError(f"Matugen config would be invalid: {error}") from error


def validate_qml(path: Path) -> None:
    qmllint = shutil.which("qmllint")
    if not qmllint:
        raise PatchError("qmllint is required but was not found")
    result = subprocess.run(
        [qmllint, "-I", str(QS_DIR), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"qmllint rejected {path.name}:\n{details}")


def install_card() -> bool:
    if not CARD_SOURCE.is_file():
        raise PatchError(f"missing addon card: {CARD_SOURCE}")
    if CARD_TARGET.is_file() and CARD_TARGET.read_bytes() == CARD_SOURCE.read_bytes():
        return False
    CARD_TARGET.parent.mkdir(parents=True, exist_ok=True)
    temporary = CARD_TARGET.with_name(f".{CARD_TARGET.name}.matugen-vibrant")
    shutil.copy2(CARD_SOURCE, temporary)
    os.replace(temporary, CARD_TARGET)
    return True


def sync_template(enabled: bool) -> bool:
    if not MATUGEN_TEMPLATE.is_file():
        raise PatchError(f"Matugen Quickshell template not found: {MATUGEN_TEMPLATE}")
    if not VIBRANT_TEMPLATE.is_file():
        raise PatchError(f"vibrant Matugen template not found: {VIBRANT_TEMPLATE}")

    current = MATUGEN_TEMPLATE.read_text(encoding="utf-8")
    if TEMPLATE_MARKER not in current:
        if not STOCK_TEMPLATE.is_file() or STOCK_TEMPLATE.read_text(encoding="utf-8") != current:
            atomic_write(STOCK_TEMPLATE, current)

    if enabled:
        desired = VIBRANT_TEMPLATE.read_text(encoding="utf-8")
    elif TEMPLATE_MARKER in current:
        if not STOCK_TEMPLATE.is_file():
            raise PatchError("cannot restore the upstream Matugen template: no saved copy")
        desired = STOCK_TEMPLATE.read_text(encoding="utf-8")
    else:
        desired = current

    if desired == current:
        return False
    backup(MATUGEN_TEMPLATE)
    atomic_write(MATUGEN_TEMPLATE, desired)
    return True


def sync_config(enabled: bool) -> bool:
    if not MATUGEN_CONFIG.is_file():
        raise PatchError(f"Matugen config not found: {MATUGEN_CONFIG}")
    current = MATUGEN_CONFIG.read_text(encoding="utf-8")
    desired = patch_matugen_config(current, enabled)
    validate_toml(desired)
    if desired == current:
        return False
    backup(MATUGEN_CONFIG)
    atomic_write(MATUGEN_CONFIG, desired)
    return True


def read_enabled() -> bool:
    try:
        data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise PatchError(f"settings.json not found: {SETTINGS}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    if not isinstance(data, dict):
        raise PatchError("settings.json root is not an object")
    return data.get("vibrantMatugenColors") is True


def write_enabled(enabled: bool) -> bool:
    try:
        data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PatchError(f"invalid settings.json: {error}") from error
    if not isinstance(data, dict):
        raise PatchError("settings.json root is not an object")
    if data.get("vibrantMatugenColors") is enabled:
        return False
    data["vibrantMatugenColors"] = enabled
    backup(SETTINGS)
    atomic_write(SETTINGS, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return True


def regenerate_theme() -> None:
    matugen = shutil.which("matugen")
    if not matugen or not WALLPAPER_CACHE.is_file():
        return
    result = subprocess.run(
        [matugen, "image", str(WALLPAPER_CACHE), "--source-color-index", "0"],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        raise PatchError(f"Matugen could not regenerate the current theme:\n{details}")
    if RELOAD_SCRIPT.is_file():
        subprocess.run(["bash", str(RELOAD_SCRIPT)], check=False)


def reload_quickshell() -> None:
    quickshell = shutil.which("quickshell")
    pgrep = shutil.which("pgrep")
    if not quickshell or not pgrep or not SHELL_QML.is_file():
        return
    running = subprocess.run(
        [pgrep, "-f", f"quickshell.*{re.escape(str(SHELL_QML))}"],
        capture_output=True,
        text=True,
    )
    if running.returncode != 0:
        return
    subprocess.run(
        [quickshell, "-p", str(SHELL_QML), "ipc", "call", "main", "forceReload"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install and manage vibrant Matugen colors")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--enable", action="store_true", help="enable vibrant Matugen colors")
    group.add_argument("--disable", action="store_true", help="disable vibrant Matugen colors")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not SETTINGS_POPUP.is_file():
        raise PatchError(f"SettingsPopup.qml not found: {SETTINGS_POPUP}")

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        explicit_toggle = args.enable or args.disable
        if explicit_toggle:
            enabled = args.enable
            settings_changed = write_enabled(enabled)
        else:
            enabled = read_enabled()
            settings_changed = False

        card_changed = install_card()
        validate_qml(CARD_TARGET)

        popup_original = SETTINGS_POPUP.read_text(encoding="utf-8")
        popup_patched = patch_settings_popup(popup_original)
        popup_changed = popup_patched != popup_original
        if popup_changed:
            fd, temporary_name = tempfile.mkstemp(
                prefix=".SettingsPopup.qml.", dir=SETTINGS_POPUP.parent, text=True
            )
            temporary = Path(temporary_name)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(popup_patched)
                os.chmod(temporary, SETTINGS_POPUP.stat().st_mode)
                validate_qml(temporary)
                backup(SETTINGS_POPUP)
                os.replace(temporary, SETTINGS_POPUP)
            except Exception:
                temporary.unlink(missing_ok=True)
                raise
        else:
            validate_qml(SETTINGS_POPUP)

        template_changed = sync_template(enabled)
        config_changed = sync_config(enabled)
        if explicit_toggle or template_changed or config_changed:
            regenerate_theme()
        if popup_changed or card_changed:
            reload_quickshell()

        changes = []
        if popup_changed:
            changes.append("settings UI")
        if card_changed:
            changes.append("card asset")
        if settings_changed:
            changes.append("saved option")
        if template_changed:
            changes.append("palette template")
        if config_changed:
            changes.append("Quickshell scheme")
        state = "enabled" if enabled else "disabled"
        if changes:
            print(f"matugen-vibrant: {state}; updated " + ", ".join(changes))
        else:
            print(f"matugen-vibrant: {state}; addon already installed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"matugen-vibrant: {error}", file=sys.stderr)
        raise SystemExit(1)

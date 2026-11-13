"""
build_data.py - validate the roadmap data against the game and generate Data/Flags.lua.

What it checks
  * every flag referenced by the Lua data (P/G/F/markers) exists in the game's flag
    definitions, and global/player usage matches the flag's allowed usage bits
  * every journal step referenced with Q(quest, step) exists in quest_prototypes
  * G() flags are really used as global flags by the Osiris story (warning otherwise)
  * every Lua source file only uses characters the in-game IMGUI font can draw
    (ASCII + Latin-1; the SE font has no glyphs for symbols like a check mark)

What it writes
  * Mods/CompanionRoadmap/ScriptExtender/Lua/Data/Flags.lua
      CR.Flags       = { FlagName = { "guid", usage }, ... }   (only referenced flags)
      CR.QuestTitles = { QuestID = "Journal title", ... }

Inputs come from extract_game_data.py (run that first; it reads your BG3 install).

--offline (used by CI, no game files needed) checks against the committed
Data/Flags.lua instead: unknown flags, wrong global/player usage, journal quests
that were never generated, unprintable characters, and the mod metadata
(Config.json, MCM_blueprint.json, meta.lsx). It never writes anything.

Usage:
  python tools/build_data.py [--cache tools/.cache] [--check-only]
  python tools/build_data.py --offline
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_DIR = os.path.join(ROOT, "Mods", "CompanionRoadmap", "ScriptExtender", "Lua")
DATA_DIR = os.path.join(LUA_DIR, "Data")
FLAGS_OUT = os.path.join(DATA_DIR, "Flags.lua")

USAGE_GLOBAL = 1
USAGE_DIALOG = 2
USAGE_OBJECT = 4

STR = r'"([^"\\]*)"'
RE_LOCAL = re.compile(r'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*' + STR + r'\s*$', re.M)
RE_Q = re.compile(r'\bQ\(\s*(?:' + STR + r'|([A-Za-z_][A-Za-z0-9_]*))\s*,\s*' + STR + r'\s*\)')
RE_FLAG = re.compile(r'\b(?:C\.)?([PGF])\(\s*' + STR + r'\s*(?:,\s*' + STR + r'\s*)?\)')
RE_MARKER_BLOCK = re.compile(r'Guides\.Markers\s*=\s*\{(.*?)\n\}', re.S)
RE_REGION_FLAG = re.compile(r'flag\s*=\s*' + STR)


def load_flags(path):
    flags = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or not parts[0]:
                continue
            flags[parts[0]] = {"guid": parts[1].lower(), "usage": int(parts[2] or 0),
                               "desc": parts[4] if len(parts) > 4 else ""}
    return flags


def load_quests(path):
    """quests.tsv: QuestID <tab> StepID <tab> Title (title repeated per row)."""
    steps = defaultdict(set)
    titles = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            quest, step, title = parts[0], parts[1], parts[2]
            steps[quest].add(step)
            if title:
                titles[quest] = title
    return steps, titles


def load_story_usage(goals_dir):
    """Collect how the Osiris story targets each flag: global (NULL / DB_GlobalFlag) or object."""
    usage = defaultdict(lambda: {"global": 0, "object": 0})
    rx_name = re.compile(r'([A-Za-z0-9_]+?)_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    rx_call = re.compile(r'\b(SetFlag|ClearFlag|GetFlag|FlagSet|FlagCleared)\(\s*(?:\(FLAG\))?\s*([A-Za-z0-9_]+?_[0-9a-fA-F-]{36})\s*,\s*([^,)]+)')
    rx_global = re.compile(r'\b(DB_GlobalFlag|PROC_GlobalSetFlagAndCache|GlobalSetFlag|GlobalClearFlag)\(\s*(?:\(FLAG\))?\s*([A-Za-z0-9_]+?_[0-9a-fA-F-]{36})')
    for root, _, files in os.walk(goals_dir):
        for fn in files:
            if not fn.endswith(".txt"):
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            for m in rx_global.finditer(text):
                name = rx_name.match(m.group(2))
                if name:
                    usage[name.group(1)]["global"] += 1
            for m in rx_call.finditer(text):
                name = rx_name.match(m.group(2))
                if not name:
                    continue
                target = m.group(3).strip()
                if target.startswith("NULL_"):
                    usage[name.group(1)]["global"] += 1
                elif target != "_":
                    usage[name.group(1)]["object"] += 1
    return usage


def latin1_problems(path):
    problems = []
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            for ch in line:
                if ord(ch) > 0xFF:
                    problems.append((lineno, ch))
    return problems


def scan_lua(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    # strip comments so commented-out code is not validated
    text_nc = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
    text_nc = re.sub(r'--[^\n]*', '', text_nc)
    consts = {m.group(1): m.group(2) for m in RE_LOCAL.finditer(text_nc)}
    quests, flags = [], []
    for m in RE_Q.finditer(text_nc):
        quest = m.group(1) if m.group(1) is not None else consts.get(m.group(2))
        quests.append((quest, m.group(3), m.group(2)))
    for m in RE_FLAG.finditer(text_nc):
        kind, name, on = m.group(1), m.group(2), m.group(3)
        if kind == "P":
            on = "player"
        elif kind == "G":
            on = "global"
        else:
            on = on or "any"
        flags.append((name, on))
    if os.path.basename(path) == "CompanionGuides.lua":
        block = RE_MARKER_BLOCK.search(text_nc)
        if block:
            for m in re.finditer(STR, block.group(1)):
                flags.append((m.group(1), "global"))
        for m in RE_REGION_FLAG.finditer(text_nc):
            flags.append((m.group(1), "global"))
    return quests, flags


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def to_latin1(s):
    return "".join(ch if ord(ch) <= 0xFF else "?" for ch in s)


RE_GEN_FLAG = re.compile(r'^\s+(\w+) = \{ "([0-9a-f-]{36})", (\d+) \},', re.M)
RE_GEN_TITLE = re.compile(r'^\s+(\w+) = "', re.M)
GUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
MOD_DIR = os.path.join(ROOT, "Mods", "CompanionRoadmap")


def load_generated(path):
    """Flags and quest titles from the committed Data/Flags.lua (offline mode)."""
    text = open(path, encoding="utf-8").read()
    flags_part, _, titles_part = text.partition("\nCR.QuestTitles = {")
    flags = {m.group(1): {"guid": m.group(2), "usage": int(m.group(3)), "desc": ""}
             for m in RE_GEN_FLAG.finditer(flags_part)}
    titles = {m.group(1) for m in RE_GEN_TITLE.finditer(titles_part)}
    return flags, titles


def check_metadata(errors):
    """Config.json, MCM_blueprint.json and meta.lsx are well formed and agree with the code."""
    def rel(p):
        return os.path.relpath(p, ROOT)

    cfg_path = os.path.join(MOD_DIR, "ScriptExtender", "Config.json")
    try:
        cfg = json.load(open(cfg_path, encoding="utf-8-sig"))
        if cfg.get("ModTable") != "CompanionRoadmap":
            errors.append(f"{rel(cfg_path)}: ModTable must be 'CompanionRoadmap'")
        if "Lua" not in cfg.get("FeatureFlags", []):
            errors.append(f"{rel(cfg_path)}: FeatureFlags must contain 'Lua'")
    except (OSError, ValueError) as e:
        errors.append(f"{rel(cfg_path)}: {e}")

    bp_path = os.path.join(MOD_DIR, "MCM_blueprint.json")
    ids = set()
    try:
        bp = json.load(open(bp_path, encoding="utf-8-sig"))

        def walk(node):
            if isinstance(node, dict):
                if "Id" in node and "Type" in node:
                    ids.add(node["Id"])
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)
        walk(bp)
    except (OSError, ValueError) as e:
        errors.append(f"{rel(bp_path)}: {e}")
    # every MCM id the Lua code uses must exist in the blueprint
    wanted = {"toggle_roadmap", "open_roadmap"}
    settings_lua = os.path.join(LUA_DIR, "Client", "Settings.lua")
    block = re.search(r'local MCM_IDS = \{(.*?)\n\}', open(settings_lua, encoding="utf-8").read(), re.S)
    if block:
        wanted |= set(re.findall(r'=\s*"(\w+)"', block.group(1)))
    for missing in sorted(wanted - ids):
        errors.append(f"{rel(bp_path)}: setting '{missing}' is used by the Lua code but missing from the blueprint")

    meta_path = os.path.join(MOD_DIR, "meta.lsx")
    try:
        tree = ET.parse(meta_path)
        attrs = {a.get("id"): a.get("value") for a in tree.iter("attribute")}
        if attrs.get("Folder") != "CompanionRoadmap":
            errors.append(f"{rel(meta_path)}: Folder must be 'CompanionRoadmap'")
        if not GUID_RE.match(attrs.get("UUID") or ""):
            errors.append(f"{rel(meta_path)}: UUID is not a valid GUID")
        versions = {a.get("value") for a in tree.iter("attribute") if a.get("id") == "Version64"}
        if len(versions) != 1:
            errors.append(f"{rel(meta_path)}: ModuleInfo and PublishVersion Version64 differ")
        try:
            v = int(attrs.get("Version64") or "x")
            meta_version = f"{v >> 55}.{(v >> 47) & 0xFF}.{(v >> 31) & 0xFFFF}"
            core = open(os.path.join(LUA_DIR, "Shared", "Core.lua"), encoding="utf-8").read()
            m = re.search(r'CR\.Version\s*=\s*"([^"]+)"', core)
            if not m or m.group(1) != meta_version:
                errors.append(f"{rel(meta_path)}: Version64 is {meta_version} but CR.Version in Shared/Core.lua is "
                              f"{m.group(1) if m else 'missing'}")
        except ValueError:
            errors.append(f"{rel(meta_path)}: Version64 must be an integer")
    except (OSError, ET.ParseError) as e:
        errors.append(f"{rel(meta_path)}: {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", ".cache"))
    ap.add_argument("--check-only", action="store_true", help="validate without regenerating Data/Flags.lua")
    ap.add_argument("--offline", action="store_true", help="validate against the committed Data/Flags.lua (no game files)")
    args = ap.parse_args()

    story = None
    quest_steps, quest_titles, known_titles = None, {}, set()
    if args.offline:
        flags, known_titles = load_generated(FLAGS_OUT)
    else:
        flags_tsv = os.path.join(args.cache, "flags.tsv")
        quests_tsv = os.path.join(args.cache, "quests.tsv")
        goals_dir = os.path.join(args.cache, "goals")
        for p in (flags_tsv, quests_tsv):
            if not os.path.exists(p):
                sys.exit(f"Missing {p}. Run tools/extract_game_data.py first (or use --offline).")
        flags = load_flags(flags_tsv)
        quest_steps, quest_titles = load_quests(quests_tsv)
        story = load_story_usage(goals_dir) if os.path.isdir(goals_dir) else None

    errors, warnings = [], []
    used_flags, used_quests = {}, set()
    check_metadata(errors)

    lua_files = []
    for root, _, files in os.walk(LUA_DIR):
        for fn in files:
            if fn.endswith(".lua"):
                lua_files.append(os.path.join(root, fn))

    for path in sorted(lua_files):
        rel = os.path.relpath(path, ROOT)
        for lineno, ch in latin1_problems(path):
            errors.append(f"{rel}:{lineno}: character U+{ord(ch):04X} cannot be drawn by the IMGUI font")
        if not path.startswith(DATA_DIR) or os.path.basename(path) == "Flags.lua":
            continue
        quests, flag_refs = scan_lua(path)
        for quest, step, var in quests:
            if quest is None:
                errors.append(f"{rel}: Q({var}, \"{step}\") uses an unknown local constant")
                continue
            used_quests.add(quest)
            if quest_steps is None:
                if quest not in known_titles:
                    errors.append(f"{rel}: quest '{quest}' is not in Data/Flags.lua - run build_data.py with the game cache")
            elif quest not in quest_steps:
                errors.append(f"{rel}: unknown quest '{quest}'")
            elif step not in quest_steps[quest]:
                errors.append(f"{rel}: quest '{quest}' has no step '{step}'")
        for name, on in flag_refs:
            info = flags.get(name)
            if info is None:
                hint = " (not in Data/Flags.lua - run build_data.py with the game cache)" if args.offline else ""
                errors.append(f"{rel}: unknown flag '{name}'{hint}")
                continue
            used_flags[name] = info
            usage = info["usage"]
            if on == "global" and not usage & USAGE_GLOBAL:
                errors.append(f"{rel}: flag '{name}' is used as global but its usage ({usage}) does not allow it")
            if on == "player" and not usage & USAGE_OBJECT:
                errors.append(f"{rel}: flag '{name}' is used on the player but its usage ({usage}) is not an object flag")
            if story is not None and on == "global" and usage & USAGE_OBJECT:
                s = story.get(name)
                if s and s["global"] == 0 and s["object"] > 0:
                    warnings.append(f"{rel}: flag '{name}' is checked globally but the story only sets it on objects - use F(name) instead")
            if story is not None and on == "player" and usage & USAGE_GLOBAL:
                s = story.get(name)
                if s and s["object"] == 0 and s["global"] > 0:
                    warnings.append(f"{rel}: flag '{name}' is checked on the player but the story only uses it globally - use G(name) instead")

    for w in sorted(set(warnings)):
        print("WARN ", w)
    for e in sorted(set(errors)):
        print("ERROR", e)
    print(f"{len(used_flags)} flags and {len(used_quests)} quests referenced; "
          f"{len(set(errors))} errors, {len(set(warnings))} warnings.")
    if errors:
        sys.exit(1)
    if args.check_only or args.offline:
        return

    lines = [
        "-- =============================================================================",
        "-- Data/Flags.lua - GENERATED by tools/build_data.py from the game's own data.",
        "-- Do not edit by hand: change the companion files and re-run the tool.",
        "--   CR.Flags[name]       = { guid, usage }  usage bits: 1 global, 2 dialog, 4 object",
        "--   CR.QuestTitles[id]   = journal title",
        "-- =============================================================================",
        "",
        "CR.Flags = {",
    ]
    for name in sorted(used_flags):
        info = used_flags[name]
        lines.append(f'    {name} = {{ "{info["guid"]}", {info["usage"]} }},')
    lines += ["}", "", "CR.QuestTitles = {"]
    for quest in sorted(used_quests):
        for q in (quest, "ORI_Avatar_" + quest[8:] if quest.startswith("ORI_COM_") else None):
            if q and q in quest_titles:
                lines.append(f"    {q} = {lua_string(to_latin1(quest_titles[q]))},")
    lines += ["}", ""]
    with open(FLAGS_OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("Wrote", os.path.relpath(FLAGS_OUT, ROOT))


if __name__ == "__main__":
    main()

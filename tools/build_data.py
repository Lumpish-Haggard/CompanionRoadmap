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
      CR.Flags             = { FlagName = { "guid", usage }, ... }   (only referenced flags)
      CR.QuestTitles       = { QuestID = "Journal title", ... }        (English fallback)
      CR.QuestTitleHandles = { QuestID = "localisation handle", ... }
      CR.JournalHandles    = { ["QuestID/StepID"] = "localisation handle", ... }
    The handles let the mod quote the journal in the player's own language at
    runtime; no journal text is stored.

It also checks the companion portraits: UI/Theme.lua (T.Portraits), the texture bank
under Public/ and, with the game cache, the sticker files the bank points at.

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


HANDLE_RE = re.compile(r'^h[0-9a-f]{8}g[0-9a-f]{4}g[0-9a-f]{4}g[0-9a-f]{4}g[0-9a-f]{12}$')


def load_quests(path):
    """quests.tsv: QuestID, StepID, title, text, flags, dev comment, title handle, text handle.

    Returns steps per quest, English titles, and the localisation handles of the
    quest titles and of each step's journal text (empty for caches made by an older
    extract_game_data.py: run it again to get them)."""
    steps = defaultdict(set)
    titles, title_handles, step_handles = {}, {}, {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            quest, step, title = parts[0], parts[1], parts[2]
            steps[quest].add(step)
            if title:
                titles[quest] = title
            if len(parts) >= 8:
                if HANDLE_RE.match(parts[6]):
                    title_handles[quest] = parts[6]
                if HANDLE_RE.match(parts[7]):
                    step_handles[(quest, step)] = parts[7]
    return steps, titles, title_handles, step_handles


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


def generated_block(text, name):
    """The body of one `CR.<name> = { ... }` table in the generated Data/Flags.lua."""
    m = re.search(r'\nCR\.' + re.escape(name) + r' = \{\n(.*?)\n\}', text, re.S)
    return m.group(1) if m else ""


def load_generated(path):
    """Flags and quest titles from the committed Data/Flags.lua (offline mode)."""
    text = open(path, encoding="utf-8").read()
    flags = {m.group(1): {"guid": m.group(2), "usage": int(m.group(3)), "desc": ""}
             for m in RE_GEN_FLAG.finditer(generated_block(text, "Flags"))}
    titles = {m.group(1) for m in RE_GEN_TITLE.finditer(generated_block(text, "QuestTitles"))}
    return flags, titles


TEXTURE_BANK = os.path.join(ROOT, "Public", "CompanionRoadmap", "Content", "UI", "[PAK]_UI", "_merged.lsx")


def check_portraits(errors, warnings, cache):
    """The companion portraits: Theme.lua's T.Portraits, the texture bank and (with the
    game cache) the sticker files in Game.pak must all agree."""
    def rel(p):
        return os.path.relpath(p, ROOT)

    theme = os.path.join(LUA_DIR, "UI", "Theme.lua")
    theme_src = open(theme, encoding="utf-8").read()
    block = re.search(r'T\.Portraits = \{(.*?)\n\}', theme_src, re.S)
    # T.Portraits = { <Companion> = { <mood> = "<texture id>", ... }, ... }
    moods = ("neutral", "high", "low", "dating", "partnered", "dead")
    wanted = {}
    for comp, inner in re.findall(r'(\w+)\s*=\s*\{([^{}]*)\}', block.group(1)) if block else []:
        wanted[comp] = dict(re.findall(r'(\w+)\s*=\s*"([0-9a-f-]{36})"', inner))
    if not wanted:
        return
    all_used = {}
    for comp, pictures in sorted(wanted.items()):
        if "neutral" not in pictures:
            errors.append(f"{rel(theme)}: portrait set '{comp}' has no 'neutral' picture")
        for mood, guid in pictures.items():
            if mood not in moods:
                errors.append(f"{rel(theme)}: portrait set '{comp}' has an unknown mood '{mood}'")
            all_used[f"{comp}.{mood}"] = guid

    # game UI icons used by name (the skull for a dead companion without a sticker of their own)
    icons_block = re.search(r'T\.GameIcons = \{(.*?)\n\}', theme_src, re.S)
    game_icons = dict(re.findall(r'(\w+)\s*=\s*"([^"]+)"', icons_block.group(1))) if icons_block else {}
    if "dead" not in game_icons and any("dead" not in p for p in wanted.values()):
        errors.append(f"{rel(theme)}: T.GameIcons.dead is needed for companions without a 'dead' picture")
    icons_list = os.path.join(cache, "icons.txt") if cache else None
    if icons_list and os.path.exists(icons_list):
        known_icons = {line.strip() for line in open(icons_list, encoding="utf-8") if line.strip()}
        for key, name in sorted(game_icons.items()):
            if name not in known_icons:
                errors.append(f"{rel(theme)}: T.GameIcons.{key} = '{name}' is not an icon in the game's UI atlases")
    elif cache and game_icons:
        warnings.append("tools/.cache/icons.txt is missing: run tools/extract_game_data.py --only icons "
                        "to check the game icon names")
    if not os.path.exists(TEXTURE_BANK):
        errors.append(f"{rel(theme)}: T.Portraits is defined but {rel(TEXTURE_BANK)} does not exist")
        return
    try:
        tree = ET.parse(TEXTURE_BANK)
    except ET.ParseError as e:
        errors.append(f"{rel(TEXTURE_BANK)}: {e}")
        return
    bank = {}
    for node in tree.iter("node"):
        if node.get("id") != "Resource":
            continue
        attrs = {a.get("id"): a.get("value") for a in node.findall("attribute")}
        if not GUID_RE.match(attrs.get("ID") or ""):
            errors.append(f"{rel(TEXTURE_BANK)}: resource '{attrs.get('Name')}' has an invalid ID")
            continue
        if attrs["ID"] in bank:
            errors.append(f"{rel(TEXTURE_BANK)}: duplicate resource ID {attrs['ID']}")
        bank[attrs["ID"]] = attrs.get("SourceFile") or ""
    for name, guid in sorted(all_used.items()):
        if guid not in bank:
            errors.append(f"{rel(theme)}: portrait '{name}' uses {guid}, which is not declared in {rel(TEXTURE_BANK)}")
    for guid in sorted(set(bank) - set(all_used.values())):
        warnings.append(f"{rel(TEXTURE_BANK)}: resource {guid} is not used by T.Portraits")

    order = re.search(r'Guides\.Order = \{(.*?)\}', open(os.path.join(DATA_DIR, "CompanionGuides.lua"), encoding="utf-8").read(), re.S)
    for comp in re.findall(r'"(\w+)"', order.group(1)) if order else []:
        if comp not in wanted:
            warnings.append(f"{rel(theme)}: companion '{comp}' has no portrait")

    stickers = os.path.join(cache, "stickers.txt") if cache else None
    if stickers and os.path.exists(stickers):
        known = {line.strip() for line in open(stickers, encoding="utf-8") if line.strip()}
        for guid, source in sorted(bank.items()):
            if source not in known:
                errors.append(f"{rel(TEXTURE_BANK)}: '{source}' does not exist in the game's Game.pak")


# -----------------------------------------------------------------------------
# Cross-check with the game's camp scheduler (GLO_CampNights and the goals that
# declare camp scenes). A step that is done when a NIGHT_* camp scene has played
# must agree with what the scheduler requires for that scene.
# -----------------------------------------------------------------------------
GUID_PART = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
OSIRIS_CAST = re.compile(r"\((?:FLAG|CHARACTER|DIALOGRESOURCE|INTEGER|STRING|GUIDSTRING|TRIGGER)\)")


def load_camp_scheduler(goals_dir):
    """The scheduler's facts about camp scenes, from the story goals (save patches and debug goals skipped)."""
    s = {"approval": {}, "startDating": set(), "partner": set(), "dating": set(), "cancel": defaultdict(set)}
    night = r"(NIGHT_\w+?)_" + GUID_PART
    who = r"\w+?_(" + GUID_PART + r")"
    rx = {
        "approval": re.compile(r"DB_CampNight_Requirement_Approval\(\s*" + night + r"\s*,\s*" + who + r"\s*,\s*(-?\d+)\s*\)"),
        "who": re.compile(r"DB_CampNight_Requirement_(Partner|Dating|CanStartDating)\(\s*" + night + r"\s*,\s*" + who + r"\s*\)"),
        "cancel": re.compile(r"DB_CampNight_CancelledBy\(\s*" + night + r"\s*,\s*(\w+?)_" + GUID_PART + r"\s*\)"),
    }
    kinds = {"Partner": "partner", "Dating": "dating", "CanStartDating": "startDating"}
    for root, _, files in os.walk(goals_dir):
        for fn in files:
            if "SavegamePatches" in fn or "Debug" in fn:
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = OSIRIS_CAST.sub("", line.strip())
                    if not line.startswith("DB_CampNight_"):
                        continue
                    m = rx["approval"].match(line)
                    if m:
                        s["approval"].setdefault(m.group(1), {})[m.group(2)] = int(m.group(3))
                        continue
                    m = rx["who"].match(line)
                    if m:
                        s[kinds[m.group(1)]].add((m.group(2), m.group(3)))
                        continue
                    m = rx["cancel"].match(line)
                    if m:
                        s["cancel"][m.group(1)].add(m.group(2))
    return s


def strip_lua_comments(text):
    """Lua source without comments (string literals kept intact)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def lua_block_at(text, start):
    """The balanced {...} block whose opening brace is at `start` (string literals respected)."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError("unbalanced braces")


def lua_top_level_items(block):
    """The comma-separated entries of a {...} block, split at depth 0."""
    inner, items, depth, cur, i = block[1:-1], [], 0, [], 0
    while i < len(inner):
        c = inner[i]
        if c in "\"'":
            j = i + 1
            while j < len(inner) and inner[j] != c:
                j += 2 if inner[j] == "\\" else 1
            cur.append(inner[i:j + 1])
            i = j + 1
            continue
        if c in "({":
            depth += 1
        elif c in ")}":
            depth -= 1
        if c == "," and depth == 0:
            items.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    if "".join(cur).strip():
        items.append("".join(cur).strip())
    return items


def parse_guide_steps():
    """Steps of every companion file: id -> { comp uuid, approval, closes, after, done, fail, skip }."""
    steps = {}
    comp_dir = os.path.join(DATA_DIR, "Companions")
    for fn in sorted(os.listdir(comp_dir)):
        if not fn.endswith(".lua"):
            continue
        text = strip_lua_comments(open(os.path.join(comp_dir, fn), encoding="utf-8").read())
        uuid = re.search(r'\buuid\s*=\s*"(' + GUID_PART + r')"', text)
        sm = re.search(r"\bsteps\s*=\s*\{", text)
        if not uuid or not sm:
            continue
        body = lua_block_at(text, sm.end() - 1)
        i = 1
        while True:
            j = body.find("{", i)
            if j < 0:
                break
            blk = lua_block_at(body, j)
            i = j + len(blk)
            sid = re.search(r'\bid\s*=\s*"(\w+)"', blk)
            if not sid:
                continue

            def field(name):
                m = re.search(r"\b" + name + r"\s*=\s*\{", blk)
                return lua_block_at(blk, m.end() - 1) if m else "{}"
            approval = re.search(r"\bapproval\s*=\s*(\d+)", blk)
            closes = re.search(r'\bcloses\s*=\s*"(\w+)"', blk)
            steps[sid.group(1)] = {
                "file": fn, "uuid": uuid.group(1), "approval": int(approval.group(1)) if approval else None,
                "closes": closes.group(1) if closes else None, "after": re.findall(r'"(\w+)"', field("after")),
                "done": field("done"), "fail": field("fail"), "skip": field("skip"),
            }
    return steps


PARTNER_EVIDENCE = re.compile(r'ORI_State_PartneredWith|C\.Rel\("partnered"\)')
DATING_EVIDENCE = re.compile(r'ORI_State_Dating|ORI_State_PartneredWith|C\.Rel\("(?:partnered|dating)"\)')


def check_scheduler(errors, warnings, goals_dir):
    """Steps that are done when a camp scene played, compared with the scheduler's rules for that scene:
    - approval: the step's `approval` is what the scheduler asks (strictly above it for a scene that starts a romance)
    - partner / dating: a scene that needs a relationship must come after a step that establishes it
    - cancelled by: when the scene is the step's only route, whatever cancels it must close the step too"""
    sched = load_camp_scheduler(goals_dir)
    steps = parse_guide_steps()
    guides = strip_lua_comments(open(os.path.join(DATA_DIR, "CompanionGuides.lua"), encoding="utf-8").read())
    mstart = guides.index("Guides.Markers = {") + len("Guides.Markers = ")
    markers = dict(re.findall(r'(\w+)\s*=\s*"(\w+)"', lua_block_at(guides, mstart)))
    deadlines = re.findall(r'id\s*=\s*"(\w+)",\s*marker\s*=\s*"(\w+)"', guides)
    order = [d for d, _ in deadlines]
    deadline_flag = {d: markers.get(m) for d, m in deadlines}

    def closure(sid, seen):
        if sid in seen or sid not in steps:
            return seen
        seen.add(sid)
        for dep in steps[sid]["after"]:
            closure(dep, seen)
        return seen

    for sid, st in sorted(steps.items()):
        where = f"Data/Companions/{st['file']} {sid}"
        nights = re.findall(r'"(NIGHT_\w+)"', st["done"])
        if not nights:
            continue
        routes = lua_top_level_items(st["done"])
        only_nights = all(re.fullmatch(r'G\("NIGHT_\w+"\)', r) for r in routes)
        uuid = st["uuid"]

        # approval: a scene that starts a romance asks for strictly more than its value
        needs = {}
        for n in nights:
            req = sched["approval"].get(n, {}).get(uuid)
            if req is not None:
                needs[n] = req + 1 if (n, uuid) in sched["startDating"] else req
        if st["approval"] is not None and needs and st["approval"] not in needs.values():
            found = ", ".join(f"{n} needs {v}" for n, v in sorted(needs.items()))
            errors.append(f"{where}: approval = {st['approval']}, but the game's camp scheduler says {found}")
        if st["approval"] is None and only_nights and len(needs) == len(nights):
            found = ", ".join(f"{n} needs {v}" for n, v in sorted(needs.items()))
            warnings.append(f"{where}: has no approval, but the game's camp scheduler says {found}")

        # partner / dating: the step itself or one it waits for must establish the relationship
        chain = closure(sid, set())
        for n in nights:
            for kind, evidence, state in (("partner", PARTNER_EVIDENCE, "their partner"),
                                          ("dating", DATING_EVIDENCE, "dating them")):
                if (n, uuid) in sched[kind] and not any(evidence.search(steps[s]["done"]) for s in chain):
                    warnings.append(f"{where}: {n} only plays while you are {state}, but neither this step nor "
                                    f"any step in its 'after' chain establishes that")

        # cancelled by: only matters when the scene is the step's only way to be done
        if not only_nights:
            continue
        later = order[order.index(st["closes"]):] if st["closes"] in order else []
        closed_by = {deadline_flag[d] for d in later if deadline_flag.get(d)}
        for n in nights:
            for flag in sorted(sched["cancel"].get(n, ())):
                quoted = '"' + flag + '"'
                if flag in nights or quoted in st["fail"] or quoted in st["skip"] or quoted in st["done"] or flag in closed_by:
                    continue
                warnings.append(f"{where}: {n} is cancelled by {flag}, which the step neither fails, skips nor closes on")


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
    enum_choices = {}
    try:
        bp = json.load(open(bp_path, encoding="utf-8-sig"))

        def walk(node):
            if isinstance(node, dict):
                if "Id" in node and "Type" in node:
                    ids.add(node["Id"])
                    if node["Type"] == "enum":
                        enum_choices[node["Id"]] = list((node.get("Options") or {}).get("Choices") or [])
                        if node.get("Default") not in enum_choices[node["Id"]]:
                            errors.append(f"{rel(bp_path)}: enum '{node['Id']}' has a default that is not one of its choices")
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
    # MCM stores the chosen text, and Settings.lua maps it back by position: the lists must be identical
    settings_src = open(settings_lua, encoding="utf-8").read()
    for lua_list, mcm_id in (("SpoilerChoices", "spoilers"), ("OpacityChoices", "window_opacity"),
                             ("ToastChoices", "notify_position")):
        m = re.search(r'Set\.' + lua_list + r'\s*=\s*\{(.*?)\}', settings_src, re.S)
        lua_choices = re.findall(r'"([^"]*)"', m.group(1)) if m else None
        if lua_choices is None:
            errors.append(f"{rel(settings_lua)}: Set.{lua_list} not found")
        elif mcm_id in enum_choices and enum_choices[mcm_id] != lua_choices:
            errors.append(f"{rel(bp_path)}: the choices of '{mcm_id}' differ from Set.{lua_list} in {rel(settings_lua)}")

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
    title_handles, step_handles = {}, {}
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
        quest_steps, quest_titles, title_handles, step_handles = load_quests(quests_tsv)
        story = load_story_usage(goals_dir) if os.path.isdir(goals_dir) else None

    errors, warnings = [], []
    used_flags, used_quests, used_steps = {}, set(), set()
    check_metadata(errors)
    check_portraits(errors, warnings, None if args.offline else args.cache)
    if not args.offline and os.path.isdir(os.path.join(args.cache, "goals")):
        check_scheduler(errors, warnings, os.path.join(args.cache, "goals"))
    if quest_steps is not None and not step_handles:
        warnings.append("tools/.cache/quests.tsv has no localisation handles - run tools/extract_game_data.py again")

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
            else:
                used_steps.add((quest, step))
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
        "--   CR.QuestTitles[id]   = journal title (English fallback)",
        "--   CR.QuestTitleHandles[id], CR.JournalHandles[quest/step] = localisation handles, so the",
        "--   journal can be quoted in the player's own language without storing any of its text",
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
    lines += ["}", "", "CR.QuestTitleHandles = {"]
    for quest in sorted(used_quests):
        for q in (quest, "ORI_Avatar_" + quest[8:] if quest.startswith("ORI_COM_") else None):
            if q and q in title_handles:
                lines.append(f'    {q} = "{title_handles[q]}",')
    lines += ["}", "", "CR.JournalHandles = {"]
    for quest, step in sorted(used_steps):
        handle = step_handles.get((quest, step))
        if handle:
            lines.append(f'    ["{quest}/{step}"] = "{handle}",')
    lines += ["}", ""]
    with open(FLAGS_OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("Wrote", os.path.relpath(FLAGS_OUT, ROOT))


if __name__ == "__main__":
    main()

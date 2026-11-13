"""
extract_game_data.py - pull the reference data the roadmap is built from out of
your own Baldur's Gate 3 installation (nothing is downloaded).

Uses LSLib's Divine.exe to extract:
  * every flag definition (Public/*/Flags)            -> tools/.cache/flags.tsv
  * the journal (quest_prototypes.lsx) + English text -> tools/.cache/quests.tsv
  * the Osiris story goals (Story/RawFiles/Goals)     -> tools/.cache/goals/

Run again after a game patch, then run build_data.py to re-validate the data.

Usage:
  python tools/extract_game_data.py [--divine PATH\\TO\\Divine.exe] [--game PATH\\TO\\Baldurs Gate 3]

Both paths are auto-detected (Steam libraries, GOG, Vortex / common LSLib folders)
or can be given with the environment variables DIVINE_PATH and BG3_PATH.
"""
from __future__ import annotations

import argparse
import glob
import html
import os
import re
import shutil
import string
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CACHE = os.path.join(ROOT, "tools", ".cache")
GAME_FOLDER = "Baldurs Gate 3"


def windows_drives():
    if os.name != "nt":
        return []
    return [f"{d}:\\" for d in string.ascii_uppercase if os.path.exists(f"{d}:\\")]


def registry_value(root_name, key, value):
    if os.name != "nt":
        return None
    try:
        import winreg
        root = getattr(winreg, root_name)
        with winreg.OpenKey(root, key) as k:
            return winreg.QueryValueEx(k, value)[0]
    except OSError:
        return None


def steam_libraries():
    """Every Steam library folder, read from Steam's libraryfolders.vdf."""
    steam = registry_value("HKEY_CURRENT_USER", r"Software\Valve\Steam", "SteamPath") \
        or registry_value("HKEY_LOCAL_MACHINE", r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath") \
        or r"C:\Program Files (x86)\Steam"
    libraries = [steam]
    vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
    if os.path.exists(vdf):
        text = open(vdf, encoding="utf-8", errors="replace").read()
        libraries += [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', text)]
    return libraries


def game_candidates():
    env = os.environ.get("BG3_PATH")
    if env:
        yield env
    for lib in steam_libraries():
        yield os.path.join(lib, "steamapps", "common", GAME_FOLDER)
    gog = registry_value("HKEY_LOCAL_MACHINE", r"SOFTWARE\WOW6432Node\GOG.com\Games\1456460669", "path")
    if gog:
        yield gog
    for drive in windows_drives():
        yield os.path.join(drive, "GOG Games", GAME_FOLDER)
        yield os.path.join(drive, "SteamLibrary", "steamapps", "common", GAME_FOLDER)


def divine_candidates():
    env = os.environ.get("DIVINE_PATH")
    if env:
        yield env
    for name in ("Divine.exe", "divine"):
        hit = shutil.which(name)
        if hit:
            yield hit
    yield os.path.join(ROOT, "tools", "Divine.exe")
    patterns = []
    if os.environ.get("APPDATA"):
        patterns.append(os.path.join(os.environ["APPDATA"], "Vortex", "baldursgate3", "mods", "ExportTool*", "tools", "Divine.exe"))
    for drive in windows_drives():
        patterns += [
            os.path.join(drive, "Vortex Mods", "baldursgate3", "ExportTool*", "tools", "Divine.exe"),
            os.path.join(drive, "Tools", "ExportTool*", "Tools", "Divine.exe"),
            os.path.join(drive, "Tools", "LSLib", "Divine.exe"),
            os.path.join(drive, "Modding", "ExportTool*", "Tools", "Divine.exe"),
        ]
    for pattern in patterns:
        yield from sorted(glob.glob(pattern), reverse=True)  # newest ExportTool version first


def first_existing(candidates, predicate=os.path.exists):
    for c in candidates:
        if c and predicate(c):
            return c
    return None


def divine(exe, *args):
    cmd = [exe, "-g", "bg3", *args]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout[-2000:], res.stderr[-2000:])
        raise SystemExit(f"Divine failed: {' '.join(cmd)}")
    return res.stdout


def extract(exe, pak, dest, expr):
    divine(exe, "-a", "extract-package", "-s", pak, "-d", dest, "-x", expr)


def index_flags(lsx_dir, out_path):
    rx = re.compile(r'<attribute id="(\w+)" type="[^"]+" value="([^"]*)"')
    rows = []
    for root, _, files in os.walk(lsx_dir):
        for fn in files:
            with open(os.path.join(root, fn), encoding="utf-8-sig", errors="replace") as fh:
                attrs = dict(rx.findall(fh.read()))
            norm = os.path.join(root, fn).replace("\\", "/")
            mod = norm.split("/Public/")[1].split("/")[0] if "/Public/" in norm else "?"
            desc = html.unescape(attrs.get("Description", "")).replace("\t", " ").replace("\n", " ")
            rows.append((attrs.get("Name", ""), attrs.get("UUID", ""), attrs.get("Usage", ""), mod, desc))
    rows.sort()
    with open(out_path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write("\t".join(r) + "\n")
    return len(rows)


def load_loca(xml_path):
    text = open(xml_path, encoding="utf-8-sig").read()
    return {m.group(1): html.unescape(m.group(2))
            for m in re.finditer(r'<content contentuid="([^"]+)" version="\d+">(.*?)</content>', text, re.S)}


def clean(text):
    return (text or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def quest_step_flags(goals_dir):
    """(quest, step) -> flag names, from the story's DB_QuestDef_State facts."""
    rx = re.compile(r'^\s*DB_QuestDef_State\(\s*(?:\(FLAG\))?\s*([A-Za-z0-9_]+?)_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                    r'\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)\s*;', re.M)
    mapping = {}
    for root, _, files in os.walk(goals_dir):
        for fn in files:
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as fh:
                for m in rx.finditer(fh.read()):
                    mapping.setdefault((m.group(2), m.group(3)), set()).add(m.group(1))
    return mapping


def index_quests(proto_path, loca, step_flags, out_path):
    """quests.tsv columns: QuestID, StepID, quest title, journal text, flags that unlock it, dev comment."""
    tree = ET.parse(proto_path)
    n = 0
    with open(out_path, "w", encoding="utf-8") as fh:
        for quest in tree.iter("node"):
            if quest.get("id") != "Quest":
                continue
            attrs = {a.get("id"): (a.get("handle") if a.get("type") == "TranslatedString" else a.get("value"))
                     for a in quest.findall("attribute")}
            qid = attrs.get("QuestID")
            title = clean(loca.get(attrs.get("QuestTitle", ""), ""))
            children = quest.find("children")
            if children is None:
                continue
            for step in children.findall("node"):
                if step.get("id") != "QuestStep":
                    continue
                s = {a.get("id"): (a.get("handle") if a.get("type") == "TranslatedString" else a.get("value"))
                     for a in step.findall("attribute")}
                text = clean(loca.get(s.get("Description", ""), ""))
                flags = ",".join(sorted(step_flags.get((qid, s.get("ID")), ())))
                fh.write("\t".join((qid, s.get("ID") or "", title, text, flags, clean(s.get("DevComment")))) + "\n")
                n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--divine", default=None, help="path to LSLib Divine.exe")
    ap.add_argument("--game", default=None, help="BG3 install folder (contains Data\\)")
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    args = ap.parse_args()

    exe = args.divine or first_existing(divine_candidates())
    game = args.game or first_existing(game_candidates(), lambda p: os.path.isdir(os.path.join(p, "Data")))
    if not exe or not os.path.exists(exe):
        sys.exit("Divine.exe not found - pass --divine (it ships with LSLib / ExportTool).")
    if not game or not os.path.isdir(os.path.join(game, "Data")):
        sys.exit("BG3 install not found - pass --game.")
    data = os.path.join(game, "Data")
    cache = os.path.abspath(args.cache)
    work = os.path.join(cache, "work")
    os.makedirs(work, exist_ok=True)
    print("Divine:", exe)
    print("Game  :", game)

    # Load order matters: later packages override earlier ones, so hotfixes are
    # sorted numerically (Patch8_HotFix9 before Patch8_HotFix10).
    def natural_key(path):
        return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", os.path.basename(path))]

    paks = [os.path.join(data, p + ".pak") for p in ("Shared", "Gustav", "GustavX")]
    hotfixes = {os.path.normcase(p): p for p in glob.glob(os.path.join(data, "Patch*_*ot*ix*.pak"))}
    paks += sorted(hotfixes.values(), key=natural_key)
    paks = [p for p in dict.fromkeys(paks) if os.path.exists(p)]

    goals_dest = os.path.join(work, "story")
    flags_dest = os.path.join(work, "flags_lsf")
    for pak in paks:
        print("Extracting from", os.path.basename(pak))
        extract(exe, pak, goals_dest, "*/Story/RawFiles/Goals/*")
        extract(exe, pak, flags_dest, "Public/*/Flags/*")
        extract(exe, pak, work, "Mods/GustavDev/Story/Journal/quest_prototypes.lsx")

    # Flatten goals into cache/goals (later paks already overwrote earlier ones)
    goals_out = os.path.join(cache, "goals")
    if os.path.isdir(goals_out):
        shutil.rmtree(goals_out)
    shutil.copytree(goals_dest, goals_out)

    print("Converting flags (LSF -> LSX)...")
    flags_lsx = os.path.join(work, "flags_lsx")
    divine(exe, "-a", "convert-resources", "-s", flags_dest, "-d", flags_lsx, "-i", "lsf", "-o", "lsx")
    n = index_flags(flags_lsx, os.path.join(cache, "flags.tsv"))
    print(f"  {n} flags")

    print("Extracting English localization...")
    loca_dir = os.path.join(work, "loca")
    extract(exe, os.path.join(data, "Localization", "English.pak"), loca_dir, "*english.loca")
    candidates = glob.glob(os.path.join(loca_dir, "**", "english.loca"), recursive=True)
    if not candidates:
        sys.exit("english.loca not found")
    loca_file = max(candidates, key=os.path.getsize)  # skip the tiny gendered stubs
    loca_xml = os.path.join(work, "english.xml")
    divine(exe, "-a", "convert-loca", "-s", loca_file, "-d", loca_xml)
    loca = load_loca(loca_xml)

    proto = os.path.join(work, "Mods", "GustavDev", "Story", "Journal", "quest_prototypes.lsx")
    n = index_quests(proto, loca, quest_step_flags(goals_out), os.path.join(cache, "quests.tsv"))
    print(f"  {n} journal steps")

    shutil.rmtree(work, ignore_errors=True)
    print("Done. Cache:", cache)


if __name__ == "__main__":
    main()

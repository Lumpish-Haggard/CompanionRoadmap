"""
search_game_data.py - find flags and journal steps to use in the guide data.

Searches the cache written by extract_game_data.py. Every term must match
(case-insensitive) the name, description or journal text.

Examples:
  python tools/search_game_data.py shadowheart orchid
  python tools/search_game_data.py --quests MintharaFate
  python tools/search_game_data.py --flags PartneredWith
  python tools/search_game_data.py --story NIGHT_Karlach_TheForgingOfTheHeart   # where the story uses it
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUID_SUFFIX = re.compile(r"_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
USAGE = {1: "global", 2: "dialog", 4: "object"}


def matches(text, terms):
    low = text.lower()
    return all(t in low for t in terms)


def usage_text(value):
    try:
        v = int(value)
    except ValueError:
        return value
    return "+".join(name for bit, name in USAGE.items() if v & bit) or str(v)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("terms", nargs="+")
    ap.add_argument("--flags", action="store_true", help="only search flags")
    ap.add_argument("--quests", action="store_true", help="only search journal steps")
    ap.add_argument("--story", action="store_true", help="show Osiris story lines that mention the term")
    ap.add_argument("--limit", type=int, default=60)
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", ".cache"))
    args = ap.parse_args()
    terms = [t.lower() for t in args.terms]
    both = not (args.flags or args.quests or args.story)

    if not os.path.exists(os.path.join(args.cache, "flags.tsv")):
        sys.exit("No cache found. Run tools/extract_game_data.py first.")

    if args.flags or both:
        print("== Flags (name | usage | description)")
        n = 0
        for line in open(os.path.join(args.cache, "flags.tsv"), encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 5 and matches(p[0] + " " + p[4], terms):
                print(f"  {p[0]:64s} {usage_text(p[2]):14s} {p[4][:110]}")
                n += 1
                if n >= args.limit:
                    print("  ... (use --limit to see more)")
                    break

    if args.quests or both:
        print("== Journal steps (Q(quest, step) | unlocked by | text)")
        n = 0
        for line in open(os.path.join(args.cache, "quests.tsv"), encoding="utf-8"):
            p = line.rstrip("\n").split("\t") + [""] * 6
            if matches(" ".join(p[:6]), terms):
                flags = f" [{p[4]}]" if p[4] else ""
                print(f'  Q("{p[0]}", "{p[1]}"){flags}  ({p[2]})  {p[3][:110]}')
                n += 1
                if n >= args.limit:
                    print("  ... (use --limit to see more)")
                    break

    if args.story:
        print("== Osiris story")
        n = 0
        goals = os.path.join(args.cache, "goals")
        for root, _, files in os.walk(goals):
            for fn in sorted(files):
                path = os.path.join(root, fn)
                for lineno, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                    if matches(line, terms):
                        print(f"  {fn}:{lineno}: {GUID_SUFFIX.sub('', line.strip())[:150]}")
                        n += 1
                        if n >= args.limit:
                            print("  ... (use --limit to see more)")
                            return


if __name__ == "__main__":
    main()

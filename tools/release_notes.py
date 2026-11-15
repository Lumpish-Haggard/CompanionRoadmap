"""
release_notes.py - print the CHANGELOG.md section of one version.

    python tools/release_notes.py 1.0.2            # Markdown, as written (for a GitHub release)
    python tools/release_notes.py 1.0.2 --plain    # plain text (for the Nexus Mods changelog)

Exits with an error if the version has no section or the section is empty, so a
release workflow cannot publish a version without notes.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")

HEADING = re.compile(r"^## \[([^\]]+)\]")
LINK_DEF = re.compile(r"^\[[^\]]+\]:\s")


def section(text: str, version: str) -> str:
    lines, inside = [], False
    for line in text.splitlines():
        m = HEADING.match(line)
        if m:
            if inside:
                break
            inside = m.group(1) == version
            continue
        if inside and not LINK_DEF.match(line):
            lines.append(line)
    return "\n".join(lines).strip()


def plain(md: str) -> str:
    out = []
    for line in md.splitlines():
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)        # links and images -> their text
        line = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)                  # bold
        line = re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])", r"\1", line)  # italic
        line = line.replace("`", "")
        m = re.match(r"^#{3,}\s+(.*)$", line)
        if m:
            line = m.group(1).rstrip(":") + ":"
        out.append(line.rstrip())
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("version", help="version without the leading v, e.g. 1.0.2")
    ap.add_argument("--plain", action="store_true", help="strip Markdown for sites that do not render it")
    args = ap.parse_args()
    version = args.version[1:] if args.version.startswith("v") else args.version

    with open(CHANGELOG, encoding="utf-8") as f:
        notes = section(f.read(), version)
    if not notes:
        print(f"CHANGELOG.md has no notes for version {version}", file=sys.stderr)
        return 1
    sys.stdout.reconfigure(encoding="utf-8")
    print(plain(notes) if args.plain else notes)
    return 0


if __name__ == "__main__":
    sys.exit(main())

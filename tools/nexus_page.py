"""
nexus_page.py - the Nexus Mods page text in .github/nexus/, as used by
.github/workflows/nexus-release.yml.

    python tools/nexus_page.py check                       # validate description.bbcode and summary.txt
    python tools/nexus_page.py body <out.json> [--description] [--summary]
    python tools/nexus_page.py decode <live.json> <out_dir>

`decode` reads the answer of GET /mods/{id}. Nexus stores the description the way
its page editor saves it (line breaks as <br />, & as &amp;, \\ as &#92; ...).
It writes both the stored text (description.raw.bbcode) and the plain BBCode
(description.bbcode, what you would type in the editor and what PATCH expects),
then prints whether the plain text equals .github/nexus/description.bbcode.
Exit code 0 = equal, 3 = different.
"""
from __future__ import annotations

import html
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE_DIR = os.path.join(ROOT, ".github", "nexus")
# Nexus shows at most 240 characters of a summary, cut at a whole word: no Baldur's Gate 3
# mod's summary is longer (1,785 of them read through the public API, 2026-11-18).
SUMMARY_MAX = 240


def description() -> str:
    with open(os.path.join(PAGE_DIR, "description.bbcode"), encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n").strip()


def summary() -> str:
    with open(os.path.join(PAGE_DIR, "summary.txt"), encoding="utf-8") as f:
        # Nexus collapses line breaks and runs of whitespace in the summary
        return re.sub(r"\s+", " ", f.read()).strip()


def problems() -> list[str]:
    out = []
    if not description():
        out.append("description.bbcode is empty")
    n = len(summary())
    if not 1 <= n <= SUMMARY_MAX:
        out.append(f"summary.txt must be 1 to {SUMMARY_MAX} characters, it is {n}")
    return out


def decode_stored(stored: str) -> str:
    """The editor's stored form back to the BBCode that was typed."""
    text = stored.replace("\r\n", "\n").replace("<br />", "").replace("<br/>", "").replace("<br>", "")
    return html.unescape(text).strip()


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "check":
        found = problems()
        for p in found:
            print(f"::error::{p}")
        if not found:
            print(f"summary: {len(summary())} characters, description: {len(description())} characters")
        return 1 if found else 0
    if cmd == "body":
        found = problems()
        if found:
            for p in found:
                print(f"::error::{p}")
            return 1
        body = {}
        if "--summary" in args:
            body["summary"] = summary()
        if "--description" in args:
            body["description"] = description()
        if not body:
            print("::error::nothing to send")
            return 1
        with open(args[0], "w", encoding="utf-8") as f:
            json.dump(body, f, ensure_ascii=False)
        print("sending:", ", ".join(body))
        return 0
    if cmd == "decode":
        with open(args[0], encoding="utf-8-sig") as f:
            stored = (json.load(f).get("data") or {}).get("description") or ""
        os.makedirs(args[1], exist_ok=True)
        with open(os.path.join(args[1], "description.raw.bbcode"), "w", encoding="utf-8", newline="\n") as f:
            f.write(stored)
        plain = decode_stored(stored)
        with open(os.path.join(args[1], "description.bbcode"), "w", encoding="utf-8", newline="\n") as f:
            f.write(plain + "\n")
        same = plain == description()
        print("The live description is", "the same as" if same else "different from", ".github/nexus/description.bbcode.")
        return 0 if same else 3
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())

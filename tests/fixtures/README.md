# Report fixtures

Report files from real saves, replayed by `tools/test_harness.py` as regression tests.

## Adding one

1. In game: *Options > Create a report file* (or `!roadmap report` in the server console).
2. Copy `report.json` from `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\CompanionRoadmap`
   into this folder and give it a name that says what it shows, for example `act1-astarion-killed-on-beach.json`.
3. Optionally add what the roadmap **should** show, so the test fails if that ever changes:

   ```json
   "expect": { "AST_A1_RECRUIT": "M", "SH_A1_RECRUIT": "D" }
   ```

   Status letters: `D` done, `O` checked, `N` next, `A` to do, `P` waiting, `U` later, `M` missed, `X` n/a, `I` not seen.

   Any other key you add, such as `about` (what the save shows) or `known_gaps` (statuses that are still wrong and
   not asserted yet), is a note for people and is ignored by the test.

Every fixture is replayed on each test run: the fake game world is rebuilt from the report, the mod is started on it,
and the run must be free of errors. The statuses recorded in the file come from the mod version that wrote it, so
they are not compared automatically; only the `expect` entries are.

A report holds game identifiers only (flag ids, journal step names, companion ids, approval values). It contains no
character names and nothing about your PC or account. The `avatar` value is the id the game gave your character in
that save. Nothing depends on its value, so you may replace every occurrence of it with another id, as the
fixtures here do.

## Fixtures

| File | What it shows |
|---|---|
| `act1-shadowheart-dating-two-companions-lost.json` | Act 1 at the Emerald Grove, written by 1.0.1. Shadowheart recruited and dating; Lae'zel dead; Astarion dead before he was recruited (so every Astarion step is missed); nobody else recruited. |
| `act1-1.1.0-earlier-save-with-memory.json` | An earlier save of the same playthrough, written by 1.1.0 in game. Shadowheart dating at 62 approval, wolf memory not shared yet (NEXT). The first real report with the choice memory in it, so the replay also loads the memory exactly as the game stored it. |
| `act1-1.0.2-markers-on-unrecruited-companions.json` | The same save later on, written by 1.0.2. The first real save with the game's removal markers recorded: Halsin, Minthara and Minsc already carry one of them before joining and must not count as lost. The recorded statuses and camp list were left out to keep the file small; when it was written, replaying the full report reproduced all 99 statuses. |

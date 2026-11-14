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

Every fixture is replayed on each test run: the fake game world is rebuilt from the report, the mod is started on it,
and the run must be free of errors. The statuses recorded in the file come from the mod version that wrote it, so
they are not compared automatically; only the `expect` entries are.

A report holds game identifiers only (flag ids, journal step names, companion ids, approval values). It contains no
character names and nothing about your PC or account.

## What changed

<!-- One topic per pull request. Link the issue it fixes, if any (e.g. "Fixes #12"). -->

## Type

- [ ] Guide data (text, steps, detection)
- [ ] Code
- [ ] Tooling or documentation

## How was it verified?

<!--
Guide data: paste the relevant tools/search_game_data.py output, a bg3.wiki link,
or describe the in-game test. Code: describe what you tested and where.
-->

## Checklist

- [ ] `py tools/build_data.py` passes (or `--offline` if you do not have the game files), and `Data/Flags.lua` is committed if it changed
- [ ] `py tools/test_harness.py` passes
- [ ] Tested in game, or explained above why not
- [ ] No released step id was renamed (manual check-offs are stored by id)
- [ ] UI text is ASCII / Latin-1 only
- [ ] `CHANGELOG.md` updated under *Unreleased*

# Contributing

Thanks for helping. This project lives or dies by the accuracy of its guide, so the most useful contributions are:

1. **Guide corrections**: a step, requirement or warning that is wrong or missing. Use the *Guide correction* issue form, or open a pull request.
2. **Detection reports**: "I did X and the roadmap did not notice" (or noticed something that did not happen). Attach the report file (*Options > Create a report file*, or `!roadmap report` in the server console).
3. **Code and documentation**: bug fixes, UI polish, tooling.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first.

## The one rule: verify, don't guess

Every flag, journal step, item name, DC, approval threshold and location must come from the game files or a reliable source (bg3.wiki, or your own in-game test). Say where it came from in your pull request. The tooling makes the game-data part easy, as described below.

## Setting up

| You want to | You need |
|---|---|
| Edit guide text or code and run the tests | Python 3.10+ and `py -m pip install -r requirements-dev.txt` (any OS) |
| Validate data against the game, add new flags or journal steps | Windows, Baldur's Gate 3, [LSLib ExportTool](https://github.com/Norbyte/lslib/releases) (`Divine.exe`) |
| Build and test the `.pak` in game | the above, plus the [Script Extender](https://github.com/Norbyte/bg3se) |

On Windows the commands below use the `py` launcher; use `python` elsewhere.

## Workflow

```powershell
# 1. Read the game's flags, journal and story scripts from your install (once per game patch).
#    Writes tools/.cache/ (git-ignored; never commit it).
py tools/extract_game_data.py          # auto-detects the game and Divine.exe; or set BG3_PATH / DIVINE_PATH

# 2. Find what you need
py tools/search_game_data.py karlach heart
py tools/search_game_data.py --quests ORI_COM_Karlach_SUB_ForgingOfTheHeart
py tools/search_game_data.py --story NIGHT_Karlach_TheForgingOfTheHeart

# 3. Edit Mods/CompanionRoadmap/ScriptExtender/Lua/Data/Companions/<Name>.lua

# 4. Validate and regenerate Data/Flags.lua (commit it with your change)
py tools/build_data.py

# 5. Run the tests
py tools/test_harness.py

# 6. Try it in game
.\pack.ps1 -Install
```

Without the game files you can still run `py tools/build_data.py --offline` (what CI runs). It checks your change against the committed `Data/Flags.lua`, but it cannot verify new flags or journal steps.

The data format, condition helpers and status rules are documented in [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md). How the pieces fit together is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Code guidelines

- **Lua 5.4** as embedded by the Script Extender. Four-space indentation; keep everything `local` except the shared `CR` namespace.
- **Never let an error escape into the game.** Osiris and IMGUI calls go through `pcall` / `CR.Try` / `CR.Guard` (see existing code), and every Osiris probe tolerates missing flags.
- **Server vs client**: Osiris only exists on the server. The client only draws what the server sends.
- **UI text is ASCII or Latin-1.** The Script Extender IMGUI font has no other glyphs; `build_data.py` fails on anything else.
- **MCM is optional.** Every MCM call is guarded and the mod must work without it.
- **Performance**: the server reacts only to watched flags and journal steps, and debounces. Don't add per-frame work or listeners that fire on every flag.
- Keep the IMGUI mock in `tools/mock_se.lua` in sync if you use an IMGUI feature it does not know about yet (it mirrors BG3SE's property map on purpose).
- Editor support: `.luarc.json` configures the Lua language server (VS Code "Lua" extension). For Script Extender autocompletion, download [`ExtIdeHelpers.lua`](https://github.com/Norbyte/bg3se/blob/main/BG3Extender/IdeHelpers/ExtIdeHelpers.lua) outside the repository and add its folder to `workspace.library` in your local settings.

## Testing in game

- `.\pack.ps1 -Install` copies the pak to your BG3 `Mods` folder; enable it in your mod manager once.
- In the Script Extender console: `!roadmap` (server) prints the tracker's view; `!roadmap debug` toggles verbose logging; `reset` reloads all Lua without restarting the game.
- Check both a fresh save and a save that is far into the story.

## Pull requests

- One topic per pull request.
- Fill in the template: what changed, how you verified it, and whether you tested it in game.
- `py tools/test_harness.py` and `py tools/build_data.py` (or `--offline`) must pass. CI runs the offline check and the tests.
- Add a line to `CHANGELOG.md` under *Unreleased*.
- Never rename a released step id: manual check-offs are stored by id.

## Releasing (maintainers)

1. Bump `Version64` in `meta.lsx` (both places) and `CR.Version` in `Shared/Core.lua`. `build_data.py --offline` checks that they match.
2. Move the *Unreleased* changelog entries under the new version.
3. `.\pack.ps1` and smoke-test the pak in game.
4. Tag `vX.Y.Z`, create a GitHub release and attach `dist/CompanionRoadmap-X.Y.Z.0.zip`; upload the same zip to Nexus Mods and update the mod page there.

`Version64` encodes `major << 55 | minor << 47 | revision << 31 | build`; for example 1.0.0.0 is `36028797018963968` and 1.1.0.0 is `36169534507319296`.

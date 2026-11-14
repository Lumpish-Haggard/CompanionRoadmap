<div align="center">

# Companion & Romance Roadmap

**A live, in-game checklist for every Baldur's Gate 3 companion's story and romance, read straight from your save.**

![BG3 Patch 8](https://img.shields.io/badge/BG3-Patch%208-7a1f1f)
![Script Extender v25+](https://img.shields.io/badge/Script%20Extender-v25%2B-informational)
![MCM optional](https://img.shields.io/badge/MCM-optional-lightgrey)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

[Download](../../releases/latest) ·
[Report a bug or wrong guide info](../../issues/new/choose) ·
[What is planned](docs/ROADMAP.md) ·
[Contributing](CONTRIBUTING.md) ·
[Changelog](CHANGELOG.md)

</div>

> [!NOTE]
> **Work in progress.** This is the first public release. The guide and its detection will keep improving, and you may run into bugs or steps that are not detected yet. Please [report them](../../issues/new/choose): every report makes the roadmap better for everyone. What comes next is in the [project plan](docs/ROADMAP.md).

---

Most of what matters for a companion in Baldur's Gate 3 is easy to miss: a conversation you never had, a long rest you skipped, an area you can never return to. Wikis tell you what *can* happen. **This mod tells you, inside the game, what has already happened in your save and what is still open.**

Press **F7** and pick a companion:

- **Where you stand**: recruited, dating, partnered or lost; live approval and its tier; special trackers such as Shadowheart's hidden *Nightsong points*, Karlach's engine upgrades and the magic items fed to Gale.
- **What to do next**: every step of their personal quest and romance, act by act, with location, what to do, what to avoid, rewards, and the approval the step needs next to your current approval. The next step is highlighted.
- **What you are about to lose**: the *Before you move on* tab lists each upcoming point of no return and the important steps still open before it. Click an entry to jump to it.

Steps tick themselves off as you play. Everything is detected from the game's own journal, story flags and approval values. The mod only reads the game, so it is safe to add to or remove from an ongoing playthrough.

## Features

- All **10 recruitable companions**, around **100 steps**: Shadowheart, Minthara, Karlach, Lae'zel, Astarion, Gale, Wyll, Halsin, Jaheira, Minsc.
- **Live statuses**: Next, To do, Not seen, Waiting, Later, Done, Checked, Missed, N/A, updated within half a second of the game changing.
- **Looks like it belongs in the game**: a quiet dark panel in BG3's own Quadraat typeface, gold headings, and colour only where it means something.
- **Points of no return**: the Shadowfell (Act 1 locks), the Mind Flayer Colony, leaving for Baldur's Gate, the Lower City and the final battle. Each comes with a short list of what you would lose.
- **Notifications** when a tracked step is completed, or when an important one is missed.
- **Manual check-offs** for anything the game does not record or another mod changes. They are saved inside each savegame.
- **Spoiler control**: the roadmap asks once how much it may reveal about later acts (everything, step titles only, or nothing). Until you choose, later acts stay hidden, including golden rules and romance notes.
- **Companion portraits** from the game's own Photo Mode stickers (can be switched off).
- **Mod Configuration Menu** support: a settings page, a rebindable hotkey and an "Open roadmap" button. MCM is optional.
- **Multiplayer and origin aware**: each player sees their own approval and romance; playing as an origin marks that companion's recruitment and romance as not applicable.

## Requirements

| | |
|---|---|
| Baldur's Gate 3 | Patch 8. The data is verified against the Patch 8 Hotfix 10 game files. |
| [BG3 Script Extender](https://github.com/Norbyte/bg3se) | v25 or newer |
| [Mod Configuration Menu](https://www.nexusmods.com/baldursgate3/mods/9162) | Optional |

## Installation

1. Install the [BG3 Script Extender](https://github.com/Norbyte/bg3se) if you have not already.
2. Download `CompanionRoadmap-<version>.zip` from the [latest release](../../releases/latest).
3. Install it with your mod manager:
   - **BG3 Mod Manager**: import the zip, move *Companion & Romance Roadmap* to the active list, then save and export the load order.
   - **Vortex**: install the zip, enable it, deploy.
   - **Manual**: put `CompanionRoadmap.pak` in `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\` and enable it in your mod manager.
4. Load a save and press **F7**.

To uninstall, disable or remove it. Saves made with it still load; the game only warns that a mod is missing.

## Using the roadmap

| To | Do this |
|---|---|
| Open / close | **F7**. Rebind it on the MCM page, or under *Options* if you do not use MCM. F8 is not used because it is BG3's Quickload key. |
| Open from MCM | *Mod Configuration Menu > Companion & Romance Roadmap > Open roadmap* |
| Read a step | Click it to expand: where, what to do, what to avoid, rewards, approval needed. Hover a status to see what it means. |
| See what you would miss | Open the *Before you move on* tab (the orange line under the header counts the open items). Click an entry to jump to it. |
| Check off a step | Expand it and tick *I did this - mark it as done*. |
| Refresh | The window updates by itself; *Options > Refresh now* forces it. |
| Close | **Esc**, the toggle key, or the X. |
| Report a problem | *Options > Create a report file*, then attach `report.json` to your bug report. |

### Step statuses

| Status | Meaning |
|---|---|
| `NEXT` | The next thing to do for this companion |
| `TO DO` | Can be done now |
| `OPTIONAL` | Can be done now, but skipping it costs you nothing important |
| `NOT SEEN` | From an earlier act and not detected. It may still be possible, or the game does not record it, so check it off if you did it. |
| `WAITING` | Waits for an earlier step |
| `LATER` | Belongs to a later act |
| `DONE` | Detected in your save |
| `CHECKED` | You checked it off |
| `MISSED` | Failed, or its window has closed |
| `N/A` | Does not apply to your path |

### Options

In the *Options* tab: hide finished steps · romance steps only · spoiler level · show how each step is tracked · companion portraits · notifications (romance and important steps, or every step) · window opacity · hotkey · Esc closes the window · clear all check-offs · create a report file. With MCM installed, the same options appear on the MCM page and stay in sync.

### Console commands

Open the Script Extender console:

| Command | Context | Does |
|---|---|---|
| `!roadmap` | client | toggle the window (`open`, `close`, `hotkey`, `debug` also work) |
| `!roadmap` | server | print what the tracker sees: act, approval, relationships, step counts |
| `!roadmap steps Minthara` | server | list one companion's steps and statuses |
| `!roadmap report` | server | write `Script Extender/CompanionRoadmap/report.json`: everything the tracker sees, for bug reports |
| `!roadmap resetoverrides` | server | clear all manual check-offs in this save |

## What is covered

| Companion | Highlights |
|---|---|
| Shadowheart | Nautiloid pod, waterfall wine scene, the wolf memory (needed for the Act 3 swim), Noblestalk, Idol of Shar, Night Orchid, **Nightsong points (4 of 6)**, Gauntlet trials and Spear of Night, the Nightsong choice, partnering after the Shadowfell, the swim or the Shar night, Viconia, her parents, Nocturne |
| Minthara | Good-path **non-lethal knockout rules** (or the raid route), the Moonrise trial, the prison rescue and escort, romance at 31+, exclusive partner at 50+, Orin |
| Karlach | Recruitment conditions, the Paladins of Tyr, **engine upgrades** with every Infernal Iron location, romance in all three acts, Gortash, the Singing Lute date |
| Lae'zel | The cage, her proposition, the Creche and Vlaakith, Voss, the night duel (partnering), the Orphic Hammer, the sunrise scene, Orpheus |
| Astarion | The bite night, the Gur hunter, his offer, Araj Oblodra and his confession, Cazador and the ascension checks (Persuasion DC 18, or DC 15 after Insight DC 20) |
| Gale | The rune circle, **magic items**, the Weave lesson, Elminster, the starry sky (before the Colony), the Annals of Karsus, Mystra |
| Wyll | Recruitment, Karlach, Waukeen's Rest, the party-only romance start, Mizora's rescue (or Wyll is lost), the dance, the pact, Duke Ravengard, Ansur, the proposal |
| Halsin | The Worg Pens, saving the Grove, Art Cullagh, the portal, Oliver, lifting the curse, the Act 3 romance (and which partners agree to share) |
| Jaheira | Last Light Inn, Isobel, recruitment, the High Harper |
| Minsc | The Stone Lord, the Counting House, the non-lethal knockout, the Emperor, Boo |

## How accurate is it?

- **Detection comes from the game itself.** The tracker reads journal steps, story flags, Osiris databases and approval through the Script Extender. Every flag and journal step it uses was extracted from the game files and is validated by [`tools/build_data.py`](tools/build_data.py). Nothing is a guessed ID.
- **Guide text is cross-checked** against the game's own journal text and story scripts, and against [bg3.wiki](https://bg3.wiki).
- **What it cannot see**: moments the game only keeps inside a conversation, and romance flags that other mods change. Use *I did this - mark it as done* for those, and [tell us](../../issues/new/choose) if a step should be detectable.
- Installing mid-playthrough works: the tracker reads what the game has already recorded.

## Compatibility

- **Romance mods** (PolyamoryFixes, NoRomanceLimit, ...) are fine. If a mod changes how romance flags are set, check the step off by hand.
- **Multiplayer**: approval and romance are per player; journal progress and check-offs are shared.
- **Other Script Extender overlays** (MCM and others) work alongside it; the roadmap uses its own window.

## Troubleshooting

<details>
<summary>Nothing happens when I press F7</summary>

Check that the Script Extender loaded: its console prints `[CompanionRoadmap] ... loaded`. With MCM installed, the key is configured on the mod's MCM page. You can always type `!roadmap` in the client console.
</details>

<details>
<summary>The window says "Waiting for the game"</summary>

Load a save; the roadmap fills in by itself. *Options > Refresh now* forces an update.
</details>

<details>
<summary>A step I completed is not detected</summary>

Some moments are only recorded inside a conversation. Tick *I did this - mark it as done*. If you think the game does record it, open an issue and attach the report file (*Options > Create a report file*). It contains game identifiers only, nothing personal.
</details>

<details>
<summary>The guide says something wrong</summary>

Please use the [guide correction form](../../issues/new/choose) and mention your source (bg3.wiki page, or what you saw in game).
</details>

## Building from source

On Windows, with BG3 and [LSLib](https://github.com/Norbyte/lslib/releases) (ExportTool) installed:

```powershell
py tools/extract_game_data.py   # read flags, journal and story from your BG3 install (local cache, not committed)
py tools/build_data.py          # validate the guide data and regenerate Data/Flags.lua
py tools/test_harness.py        # run the mod's Lua against a strict Script Extender mock (needs: py -m pip install -r requirements-dev.txt)
.\pack.ps1                      # dist/CompanionRoadmap.pak and dist/CompanionRoadmap-<version>.zip
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Project layout

```
Mods/CompanionRoadmap/            the mod (what goes into the .pak)
  meta.lsx, MCM_blueprint.json
  ScriptExtender/Config.json
  ScriptExtender/Lua/
    Bootstrap{Server,Client}.lua
    Shared/      namespace, logging, timers, network channels
    Data/        guide registry, one file per companion, generated Flags.lua
    Tracker/     evaluation (server) and live sync
    Client/      settings, hotkey, network client
    UI/          overlay window, notifications, theme
Public/CompanionRoadmap/          portrait definitions (they point at textures that ship with the game)
tools/            game-data extraction, validation, search, test harness
tests/fixtures/   report files from real saves, replayed as regression tests
docs/             data format, architecture, roadmap
pack.ps1          build and verify the .pak and the release zip
```

## Contributing

Corrections to the guide are the most valuable contribution, together with reports of what does or does not get detected in your game. Code, documentation and ideas are welcome too. Start with [CONTRIBUTING.md](CONTRIBUTING.md). By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Credits

- **Norbyte**: [BG3 Script Extender](https://github.com/Norbyte/bg3se) and [LSLib](https://github.com/Norbyte/lslib), which make this mod and its tooling possible.
- **Volitio**: [Mod Configuration Menu](https://github.com/AtilioA/BG3-MCM).
- The editors of [bg3.wiki](https://bg3.wiki).
- **Larian Studios**: Baldur's Gate 3.

This project is not affiliated with or endorsed by Larian Studios.

## License

[MIT](LICENSE). Baldur's Gate 3 names, story content and identifiers belong to Larian Studios. Apart from the flag identifiers, journal titles and localisation handles the mod needs at runtime (`Data/Flags.lua`), this repository contains no game data, and no game art: the companion portraits are the game's own Photo Mode stickers, referenced by file path. The reference data is read locally: `tools/extract_game_data.py` reads it from your own installation into a local cache that is never committed.

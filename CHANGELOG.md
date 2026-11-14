# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [1.0.1] - 2026-11-14

### Fixed
- A companion who died **before joining** was shown as "Dead - revive" and counted in "Before you move on". They are now marked as lost ("Died before joining"), because in most cases they can no longer be revived or recruited. Wyll (goblin attack on the Grove) and Lae'zel are the documented exceptions and say how to bring them back.
- **Spoilers**: golden rules, romance notes and the details of trackers (for example Shadowheart's hidden score) ignored the spoiler setting. Each one is now tied to an act and hidden until you reach it, unless you choose to see everything.
- A companion who was **revived** stayed "dead" until something else changed.
- "Detected" and "Missed" lines showed internal names. They now quote the game's own journal entry, in your game's language, or use a plain sentence.
- An optional step that can be done now is labelled `OPTIONAL` instead of `TO DO`, so it no longer looks more urgent than the `NEXT` step below it.
- Notices no longer appear in the middle of a conversation or camp scene; they wait until it ends.
- The status column was too narrow in the legend, and an empty progress bar was invisible.

### Added
- **First-run question**: how much may the roadmap reveal about acts you have not reached? Until you answer, later acts stay hidden.
- **Report file**: *Options > Create a report file* (or `!roadmap report`) writes everything the tracker sees to `report.json`. Attach it to bug reports; it contains game identifiers only.
- **Companion portraits** (experimental): the game's own Photo Mode stickers next to each companion. No art is shipped; the mod points at files in your game. Can be switched off.
- **Esc** closes the roadmap (can be switched off).
- Developer tooling: report files replay as regression tests (`tests/fixtures`), the validator checks the portrait definitions against the game, and journal text is resolved through localisation handles instead of being stored.

## [1.0.0] - 2026-11-13

First public release. A full rebuild of an earlier prototype that could not run in game.

### Added
- Guide data for all 10 recruitable companions (about 100 steps): where to go, what to do, what to avoid, rewards and approval requirements.
- Live statuses (Next, To do, Not seen, Waiting, Later, Done, Checked, Missed, N/A) that understand dependencies: a step whose prerequisite was missed is missed too.
- A BG3-style window: the game's Quadraat typeface, a status column, act sections that open where there is something to do, a highlighted next step, and status explanations on hover.
- "Before you move on" tab: the Shadowfell, the Mind Flayer Colony, leaving for Baldur's Gate, the Lower City and the final battle, with what is still open before each.
- Live trackers: Shadowheart's Nightsong points, Karlach's engine upgrades, Gale's magic items.
- Notifications when a step is completed or an important one is missed.
- Manual check-offs stored per savegame and shared in multiplayer.
- Per-player approval and romance in multiplayer; origin-character awareness.
- Options: hide completed steps, romance only, spoiler level, tracking details, opacity, notifications, hotkey. Mirrored to Mod Configuration Menu when installed.
- MCM page with an "Open roadmap" button and a rebindable keybinding.
- Console commands: `!roadmap` (client: toggle; server: diagnostics, `steps <Companion>`, `resetoverrides`, `debug`).
- Developer tools: game-data extraction from your own install, a validator that generates `Data/Flags.lua`, a game-data search tool, a test harness with a strict Script Extender / IMGUI mock, and a packager that verifies the pak and builds the release zip.
- GitHub project files: contributing guide, code of conduct, security policy, issue forms, pull request template and CI.

### Fixed (compared with the prototype)
- The overlay crashed on its first frame (`AddSameLine` does not exist in the Script Extender; `.SameLine` is a property).
- Osiris listeners were registered with the wrong arity (`FlagSet`/`FlagCleared` take three parameters), so live updates never fired.
- Most flag GUIDs were invented, and several were reused for unrelated steps. Every flag and journal step now comes from the game files and is validated.
- The default hotkey F8 is BG3's Quickload. The default is now F7, and it is rebindable.
- `Config.json` used invalid feature flags (`Client`, `Server`), and the MCM blueprint used a schema MCM does not understand.
- Symbols such as check marks, hearts and arrows rendered as `?` (the Script Extender IMGUI font is Latin-1 only).
- Approval tiers now follow the game: Neutral -19 to 20, Medium 21+, High 41+, Very High 61+, Exceptional 81+; companions leave at -50.
- Any dating/partner flag marked every companion as partnered.
- `pack.ps1` packed the whole project folder into the `.pak`.
- Story corrections:
  - Ketheric always condemns Minthara, and looting her in Act 1 is safe.
  - Karlach's heart can be fixed in any act, and her Act 3 date is at The Singing Lute.
  - Lae'zel becomes your partner at the Act 2 duel; the sunrise scene is in Act 3.
  - Shadowheart becomes your partner after the Shadowfell; the swim is Act 3, Selûne path only.
  - Wyll's romance only starts at the Tiefling party and needs Duke Ravengard alive; rescuing Mizora is what keeps Wyll himself alive.
  - Gale leaves only if you refuse the first magic item.

[Unreleased]: ../../compare/v1.0.1...HEAD
[1.0.1]: ../../releases/tag/v1.0.1
[1.0.0]: ../../releases/tag/Latest

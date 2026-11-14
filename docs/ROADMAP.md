# Roadmap

Where Companion & Romance Roadmap is going after 1.0. The aim is simple to say and hard to do: **be the companion guide you can trust completely, that warns you before you lose something, and that feels like part of the game.**

This is a plan, not a promise. Order and scope will change with what players report. If something here matters to you, or you think the order is wrong, [open an issue](../../../issues/new/choose).

## Principles

1. **Read-only.** The mod never changes flags, approval, quests or items. That does not change.
2. **Game data first.** Every flag, journal step, number and requirement is checked against the game's own files. The wiki is used to cross-check and explain, never copied.
3. **Say why.** Every status should be explainable in plain words: what the game recorded, or why a step is closed.
4. **Spoilers are the player's choice.** Nothing about a later act is shown unless the player asked for it.
5. **Never guess silently.** If the mod cannot know something, it says so and lets you check it off.

## Versions

| Version | Theme | What it brings |
|---|---|---|
| **1.0.1** | Fixes | Known issues below, and a one-click report file that makes bug reports useful |
| **1.1** | Trust | The mod remembers choices as they happen; data cross-checked against the game automatically |
| **1.2** | Camp and warnings | "Tonight at camp", warnings at the game's own "are you sure?" prompts, "do you have the item" |
| **1.3** | Look | Overview page, mini tracker, icons, search and pins |
| **1.4** | Everyone | Deeper companion content, camp followers and allies, paths and endings |
| **2.0** | Native | A real journal-style page (if the research works out), translations |

## 1.0.1: fixes

- A companion who died **before joining** is shown as revivable and inflates the warning count. In most cases they are lost; Wyll (goblin battle) and Lae'zel are the documented exceptions.
- **Spoilers leak**: golden rules, romance notes and tracker details ignore the spoiler setting.
- A **revived** companion stays "dead" until something else changes.
- "Detected" lines show **internal names** instead of plain words.
- An optional step shown as TO DO above the NEXT step is confusing; optional steps get their own label.
- Notices can appear **during a conversation**; they should wait until it ends.
- Small layout issues, and Esc should close the window.
- **Report file**: one button (or `!roadmap report`) writes what the tracker sees to a file you can attach to a bug report. Those files also become regression tests.
- **First-run question** about spoilers: until it is answered, nothing from later acts is shown.
- **Companion portraits** arrive early as an experiment: the game's own Photo Mode stickers, referenced from the game files rather than shipped.

All of the above is built and covered by tests; see the [changelog](../CHANGELOG.md). What it still needs is play time in real saves.

## 1.1: trust

**The limit today.** The mod only sees what is still in the save when it looks. A moment that happens inside a conversation and then vanishes shows as NOT SEEN.

- **Choice memory.** From the moment the mod is installed, record moments as they happen and keep them in the save: conversations starting and ending, flags set or cleared, dice results, approval changes, deaths and resurrections, long rests, items picked up, and a companion leaving for good together with the game's own reason. Anything from before installation stays NOT SEEN.
- **Conversation index** (developer tooling). Every conversation in the game lists, per option, the flags it sets and who approves. Indexing them shows exactly what evidence a moment leaves, which replaces guesswork and lets coverage grow quickly.
- **Automatic cross-checks.** Approval thresholds, camp-scene requirements and "cancelled by" rules are compared with the game's scheduler on every build.
- **Journal text in your language.** "Detected" lines quote the game's own journal entry, using the game's localisation.
- **Patch-day check.** Warn inside the game when a watched flag no longer exists after a game update.

## 1.2: camp and warnings

- **Tonight at camp.** The game schedules camp scenes from a prioritised list with explicit requirements. The mod can read that list and show which scene plays at your next long rest, what blocks the ones you are waiting for ("needs 40 approval, you have 31"), and which are about to expire.
- **Point-of-no-return warnings.** When the game asks "are you sure?" before the Shadowfell, before leaving for Baldur's Gate or before the final assault, show what is still open, right then.
- **Item awareness.** "You have the Night Orchid", "Infernal Iron 1 of 2".
- **Approval log.** The last changes per companion and the conversation that caused them.
- **Non-lethal reminder** before the Minthara and Minsc fights (needs research).

## 1.3: look

- **Overview page**: one row per companion with state, approval, romance, next step and open warnings.
- **Mini tracker**: a small always-visible panel with pinned steps and tonight's scene.
- A **next step card** at the top of each page; golden rules shrink once read.
- **Icons** from the game for items and statuses; companion portraits.
- **Search**, pins, size presets and text size.

## 1.4: everyone

- Each companion's full arc, including every camp scene, taken from the game's scheduler.
- **Camp followers and allies**: Scratch, the owlbear cub, Withers, Volo, Barcus, Dammon, the tieflings, and the allies gathered for the final battle.
- **Paths and endings**: which branch you are on for each companion, and what the other one would have been.
- Dark Urge and origin-specific differences.

## 2.0: native

- **A journal-style page.** The Script Extender can feed mod data into the game's real UI layer. The goal is a Companions page that looks and behaves like the journal, controller included. This needs an experiment first: the open question is adding a page without overwriting UI files that other mods also change.
- **Translations**, with a simple workflow for contributors.

## How to help

- **Report what is wrong.** A wrong status, a missing step, a spoiler where there should not be one. From 1.0.1, attach the report file.
- **Correct the guide.** See [CONTRIBUTING.md](../CONTRIBUTING.md) and [DATA_FORMAT.md](DATA_FORMAT.md). Say where the fact comes from.
- **Test on your save.** Unusual paths (evil runs, origin characters, the Dark Urge, multiplayer) are where bugs hide.

## Notes for contributors

Verified against the Patch 8 story scripts, for anyone picking up the items above:

- Camp scenes: `DB_CampNight(flag, priority)` with `DB_CampNight_Requirement*`, `_Camp`, `_CancelledBy`, `_ExpiresAfter`, `_Completed` (goal `GLO_CampNights`).
- Point-of-no-return prompts are ready checks, for example `ReadyCheck_EnterNightsongPrison`, `ReadyCheck_ToBGFromSCL`, `TWN_Finale_ReadyCheck`.
- A companion leaving for good goes through `PROC_Origins_CompanionLeavePermanently(companion, reason)`.
- `Ext.Osiris.RegisterListener` can capture events, databases and user-defined PROCs and QRYs, but not built-in calls.
- Conversations ship as JSON with per-node `setflags` / `checkflags` (scope Global, Object or Dialog) and approval reactions.

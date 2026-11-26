# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [1.2.1] - 2026-11-26

A fix for the roadmap window acting on its own.

### Fixed
- **The window no longer reacts to the keyboard or a controller** ([#4](../../issues/4)). The Script Extender lets the keyboard and a game controller drive every mod window, while the game receives the same keys and buttons. Once the roadmap had opened, keys pressed for the game (Space, the arrow keys, Tab, Page Up/Down) or a connected controller, also one you were not holding if its stick drifts, could switch tabs, tick boxes, scroll the window or move it. The roadmap now opens without taking the keyboard and controller, ignores them, and only responds to the mouse. Esc still closes it.
- If boxes were ticked by themselves while this happened, untick them: *I did this - mark it as done* on a step, *Not interested* on a romance, or the settings in *Options*. *Options > Clear all manual check-offs* removes every check-off at once.

### Known limits
- One window shortcut that the Script Extender gives every mod window still works after you click into the roadmap: holding X (Square on PlayStation) and moving the left stick, or Ctrl+Tab and the arrow keys, moves the window. Clicking anywhere in the game ends it.

## [1.2.0] - 2026-11-25

"Camp and warnings": what plays at your next long rest, a heads-up at every point of no return, and a way to say no to a romance.

### Added
- **Tonight at camp.** A new tab shows which camp scenes the game would play if you took a long rest now, and, for each of this guide's camp scenes the game is still holding, what it needs: *Needs 40 approval with Shadowheart (you have 31); you to be Shadowheart's partner.* A scene whose time is running out says so (*Last chance: only at your next long rest*). The roadmap reads the game's own camp-scene scheduler and repeats its choice: the most important scene whose conditions are met, then any others that do not clash with it. The game makes its choice when you rest, so anything that changes before then can change it. The steps these scenes complete say the same on the companion's page. In the console, `!roadmap camp` lists the prediction with the game's own names.
- **A warning at the game's "are you sure?".** When the game asks whether you are ready to enter Nightsong's prison, jump into the Mind Flayer Colony from Moonrise's roof, leave for Baldur's Gate, enter the Lower City or take the boat to the Morphic Pool, a heads-up lists what is still open before that point (the same list as *Before you move on*) and goes away with your answer. *Options > Notifications* can switch it off.
- **Not interested** (requested on Nexus). Tick it on a companion's page, under *Romance path*, or in *Options > Romances you do not want*. Their romance steps then only show where the romance can begin, labelled `SAY NO`, so you know which conversation to turn it down in. The rest of their romance no longer counts, and its notices and warnings stop. Their own story is untouched. The choice is kept in your save, for each player. The roadmap cannot stop a romance in the game, only help you avoid it.
- **Knock out, do not kill.** When a fight starts against Minthara or Minsc while you can still recruit them, a heads-up reminds you to switch on Non-Lethal Attacks and land the last hit with a melee weapon or an unarmed strike. It stays away when Minthara fights on your side. *Options > Notifications* can switch it off.
- **Recent approval changes.** Under a companion's approval bar: the last ten changes, by how much, who you were talking to and how many long rests ago (*-5, talking with Karlach, 1 long rest ago, now 28*). Kept in your save; it starts with this version.
- **Do you have the item?** A step that needs an item says whether your party has it, camp chest included: the Noblestalk, the Idol of Shar, a Night Orchid, the Spear of Night (also on the Nightsong step, because entering the Shadowfell without it sends Shadowheart away), Infernal Iron for Karlach's engine, the Orphic Hammer and the Annals of Karsus. The roadmap reads the markers the game itself keeps for these items.

### Changed
- Report files also carry the camp-scene scheduler's tables and the prediction made from them, the approval log and the romances marked as not wanted, so a report replays to the same "Tonight at camp".
- `!roadmap forget` also clears the approval log.
- The network protocol changed: in multiplayer, everyone needs this version.
- For guide writers: `item` and `campScene` on steps, `knockOut` on companions (see [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md)).

## [1.1.0] - 2026-11-17

"Trust": the roadmap remembers what it has seen, and its data is now checked against the game's own camp-scene rules.

### Added
- **The roadmap remembers.** When the roadmap sees a step happen, it now writes that down in your save. Some moments only last as long as their scene: the game clears its own marker afterwards, and the step used to fall back to `NOT SEEN`. A remembered step stays `DONE`, and says so: *Remembered: ... The roadmap saw this in Act 2; your save no longer shows it.* A failure the game records still wins, and a memory never marks anything as missed. Moments that were already over before you installed this version cannot be remembered. *Options* shows how many moments are remembered; in the console, `!roadmap memory` sums them up and `!roadmap forget` clears them for this save.
- **Why a companion left.** When the game removes a companion for good, the roadmap records the game's own reason and gives it on their page in plain words, for example "Karlach was left behind in the prison at Wyrm's Rock" or "Gale left camp after Ketheric fell: Elminster's message never reached him". This also covers departures the journal never mentions.
- **Patch-day check.** On loading a save, the roadmap looks up every story flag it watches. If a game update removed some, the window says so at the top and the console names them, so a step that can no longer be detected shows up as a warning instead of a silent `NOT SEEN`.
- **Portraits follow the companion's mood.** Each picture now changes with how things stand between you:
  - **dead**: the game's own red skull (Lae'zel keeps her own "dead" sticker);
  - **dating or partnered**: their smitten sticker, where the game has one (Astarion, Wyll, Halsin);
  - **approval of 41 or more** (the game's "High"): a pleased one (Shadowheart, Gale);
  - **approval of -20 or less** (the game's "Low"): a sour one (Shadowheart, Karlach, Lae'zel, Minthara, Gale);
  - **gone for good but alive**: the sour one, faded;
  - otherwise a neutral one.

  The game only has a few Photo Mode stickers per companion, so some moods share a picture, and Jaheira and Minsc have a single one. There are no stickers for a companion's path (Shar or Selûne, ascended or not), so that is not shown.

### Fixed
- Found by the new cross-check with the game's camp scenes:
  - Shadowheart's night swim, her Shar-path night and the shrine at nightfall only play while you are her partner. They now wait for the partner step, and are closed when it was missed, instead of staying open.
  - Astarion's night after the Black Mass needs you to still be his partner, and now waits for that step too.
  - Karlach's "cool her down" step counted as done as soon as she asked you about it. It now waits for the cooling scene itself, and says what works (water or cold) and that a long rest makes her drop the idea.
- Minthara's raid path is marked done as soon as the Grove falls, not only once the goblins' celebration at camp has played.
- A companion abducted by Orin would have been shown as gone for good: while she holds them, the game marks them the way it marks a companion it has removed. They are no longer counted as lost; they can still be rescued.
- Pictures no longer contradict the companion's state. Shadowheart's was her angry sticker even at high approval, and Astarion's had heart eyes whatever happened, including when he was dead. (1.0.3 only tinted the same picture.)

### Changed
- Report files also contain what the roadmap remembers and any flags the patch-day check could not find, so a report replays to the same result.
- For contributors: `tools/build_data.py` compares every step that is completed by a camp scene with the game's camp-scene scheduler: approval thresholds, scenes that need you to be dating or partnered, and what cancels a scene. It runs whenever the local game-data cache is present. `tools/extract_game_data.py` also lists the game's UI icon names (`--only icons` refreshes just that), and the validator checks the portrait sets and the icon the mod uses against the game.

## [1.0.3] - 2026-11-15

### Added
- **Choose where notices appear** (requested on Nexus). *Options > Notifications > Where notices appear*: right under the minimap (as before), right middle, right bottom, top centre, left middle, bottom centre above the hotbar, or anywhere with two sliders. Changing it shows a sample notice; *Show a test notice* does too. Also on the MCM page.
- **Paths are equal choices.** Where a companion's story splits, the paths are now shown side by side with a new status, `CHOOSE`, instead of one being `NEXT` and the other `OPTIONAL`. Each path lists what it changes under a neutral *What it changes*, rather than under *Avoid*. "Before you move on" lists the decision once, with every path. Minthara's knockout and the raid on the Grove are the first such paths.

### Fixed
- **Minthara's evil path read as a dead end.** The romance notes said the night after the raid "does not start a relationship", which suggested she could no longer join. She can: on both paths she turns up at Moonrise Towers in Act 2 and joins once freed (confirmed in the game's story scripts), and her romance can start on either path.
- **Portraits did not show a companion's state.** Lae'zel's picture was a Photo Mode sticker of her dead, even while she was alive, and Astarion's has heart eyes; the faint fade on lost companions was easy to miss. Lae'zel now has a neutral picture, and her "dead" sticker appears only while she is dead. Every portrait turns red while its companion is dead but can be revived, and dark and faded once they are gone for good.
- Gale's ending is a choice, not a mistake: the Mystra step now describes both the human and the god ending instead of listing his ambition under *Avoid*.

### Changed
- For guide writers: `changes` on a step, and `alt` groups now show as `CHOOSE` (see [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md)). The validator checks that MCM's choice lists match the code's.

## [1.0.2] - 2026-11-15

"Nothing missed": a completeness review of every companion. What was reviewed, and what each point was confirmed against, is in [docs/COVERAGE.md](docs/COVERAGE.md).

### Added
- **Every way to lose a companion that could be confirmed is now a golden rule.** 24 new rules, each confirmed in the game's story scripts or journal. Among them: Lae'zel (the night she wants to kill everyone, the githyanki patrol, the zaith'isk, the Inquisitor, reaching Moonrise without the creche, the very end), Karlach (the paladins, Minthara and the Grove, Wyrm's Rock prison), Astarion (staking him, the Gur in Act 3, Cazador finishing the ritual), Gale (sending him away, raiding the Grove), Wyll (defending Karlach from him, anyone in your party killing the Duke), Shadowheart (attacking her at the Nightsong, her parents), Minthara (sending her away after Ketheric), Jaheira and Minsc (her children, her allies, the Murder Tribunal, leaving her behind).
- **"For every companion"**: a short list on every page with the ways to lose anyone: approval at -50, telling them to leave, BOOOAL, the necromancer's laboratory in the Colony, the Dark Urge, Orin's abduction, Haarlep. It follows the spoiler setting like the golden rules do.
- **A companion the game has removed is shown as lost even when the journal says nothing.** Most ways of losing a companion leave no journal entry (Halsin staying behind in Act 2, for example). The tracker now also reads the marker the game itself puts on a companion it has removed for good.
- New steps: Shadowheart's Shar-path scene at the shrine (Act 3) and Gale's Act 3 romance night.
- [docs/COVERAGE.md](docs/COVERAGE.md): per companion, what the guide warns about, where it was confirmed, and what is still open.
- A note on mods that rewrite a companion's story, starting with what was checked for *Really Shadowheart* (see the README).

### Fixed
- **Steps wait for recruitment.** A romance or approval step of a companion who has not joined yet was shown as TO DO. It is now WAITING, and it is closed for good once that companion can no longer join. (Found in the first real-save report: Karlach, Wyll and Gale.)
- **Steps that involve two companions**: the night Lae'zel and Shadowheart fight over the artefact stayed open after one of them was gone. It is now N/A.
- More outcomes are recognised as "gone for good": Shadowheart (killed at the Nightsong, surrendered to Viconia, her parents' scene broken), Lae'zel (turning on you at the very end), Astarion (handed to the Gur in Act 3), Gale (dead beyond resurrection, or leaving because Elminster never delivered his message), Jaheira (dead), Karlach.
- Lae'zel going ahead to the creche on her own was shown as a missed creche. She is waiting for you there; the step stays open.
- Wyll's proposal was shown as DONE when the same camp night had played as his goodbye (the Duke dead). It now needs you to still be his partner.
- From the game's camp-scene scheduler: Karlach's date at the Singing Lute needs 30 approval; her night visit in Act 1 needs approval above 30; Gale's starry night needs Elminster's message first; Shadowheart's Dark Justiciar night is cancelled once the House of Grief is finished, and her talk about the future needs the night swim; Halsin's night is on offer for two long rests only, and he waits for Karlach's second upgrade if she is your partner.

### Changed
- Report files also record the two markers mentioned above, so a report replays to the same result.
- For guide writers: `C.Lost("<Companion>")` (another companion is gone), `needsJoin` on a step, `joined` on a companion. See [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md).

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

[Unreleased]: ../../compare/v1.2.1...HEAD
[1.2.1]: ../../releases/tag/v1.2.1
[1.2.0]: ../../releases/tag/v1.2.0
[1.1.0]: ../../releases/tag/v1.1.0
[1.0.3]: ../../releases/tag/v1.0.3
[1.0.2]: ../../releases/tag/v1.0.2
[1.0.1]: ../../releases/tag/v1.0.1
[1.0.0]: ../../releases/tag/v1.0.0

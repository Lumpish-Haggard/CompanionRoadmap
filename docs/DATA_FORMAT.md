# Writing guide data

Every companion lives in its own file, `Mods/CompanionRoadmap/ScriptExtender/Lua/Data/Companions/<Name>.lua`, which calls `CR.Guides.Register { ... }`. This page explains every field, how the tracker turns conditions into a status, and how to find the right game flag or journal step.

The rule that matters most: **every fact must come from the game files or a reliable source.** Item names, DCs, approval thresholds and locations are checked against the extracted game data or bg3.wiki before they go in.

---

## A minimal step

```lua
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G
local SH = "ORI_COM_ShadowHeart"

{
    id = "SH_A2_ORCHID", act = 2, kind = "romance", romance = true,
    title = "Give her a Night Orchid",
    where = "Ruined Battlefield, Shadow-Cursed Lands",
    todo = { "Pick the Night Orchid and give it to her from the inventory or in conversation." },
    rewards = "Approval, a sweet scene and a Nightsong point.",
    done = { Q(SH, "GaveNightOrchid"), G("ORI_Shadowheart_State_NightsongPoint_GaveNightOrchid") },
    closes = "act3",
},
```

## Companion fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable id (`Shadowheart`, `Laezel`, ...). Also used by the MCM "last companion" setting. |
| `name` | string | Display name (`Lae'zel`). |
| `uuid` | string | The character's GUID (`S_Player_..._<guid>`, the GUID part only). |
| `subtitle` | string | One line under the name. |
| `romanceable` | bool | Shows relationship state and the romance panel. |
| `recruited` | condition | True while the companion is in camp or party (`GLO_Origin_PartOfTheTeam_<Name>`). |
| `left` | condition list | Any true means the companion is gone for good. Their unfinished steps become MISSED. |
| `romance` | table | `dating`, `partnered`, `ex` conditions and a `closed` list (romance ended). |
| `rules` | string list | The "Golden rules" shown at the top of the page: things that lose the companion. |
| `romanceNotes` | string list | The "Romance path" summary. |
| `counters` | list | Live counters such as Nightsong points: `{ id, label, need, help, items = { { label, cond } }, reached = cond }`. |
| `steps` | list | The steps, in story order. |

## Step fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Unique across all companions. Convention: `<PREFIX>_A<act>_<NAME>`, e.g. `KAR_A2_UPGRADE`. Never rename a released id: manual check-offs are stored by id. |
| `act` | 0-3 | 0 = prologue (shown in the Act 1 section), 1, 2 or 3. |
| `kind` | string | `recruit`, `story`, `romance`, `choice` or `approval`. Recruit and romance steps become N/A when you play as that origin. |
| `title` | string | Short and specific. Romance steps start with `Romance:`. |
| `where` | string | Location; add `(X:.. Y:..)` coordinates only when verified. |
| `todo` | string list | One action per line, imperative. |
| `avoid` | string list | Mistakes and their consequences ("... - she leaves for good."). |
| `rewards` | string | Items, approval, unlocks. |
| `notes` | string | Optional extra text. |
| `approval` | number | Approval this step needs. The UI compares it with the player's live approval. |
| `romance` | bool | Part of the romance track (romance filter, notifications, "Your romance" warnings). |
| `romanceStart` | bool | The step that *starts* a romance. Listed under "Romances that can only begin before this point" for single players. |
| `critical` | bool | Important: shown in point-of-no-return warnings and "missed" notifications. |
| `optional` | bool | Skipping it is fine: becomes N/A instead of NOT SEEN, never triggers "missed" notifications. |
| `done` | condition list | Any true means DONE. |
| `fail` | condition list | Any true means MISSED. |
| `skip` | condition list | Any true means N/A (another path was taken). |
| `after` | step id list | Steps that must be finished first (WAITING until then; MISSED if one of them was missed). |
| `closes` | deadline id | The point of no return after which this step can no longer be done. |
| `alt` | string | Group of alternative routes; once one is done, the others become N/A (e.g. Minthara knockout vs raid). |

## Conditions

| Constructor | True when |
|---|---|
| `Q(quest, step)` | The journal step is unlocked (`QuestUpdateIsUnlocked`). `ORI_COM_X` quests are also checked as `ORI_Avatar_X`, so origin playthroughs work. |
| `P(flag)` | The flag is set on the player's avatar. Use for `ORI_State_DatingX` / `ORI_State_PartneredWithX`. |
| `G(flag)` | The global flag is set. Use for camp nights (`NIGHT_*`), `*_PartyProgress_*`, `VISITEDREGION_*`. |
| `F(flag, on)` | `on` is `"player"`, `"global"`, `"companion"` or `"any"`. `"any"` checks every target the flag's usage allows; use it when the story does not show how the flag is set. |
| `C.Rel(state)` | Relationship with this companion is `"dating"`, `"partnered"` or `"ex"` (flags plus the `DB_ORI_Dating`/`DB_ORI_Partnered` databases). |
| `C.Recruited()` | This companion is in camp or party. |
| `C.Dead()` | This companion is dead or permanently defeated. |
| `C.KO()` | This companion is knocked out instead of dead (Minthara's good path). |
| `C.Prog(marker)` | A progress marker from `CR.Guides.Markers` was reached. |
| `C.Any{...}`, `C.All{...}`, `C.Not(c)` | Combinations. |

Lists (`done`, `fail`, `skip`, `left`) are "any of". Use `C.All{}` for "both".

## How a status is decided

`Tracker/FlagEvaluator.lua` checks, in this order:

1. any `done` condition -> **DONE**
2. checked off by hand -> **CHECKED**
3. playing as this origin and the step is a recruit/romance step -> **N/A**
4. any `skip` condition -> **N/A**
5. any `fail` condition -> **MISSED**
6. the companion is gone (`left`, or permanently defeated) -> **MISSED**
7. the `closes` deadline was reached -> **MISSED**
8. a step in `after` is missed -> **MISSED** (blocked)
9. the step's act is later than the campaign -> **LATER**
10. a step in `after` is not finished -> **WAITING**
11. an earlier act and no `closes` -> **NOT SEEN** (or **N/A** if `optional`)
12. otherwise **TO DO**; the first one (required before optional) becomes **NEXT**

These are the labels the window shows (`UI/Theme.lua`); the code uses one-letter status codes (`CR.Status`).

Then `alt` groups are resolved.

## Deadlines (`closes`)

| id | Reached when (global flag) | Meaning |
|---|---|---|
| `act1` | `Act2_PointOfNoReturnReached` | Entered Nightsong's prison in the Shadowfell; Act 1 areas are gone |
| `colony` | `COL_PartyProgress_EnteredColony` | Went down into the Mind Flayer Colony; no more Act 2 long rests |
| `act3` | `VISITEDREGION_BGO_Main_A` | Reached Rivington; the Shadow-Cursed Lands are gone |
| `lowercity` | `VISITEDREGION_CTY_Main_A` | Entered the Lower City |
| `endgame` | `END_General_State_Started` | The final battle started |

## Finding flags and journal steps

Extract the game data once (Windows, needs your BG3 install and LSLib):

```powershell
py tools/extract_game_data.py
```

Then search it:

```powershell
py tools/search_game_data.py shadowheart orchid          # flags and journal steps
py tools/search_game_data.py --quests MintharaFate        # every step of a quest, with the flag that unlocks it
py tools/search_game_data.py --story ORI_State_DatingKarlach   # how the Osiris story sets/uses a flag
```

Guidelines:

- **Prefer journal steps (`Q`)** for story progress. They are what the player sees in the journal, and the game sets them in all the right situations.
- **Use romance flags (`P`)** for dating/partnered state: `ORI_State_Dating<Name>`, `ORI_State_PartneredWith<Name>`, `ORI_State_WasPartneredWith<Name>`, `ORI_State_ChosePartnerOver<Name>`.
- **Camp scenes** are global `NIGHT_*` flags, set only when the scene has actually played.
- **Pick the target from the flag's usage**: `global` -> `G`, `object` -> `P` or `F(..., "companion")`, `global+object` -> check `--story` output; if unclear, use `F(name, "any")`.
- Dialog-only flags (usage `dialog`) cannot be read outside a conversation. Don't use them.

## Writing style

- Short, concrete, imperative. One action per `todo` line.
- **ASCII and Latin-1 only.** The Script Extender IMGUI font has no other glyphs: no em/en dashes, curly quotes, ellipsis characters, arrows or check marks (`build_data.py` rejects them). Latin-1 letters such as `û` in Selûne are fine.
- Name items, NPCs and places exactly as the game does (search the English localization if unsure).
- Don't invent numbers. Give a DC, approval threshold or coordinate only if it is verified, and mention the source in your pull request.

## Before you open a pull request

```powershell
py tools/build_data.py        # with the game cache: validates against the game and regenerates Data/Flags.lua
py tools/build_data.py --offline   # without game files (what CI runs)
py tools/test_harness.py
```

Commit the regenerated `Data/Flags.lua` together with your data change.

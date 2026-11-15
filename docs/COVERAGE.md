# Coverage

What the guide warns about, and what each warning was checked against. This page exists so that gaps are visible instead of assumed away.

> [!WARNING]
> **Spoilers for the whole game.** This page lists how every companion can die or leave.

Last reviewed for **1.0.2**, against the story scripts and journal of **Patch 8**.

## How the review was done

1. **Collect.** Everything published about losing a companion was read: the bg3.wiki pages on companions, each companion's own page, their romance, approval and quest pages. That gives a list of *what to look for*.
2. **Confirm.** Each point was then looked up in the game's own files (see [DATA_FORMAT.md](DATA_FORMAT.md) for how to extract them). The game decides what is true. A point that could not be found there is listed under *Still open* and is **not** in the guide.
3. **Write.** Confirmed points became golden rules, in our own words, tagged with the act they belong to so the spoiler setting can hide them.

The game files gave three independent checks:

- **The removal routine.** Every permanent departure goes through one story routine. The scripts call it from 61 places in 29 story goals; each call names the companion and the scene it happens in.
- **The leaving conversations.** The game keeps a list of every conversation in which a companion may walk out, die or turn on you (42 entries).
- **The journal.** For the six origin companions the game also keeps a fixed list of journal entries that mean "gone for good".

In the tables below, *Scripts* names the story goal that removes the companion, *Journal* a journal entry, *Conversation* an entry of the leaving list, *Scheduler* the game's camp-scene scheduler. *Reference only* means the rule was carried over from 1.0, where it was checked against published references but not traced in the scripts.

## How a lost companion is detected

| Signal | Used for |
|---|---|
| Journal entries that end the companionship | The six origin companions, and the quests of Halsin, Minthara, Jaheira and Minsc |
| The game's "permanently defeated" record | Any companion killed for good |
| Dead and never recruited | Anyone except Wyll and Lae'zel, who can still be revived |
| **New in 1.0.2:** the marker the removal routine leaves on the companion | Everything else. Most departures write nothing to the journal: Halsin staying behind, Karlach left in prison, Astarion sacrificed, Jaheira and Minsc turning on you, Minthara sent away. |

The game also uses one of the two markers for other purposes: in a real Act 1 save, Halsin, Minthara and Minsc already carry it before they ever join. That is why both markers are required, and why a companion who is in your team is never counted as lost this way. That save is now a regression test. Later acts have not been seen with this check yet. If a companion is shown as lost who is not, or the other way round, please send a report file.

## For every companion

| The guide warns | Confirmed in |
|---|---|
| Approval of -50 or lower: they leave with what they have equipped | Scripts: `_GLO_Shared_Origins` (the leaving conversation); Journal: `CompanionLowRelation` |
| Telling a companion to leave is final | Scripts: `_GLO_Shared_Origins` (the list of leaving conversations) |
| Sacrificing a companion to BOOOAL | Scripts: `Act1_UND_KuoToaGod` |
| A party member raised as a zombie in the necromancer's laboratory | Scripts: `Act2_COL_NecromancerRoom` (killing the zombie lifts the block; leaving the Colony makes it final) |
| The Dark Urge killing the companion closest to them | Scripts: `GLO_Origin_DarkUrge_KillFavourite` |
| Orin's abduction | Scripts: `Act3_GEN_OrinsAbduction`, `Act3b_LOW_BhaalTemple` |
| Giving a companion to Haarlep | Scripts: `Act3b_LOW_HouseOfHope2` |

## Shadowheart

| The guide warns | Confirmed in |
|---|---|
| Siding with Lae'zel when they fight at camp | Journal: `CampFight_ShadowheartDied` |
| Entering the Shadowfell without her, or without the Spear of Night | Scripts: `Act2_OriginMoments_Shadowheart` (left out of the party, she confronts you in the temple; that conversation can end with her leaving, and if you leave Act 2 without making it up she is gone); Conversation: two at the temple |
| Handing Nightsong to Balthazar | Journal: `Nightsong_Surrendered` |
| Deciding Nightsong's fate for her | Journal: `SharTemple_NoDecisionAllowed` |
| Attacking her at the Nightsong | Journal: `ShadowHeartDead_SUB_Justiciar`; Conversation: three in Nightsong's prison |
| Surrendering her to Viconia | Scripts: `Act3b_LOW_SharGrotto`; Journal: `SurrenderedShadowheart` |
| Harming her parents, or breaking up that scene | Scripts: `Act3b_LOW_SharGrotto`; Journal: `EnemyOfShar_ParentsSceneBroken`, `SharPath_ParentsSceneBroken` |

## Lae'zel

| The guide warns | Confirmed in |
|---|---|
| Fighting her, or leaving her, at the tiefling cage | Scripts: `Act1_CHA_LaezelRecruit`; Journal: `KilledLaezel`, `SidedTieflings` |
| The night she decides to kill everyone | Scripts: `Act1a_Camp`; Journal: `LaezelDied_KilledAtCampNight` |
| The fight with Shadowheart at camp | Journal: `LaezelDied_KilledByShadowheart` |
| The githyanki patrol: attacking early, or leaving her there | Scripts: `Act1_PLA_GithChokepoint`; Journal: `TurnedHostileAtChokepoint`, `LaezelDied_KilledByVossInPlains` |
| Forbidding her the zaith'isk | Conversation: the zaith'isk scene |
| Attacking the Inquisitor, defying Vlaakith's order | Scripts: `Act1b_OriginMoments_Laezel`; Journal: `TurnedHostileDuringInquisitor` |
| Reaching Moonrise Towers or the Gauntlet of Shar without the creche | Scripts: `GLO_Origin_Laezel_PostEA`; Journal: `LeftInSCL`, `LaezelDied_FoundShadowcursedInSCL` |
| The very end: Orpheus consumed, or freed, against her loyalty | Scripts: `Act3c_END_IllithidOptions`; Journal: `TurnedHostile_MorphicPool_OrpheusPath`, `..._VlaakithPath` |

## Karlach

| The guide warns | Confirmed in |
|---|---|
| Meeting her only after the Grove is raided or the Rite of Thorns is done | Reference only |
| Siding with the paladins, or attacking her | Scripts: `Act1_PLA_KarlachRecruitment`, `Act1_OriginMoments_Karlach` (she leaves hostile after the paladins' conversation) |
| Letting Wyll kill her | Journal (Wyll): `KarlachKilled`; Scripts: `Act1_OriginMoments_Karlach` (the confrontation can also end with her leaving hostile) |
| Leaving for the Mountain Pass or the Shadow-Cursed Lands with the paladins alive | Journal: `PaladinsReminder`; Conversation: her camp talk about the paladins |
| Raiding the Grove with Minthara | Scripts: `Act1_CAMP_GoblinHuntCelebration` (she and Wyll are the companions who walk out); Conversation: the raiders' celebration |
| Losing Dammon | Journal: `DammonPermadefeated` |
| Missing her Act 2 night (ends the romance, not the companionship) | Reference only |
| Leaving her in the Wyrm's Rock prison | Scripts: `Act3_OriginMoments_Karlach`; Journal: `KarlachNotRescued` |

## Astarion

| The guide warns | Confirmed in |
|---|---|
| Giving him up to Gandrel, or telling Gandrel where you camp | Scripts: `Act1a_Camp`; Journal: `MetGur_AstarionCapture`, `MetGur_AstarionDisappear` |
| Letting him drink you dry | Reference only |
| Staking him or sending him away when he reveals what he is | Conversation: the bite night |
| Pushing him with Araj Oblodra (ends the romance) | Reference only |
| Siding with the Gur against him in Act 3 | Journal: `Ulma_BetrayedAstarion`; Conversation: the Gur camp |
| Cazador finishing the ritual | Scripts: `Act3b_LOW_CazadorsPalace_RitualRoom` |
| Refusing him at the ritual without talking him down | Conversation: after the fight with Cazador |
| Interrupting the ritual once he has started | Reference only |

## Gale

| The guide warns | Confirmed in |
|---|---|
| Failing to pull him out of the rune circle | Reference only |
| Refusing the first magic item | Conversation: his in-party talk; Reference |
| Telling him to leave | Conversation: his in-party talk, the "betrayal" camp talk |
| Leaving him dead for three long rests | Reference only |
| Raiding the Grove | Scripts: `Act1_CAMP_GoblinHuntCelebration`; Conversation: the raiders' celebration |
| Ignoring or attacking Elminster | Scripts: `Act2b_ORI_Gale`; Journal: `ORI_Gale_BombNotDisarmed`, `ORI_Gale_AbandonedBombNotDisarmed` |

## Wyll

| The guide warns | Confirmed in |
|---|---|
| His romance only starts at the Tiefling celebration | Reference. See *Still open*. |
| Raiding the Grove | Scripts: `Act1_DEN_AttackOnDen`, `Act1_CAMP_GoblinHuntCelebration` |
| Taking up arms for Karlach against him | Scripts: `Act1_OriginMoments_Karlach` (the confrontation can end with Wyll leaving hostile) |
| Mizora dying, or being left in her pod | Scripts: `Act2_OriginMoments_Wyll`; Journal: `MizoraDied` |
| The Duke dying (he ends the romance) | Scheduler: the two versions of his Act 3 night; Reference |
| Anyone in your party killing or fighting the Duke | Scripts: `Act3_OriginMoments_Wyll`, `Act3i_IRN_IronThrone` |

## Halsin

| The guide warns | Confirmed in |
|---|---|
| Leaving Act 1 without rescuing him | Journal: `DruidLeaderDied`, `Halsin_Lockdown` |
| Raiding the Grove | Journal: `Betrayal_DruidDead_Halsin` |
| Letting his portal close | Journal: `HalsinDied` |
| Leaving Act 2 with the shadow curse in place | Scripts: `Act2_TWN_LiftingTheCurse_Finale` (no journal entry: detected by the marker) |

## Minthara

| The guide warns | Confirmed in |
|---|---|
| Killing her instead of knocking her out | Scripts: `Act1_GOB_DrowCommander`; the game's knocked-out record |
| Letting the inquisitors erase her mind | Journal: `MintharaPacified` |
| Going down into the Colony before freeing her | Journal: `MintharaLeftBehind`, `MintharaIgnored` |
| Insisting that she leave after Ketheric is defeated | Scripts: `Act2_SCE_MintharaFollowUp` (no journal entry: detected by the marker) |

## Jaheira

| The guide warns | Confirmed in |
|---|---|
| Letting her die before Ketheric retreats | Reference only |
| Attacking Isobel | Conversation: "attacked an ally"; Reference |
| Telling her to stay behind and entering the Lower City without speaking to her again | Scripts: `GLO_Companion_Jaheira` |
| Attacking her children or her Harper allies | Scripts: `Act3b_LOW_JaheirasHouse`; Conversation: two |
| Killing Minsc, or refusing to take him in | Journal: `MinscDefeated`, `NotRecruitedMinsc`, `JaheiraLeavesParty` |
| Offering her or Minsc at the Murder Tribunal | Scripts: `Act3b_LOW_MurderTribunal` (either offer starts a fight with both of them) |

## Minsc

| The guide warns | Confirmed in |
|---|---|
| Coming without Jaheira | Journal: `FailedToSaveMinsc` |
| Killing him instead of knocking him out | Journal: `MinscDefeated` |
| The Emperor refusing to shield him | Journal: `FailedToSaveMinsc` |
| Losing Jaheira, attacking her children, the Murder Tribunal | Scripts: `GLO_Companion_Minsc`, `Act3b_LOW_JaheirasHouse`, `Act3b_LOW_MurderTribunal` |

## Scenes, requirements and deadlines

The loss review above is complete. This part has only had a **first pass**, against the game's camp-scene scheduler, which lists every camp scene with its requirements, what cancels it and when it expires.

Corrected in 1.0.2 from the scheduler:

| Fact | In the guide as |
|---|---|
| Karlach's date at the Singing Lute needs 30 approval and being her partner | A requirement on that step |
| Her Act 1 night visit needs approval *above* 30 | Wording of that step |
| Gale's starry night needs Elminster's message first, and is cancelled by entering the Colony | A dependency on the Elminster step |
| Gale has an Act 3 romance night once he has read the Annals of Karsus | A new step |
| Shadowheart's Dark Justiciar night is cancelled once the House of Grief is concluded | A deadline on that step |
| On the Shar path, with her parents killed and 40 approval, there is a later scene at a shrine | A new step |
| Shadowheart's talk about the future needs the night swim | A dependency |
| Halsin's night expires two long rests after it becomes available; with Karlach as your partner he waits for her second upgrade | Warnings on that step |
| Wyll's Act 3 night also plays as his goodbye when the Duke is dead | The proposal is only detected while you are still his partner |

The approval thresholds for starting a romance through a camp night (Gale 36, Karlach above 30) match the scheduler, which requires approval strictly above its stored value.

## Still open

Mentioned in published references, **not confirmed in the game files, and therefore not in the guide**:

- **Astarion:** leaving if Yurgir's contract is broken without a successful check; leaving if Cazador is killed without him while approval is low (the conversation after the fight has a version for when he is not in the party, but the threshold was not found); leaving if a romanced, ascended Astarion is refused.
- **Lae'zel:** turning on you if Voss is attacked in Act 3 after she has rejected Vlaakith. The exact lines that end the zaith'isk and Inquisitor scenes badly were not traced either; the rules for those two are deliberately general.
- **Karlach:** leaving on the spot when you tell Minthara where the Grove is (as opposed to walking out at the celebration after the raid, which is confirmed).
- **Wyll:** leaving when a member of the Grove is killed, as something separate from raiding it. And his romance: the scheduler still lists a second way to begin it in Act 2 (approval above 40, no partner), which references say no longer triggers in the unmodded game. The guide keeps the safe advice: begin it at the celebration.
- **Jaheira:** which attacks on Isobel count. References describe a bug where any damage to Isobel can turn her.

Known and **not in the guide yet** (planned, see the [roadmap](ROADMAP.md)):

- Losses that only exist for an **origin character or the Dark Urge**: Astarion as the player drinking a companion's blood, and Jaheira, Minsc, Wyll, Gale and Karlach leaving a Dark Urge who becomes Bhaal's chosen (Scripts: `Act3b_LOW_BhaalTemple`).
- **Optional camp scenes** the scheduler lists that are not steps yet, for example the second nights with Astarion and Lae'zel, Lae'zel's scene after the duel, and Mizora's night.
- **Approval**: which choices raise or lower it. The guide only gives thresholds.
- **Minthara, Halsin, Jaheira and Minsc** have no journal list of their own, so their generic departures rely on the marker described above.

## Found a gap?

[Open an issue](../../../issues/new/choose) and say where the fact comes from. If it is about your own save, attach the report file (*Options > Create a report file*).

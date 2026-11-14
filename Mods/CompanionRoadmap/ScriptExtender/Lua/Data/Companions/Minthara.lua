-- =============================================================================
-- Minthara Baenre - drow paladin of the Absolute
-- Good-path recruitment (knock her out in Act 1) and the evil-path raid are both
-- tracked. Sources: Act1_GOB_DrowCommander / Act2_MOO_MintharaFate goals,
-- MOO_MintharaFate journal, flags (Patch 8), bg3.wiki.
-- =============================================================================
local C = CR.Cond
local Q, P, G, F = C.Q, C.P, C.G, C.F

local FATE = "MOO_MintharaFate"

CR.Guides.Register {
    id = "Minthara",
    name = "Minthara",
    uuid = "25721313-0c15-4935-8176-9f134385451b",
    subtitle = "Drow paladin - Decide Minthara's Fate",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Minthara"),
    left = { Q(FATE, "MintharaPermaDefeated"), Q(FATE, "MintharaPacified") },
    romance = {
        dating = P("ORI_State_DatingMinthara"),
        partnered = P("ORI_State_PartneredWithMinthara"),
        ex = P("ORI_State_WasPartneredWithMinthara"),
        closed = { P("ORI_State_ChosePartnerOverMinthara") },
    },

    rules = {
        { act = 1, "Good path: she must be KNOCKED OUT, never killed. Toggle Non-Lethal Attacks and land the final hit with a melee weapon or an unarmed strike." },
        { act = 1, "Spells, ranged attacks, thrown items, surfaces (fire, acid) and damage-over-time (bleeding, burning, poison) still KILL her." },
        { act = 1, "Once she is down, nobody may hit her again - stop area spells near her body." },
        { act = 2, "Rescue her on your first visit to Moonrise Towers - going down into the Mind Flayer Colony leaves her behind for good." },
        { act = 2, "She does not share: reaching her partner threshold ends every other romance automatically." },
    },
    romanceNotes = {
        { act = 1, "Evil path only: a one-night stand at the goblin party (does not start a relationship)." },
        "Act 2/3: after her rescue, at 31+ approval she opens her mind to you before a long rest - imagine her as anything but 'a monster'.",
        { act = 2, "Partnered automatically (and exclusively) at 50+ approval, or when Ketheric falls if you are only dating others." },
        "Act 3: entering the sealed Undercity Ruins with 40+ approval triggers her deepest confession.",
        { act = 3, "Sleeping with Mizora ends the relationship." },
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "MIN_A1_MEET", act = 1, kind = "story", optional = true,
            title = "Meet Minthara in the Shattered Sanctum",
            where = "Goblin Camp - Shattered Sanctum, war room upstairs",
            todo = {
                "Talk to her as a 'True Soul'. She asks where the druid grove is.",
                "Good path: refuse or dodge the question. Evil path: tell her and agree to the raid.",
            },
            avoid = { "Agreeing to raid the Grove (unless you want the evil path): Karlach and Wyll leave, the tieflings and druids die." },
            done = { F("GOB_DrowCommander_HasMet", "any"), C.KO(), G("NIGHT_GoblinHunt_RaiderCelebration") },
            closes = "act1",
        },
        {
            id = "MIN_A1_KO", act = 1, kind = "recruit", critical = true, alt = "MIN_ROUTE",
            title = "Good path: knock her out (never kill)",
            where = "Shattered Sanctum war room - or when she attacks the Grove",
            todo = {
                "Passives tab: toggle Non-Lethal Attacks ON for every character who will hit her.",
                "Start the fight (refuse her, or attack). Her guards and nearby goblins join in.",
                "Bring her low with anything, but the FINAL blow must be a melee weapon or unarmed strike.",
                "Check her portrait: it must say Knocked Out, not dead. Then leave her alone.",
                "Safe to loot: Xyanyde, Boots of Striding, Spidersilk Armour, Spider's Lyre - the game gives her new clothes for Act 2.",
                "You can fight Dror Ragzlin and Priestess Gut in any order; only the way Minthara goes down matters.",
            },
            avoid = {
                "Spells, cantrips, ranged or thrown attacks as the finishing hit - they kill.",
                "Fire, acid or other surfaces, bleeding, burning or poison ticking while she is low - they kill.",
                "Hitting or blasting her body after she is knocked out - that finishes her off.",
            },
            rewards = "She is taken to Moonrise Towers and can be recruited in Act 2.",
            done = { C.KO() },
            fail = { G("GLO_DrowCommander_State_Dead"), C.Dead() },
            closes = "act1",
        },
        {
            id = "MIN_A1_RAID", act = 1, kind = "choice", alt = "MIN_ROUTE", optional = true,
            title = "Evil path: raid the Grove with her",
            where = "Shattered Sanctum, then the Emerald Grove",
            todo = {
                "Tell her where the Grove is and join the raid after the next long rest.",
                "Celebrate with the goblins at camp; she offers a night together and later gives you her Spider's Lyre.",
            },
            avoid = { "This path permanently loses Karlach, Wyll and Halsin (and angers Gale and Shadowheart)." },
            rewards = "Minthara is waiting at Moonrise Towers in Act 2.",
            done = { G("NIGHT_GoblinHunt_RaiderCelebration") },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "MIN_A2_TRIAL", act = 2, kind = "story", critical = true,
            title = "Moonrise Towers: her trial",
            where = "Moonrise Towers, main hall (first visit)",
            todo = {
                "Enter Moonrise and watch Ketheric Thorm judge her for losing the artefact.",
                "Speaking up for her is good roleplay, but Ketheric condemns her no matter what - follow her to the prison.",
            },
            avoid = { "Attacking Ketheric during the trial." },
            done = { Q(FATE, "KnownMintharaCondemned"), Q(FATE, "UnknownMintharaCondemned"), F("MOO_Execution_Event_MintharaLeaves", "any") },
            fail = { Q(FATE, "MintharaPermaDefeated") },
            closes = "colony",
        },
        {
            id = "MIN_A2_PRISON", act = 2, kind = "recruit", critical = true,
            title = "Free her from the interrogation",
            where = "Moonrise Towers prison - interrogation room",
            todo = {
                "Find her being 'questioned' by two gnome inquisitors.",
                "Free her: talk the inquisitors down (skill checks) or kill them, then speak to her.",
            },
            avoid = {
                "Helping the inquisitors erase her mind - she becomes an empty thrall forever.",
                "Leaving Moonrise for the Mind Flayer Colony before freeing her.",
            },
            rewards = "Minthara agrees to escape with you.",
            done = { Q(FATE, "EscapeMoonrise"), Q(FATE, "TalkToMinthara"), Q(FATE, "MintharaEscapedToCamp"), Q(FATE, "MintharaEscapedDisappear") },
            fail = { Q(FATE, "MintharaPacified"), Q(FATE, "MintharaPermaDefeated"), Q(FATE, "MintharaLeftBehind"), Q(FATE, "MintharaIgnored") },
            after = { "MIN_A2_TRIAL" },
            closes = "colony",
        },
        {
            id = "MIN_A2_ESCAPE", act = 2, kind = "recruit", critical = true,
            title = "Escort her out and invite her to camp",
            where = "Out of the Moonrise Towers prison",
            todo = {
                "Lead her out without letting the guards catch you (stealth, invisibility or a clean fight).",
                "Once clear of Moonrise, talk to her and invite her to your camp.",
                "Told her to go her own way? She returns on Ketheric's throne after the Colony - recruit her then.",
            },
            avoid = { "Fast-travelling or abandoning her mid-escape." },
            rewards = "Minthara joins as a permanent companion (Oath of Vengeance paladin).",
            done = { Q(FATE, "MintharaEscapedToCamp"), G("GLO_Origin_PartOfTheTeam_Minthara") },
            fail = { Q(FATE, "MintharaPermaDefeated"), Q(FATE, "MintharaLeftBehind"), Q(FATE, "MintharaIgnored") },
            after = { "MIN_A2_PRISON" },
        },
        {
            id = "MIN_A2_ROMANCE", act = 2, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 31,
            title = "Romance: open your mind to her",
            where = "Camp, before a long rest (after recruiting her)",
            todo = {
                "Raise her approval to 31+; she starts a conversation at camp and touches your mind.",
                "Imagine her as 'a lover' and answer 'There's nothing I want more' - or later reply 'I want you too'.",
            },
            avoid = { "Imagining her as 'a monster' - that permanently closes her romance." },
            rewards = "Relationship: Dating.",
            done = { P("ORI_State_DatingMinthara"), P("ORI_State_PartneredWithMinthara"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverMinthara") },
            after = { "MIN_A2_ESCAPE" },
        },
        {
            id = "MIN_A2_PARTNER", act = 2, kind = "romance", romance = true, approval = 50,
            title = "Romance: exclusive partner",
            where = "Automatic",
            todo = {
                "Reach 50 approval while dating her - she becomes your partner immediately.",
                "Or keep dating her until Ketheric falls in the Colony.",
            },
            avoid = { "Committing to another companion first - she will not share." },
            rewards = "Relationship: Partnered. Unlocks 'Can I kiss you?'.",
            done = { P("ORI_State_PartneredWithMinthara"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverMinthara"), P("ORI_State_WasPartneredWithMinthara") },
            after = { "MIN_A2_ROMANCE" },
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "MIN_A3_ORIN", act = 3, kind = "story", critical = true,
            title = "Revenge on Orin",
            where = "Temple of Bhaal, Lower City (Undercity Ruins)",
            todo = {
                "Take Minthara with you against Orin - Orin enslaved her to the Absolute.",
                "Entering the sealed part of the Undercity Ruins with her triggers a key conversation (her deepest confession at 40+ approval if romanced).",
            },
            rewards = "Completes her arc; approval.",
            done = { Q("LOW_FindBhaalTemple", "HaveControlGem"), Q("LOW_FindBhaalTemple", "RetrievedDagger") },
            closes = "endgame",
        },
        {
            id = "MIN_A3_LOYALTY", act = 3, kind = "romance", romance = true, optional = true,
            title = "Romance: stay faithful",
            where = "Act 3",
            todo = {
                "Optional: take the dryad Zethino's love test with her at the Circus of the Last Days (Rivington).",
                "Turn down Mizora, Haarlep and other trysts she would see as betrayal.",
            },
            avoid = { "Sleeping with Mizora - Minthara ends the relationship." },
            done = { P("ORI_State_PartneredWithMinthara") },
            fail = { P("ORI_State_WasPartneredWithMinthara") },
            after = { "MIN_A2_PARTNER" },
            closes = "endgame",
        },
    },
}

-- =============================================================================
-- Minsc (and Boo) - recruited through Jaheira's "The High Harper"
-- Sources: ORI_HighHarper journal, flags (Patch 8), bg3.wiki.
-- Minsc cannot be romanced.
-- =============================================================================
local C = CR.Cond
local Q, G, F = C.Q, C.G, C.F

local HH = "ORI_HighHarper"

CR.Guides.Register {
    id = "Minsc",
    name = "Minsc",
    uuid = "0de603c5-42e2-4811-9dad-f652de080eba",
    subtitle = "Ranger of Rashemen (and Boo) - The High Harper",
    romanceable = false,

    recruited = G("GLO_Origin_PartOfTheTeam_Minsc"),
    left = { Q(HH, "MinscDefeated"), Q(HH, "FailedToSaveMinsc"), F("ORI_Minsc_State_PermaDefeated", "any") },

    rules = {
        "Jaheira must be recruited in Act 2 - without her, Minsc cannot be saved.",
        "Bring Jaheira to the sewer fight and make the FINAL blow on Minsc non-lethal (melee/unarmed with Non-Lethal Attacks on).",
        "Ask the Emperor to shield him, then take him into the party - refusing makes Jaheira leave too.",
    },
    romanceNotes = { "Minsc cannot be romanced." },

    steps = {
        {
            id = "MINSC_A3_STONELORD", act = 3, kind = "story",
            title = "Who is the 'Stone Lord'?",
            where = "Guildhall (Nine-Fingers Keene), Lower City",
            todo = { "Follow Jaheira's lead to Nine-Fingers Keene: the rival gang boss 'Stone Lord' is Minsc." },
            done = { Q(HH, "MinscIsStoneLord"), Q(HH, "CountingHouseTrapNote"), Q(HH, "CountingHouseTrapBursar"), Q(HH, "CountingHouseTrapDrunkards") },
            closes = "endgame",
        },
        {
            id = "MINSC_A3_VAULT", act = 3, kind = "story",
            title = "The Counting House vault",
            where = "The Counting House, Lower City (vault levels)",
            todo = {
                "Get a vault pass (or another way in) and go down to the vaults.",
                "Follow the muddy footprints / cultist note to Minsc's hideout in the sewers.",
            },
            avoid = { "Starting a fight with the bank's guards." },
            done = { Q(HH, "FindMinscLairStart"), Q(HH, "FindMinscLair"), Q(HH, "FoundMinscNote"), Q(HH, "FoundMinscSWDCultist"), Q(HH, "FoundMinscFootPrints"), Q(HH, "TakeOutMinsc"), Q(HH, "TakeOutMinscStart") },
            after = { "MINSC_A3_STONELORD" },
            closes = "endgame",
        },
        {
            id = "MINSC_A3_KO", act = 3, kind = "recruit", critical = true,
            title = "Knock Minsc out - do not kill him",
            where = "Minsc's hideout, Lower City Sewers",
            todo = {
                "Have Jaheira in the active party.",
                "Toggle Non-Lethal Attacks; finish Minsc with a melee weapon or unarmed strike.",
                "Kill the doppelganger and cultists around him normally.",
            },
            avoid = { "Spells, ranged attacks or damage-over-time finishing him - he dies for good and Jaheira leaves." },
            done = { Q(HH, "SaveMinscFromAbsolute"), Q(HH, "WaitForMinscToFindBoo"), Q(HH, "TalkToMinscAndBoo"), Q(HH, "RecruitedMinsc") },
            fail = { Q(HH, "MinscDefeated"), C.Dead() },
            after = { "MINSC_A3_VAULT" },
            closes = "endgame",
        },
        {
            id = "MINSC_A3_EMPEROR", act = 3, kind = "choice", critical = true,
            title = "Ask the Emperor to protect him",
            where = "Right after the fight",
            todo = { "Convince the Emperor to extend the artefact's protection to Minsc." },
            avoid = { "If Jaheira is absent or gone, the Emperor refuses - Minsc is 'too far gone'." },
            done = { Q(HH, "WaitForMinscToFindBoo"), Q(HH, "TalkToMinscAndBoo"), Q(HH, "RecruitedMinsc") },
            fail = { Q(HH, "FailedToSaveMinsc") },
            after = { "MINSC_A3_KO" },
            closes = "endgame",
        },
        {
            id = "MINSC_A3_BOO", act = 3, kind = "recruit", critical = true,
            title = "Find Boo and recruit Minsc",
            where = "Follow Minsc through the wall he breaks",
            todo = { "Follow him to Boo, then invite them both to join." },
            avoid = { "Sending him away - Jaheira leaves with him." },
            rewards = "Minsc (and Boo) join the party.",
            done = { Q(HH, "RecruitedMinsc"), G("GLO_Origin_PartOfTheTeam_Minsc") },
            fail = { Q(HH, "NotRecruitedMinsc"), Q(HH, "FailedToSaveMinsc") },
            after = { "MINSC_A3_EMPEROR" },
            closes = "endgame",
        },
    },
}

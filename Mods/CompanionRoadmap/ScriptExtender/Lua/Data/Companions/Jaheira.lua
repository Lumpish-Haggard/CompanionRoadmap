-- =============================================================================
-- Jaheira - "The High Harper"
-- Sources: GLO_Moonrise_SUB_MarcusCapture / ORI_HighHarper journals,
-- flags (Patch 8), bg3.wiki (recruitment and leaving conditions).
-- Jaheira cannot be romanced.
-- =============================================================================
local C = CR.Cond
local Q, G, F = C.Q, C.G, C.F

local HH = "ORI_HighHarper"
local MARCUS = "GLO_Moonrise_SUB_MarcusCapture"

CR.Guides.Register {
    id = "Jaheira",
    name = "Jaheira",
    uuid = "91b6b200-7d00-4d62-8dc9-99e8339dfa1a",
    subtitle = "Harper druid - The High Harper",
    romanceable = false,

    recruited = G("GLO_Origin_PartOfTheTeam_Jaheira"),
    left = { F("ORI_Jaheira_State_LeftPermanently", "any"), Q(HH, "JaheiraLeavesParty") },

    rules = {
        { act = 2, "She only becomes a real companion after Ketheric retreats to the Colony - keep her alive until then." },
        { act = 3, "Never kill Minsc, refuse to recruit him once he is saved, or sacrifice him to Sarevok - she leaves." },
        { act = 2, "Never harm her children or Isobel." },
    },
    romanceNotes = { "Jaheira cannot be romanced." },

    steps = {
        {
            id = "JAH_A2_MEET", act = 2, kind = "story", optional = true,
            title = "Meet Jaheira at Last Light Inn",
            where = "Last Light Inn, Shadow-Cursed Lands",
            todo = { "Pass her test of trust (she is suspicious of tadpoled strangers)." },
            done = { G("HAV_PartyProgress_EnteredHaven") },
            closes = "act3",
        },
        {
            id = "JAH_A2_ISOBEL", act = 2, kind = "choice", critical = true,
            title = "Stop Marcus from taking Isobel",
            where = "Last Light Inn - Isobel's room",
            todo = { "When the winged Flaming Fist Marcus comes for Isobel, protect her (warning Jaheira helps)." },
            avoid = { "Letting Isobel be taken - the shield protecting Last Light collapses." },
            rewards = "Last Light Inn stays safe (and so do Dammon and the others there).",
            done = { Q(MARCUS, "SavedIsobel"), Q(MARCUS, "BetrayMarcus"), Q(MARCUS, "SurpriseProtect") },
            fail = { Q(MARCUS, "MarcusCapturedIsobel"), Q(MARCUS, "HelpedMarcusCaptureIsobel"), Q(MARCUS, "HelpedMarcusCaptureIsobel_Zrell"), Q(MARCUS, "HelpedMarcusCaptureIsobel_Ketheric") },
            closes = "act3",
        },
        {
            id = "JAH_A2_RECRUIT", act = 2, kind = "recruit", critical = true,
            title = "Recruit Jaheira",
            where = "After the assault on Moonrise Towers (once Ketheric flees to the Colony)",
            todo = {
                "Keep her alive through the Moonrise assault - having her in your active party lets you protect her.",
                "Invite her to camp when Ketheric retreats.",
            },
            avoid = { "Letting her die before she is recruited - she cannot be revived as a companion." },
            rewards = "Jaheira (druid) joins. Required to recruit Minsc in Act 3.",
            done = { G("GLO_Origin_PartOfTheTeam_Jaheira") },
            fail = { C.Dead() },
        },
        {
            id = "JAH_A3_HARPERS", act = 3, kind = "story", critical = true,
            title = "The High Harper: the doppelganger trap",
            where = "Danthelon's Dancing Axe, Wyrm's Crossing",
            todo = { "Go to the Harper meeting under the shop with Jaheira; it is a doppelganger ambush. Afterwards she asks you to find Minsc." },
            done = { Q(HH, "TalkToJaheira"), Q(HH, "TalkToHarper"), Q(HH, "JaheiraAskedToFindMinsc"), Q(HH, "JaheiraAskedToFindMinscBackup") },
            closes = "endgame",
        },
        {
            id = "JAH_A3_MINSC", act = 3, kind = "choice", critical = true,
            title = "Save Minsc (see Minsc's page)",
            where = "Counting House vault and the Lower City Sewers",
            todo = { "Bring Jaheira to the confrontation in the sewers; knock Minsc out instead of killing him." },
            avoid = { "Killing Minsc or refusing to take him in - Jaheira leaves for good." },
            done = { Q(HH, "WaitForMinscToFindBoo"), Q(HH, "TalkToMinscAndBoo"), Q(HH, "RecruitedMinsc") },
            fail = { Q(HH, "MinscDefeated"), Q(HH, "FailedToSaveMinsc"), Q(HH, "NotRecruitedMinsc") },
            after = { "JAH_A3_HARPERS" },
            closes = "endgame",
        },
    },
}

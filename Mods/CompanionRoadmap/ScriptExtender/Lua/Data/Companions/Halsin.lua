-- =============================================================================
-- Halsin - First Druid of the Emerald Grove
-- Sources: DEN_Conflict_SUB_Halsin / SCL_CursedFist / SCL_LiftingTheCurse
-- journals, NIGHT_Halsin_* camp nights, flags (Patch 8), bg3.wiki.
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local SAVE = "DEN_Conflict_SUB_Halsin"
local ART = "SCL_CursedFist"
local CURSE = "SCL_LiftingTheCurse"

CR.Guides.Register {
    id = "Halsin",
    name = "Halsin",
    uuid = "7628bc0e-52b8-42a7-856a-13a6fd413323",
    subtitle = "Archdruid - Rescue the Druid Halsin / Lift the Shadow Curse",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Halsin"),
    left = { Q(SAVE, "DruidLeaderDied"), Q(CURSE, "HalsinDied"), Q(CURSE, "HalsinDiedOther"), Q(CURSE, "OliverNotFound") },
    romance = {
        partnered = C.Any { P("ORI_State_PartneredWithHalsin"), P("ORI_State_PartneredWithHalsinSecondary") },
        ex = P("ORI_State_WasPartneredWithHalsin"),
    },

    rules = {
        "Rescue him from the Worg Pens before heading to the Mountain Pass trail or the Shadow-Cursed Lands - otherwise he is found dead in his cell.",
        "Save the Grove (defeat the goblin leaders). Raiding the Grove loses him.",
        "In Act 2, defend his portal until he returns - if it closes, he is lost in the Shadowfell.",
        "Lift the shadow curse BEFORE leaving Act 2, or he stays behind and his romance never happens.",
    },
    romanceNotes = {
        "Halsin cannot be romanced until Act 3, after the shadow curse is lifted.",
        "Already partnered? Ask your partner first: Shadowheart, Astarion and Karlach agree to share; Lae'zel, Wyll, Gale (and Minthara) refuse.",
        "His relationship is open and non-exclusive.",
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "HAL_A1_RESCUE", act = 1, kind = "recruit", critical = true,
            title = "Rescue the bear in the Worg Pens",
            where = "Goblin Camp - Shattered Sanctum, Worg Pens",
            todo = {
                "Goblins are tormenting a caged bear - it is Halsin in wild shape.",
                "Side with the bear: tell the goblins to stop (they refuse) and fight alongside him.",
                "He asks you to defeat the goblin leaders; he can join temporarily or wait in the pens.",
            },
            avoid = {
                "Throwing a stone at him or joining the goblins against him.",
                "Leaving for the Rosymorn Monastery trail or Act 2 before rescuing him - he dies in his cell.",
            },
            rewards = "Halsin joins temporarily; starts 'Save the First Druid'.",
            done = {
                Q(SAVE, "FoundHalsin_Unknown_KillLeaders"), Q(SAVE, "FoundHalsin_Known_KillLeaders"),
                Q(SAVE, "FoundHalsin_Unknown_AoD"), Q(SAVE, "FoundHalsin_Known_AoD"),
                Q(SAVE, "FoundHalsin_Unknown_LeadershipDead"), Q(SAVE, "FoundHalsin_Known_LeadershipDead"),
                Q(SAVE, "HalsinReturned_Known"), Q(SAVE, "HalsinLeft_KilledLeaders"),
            },
            fail = { Q(SAVE, "DruidLeaderDied"), Q(SAVE, "Betrayal_DruidDead_Halsin"), Q(SAVE, "Halsin_Lockdown") },
            closes = "act1",
        },
        {
            id = "HAL_A1_GROVE", act = 1, kind = "story", critical = true,
            title = "Save the Grove: defeat the goblin leaders",
            where = "Goblin Camp (Dror Ragzlin, Priestess Gut, Minthara)",
            todo = {
                "Defeat Dror Ragzlin and Priestess Gut, and deal with Minthara (knock her out to keep her recruitable).",
                "Report back to Halsin at the Grove; he confronts Kagha.",
                "Long rest for the celebration. The morning after, Halsin travels with you as a camp follower.",
            },
            avoid = { "Agreeing to raid the Grove." },
            rewards = "The Grove is saved; Halsin follows you toward the Shadow-Cursed Lands.",
            done = { Q(SAVE, "ReportHalsin_LeadersDefeated"), Q(SAVE, "HalsinLeft_KilledLeaders"), Q(SAVE, "Celebration_MetHalsin"), Q(SAVE, "LeftSafe_MetHalsin"), G("NIGHT_GoblinHunt_TieflingCelebration") },
            fail = { Q(SAVE, "Betrayal_DruidDead_Halsin") },
            after = { "HAL_A1_RESCUE" },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "HAL_A2_ART", act = 2, kind = "story", critical = true,
            title = "Wake Art Cullagh",
            where = "Last Light Inn (Art) and the House of Healing in Reithwin (his lute)",
            todo = {
                "Find the comatose Flaming Fist, Art Cullagh, at Last Light Inn.",
                "Get his lute (with his initials) from the House of Healing and play it for him, with Halsin present.",
            },
            avoid = { "Letting Art die before he talks - Speak with Dead still works on his corpse." },
            rewards = "Art reveals where Thaniel is.",
            done = { Q(ART, "BringHalsin"), Q(ART, "HalsinThereWhenWoken"), Q(CURSE, "HalsinRitualReady"), Q(CURSE, "TellHalsinArt_SwD") },
            fail = { Q(ART, "HalsinAlreadyDead") },
            closes = "act3",
        },
        {
            id = "HAL_A2_PORTAL", act = 2, kind = "story", critical = true,
            title = "Defend Halsin's portal",
            where = "Lakeshore near Last Light Inn",
            todo = {
                "Halsin opens a portal into the Shadowfell to rescue Thaniel.",
                "Hold the line against the shadow waves until he comes back. Keep the portal alive.",
            },
            avoid = { "Letting the portal be destroyed - Halsin is lost in the Shadowfell forever." },
            rewards = "Thaniel is rescued (half of him).",
            done = { Q(CURSE, "HalsinRitualComplete"), Q(CURSE, "SeekOliver"), Q(CURSE, "TalkToThaniel") },
            fail = { Q(CURSE, "HalsinDied") },
            after = { "HAL_A2_ART" },
            closes = "act3",
        },
        {
            id = "HAL_A2_OLIVER", act = 2, kind = "story", critical = true,
            title = "Reunite Thaniel with Oliver",
            where = "'A place where flowers still grow in the Shadow-Cursed Lands'",
            todo = { "Find Oliver, Thaniel's other half, and convince him to return." },
            rewards = "Halsin offers to join permanently.",
            done = { Q(CURSE, "TalkToThaniel"), Q(CURSE, "KillKetheric"), Q(CURSE, "CurseLifted") },
            fail = { Q(CURSE, "OliverNotFound") },
            after = { "HAL_A2_PORTAL" },
            closes = "act3",
        },
        {
            id = "HAL_A2_CURSE", act = 2, kind = "story", critical = true,
            title = "Lift the shadow curse",
            where = "Ketheric Thorm (Mind Flayer Colony)",
            todo = { "Defeat Ketheric Thorm - he anchors the curse. Then talk to Halsin and Thaniel." },
            avoid = { "Reaching Act 3 with the curse still in place - Halsin stays behind and his romance never happens." },
            rewards = "The land heals; Halsin becomes a full companion. Kindness to Thaniel afterwards gives big approval.",
            done = { Q(CURSE, "CurseLifted") },
            fail = { Q(CURSE, "OliverNotFound"), Q(CURSE, "HalsinDied"), Q(CURSE, "HalsinDiedOther") },
            after = { "HAL_A2_OLIVER" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "HAL_A3_ROMANCE", act = 3, kind = "romance", romance = true, romanceStart = true,
            title = "Romance: Halsin's offer",
            where = "Camp in Rivington or the Lower City",
            todo = {
                "With high approval, Halsin suggests a night together.",
                "If you have a partner, ask them first (Shadowheart, Astarion and Karlach agree).",
                "Meet him by the secluded tree on the next long rest.",
            },
            avoid = { "Partnered with Lae'zel, Wyll, Gale or Minthara: you must break up with them or turn Halsin down." },
            rewards = "An open relationship with Halsin.",
            done = { P("ORI_State_PartneredWithHalsin"), P("ORI_State_PartneredWithHalsinSecondary"), G("NIGHT_Halsin_Romance_Execution") },
            after = { "HAL_A2_CURSE" },
            closes = "endgame",
        },
    },
}

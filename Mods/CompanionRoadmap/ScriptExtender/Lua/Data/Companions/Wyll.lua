-- =============================================================================
-- Wyll Ravengard - "The Blade of Frontiers"
-- Sources: ORI_COM_Wyll / ORI_COM_Wyll_SUB_Duke journals, NIGHT_Wyll_* camp
-- nights, flags (Patch 8), bg3.wiki.
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local WY = "ORI_COM_Wyll"
local DUKE = "ORI_COM_Wyll_SUB_Duke"

CR.Guides.Register {
    id = "Wyll",
    name = "Wyll",
    uuid = "c774d764-4a17-48dc-b470-32ace9ce447d",
    subtitle = "Warlock of Mizora - The Blade of Frontiers",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Wyll"),
    left = { Q(WY, "CompanionMurdered"), Q(WY, "CompanionLowRelation"), Q(WY, "CompanionHostile"), Q(WY, "MizoraDied") },
    romance = {
        dating = P("ORI_State_DatingWithWyll"),
        partnered = P("ORI_State_PartneredWithWyll"),
        ex = P("ORI_State_WasPartneredWithWyll"),
        closed = { P("ORI_State_ChosePartnerOverWyll") },
    },

    rules = {
        "His romance can ONLY start at the Tiefling celebration in Act 1 (10+ approval).",
        "Siding with the goblins (raiding the Grove) makes Wyll leave for good.",
        "Rescue Mizora in the Mind Flayer Colony - if she dies, Wyll is dragged to Avernus as a lemure.",
        "Keep Duke Ravengard alive in Act 3 - if he dies, Wyll breaks up with you.",
    },
    romanceNotes = {
        "Act 1: at the Tiefling celebration, find him by the water and flirt (dance, guessing game or ask for a kiss). 'There will be another time for us' = Dating.",
        "He turns you down if you already agreed to another companion's night, are double-dating, or have under 10 approval.",
        "Act 2: 20+ approval, dating him, and a visit to Last Light Inn or Moonrise -> the dance at camp -> Partnered.",
        "Act 3: after his father's fate is settled (alive), he proposes on the banks of the Chionthar.",
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "WYLL_A1_RECRUIT", act = 1, kind = "recruit", critical = true,
            title = "Recruit Wyll",
            where = "Emerald Grove gate fight, then The Hollow (training tiefling kids)",
            todo = { "Help defend the Grove gate, then find him training the children and join forces." },
            rewards = "Wyll (Fiend warlock) joins.",
            done = { Q(WY, "RecruitedWyll"), Q(WY, "RecrtuitedMetKarlach"), Q(WY, "RecruitedAmbush"), Q(WY, "RecruitedAmbushKarlachKilled"), G("GLO_Origin_PartOfTheTeam_Wyll") },
            fail = { Q(WY, "CompanionMurdered") },
            closes = "act1",
        },
        {
            id = "WYLL_A1_KARLACH", act = 1, kind = "choice", critical = true,
            title = "Karlach: talk him down",
            where = "Risen Road (or your camp if Karlach was recruited first)",
            todo = { "Hear Karlach's side and convince Wyll she is no devil. Mizora will punish him for it later (horns) - that is expected." },
            avoid = { "Killing Karlach - you lose her for good (Mizora rewards Wyll instead)." },
            done = { Q(WY, "KarlachHired"), Q(WY, "PostKarlachSpared"), Q(WY, "MizorasJudgementDevil") },
            skip = { Q(WY, "KarlachKilled"), Q(WY, "PostKarlachDead"), Q(WY, "RecruitedAmbushKarlachKilled") },
            after = { "WYLL_A1_RECRUIT" },
            closes = "act1",
        },
        {
            id = "WYLL_A1_DUKE", act = 1, kind = "story", optional = true,
            title = "Waukeen's Rest: the Grand Duke's trail",
            where = "Waukeen's Rest (burning inn), Risen Road area",
            todo = { "Put out the fire and save Counsellor Florrick; learn that drow took Duke Ravengard - Wyll's father." },
            done = { Q(DUKE, "CouncillorTalked"), Q(DUKE, "CouncillorTalkedKnowsMT"), Q(DUKE, "RavengardFather") },
            fail = { Q(DUKE, "CouncillorDead"), Q(DUKE, "CouncillorDeadKnown") },
            closes = "act1",
        },
        {
            id = "WYLL_A1_PARTY", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 10,
            title = "Romance: the Tiefling celebration (only chance)",
            where = "Camp celebration after saving the Grove - Wyll is by the water",
            todo = {
                "Cheer him up, then dance, play his guessing game or simply ask for a kiss.",
                "When he says 'There will be another time for us', you are dating.",
            },
            avoid = {
                "Agreeing to spend the night with another companion first, or already dating two.",
                "Skipping him at the party - his romance cannot start anywhere else.",
            },
            rewards = "Relationship: Dating.",
            done = { P("ORI_State_DatingWithWyll"), P("ORI_State_PartneredWithWyll"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverWyll"), C.All { G("NIGHT_GoblinHunt_TieflingCelebration"), C.Not(P("ORI_State_DatingWithWyll")) } },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "WYLL_A2_DANCE", act = 2, kind = "romance", romance = true, critical = true, approval = 20,
            title = "Romance: the dance",
            where = "Camp, after visiting Last Light Inn or Moonrise Towers",
            todo = {
                "Long rest while dating him with 20+ approval - he is practising a dance.",
                "Dance with him (skill checks are just flavour) and kiss him.",
            },
            avoid = { "Partnering with someone else first." },
            rewards = "Relationship: Partnered.",
            done = { P("ORI_State_PartneredWithWyll"), C.Rel("partnered"), G("NIGHT_Wyll_HavenRomance_Dating"), G("NIGHT_Wyll_HavenRomance") },
            fail = { P("ORI_State_ChosePartnerOverWyll"), P("ORI_State_WasPartneredWithWyll") },
            after = { "WYLL_A1_PARTY" },
            closes = "act3",
        },
        {
            id = "WYLL_A2_MIZORA", act = 2, kind = "story", critical = true,
            title = "Rescue Mizora in the Mind Flayer Colony",
            where = "Mind Flayer Colony below Moonrise Towers - a pod",
            todo = { "Mizora tells Wyll 'Zariel's asset' is held in the Colony. Find the pod and free her." },
            avoid = { "Letting Mizora die - Wyll is punished and dragged into Avernus as a lemure." },
            rewards = "Wyll keeps his life; Mizora owes you (and offers a reward).",
            done = { Q(WY, "MizorasRescueHappened"), Q(WY, "MizorasRescueHappenedPact"), Q(WY, "MizorasRescueReward") },
            fail = { Q(WY, "MizoraDied") },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "WYLL_A3_PACT", act = 3, kind = "choice", critical = true,
            title = "Mizora's offer",
            where = "Wyrm's Rock Fortress, then camp",
            todo = {
                "After Gortash's coronation, Mizora offers Wyll a deal concerning his father.",
                "Breaking the pact frees Wyll (keeps his soul); keeping it makes Mizora help with his father.",
            },
            done = { Q(WY, "EternalPactRavengardHint"), Q(WY, "BrokenPactRavengardSearch"), Q(WY, "EternalPactRavengardResurrected"), Q(WY, "BrokenPactRavengardDead"), Q(DUKE, "PactBroken"), Q(DUKE, "PactedHint") },
            closes = "endgame",
        },
        {
            id = "WYLL_A3_RAVENGARD", act = 3, kind = "story", critical = true, romance = true,
            title = "Rescue Duke Ravengard from the Iron Throne",
            where = "The Iron Throne (submersible from the Lower City docks)",
            todo = {
                "Take the submersible to the Iron Throne and get the Duke (and the other prisoners) out before time runs out - the turn counter is short.",
                "Talk to him at camp afterwards.",
            },
            avoid = { "Letting the Duke die (here or at the coronation) - Wyll breaks up with you." },
            rewards = "Duke Ravengard lives; unlocks the Wyrmway and Wyll's proposal.",
            done = { Q(DUKE, "RescuedIRN"), Q(DUKE, "RescuedTalked"), Q(DUKE, "PactedEscort"), Q(DUKE, "Resurrected"), Q(DUKE, "PactedTalked"), Q(WY, "RavengardRescuedIRN") },
            fail = { Q(DUKE, "DiedIRN"), Q(DUKE, "Died"), Q(DUKE, "BrokenDied") },
            closes = "endgame",
        },
        {
            id = "WYLL_A3_ANSUR", act = 3, kind = "story",
            title = "The Wyrmway: Ansur",
            where = "Below Wyrm's Rock",
            todo = { "Follow 'The Legend of Ansur' into the Wyrmway and defeat the dragon." },
            rewards = "Balduran's Giantslayer and the story of Ansur.",
            done = { Q(WY, "WyrmwaySolved"), Q(WY, "WyrmwayReportRavengard") },
            closes = "endgame",
        },
        {
            id = "WYLL_A3_PROPOSAL", act = 3, kind = "romance", romance = true,
            title = "Romance: the proposal",
            where = "Camp ([!] after a long rest), then the banks of the Chionthar",
            todo = { "With the Duke alive, talk to Wyll after a long rest. He proposes with an acorn from the Wilden Oak." },
            rewards = "Engagement and his final romance scene.",
            done = { G("NIGHT_Wyll_Act3Romance") },
            after = { "WYLL_A2_DANCE", "WYLL_A3_RAVENGARD" },
            closes = "endgame",
        },
    },
}

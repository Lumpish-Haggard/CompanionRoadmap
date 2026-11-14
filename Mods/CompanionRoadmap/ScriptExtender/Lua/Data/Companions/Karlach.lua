-- =============================================================================
-- Karlach - "Our Fiery Friend" / "The Hellion's Heart"
-- Sources: ORI_COM_Karlach journal, NIGHT_Karlach_* camp nights, flags (Patch 8),
-- bg3.wiki (romance thresholds, Infernal Iron locations).
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local KAR = "ORI_COM_Karlach"
local HEART = "ORI_COM_Karlach_SUB_ForgingOfTheHeart"

local FIRST_UPGRADE = C.Any {
    Q(HEART, "WaitForNextAct"), Q(HEART, "WaitForNextDay_Act2"), Q(HEART, "WaitForNextDay_Act3"),
    Q(HEART, "TalkToDammon_Act2"), Q(HEART, "TalkToDammon_Act3"),
    Q(HEART, "KarlachFullyUpgraded_Act2"), Q(HEART, "KarlachFullyUpgraded_Act3"),
}
local SECOND_UPGRADE = C.Any { Q(HEART, "KarlachFullyUpgraded_Act2"), Q(HEART, "KarlachFullyUpgraded_Act3") }

CR.Guides.Register {
    id = "Karlach",
    name = "Karlach",
    uuid = "2c76687d-93a2-477b-8b18-8a14b549304c",
    subtitle = "Tiefling barbarian with an infernal engine - Our Fiery Friend",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Karlach"),
    left = {
        Q(KAR, "CompanionLowRelation"), Q(KAR, "CompanionHostile"), Q(KAR, "CompanionMurdered"),
        Q(KAR, "KarlachPermanentlyDies"), Q(KAR, "KarlachRescued_NotRecruited"), Q(KAR, "KarlachNotRescued"),
    },
    romance = {
        dating = P("ORI_State_DatingKarlach"),
        partnered = P("ORI_State_PartneredWithKarlach"),
        ex = P("ORI_State_WasPartneredWithKarlach"),
        closed = { P("ORI_State_ChosePartnerOverKarlach"), C.F("GLO_Karlach_PlayerDumpedKarlach", "any") },
    },

    rules = {
        { act = 1, "Meet her BEFORE raiding the Grove, starting a fight inside the Grove, or letting the Rite of Thorns finish - otherwise she refuses to join." },
        { act = 1, "Two pieces of Infernal Iron + Dammon = a fixed heart (she can touch people again). Dammon must survive." },
        { act = 2, "Her Act 2 romance night must happen before you leave Act 2, or she ends the relationship in Act 3." },
        { act = 1, "If Wyll meets her first, talk him down - do not let him kill her." },
    },
    romanceNotes = {
        "Act 1: at 30+ approval (and not dating two others) she visits you at night to confess.",
        { act = 1, "Otherwise accept her at the camp celebration (20+ approval, at most one other active romance)." },
        "Act 2: once Dammon finishes the second upgrade, long rest for her big romance night -> Partnered.",
        { act = 2, "Partnering with someone else before that night ends her romance." },
        "Act 3: say yes to her 'first date' at The Singing Lute in the Lower City.",
    },

    counters = {
        {
            id = "engine", label = "Engine upgrades", need = 2,
            help = "Each upgrade needs one piece of Infernal Iron and Dammon.",
            items = {
                { label = "First upgrade (she can almost touch)", cond = FIRST_UPGRADE },
                { label = "Second upgrade (safe to touch)", cond = SECOND_UPGRADE },
            },
        },
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "KAR_A1_RECRUIT", act = 1, kind = "recruit", critical = true,
            title = "Meet Karlach on the Risen Road",
            where = "Risen Road, near the Toll House (X:111 Y:503)",
            todo = {
                "Hear her out: the 'Paladins of Tyr' hunting her are really Zariel's hunters.",
                "Agree to deal with them and recruit her.",
            },
            avoid = {
                "Raiding the Grove, starting a fight in the Grove or letting the Rite of Thorns finish before meeting her - she will refuse to join.",
                "Siding with Wyll if he wants to kill her.",
            },
            rewards = "Karlach (Berserker barbarian) joins.",
            done = { Q(KAR, "Recruited_PaladinsNotDefeated"), Q(KAR, "Recruited_PaladinsDefeated"), Q(KAR, "ExploreSwordCoast"), G("GLO_Origin_PartOfTheTeam_Karlach") },
            fail = { Q(KAR, "CompanionMurdered"), Q(KAR, "KarlachPermanentlyDies"), Q("ORI_COM_Wyll", "KarlachKilled") },
            closes = "act1",
        },
        {
            id = "KAR_A1_PALADINS", act = 1, kind = "story",
            title = "Deal with the 'Paladins of Tyr'",
            where = "Risen Road Toll House",
            todo = { "Go to Anders and his paladins with Karlach in the party and take them down." },
            rewards = "Approval, and Anders' Sword of Justice.",
            done = { Q(KAR, "Recruited_PaladinsDefeated"), Q(KAR, "ExploreSwordCoast") },
            after = { "KAR_A1_RECRUIT" },
            closes = "act1",
        },
        {
            id = "KAR_A1_DAMMON", act = 1, kind = "story", critical = true,
            title = "First heart upgrade with Dammon",
            where = "Emerald Grove - Dammon, the tiefling smith",
            todo = {
                "Bring Karlach to Dammon. He needs Infernal Iron.",
                "Act 1 Infernal Iron: forge basement chest in the Blighted Village; treasure crates in the Shattered Sanctum; trapped chest in the Zhentarim Basement; sold or given by a duergar in Grymforge.",
                "Missed it? Dammon moves on to Last Light Inn (Act 2) and later the Lower City - you can still do it there.",
            },
            avoid = { "Letting the Grove fall or Dammon die - he is the only one who can fix her heart." },
            rewards = "First engine upgrade (new passive). Unlocks 'Of course I do' (+approval) when she asks if you want to touch her.",
            done = { FIRST_UPGRADE },
            fail = { Q(HEART, "DammonPermadefeated"), Q(HEART, "DammonNeverMet") },
            after = { "KAR_A1_RECRUIT" },
        },
        {
            id = "KAR_A1_ROMANCE", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 20,
            title = "Romance: tell her how you feel",
            where = "Camp (night visit) or the camp celebration",
            todo = {
                "At 30+ approval she visits you at night and confesses - return her feelings.",
                "Or at the celebration (20+ approval, at most one other active romance) tell her you like her and agree to meet later.",
                "She cannot be touched yet. Be sweet about it - the kiss burns.",
            },
            avoid = { "Already dating two companions, or having had a romance scene with someone else before the party - she turns you down." },
            rewards = "Relationship: Dating.",
            done = { P("ORI_State_DatingKarlach"), P("ORI_State_PartneredWithKarlach"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverKarlach") },
            closes = "act1",
        },
        {
            id = "KAR_A1_COOL", act = 1, kind = "romance", romance = true, optional = true,
            title = "Romance: find a way to cool her down",
            where = "Camp",
            todo = { "When she asks if you found a way to touch her, cool her with frost or water magic (Ray of Frost, Create Water...) for a brief touch." },
            done = { G("NIGHT_Karlach_CoolingDownForYou") },
            after = { "KAR_A1_ROMANCE" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "KAR_A2_DAMMON", act = 2, kind = "story",
            title = "Find Dammon at Last Light Inn",
            where = "Last Light Inn, Shadow-Cursed Lands",
            todo = { "Dammon set up his forge at Last Light Inn. Bring Karlach to him." },
            avoid = { "Letting Isobel be abducted - Last Light's protection falls with her." },
            done = { Q(HEART, "DammonFound_Act2"), SECOND_UPGRADE },
            fail = { Q(HEART, "DammonPermadefeated") },
            closes = "act3",
        },
        {
            id = "KAR_A2_UPGRADE", act = 2, kind = "story", critical = true, romance = true,
            title = "Second heart upgrade: she can touch again",
            where = "Last Light Inn - Dammon's forge",
            todo = {
                "Bring another piece of Infernal Iron (and the first one if you skipped it in Act 1). Sleep once between upgrades if he asks for time.",
                "Act 2 Infernal Iron: Mason's Guild in Reithwin; an opulent chest in the Gauntlet of Shar vault; carried by a Gauntlet of Shar enemy.",
            },
            avoid = { "Leaving Act 2 without it - you must then find Dammon again in Baldur's Gate." },
            rewards = "Karlach can touch people again. Unlocks her Act 2 romance night.",
            done = { SECOND_UPGRADE },
            fail = { Q(HEART, "DammonPermadefeated"), Q(HEART, "ForgingOfTheHeart_ReachEND") },
        },
        {
            id = "KAR_A2_ROMANCE", act = 2, kind = "romance", romance = true, critical = true,
            title = "Romance: the night her heart is fixed",
            where = "Camp, first long rest after the second upgrade",
            todo = {
                "Long rest right after the upgrade (with no other big camp event queued).",
                "Choose intimacy or simply holding each other - both partner you with her.",
            },
            avoid = {
                "Partnering with another companion first - her romance ends.",
                "Leaving Act 2 before this night - she ends the relationship when you reach Act 3.",
            },
            rewards = "Relationship: Partnered.",
            done = { G("NIGHT_Karlach_TheForgingOfTheHeart"), P("ORI_State_PartneredWithKarlach"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverKarlach") },
            after = { "KAR_A1_ROMANCE", "KAR_A2_UPGRADE" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "KAR_A3_GORTASH", act = 3, kind = "story", critical = true,
            title = "Gortash: Karlach's revenge",
            where = "Wyrm's Rock Fortress, then the Upper City / Gortash's palace",
            todo = {
                "Learn that Gortash, her old boss who sold her to Zariel, is being crowned Archduke.",
                "If she storms the ceremony and gets locked up, break her out of the Wyrm's Rock prison quickly.",
                "Bring her when you kill Gortash and let her see the body.",
            },
            avoid = { "Leaving her in prison - she is lost." },
            rewards = "Her revenge, big approval and a key companion beat.",
            done = { Q(KAR, "KillGortash_AtWYR"), Q(KAR, "GoToGortashCorpse"), Q(KAR, "SaveTheCity") },
            fail = { Q(KAR, "KarlachNotRescued"), Q(KAR, "KarlachRescued_NotRecruited") },
            closes = "endgame",
        },
        {
            id = "KAR_A3_DATE", act = 3, kind = "romance", romance = true,
            title = "Romance: first date at The Singing Lute",
            where = "Lower City - The Singing Lute",
            todo = {
                "After entering the Lower City she asks you on a 'first date' - accept.",
                "Over dinner she says she loves you; follow her upstairs (intimacy is optional).",
            },
            rewards = "Her Act 3 romance scene.",
            done = { G("NIGHT_Karlach_ANightAtTheTown") },
            after = { "KAR_A2_ROMANCE" },
            closes = "endgame",
        },
        {
            id = "KAR_A3_FATE", act = 3, kind = "choice", romance = true, optional = true,
            title = "Her engine and the ending",
            where = "After the final battle",
            todo = {
                "With both upgrades and Gortash dead, she can face her fate with you: going back to Avernus (with you and/or Wyll) keeps her alive.",
                "Act 3 Infernal Iron (if still needed): Flymm Cargo basement, carried by an enemy in the Lower City, a table at the Iron Throne submersible dock, or bought at the docks.",
            },
            done = { Q(KAR, "ReachEND_FullyUpgraded_GortashDefeated") },
        },
    },
}

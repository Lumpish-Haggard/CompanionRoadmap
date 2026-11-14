-- =============================================================================
-- Lae'zel - "The Githyanki Warrior"
-- Sources: CHA_LaezelRecruit / ORI_COM_Laezel / GLO_FreeOrpheus journals,
-- NIGHT_Laezel_* camp nights, flags (Patch 8), bg3.wiki.
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local LZ = "ORI_COM_Laezel"
local CAGE = "CHA_LaezelRecruit"
local ORPH = "GLO_FreeOrpheus"

CR.Guides.Register {
    id = "Laezel",
    name = "Lae'zel",
    uuid = "58a69333-40bf-8358-1d17-fff240d7fb12",
    subtitle = "Githyanki fighter - The Githyanki Warrior",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Laezel"),
    -- bg3.wiki (Lae'zel): her body can be revived and she can still be invited to join
    revivable = "If she died on the Nautiloid or fighting beside you at the mountain pass, a Scroll of Revivify brings her back and she can still join you.",
    left = {
        Q(LZ, "CompanionLowRelation"), Q(LZ, "LaezelDied_Generic"), Q(LZ, "LaezelTurnedHostile_Generic"),
        Q(LZ, "LaezelDied_KilledByShadowheart"), Q(LZ, "LaezelDied_KilledAtCampNight"), Q(LZ, "TurnedHostileAtChokepoint"),
        Q(LZ, "LaezelDied_KilledByVossInPlains"), Q(LZ, "LaezelDied_FoundShadowcursedInSCL"), Q(LZ, "TurnedHostileDuringInquisitor"),
        Q(LZ, "LeftInSCL"), Q(CAGE, "KilledLaezel"), Q(CAGE, "LaezelPermaDefeatead"),
    },
    romance = {
        dating = P("ORI_State_DatingLaezel"),
        partnered = P("ORI_State_PartneredWithLaezel"),
        ex = P("ORI_State_WasPartneredWithLaezel"),
        closed = { P("ORI_State_ChosePartnerOverLaezel") },
    },

    rules = {
        { act = 1, "Free her from the tiefling cage near the crash site early - fighting her or leaving her there loses her." },
        { act = 1, "When she and Shadowheart fight at camp, calm them down; a death here is permanent." },
        { act = 1, "Pull her out of the zaith'isk in the Creche if it starts killing her." },
        "She hates shared love: committing to someone else ends her romance.",
    },
    romanceNotes = {
        "Act 1: at 20+ approval she propositions you after a big fight (hag, ogres, owlbear, spider matriarch) - or ask 'Is it just me, or have you been looking at me differently lately?'.",
        { act = 1, "The camp celebration also works (20+ approval, not dating two others)." },
        "Act 2: dating + one night passed + visited Last Light Inn or Moonrise -> night duel -> Partnered.",
        "Act 3: one night after Vlaakith's visit, long rest in the Lower City for the sunrise scene.",
        { act = 3, "If she stays loyal to Vlaakith, she ends the relationship in Act 3." },
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "LAE_A1_CAGE", act = 1, kind = "recruit", critical = true,
            title = "Free Lae'zel from the tiefling cage",
            where = "Roadside Cliffs, near the crash site (X:242 Y:370)",
            todo = {
                "Two tieflings (Damays and Nymessa) have her caged. Persuade or intimidate them into leaving - or fight them.",
                "Get her down and invite her to the party.",
            },
            avoid = { "Siding with the tieflings against her, or walking away - she is lost." },
            rewards = "Lae'zel (Battle Master fighter) joins and promises to lead you to a githyanki creche.",
            done = {
                Q(CAGE, "Recruited"), Q(CAGE, "InvitedCamp"), Q(LZ, "RecruitedLaezel_Cage"), Q(LZ, "RecruitedLaezel_Beach"),
                Q(LZ, "RecruitedLaezel_Plains"), Q(LZ, "RecruitedLaezel_PlainsAfterMap"), Q(LZ, "RecruitedLaezel_Creche"),
                G("GLO_Origin_PartOfTheTeam_Laezel"),
            },
            fail = { Q(CAGE, "KilledLaezel"), Q(CAGE, "LaezelPermaDefeatead"), Q(CAGE, "SidedTieflings"), Q(CAGE, "RefusedInvolvement"), Q(CAGE, "LeftArea") },
            closes = "act1",
        },
        {
            id = "LAE_A1_ROMANCE", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 20,
            title = "Romance: her proposition",
            where = "Camp",
            todo = {
                "Get her to 20+ approval and win a big fight with her in the party (hag, ogres, owlbear or spider matriarch). Talk to her when she has a [!].",
                "Or use the line 'Is it just me, or have you been looking at me differently lately?'.",
                "Accept her offer; she leads at the camp altar that night.",
            },
            avoid = { "Mocking her offer. Already dating two others or being partnered - she refuses." },
            rewards = "Relationship: Dating.",
            done = { P("ORI_State_DatingLaezel"), P("ORI_State_PartneredWithLaezel"), C.Rel("partnered"), C.F("ORI_Laezel_State_Romance1HadSex", "any") },
            fail = { P("ORI_State_ChosePartnerOverLaezel") },
            closes = "act3",
        },
        {
            id = "LAE_A1_SHADOWHEART", act = 1, kind = "choice", critical = true, optional = true,
            title = "The night she confronts Shadowheart",
            where = "Camp, after meeting the githyanki patrol near the Mountain Pass",
            todo = { "Calm both of them down (or side with Shadowheart) when Lae'zel demands the artefact." },
            avoid = { "Letting it come to blows - one of them can die." },
            done = { Q("ORI_COM_ShadowHeart", "CampFight_Peace") },
            fail = { Q("ORI_COM_ShadowHeart", "CampFight_LaezelDied") },
        },
        {
            id = "LAE_A1_FIND", act = 1, kind = "story",
            title = "Find the githyanki creche",
            where = "Emerald Grove (Zorru) - Risen Road patrol - Mountain Pass",
            todo = {
                "Ask the tiefling Zorru in the Grove where he saw githyanki, or follow the red dragon.",
                "Meet Kith'rak Voss's patrol: talking peacefully reveals the creche in the mountains.",
            },
            done = { Q(LZ, "ResolvedPeaceCreche"), Q(LZ, "ReadCrecheMap"), Q(LZ, "FoundCrecheLocationWithHints"), Q(LZ, "FoundCrecheLocationNoHints"), Q(LZ, "EnteredCreche") },
            closes = "act1",
        },
        {
            id = "LAE_A1_CRECHE", act = 1, kind = "story", critical = true,
            title = "Creche Y'llek: the zaith'isk and Vlaakith",
            where = "Rosymorn Monastery - Githyanki Creche (Mountain Pass)",
            todo = {
                "Take Lae'zel to the infirmary and Ghustil Stornugoss. Pull her out of the zaith'isk when it turns on her.",
                "Follow up with the Inquisitor; listen to Queen Vlaakith's projection, then enter the artefact.",
                "Talk to Lae'zel afterwards about Vlaakith's betrayal.",
            },
            avoid = { "Skipping the creche entirely - her questline loses its Act 1 turning point." },
            rewards = "Her crisis of faith begins - the turning point of her personal quest.",
            done = { Q(LZ, "VlaakithBetrayal_LaezelPresent"), Q(LZ, "FindCure_AfterBetrayal"), Q(LZ, "CrecheFinished"), Q(LZ, "SpokeToVlaakith_LaezelConvinced") },
            fail = { Q(LZ, "PointOfNoReturnReachedWithoutCreche"), Q(LZ, "LaezelLeftAtCreche") },
            after = { "LAE_A1_FIND" },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "LAE_A2_VOSS", act = 2, kind = "choice", critical = true,
            title = "Kith'rak Voss comes to camp",
            where = "Camp (Act 2)",
            todo = { "Hear Voss out - he reveals what Vlaakith really plans for Lae'zel. Do not kill him if you want the Orpheus path." },
            avoid = { "Killing Voss closes off his help with Prince Orpheus in Act 3." },
            done = { Q(LZ, "AgreedVoss") },
            skip = { Q(LZ, "KilledVoss") },
            closes = "act3",
        },
        {
            id = "LAE_A2_DUEL", act = 2, kind = "romance", romance = true, critical = true,
            title = "Romance: the night duel",
            where = "Camp, long rest after visiting Last Light Inn or Moonrise Towers",
            todo = {
                "Requires: dating her, one night since your first scene, and a visit to Last Light Inn or Moonrise.",
                "She wakes you and demands a duel. Win or lose, confirm your feelings afterwards.",
            },
            avoid = { "Rejecting her after the duel. Partnering with another companion first." },
            rewards = "Relationship: Partnered ('Source of my bruises'). Ends other affairs.",
            done = { P("ORI_State_PartneredWithLaezel"), C.Rel("partnered"), G("NIGHT_Laezel_Romance2") },
            fail = { P("ORI_State_ChosePartnerOverLaezel") },
            after = { "LAE_A1_ROMANCE" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "LAE_A3_VLAAKITH", act = 3, kind = "choice", critical = true,
            title = "Vlaakith's visit: Orpheus or the Queen",
            where = "Camp (Act 3)",
            todo = {
                "Vlaakith appears and orders Lae'zel to kill Orpheus.",
                "Encourage her to question Vlaakith if you want her free (Orpheus path).",
            },
            avoid = { "If she stays loyal to Vlaakith she ends any romance with you." },
            done = {
                Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossNotPresent_OrpheusPath"), Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossNotPresent_VlaakithPath"),
                Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossContact_OrpheusPath"), Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossContact_VlaakithPath"),
                Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossInSC_OrpheusPath"), Q(LZ, "VlaakithVisited_TalkedToLaezelAboutOrpheus_VossInSC_VlaakithPath"),
                Q(LZ, "VlaakithVisited_SpeakToRaphael_OrpheusPath"), Q(LZ, "VlaakithVisited_SpeakToRaphael_VlaakithPath"),
                G("NIGHT_Laezel_VlaakithVisit"),
            },
            closes = "endgame",
        },
        {
            id = "LAE_A3_SUNRISE", act = 3, kind = "romance", romance = true,
            title = "Romance: sunrise on the rooftops",
            where = "Long rest in the Lower City, one night after Vlaakith's visit",
            todo = { "She wakes you before dawn to watch the sunrise. On the Orpheus path she asks you to stay with her 'when this is all over'." },
            done = { G("NIGHT_Laezel_Romance3") },
            after = { "LAE_A2_DUEL", "LAE_A3_VLAAKITH" },
            closes = "endgame",
        },
        {
            id = "LAE_A3_HAMMER", act = 3, kind = "story", critical = true,
            title = "Get the Orphic Hammer",
            where = "House of Hope (Raphael's realm) via Helsik at the Devil's Fee",
            todo = {
                "Meet Voss at Sharess' Caress, then open a portal to the House of Hope (Helsik, Devil's Fee).",
                "Steal the Orphic Hammer (or defeat Raphael). Signing Raphael's contract also gives it to you - at a price.",
            },
            avoid = { "Raphael's contract costs you the Crown of Karsus at the end - stealing the hammer avoids that deal." },
            rewards = "The only way to free Prince Orpheus.",
            done = { Q(ORPH, "StoleOrphicHammer"), Q(ORPH, "StoleOrphicHammer_RaphaelDefeated"), Q(ORPH, "DefeatedRaphael"), Q(ORPH, "MadeDeal"), Q(ORPH, "RaphaelReturnedHammer") },
            closes = "endgame",
        },
        {
            id = "LAE_A3_ORPHEUS", act = 3, kind = "choice", critical = true,
            title = "Free Prince Orpheus",
            where = "The Astral Prism (after the Netherstones)",
            todo = { "Use the Orphic Hammer to break Orpheus's chains." },
            avoid = { "Letting the Emperor absorb Orpheus angers Lae'zel." },
            rewards = "Lae'zel can lead the githyanki rebellion beside Orpheus.",
            done = { Q(ORPH, "SmashedChains") },
            skip = { Q(ORPH, "AssimilatedOrpheus") },
            after = { "LAE_A3_HAMMER" },
        },
    },
}

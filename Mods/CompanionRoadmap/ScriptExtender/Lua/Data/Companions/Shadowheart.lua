-- =============================================================================
-- Shadowheart - "Daughter of Darkness"
-- Sources: game journal (quest_prototypes), Osiris story goals and flags
-- (Patch 8), cross-checked with bg3.wiki. Only verified flags/steps are used.
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local SH = "ORI_COM_ShadowHeart"
local SHAR = "ORI_COM_ShadowHeart_SUB_Justiciar"
local FRIEND = "ORI_COM_ShadowHeart_SUB_OldFriend"

CR.Guides.Register {
    id = "Shadowheart",
    name = "Shadowheart",
    uuid = "3ed74f06-3c60-42dc-83f6-f034cb47c679",
    subtitle = "Half-elf cleric of Shar - Daughter of Darkness",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Shadowheart"),
    left = {
        Q(SH, "CompanionLowRelation"), Q(SH, "CompanionHostile"), Q(SH, "CompanionMurdered"),
        Q(SHAR, "ShadowheartLeftParty_SUB_Justiciar"), Q(SH, "SharTemple_NoDecisionAllowed"),
        Q(SHAR, "Nightsong_Surrendered"),
    },
    romance = {
        dating = P("ORI_State_DatingShadowheart"),
        partnered = P("ORI_State_PartneredWithShadowheart"),
        ex = P("ORI_State_WasPartneredWithShadowheart"),
        closed = { P("ORI_State_ChosePartnerOverShadowheart") },
    },

    rules = {
        "Never side with Lae'zel when the two of them fight at camp - Shadowheart leaves for good.",
        "Bring her (and the Spear of Night) into the Shadowfell. Entering without her, or without the spear, makes her leave.",
        "Never hand Nightsong to Balthazar, and never surrender Shadowheart to Viconia in Act 3.",
        "Let her make the Nightsong decision herself - deciding for her ends the relationship.",
    },
    romanceNotes = {
        "Act 1: accept her bottle of wine at the camp celebration (20+ approval, at most one other active romance).",
        "No party? At 40+ approval ask whether you 'missed a chance to truly connect' - works until you enter the Shadowfell.",
        "Act 2: after the Shadowfell she asks to make it serious -> Partnered.",
        "Act 3 (Selune path): the night swim needs 40+ approval and knowing she cannot swim.",
        "Shar path: she stays with you, but always ends the relationship after the final battle.",
    },

    -- Shadowheart's hidden 'Nightsong points' (4 of 6 make sparing Nightsong much easier).
    counters = {
        {
            id = "nightsong", label = "Nightsong points", need = 4,
            help = "Hidden Selune-path score. With 4 or more she is far easier to talk into sparing Nightsong.",
            items = {
                { label = "Encouraged her to stop living with the wound", cond = G("ORI_Shadowheart_State_NightsongPoint_CureIncurableWound") },
                { label = "Pointed out the Selunite meaning of her wolf memory", cond = G("ORI_Shadowheart_State_NightsongPoint_MadeSeluniteConnection") },
                { label = "Got her to eat the Noblestalk", cond = G("ORI_Shadowheart_State_NightsongPoint_AteNoblestalk") },
                { label = "Gave her a Night Orchid", cond = G("ORI_Shadowheart_State_NightsongPoint_GaveNightOrchid") },
                { label = "Let her attempt the Gauntlet trials", cond = G("ORI_Shadowheart_State_NightsongPoint_AgreedToTrials") },
                { label = "Told her she owes nothing to an abusive mother", cond = G("ORI_Shadowheart_State_NightsongPoint_AbuseEmancipation") },
            },
            reached = G("ORI_Shadowheart_State_NightsongPoint_HasEnoughPoints"),
        },
    },

    steps = {
        -- ------------------------------------------------------------------ Prologue
        {
            id = "SH_P_POD", act = 0, kind = "recruit", optional = true,
            title = "Free the captive from the mind flayer pod",
            where = "Nautiloid (prologue)",
            todo = {
                "Interact with the console beside her pod. An Eldritch Rune found aboard the ship opens it; otherwise you can force it.",
                "Let her join you to escape the ship.",
            },
            avoid = { "Skipping her is not fatal - she still turns up on the Ravaged Beach - but you lose an extra fighter for the escape." },
            rewards = "A temporary healer for the nautiloid escape.",
            done = { Q("TUT_ShadowheartEscape", "UsedRune"), Q("TUT_ShadowheartEscape", "UsedForce"), Q("TUT_ShadowheartEscape", "FreedAndRecruited") },
            skip = { Q("TUT_ShadowheartEscape", "LeftBehind") },
        },

        -- ------------------------------------------------------------------ Act 1
        {
            id = "SH_A1_RECRUIT", act = 1, kind = "recruit", critical = true,
            title = "Recruit Shadowheart",
            where = "Ravaged Beach, next to the nautiloid wreck",
            todo = {
                "If you freed her on the ship she lies unconscious on the beach - wake her up.",
                "Otherwise she is trying to open the Dank Crypt door nearby. Either way, invite her to the party.",
                "Do not pry into the artefact or her faith yet - she reveals both as trust grows.",
            },
            avoid = { "Attacking her or turning her away. If you still have not recruited her, she later appears at the Goblin Camp or your camp." },
            rewards = "Shadowheart (Trickery cleric) joins. She carries the githyanki artefact that shields everyone from the tadpoles.",
            done = {
                Q(SH, "Recruited_Beach"), Q(SH, "Recruited_Den"), Q(SH, "Recruited_Camp"), Q(SH, "Recruited_Githyanki"),
                Q(SH, "Recruited_Laezel"), Q(SH, "Recruited_Box"), Q(SH, "Recruited_Reanimated"),
                G("GLO_Origin_PartOfTheTeam_Shadowheart"),
            },
            fail = { Q(SH, "CompanionMurdered") },
        },
        {
            id = "SH_A1_WOUND", act = 1, kind = "story", romance = true, optional = true,
            title = "Her wound: encourage her to live without the pain",
            where = "Camp, after her hand flares up",
            todo = {
                "When her hand wound flares, ask her about it and promise to help.",
                "In the follow-up talk, encourage her to find a way to stop the pain (Nightsong point).",
            },
            avoid = { "Calling the pain a liability or mocking her faith costs approval." },
            rewards = "Approval and a Nightsong point (Selune path).",
            done = { Q(SH, "IncurableWoundCure"), G("ORI_Shadowheart_State_NightsongPoint_CureIncurableWound") },
            skip = { Q(SH, "IncurableWoundCureRefused") },
            closes = "act1",
        },
        {
            id = "SH_A1_WOLF", act = 1, kind = "romance", romance = true, critical = true,
            title = "The wolf memory - learn that she cannot swim",
            where = "Camp, after she panics near wolves or worgs",
            todo = {
                "After she freezes in front of a wolf, ask her about the fear at camp.",
                "With good approval she shares a childhood memory of being hunted by a wolf - and that she loves Night Orchids and cannot swim.",
                "Then point out that the memory sounds like a Selunite coming-of-age rite (Nightsong point).",
            },
            avoid = { "Skipping this conversation removes the Act 3 swimming scene - it requires knowing she cannot swim." },
            rewards = "Unlocks the Act 3 romance swim and the Night Orchid gift; Nightsong point for the Selunite connection.",
            done = {
                G("ORI_Shadowheart_State_WolfDreamPoint_LearnedPersonalKnowledge"), C.F("ORI_Shadowheart_Knows_PersonalInfo", "any"), Q(SH, "WolfDreamShared"),
                Q(SH, "WolfDreamSharedAbuse"), Q(SH, "WolfPhobiaDiscussedDreamShared"), Q(SH, "ToldSeluniteConnection"),
            },
            closes = "act3",
        },
        {
            id = "SH_A1_NOBLESTALK", act = 1, kind = "story", optional = true,
            title = "Noblestalk: restore a lost memory",
            where = "Underdark - Bibberbang Grotto, north of Dread Hollow (X:-6 Y:-66)",
            todo = {
                "Pick up the Noblestalk mushroom and give it to Shadowheart.",
                "She refuses at first - persuade her to eat it.",
            },
            avoid = { "Giving it to Derryth or another companion instead - there is only one." },
            rewards = "She remembers a childhood friend; starts 'A Familiar Face' in Act 3 and grants a Nightsong point.",
            done = { Q(SH, "NobleStalk"), G("ORI_Shadowheart_State_NightsongPoint_AteNoblestalk") },
            closes = "act1",
        },
        {
            id = "SH_A1_IDOL", act = 1, kind = "approval", optional = true,
            title = "Give her the Idol of Shar",
            where = "Grymforge (Underdark)",
            todo = { "Find the Idol of Shar in Grymforge and gift it to her." },
            rewards = "Approval and special dialogue; hints at the Dark Justiciar lair.",
            done = { Q(SHAR, "JusticiarHint_SharIdol_Update") },
            closes = "act1",
        },
        {
            id = "SH_A1_LAEZEL", act = 1, kind = "choice", critical = true, optional = true,
            title = "The night Lae'zel draws a blade on her",
            where = "Camp, after meeting the githyanki patrol near the Mountain Pass",
            todo = {
                "When you wake to Lae'zel and Shadowheart about to fight over the artefact, calm them both down.",
                "If it comes to it, side with Shadowheart.",
            },
            avoid = { "Siding with Lae'zel - Shadowheart leaves permanently (or one of them dies)." },
            rewards = "Both companions stay.",
            done = { Q(SH, "CampFight_Peace") },
            fail = { Q(SH, "CampFight_ShadowheartDied") },
            skip = { Q(SH, "CampFight_LaezelDied") },
        },
        {
            id = "SH_A1_PARTY", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 20,
            title = "Romance: wine by the waterfall",
            where = "Camp celebration after the Grove is saved (or the Goblin party)",
            todo = {
                "At the party, talk to Shadowheart and accept her offer to share a bottle (needs 20+ approval and no more than one other active romance).",
                "At the waterfall, stay with her through the night. A passive Insight check (DC 5) lets you kiss her.",
                "Next morning tell her you enjoyed it. If the kiss did not happen, say you wish it had.",
                "No party? At 40+ approval ask whether you 'missed a chance to truly connect' - the scene plays on the next long rest.",
            },
            avoid = {
                "Agreeing to spend the party night with a third companion while already dating two.",
                "Saying the night was a mistake or that you got carried away - that ends the romance.",
            },
            rewards = "Relationship: Dating. Unlocks her romance dialogue and greetings.",
            done = { P("ORI_State_DatingShadowheart"), P("ORI_State_PartneredWithShadowheart"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverShadowheart") },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "SH_A2_ORCHID", act = 2, kind = "romance", romance = true,
            title = "Give her a Night Orchid",
            where = "Ruined Battlefield, Shadow-Cursed Lands",
            todo = { "Pick the Night Orchid and give it to her from the inventory or in conversation." },
            rewards = "Approval, a sweet scene and a Nightsong point.",
            done = { Q(SH, "GaveNightOrchid"), C.F("ORI_Shadowheart_State_AvatarGaveNightOrchid", "any"), C.F("ORI_Shadowheart_State_HasReceivedNightOrchid", "any"), G("ORI_Shadowheart_State_NightsongPoint_GaveNightOrchid") },
            closes = "act3",
        },
        {
            id = "SH_A2_TRIALS", act = 2, kind = "story", critical = true,
            title = "Gauntlet of Shar: complete the trials with her",
            where = "Gauntlet of Shar, below the Grand Mausoleum",
            todo = {
                "Bring Shadowheart into the Gauntlet and agree to let her pursue the trials (Nightsong point).",
                "Complete the Soft-Step, Self-Same and Faith-Leap trials.",
            },
            avoid = { "Leaving her at camp: she must be present when the Nightsong decision happens." },
            rewards = "Approval, Shar's gifts along the way, access to the Inner Sanctum.",
            done = { Q(SHAR, "CompletedTrials"), Q(SHAR, "EnteredSanctum_Alt") },
            after = { "SH_A1_RECRUIT" },
            closes = "act3",
        },
        {
            id = "SH_A2_SPEAR", act = 2, kind = "story", critical = true,
            title = "Retrieve the Spear of Night",
            where = "Silent Library, Gauntlet of Shar",
            todo = { "Search the Silent Library for the Spear of Night and let Shadowheart take it." },
            avoid = { "Entering the Shadowfell without the spear - she leaves the party." },
            rewards = "The weapon Shar expects her to use on Nightsong.",
            done = { Q(SHAR, "LootedSpearOfNight_Communion"), Q(SHAR, "LootedSpearOfNight_WaterCommunion") },
            closes = "act3",
        },
        {
            id = "SH_A2_NIGHTSONG", act = 2, kind = "choice", romance = true, critical = true,
            title = "The Nightsong: Selune or Shar",
            where = "The Shadowfell, below the Gauntlet of Shar",
            todo = {
                "Bring Shadowheart (with the spear) to Nightsong and defeat Balthazar.",
                "Selune path: persuade her not to kill Aylin. Earning 4 Nightsong points first makes this much easier.",
                "Shar path: support her and she becomes a Dark Justiciar.",
            },
            avoid = {
                "Deciding Nightsong's fate yourself or ignoring Shadowheart - she leaves.",
                "Handing Nightsong to Balthazar - Shadowheart turns on you.",
                "Shar path: she will break up with you after the final battle, no matter what.",
            },
            rewards = "Selune: Moonlight Glaive and Selune's Spear of Night (after Ketheric falls). Shar: Dark Justiciar Boots, Gauntlets, Half-Plate and Shar's Spear of Evening.",
            done = { Q(SHAR, "Nightsong_Spared"), Q(SHAR, "Nightsong_Killed"), Q(SH, "SparedNightsong"), Q(SH, "KilledNightsong") },
            fail = { Q(SHAR, "Nightsong_Surrendered"), Q(SHAR, "ShadowheartLeftOut"), Q(SH, "SharTemple_NoDecisionAllowed") },
            after = { "SH_A2_SPEAR" },
            closes = "act3",
        },
        {
            id = "SH_A2_PARTNER", act = 2, kind = "romance", romance = true, critical = true,
            title = "Romance: make it serious after the Shadowfell",
            where = "Right after leaving the Shadowfell",
            todo = {
                "While dating her, talk to Shadowheart after the Nightsong decision.",
                "Selune path: she says she wants to be with you 'now and always' - say yes.",
                "Shar path: she says Shar comes first - insist that you still want to be with her.",
            },
            avoid = { "Rejecting her here ends the romance. Partnering with someone else first also ends it." },
            rewards = "Relationship: Partnered.",
            done = { P("ORI_State_PartneredWithShadowheart"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverShadowheart"), P("ORI_State_WasPartneredWithShadowheart") },
            after = { "SH_A1_PARTY", "SH_A2_NIGHTSONG" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "SH_A3_SWIM", act = 3, kind = "romance", romance = true, approval = 40,
            title = "Romance (Selune path): the night swim",
            where = "Act 3 camp (long rest)",
            todo = {
                "Requires: she spared Nightsong, you know she cannot swim (Act 1 wolf talk) and 40+ approval.",
                "Accept her invitation to sneak away to the water.",
            },
            rewards = "One of her best romance scenes; she remembers it in later dialogue.",
            done = { G("NIGHT_Shadowheart_Skinnydipping"), C.F("ORI_Shadowheart_Event_SkinnyDippingRomanceScene", "any") },
            skip = { G("ORI_Shadowheart_State_SharPath") },
            after = { "SH_A1_WOLF" },
            closes = "endgame",
        },
        {
            id = "SH_A3_SHARNIGHT", act = 3, kind = "romance", romance = true, optional = true,
            title = "Romance (Shar path): the Dark Justiciar's night",
            where = "Act 3 camp (long rest)",
            todo = { "Stay partnered with the Dark Justiciar Shadowheart and long rest in Act 3." },
            done = { G("NIGHT_Shadowheart_SharRomance") },
            skip = { G("ORI_Shadowheart_State_EnemyOfSharPath") },
            closes = "endgame",
        },
        {
            id = "SH_A3_LOOKOUT", act = 3, kind = "story",
            title = "Find the Sharran lookout",
            where = "Wyrm's Crossing",
            todo = { "Look for the Sharran lookout Ferg Drogher; he reveals the cloister is in the House of Grief." },
            done = { Q(SH, "EnemyOfShar_LearnedCultLocation"), Q(SH, "SharPath_LearnedCultLocation") },
            closes = "endgame",
        },
        {
            id = "SH_A3_GRIEF", act = 3, kind = "choice", critical = true,
            title = "House of Grief: face Viconia",
            where = "House of Grief, Lower City",
            todo = {
                "Bring Shadowheart into the House of Grief and descend to meet Mother Superior Viconia DeVir.",
                "Refuse Viconia's demand and defeat her.",
            },
            avoid = { "Surrendering Shadowheart to Viconia - she is gone for good." },
            rewards = "Viconia's Walking Fortress (legendary shield) and the way into the Chamber of Loss.",
            done = { Q(SH, "EnemyOfShar_DefeatedViconia"), Q(SH, "SharPath_DefeatedViconia"), Q(SH, "EnemyOfShar_EnteredLossChamber"), Q(SH, "SharPath_EnteredLossChamber") },
            fail = { Q("LOW_InvestigateSharrans_SUB_ViconiaDeal", "SoldShadowheart"), Q(SH, "SurrenderedShadowheart") },
            after = { "SH_A3_LOOKOUT" },
            closes = "endgame",
        },
        {
            id = "SH_A3_PARENTS", act = 3, kind = "choice", romance = true, critical = true,
            title = "Chamber of Loss: her parents",
            where = "Chamber of Loss, beneath the House of Grief",
            todo = {
                "Support her decision about her parents (Arnell and Emmeline).",
                "Selune path: freeing them keeps her bound to the wound; letting them go frees her - both are valid.",
            },
            avoid = { "Interrupting the scene or attacking the parents - she leaves for good." },
            rewards = "Completes Daughter of Darkness; decides her epilogue (farm with her parents, or Mother Superior).",
            done = { Q(SH, "EnemyOfShar_SavedParents"), Q(SH, "EnemyOfShar_KilledParents"), Q(SH, "SharPath_SavedParents"), Q(SH, "SharPath_KilledParents") },
            fail = { Q(SH, "EnemyOfShar_ParentsSceneBroken"), Q(SH, "SharPath_ParentsSceneBroken") },
            after = { "SH_A3_GRIEF" },
            closes = "endgame",
        },
        {
            id = "SH_A3_NOCTURNE", act = 3, kind = "story", optional = true,
            title = "A Familiar Face: Nocturne",
            where = "Sharran cloister, House of Grief",
            todo = { "If she ate the Noblestalk, find her old friend Nocturne (the cloister's quartermaster) before fighting Viconia." },
            done = { Q(FRIEND, "EnemyOfShar_MetNocturne"), Q(FRIEND, "SharPath_MetNocturne") },
            fail = { Q(FRIEND, "KilledNocturne"), Q(FRIEND, "NeverFoundNocturne") },
            after = { "SH_A1_NOBLESTALK" },
            closes = "endgame",
        },
        {
            id = "SH_A3_FUTURE", act = 3, kind = "romance", romance = true, optional = true,
            title = "Romance: the statue and the future she wants",
            where = "Camp, after the House of Grief",
            todo = { "Long rest after her personal quest; join her at the Selune statue and talk about the future." },
            done = { G("NIGHT_Shadowheart_SharedFuture"), C.F("ORI_Shadowheart_State_Act3RomanceEnded", "any") },
            after = { "SH_A3_PARENTS" },
            closes = "endgame",
        },
    },
}

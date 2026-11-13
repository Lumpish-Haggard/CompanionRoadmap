-- =============================================================================
-- Astarion - "The Pale Elf"
-- Sources: ORI_COM_Astarion journal, NIGHT_Astarion_* camp nights, flags
-- (Patch 8), bg3.wiki (romance requirements and Ascension checks).
-- =============================================================================
local C = CR.Cond
local Q, P, G = C.Q, C.P, C.G

local AS = "ORI_COM_Astarion"

CR.Guides.Register {
    id = "Astarion",
    name = "Astarion",
    uuid = "c7c13742-bacd-460a-8f65-f864fe41f255",
    subtitle = "Vampire spawn rogue - The Pale Elf",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Astarion"),
    left = {
        Q(AS, "CompanionMurdered"), Q(AS, "CompanionLowRelation"), Q(AS, "CompanionHostile"),
        Q(AS, "MetGur_AstarionCapture"), Q(AS, "MetGur_AstarionDisappear"),
    },
    romance = {
        dating = P("ORI_State_DatingAstarion"),
        partnered = P("ORI_State_PartneredWithAstarion"),
        ex = P("ORI_State_WasPartneredWithAstarion"),
        closed = { P("ORI_State_ChosePartnerOverAstarion") },
    },

    rules = {
        "Never tell the Gur monster hunter (Gandrel) where your camp is or hand Astarion over - he is captured and gone.",
        "During the bite night, stop him before he drinks you dry (two failed stops = death).",
        "In Act 2, let Astarion make his own choice with Araj Oblodra - pushing him ends the romance.",
        "At Cazador's ritual: refusing or failing to talk him down makes him leave; helping him ascend makes him a Vampire Ascendant.",
    },
    romanceNotes = {
        "Act 1: at 40+ approval (before the Grove is resolved) he offers to spend the night with you.",
        "Or accept him at the camp celebration (at most one other active romance).",
        "Act 2: the Araj Oblodra scene in Moonrise, then his confession on the next long rest -> Partnered if you support him.",
        "No Araj scene? Killing Raphael's old enemy with 70+ approval triggers the same confession.",
        "Act 3: after Cazador, a final scene - at his grave (spawn) or the offer to become his spawn (ascended).",
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "AST_A1_RECRUIT", act = 1, kind = "recruit", critical = true,
            title = "Recruit Astarion",
            where = "Road west of the nautiloid crash, north-west of the broken pier",
            todo = { "He pretends to need help against an Intellect Devourer, then puts a knife to your throat. Talk him down and invite him." },
            rewards = "Astarion (rogue) joins.",
            done = { G("GLO_Origin_PartOfTheTeam_Astarion"), Q(AS, "LearnedVampire_GaveBlood"), Q(AS, "LearnedVampire_NoBlood"), Q(AS, "LearnedVampire_Attacked") },
            fail = { Q(AS, "CompanionMurdered") },
            closes = "act1",
        },
        {
            id = "AST_A1_BITE", act = 1, kind = "romance", romance = true, critical = true,
            title = "The bite night",
            where = "Camp, around your second long rest after recruiting him",
            todo = {
                "When you wake to Astarion bending over you, say you trust him and let him drink - he approves.",
                "Stop him in time with the dialogue checks.",
                "Next morning, talk it through; you can offer to let him feed on you regularly.",
            },
            avoid = { "Letting him keep drinking twice in a row - you die." },
            rewards = "Approval; reveals he is a vampire spawn. You can let him feed on you regularly afterwards (he gets a buff, you get Bloodless).",
            done = { Q(AS, "LearnedVampire_GaveBlood"), Q(AS, "LearnedVampire_NoBlood") },
            skip = { Q(AS, "LearnedVampire_Attacked"), Q(AS, "LearnedVampire_Act2Fallback"), Q(AS, "LearnedVampire_Act3Fallback") },
            after = { "AST_A1_RECRUIT" },
            closes = "act1",
        },
        {
            id = "AST_A1_GUR", act = 1, kind = "choice", critical = true, optional = true,
            title = "The Gur monster hunter",
            where = "Hill above the Riverside Teahouse (Gandrel)",
            todo = {
                "Gandrel is hunting a vampire spawn. Keep your camp location secret.",
                "If you already know what Astarion is, you can let him attack the hunter.",
            },
            avoid = { "Telling Gandrel where you camp or giving Astarion up - he is captured and gone." },
            done = { Q(AS, "MetGur_DidNotToldCampLocation"), Q(AS, "MetGur_AstarionKilledGur"), Q(AS, "MetGur_Combat") },
            fail = { Q(AS, "MetGur_AstarionCapture"), Q(AS, "MetGur_AstarionDisappear") },
            closes = "act1",
        },
        {
            id = "AST_A1_ROMANCE", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 40,
            title = "Romance: his offer",
            where = "Camp",
            todo = {
                "Reach 40+ approval before the Grove is resolved; he proposes a night together - agree, and confirm your interest in the scene.",
                "Or at the camp celebration accept his proposal (at most one other active romance).",
                "If you know he is a vampire, offering your neck earns extra approval.",
            },
            avoid = { "Showing distrust of his nature during the scene - he leaves upset." },
            rewards = "Relationship: Dating. You may notice the Infernal script carved into his back.",
            done = { P("ORI_State_DatingAstarion"), P("ORI_State_PartneredWithAstarion"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverAstarion") },
            closes = "act1",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "AST_A2_SCARS", act = 2, kind = "story",
            title = "Raphael and the scars",
            where = "Last Light Inn or the Thorm Mausoleum entrance; Gauntlet of Shar (Yurgir)",
            todo = {
                "Let Astarion question Raphael about the scars.",
                "Kill Raphael's old enemy, the orthon Yurgir, in the Gauntlet of Shar - Raphael then reveals the Rite of Profane Ascension.",
            },
            avoid = { "Helping Yurgir instead means Raphael reveals nothing (you learn it later anyway)." },
            done = { Q(AS, "ScarsRevealed"), Q(AS, "KilledOrhon"), G("NIGHT_Astarion_RaphaelsRevelation") },
            skip = { Q(AS, "HelpedOrthon"), Q(AS, "RaphaelLeftNoInfo") },
            closes = "act3",
        },
        {
            id = "AST_A2_CONFESSION", act = 2, kind = "romance", romance = true, critical = true,
            title = "Romance: Araj Oblodra and his confession",
            where = "Moonrise Towers - Araj Oblodra's alchemy shop, then camp",
            todo = {
                "Bring Astarion to Araj Oblodra. She shows interest in him - let him decide for himself and back his choice.",
                "On the next long rest he admits he seduced you to survive. Answer supportively - you want him for him.",
            },
            avoid = {
                "Pressuring him into Araj's offer or treating him as a possession - he ends the relationship.",
                "Telling him you only wanted him for sex.",
            },
            rewards = "Relationship: Partnered - the romance becomes genuine.",
            done = { P("ORI_State_PartneredWithAstarion"), C.Rel("partnered"), G("NIGHT_Astarion_BloodMerchantAftermath"), G("NIGHT_Astarion_Act2RomanceFallback") },
            fail = { P("ORI_State_ChosePartnerOverAstarion"), P("ORI_State_WasPartneredWithAstarion") },
            after = { "AST_A1_ROMANCE" },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "AST_A3_SPAWNS", act = 3, kind = "story",
            title = "Find Cazador's other spawn",
            where = "Fraygo's Flophouse, Wyrm's Crossing",
            todo = { "Meet Dalyria and Petras for information on Cazador's ritual." },
            done = { Q(AS, "MetFlophouseSpawns"), Q(AS, "MetFlophouseSpawns_Ritual") },
            closes = "endgame",
        },
        {
            id = "AST_A3_AMBUSH", act = 3, kind = "choice",
            title = "The spawn ambush at camp",
            where = "Camp, a few long rests after reaching the city",
            todo = { "Side with Astarion when his siblings come for him; drive them off." },
            avoid = { "If they kidnap him, rescue him from the kennel under Cazador's palace quickly." },
            done = { Q(AS, "MetAmbushSpawns_Failed"), Q(AS, "EscapedFromKennel") },
            closes = "endgame",
        },
        {
            id = "AST_A3_CAZADOR", act = 3, kind = "choice", romance = true, critical = true,
            title = "Cazador's Palace: ascend or stay a spawn",
            where = "Cazador's Palace (Szarr Palace), Lower City - the dungeon below",
            todo = {
                "Defeat Cazador. At the coffin, Astarion asks for your help to finish the ritual.",
                "To stop him ascending: Persuasion DC 18 - or pass Insight DC 20 first to unlock an easier DC 15 Persuasion.",
                "To let him ascend: help with the ritual (he becomes the Vampire Ascendant).",
            },
            avoid = {
                "Simply refusing him or failing the checks - he leaves the party permanently.",
                "Starting the ritual and interrupting it - he attacks you.",
            },
            rewards = "Ends 'The Pale Elf'. Spawn: Astarion keeps his humanity. Ascended: immense power and a changed personality.",
            done = { Q(AS, "Ascended"), Q(AS, "ReleasedPrisoners"), Q(AS, "KilledPrisoners"), Q(AS, "LeftPrisoners") },
            fail = { Q(AS, "LeftToEND") },
            closes = "endgame",
        },
        {
            id = "AST_A3_FINALE", act = 3, kind = "romance", romance = true,
            title = "Romance: after the Black Mass",
            where = "Camp, first long rest after Cazador",
            todo = {
                "Spawn path: he takes you to his grave and says he wants to stay with you.",
                "Ascended path: he offers to make you his vampire spawn - refusing ends the relationship.",
            },
            done = { G("NIGHT_Astarion_BlackMassAftermath") },
            after = { "AST_A3_CAZADOR" },
            closes = "endgame",
        },
    },
}

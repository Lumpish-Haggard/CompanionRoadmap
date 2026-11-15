-- =============================================================================
-- Gale of Waterdeep - "The Wizard of Waterdeep"
-- Sources: ORI_COM_Gale journal, NIGHT_Gale_* camp nights, flags (Patch 8),
-- bg3.wiki (romance requirements, leaving conditions).
-- =============================================================================
local C = CR.Cond
local Q, P, G, F = C.Q, C.P, C.G, C.F

local GA = "ORI_COM_Gale"

CR.Guides.Register {
    id = "Gale",
    name = "Gale",
    uuid = "ad9af97d-75da-406a-ae13-7071c563f604",
    subtitle = "Wizard with a Netherese orb in his chest - The Wizard of Waterdeep",
    romanceable = true,

    recruited = G("GLO_Origin_PartOfTheTeam_Gale"),
    left = {
        Q(GA, "CompanionLowRelation"), Q(GA, "CompanionHostile"),
        -- added in 1.0.2: dead beyond resurrection, and leaving because Elminster never delivered his message
        Q(GA, "CompanionMurdered"), Q(GA, "ORI_Gale_BombNotDisarmed"), Q(GA, "ORI_Gale_AbandonedBombNotDisarmed"),
    },
    romance = {
        dating = P("ORI_State_DatingGale"),
        partnered = P("ORI_State_PartneredWithGale"),
        ex = P("ORI_State_WasPartneredWithGale"),
        closed = { P("ORI_State_ChosePartnerOverGale") },
    },

    rules = {
        { act = 1, "Pull him out of the rune circle on the first or second try - failing both locks him out." },
        { act = 1, "Give him at least ONE magic item when he first asks - refusing makes him leave. (The 2nd and 3rd are optional.)" },
        { act = 1, "Never tell him to leave: not when he catches you prying into his mind, and not when he tells you about the orb." },
        { act = 1, "If he dies, revive him within 3 long rests or his orb detonates (game over)." },
        { act = 1, "Raiding the Grove: he confronts you at the goblin party and leaves unless you talk him round." },
        { act = 2, "Talk to Elminster - ignoring or attacking him makes Gale leave once Ketheric is dead." },
    },
    romanceNotes = {
        "Act 1: at 36+ approval he shows you Mystra's portrait and teaches you to touch the Weave; imagine kissing him or walking hand in hand.",
        { act = 1, "The camp celebration can also start his romance." },
        "Act 2: after reaching the Moonrise Towers waypoint, interact with his projection at camp for the starry-sky night -> Partnered next morning.",
        { act = 2, "That night must happen before you go down into the Mind Flayer Colony." },
        "Act 3: the Crown of Karsus conversation shapes the romance - telling him you love him as he is keeps him human.",
    },

    counters = {
        {
            id = "items", label = "Magic items fed to Gale", need = 1,
            help = "Only the first is mandatory. Items he accepts: Idol of Silvanus, Amulet of Selune, Iron Flask, Sword of Justice, Staff of Crones, Night Walkers, Shadow of Menzoberranzan, Necromancy of Thay.",
            items = {
                { label = "First item", cond = F("ORI_Gale_State_GotOneMagicItem", "any") },
                { label = "Second item", cond = F("ORI_Gale_State_GotTwoMagicItems", "any") },
                { label = "Third item", cond = F("ORI_Gale_State_GotThreeMagicItems", "any") },
            },
        },
    },

    steps = {
        -- ------------------------------------------------------------------ Act 1
        {
            id = "GALE_A1_PORTAL", act = 1, kind = "recruit", critical = true,
            title = "Pull Gale out of the rune circle",
            where = "Roadside Cliffs, ancient rune circle north of the Ravaged Beach",
            todo = { "Investigate the circle and take his hand. Pass the ability check (a second, harder try is allowed)." },
            avoid = { "Failing both checks or leaving him - he falls back in and cannot be recruited." },
            rewards = "Gale (Evocation wizard) joins.",
            done = { Q(GA, "RecruitedGale"), F("ORI_Gale_State_WasRecruited", "any"), G("GLO_Origin_PartOfTheTeam_Gale") },
            closes = "act1",
        },
        {
            id = "GALE_A1_ITEM", act = 1, kind = "story", critical = true,
            title = "Feed him a magic item when he asks",
            where = "Camp, when his 'condition' flares",
            todo = {
                "Give him one of the items he can absorb: Idol of Silvanus, Amulet of Selune, Iron Flask, Sword of Justice, Staff of Crones, Night Walkers, Shadow of Menzoberranzan or the Necromancy of Thay.",
                "Pick items you do not need yourself.",
            },
            avoid = { "Refusing the FIRST request - Gale leaves the party." },
            rewards = "His condition stabilizes; leads to the truth about the orb.",
            done = { Q(GA, "GaveOneItem"), F("ORI_Gale_State_GotOneMagicItem", "any") },
            after = { "GALE_A1_PORTAL" },
        },
        {
            id = "GALE_A1_WEAVE", act = 1, kind = "romance", romance = true, romanceStart = true, critical = true, approval = 36,
            title = "Romance: the Weave lesson",
            where = "Camp at night (36+ approval) - or the camp celebration",
            todo = {
                "Ask about the woman in his conjured portrait (Insight DC 5): it is Mystra.",
                "Accept his offer to experience the Weave and pass the three steps (gesture, words, harmony).",
                "Hold the moment and imagine kissing him or walking hand in hand.",
            },
            avoid = { "Being dismissive of his magic. Imagining anything hostile." },
            rewards = "Relationship: Dating.",
            done = { P("ORI_State_DatingGale"), P("ORI_State_PartneredWithGale"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverGale") },
            closes = "act1",
        },
        {
            id = "GALE_A1_TRUTH", act = 1, kind = "story", optional = true, needsJoin = true,
            title = "Learn the truth about the orb",
            where = "Camp",
            todo = { "Keep talking to him after feeding him items; he tells you about Mystra and the Netherese orb." },
            done = { Q(GA, "LearnedBackstory"), F("ORI_Gale_Knows_LearnedBackstory", "any") },
            closes = "act3",
        },

        -- ------------------------------------------------------------------ Act 2
        {
            id = "GALE_A2_ELMINSTER", act = 2, kind = "story", critical = true,
            title = "Elminster's message",
            where = "Rosymorn Monastery Trail, or right after the Grymforge lift",
            todo = { "Talk to the old man on the road - it is Elminster, bringing Mystra's request." },
            avoid = { "Ignoring or attacking Elminster - Gale leaves camp once Ketheric is dead, with only a letter left behind." },
            done = { Q(GA, "ElminsterBrief"), Q(GA, "MeetElminster"), F("ORI_Gale_Event_BombDisarmed", "any") },
            fail = { Q(GA, "ORI_Gale_BombNotDisarmed"), Q(GA, "ORI_Gale_AbandonedBombNotDisarmed") },
            closes = "act3",
        },
        {
            id = "GALE_A2_STARS", act = 2, kind = "romance", romance = true, critical = true,
            title = "Romance: the starry sky",
            where = "Camp, after unlocking the Moonrise Towers waypoint",
            todo = {
                "Requires Elminster's message (see the step above): without it this night never comes.",
                "While dating him (and not partnered with anyone else), interact with his projection at camp before a long rest.",
                "Comfort him, return his confession, then choose the Weave or 'a real man' love scene.",
                "Next morning, do not call it a one-time thing.",
            },
            avoid = { "Going down into the Mind Flayer Colony first - you cannot long rest there and the night is lost." },
            rewards = "Relationship: Partnered.",
            done = { P("ORI_State_PartneredWithGale"), C.Rel("partnered") },
            fail = { P("ORI_State_ChosePartnerOverGale"), P("ORI_State_WasPartneredWithGale") },
            after = { "GALE_A1_WEAVE", "GALE_A2_ELMINSTER" },
            closes = "colony",
        },

        -- ------------------------------------------------------------------ Act 3
        {
            id = "GALE_A3_KARSUS", act = 3, kind = "story", critical = true,
            title = "The Annals of Karsus",
            where = "Sorcerous Sundries, Lower City - the secure vaults",
            todo = { "Ask Tolna about the book, get into the vaults and recover The Annals of Karsus. Let Gale read it." },
            done = { Q(GA, "FoundBook"), Q(GA, "ReadNotes") },
            closes = "endgame",
        },
        {
            id = "GALE_A3_ROMANCE", act = 3, kind = "romance", romance = true,
            title = "Romance: the night after the Annals of Karsus",
            where = "Act 3 camp (long rest)",
            todo = {
                "Requires: being his partner, and Gale having read the Annals of Karsus.",
                "Long rest for his Act 3 romance scene. How you talk to him about the Crown from here on shapes his ending.",
            },
            done = { G("NIGHT_Gale_BeMyGod") },
            after = { "GALE_A2_STARS", "GALE_A3_KARSUS" },
            closes = "endgame",
        },
        {
            id = "GALE_A3_MYSTRA", act = 3, kind = "choice", romance = true, critical = true,
            title = "Mystra at the Stormshore Tabernacle",
            where = "Stormshore Tabernacle, Lower City",
            todo = {
                "Bring Gale to pray at the Tabernacle when Elminster asks.",
                "Afterwards, in the rowboat talk, tell him he does not need godhood - promise the Crown to Mystra for a human ending.",
            },
            avoid = { "Skipping Mystra entirely. Encouraging his hubris leads to the god-of-ambition ending." },
            rewards = "Decides his ending: professor in Waterdeep (and a proposal) or a would-be god.",
            done = { Q(GA, "PromiseMystra"), Q(GA, "RefusedMystra"), Q(GA, "DelayedMystra"), Q(GA, "KarsiteWeave") },
            fail = { Q(GA, "MystraBlocked") },
            after = { "GALE_A3_KARSUS" },
            closes = "endgame",
        },
    },
}

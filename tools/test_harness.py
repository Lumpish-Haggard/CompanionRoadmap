"""
test_harness.py - run the mod's real Lua code (server + client) outside the game.

Two independent Lua 5.4 states (like BG3SE's server and client contexts) load the
mod through tools/mock_se.lua: a strict Script Extender stand-in whose IMGUI mock
is built from BG3SE's property map. A fake Osiris world (flags, journal, databases,
approval) drives scenarios, and messages travel between the states as JSON.

Requires:  pip install lupa
Usage:     python tools/test_harness.py
"""
from __future__ import annotations

import heapq
import itertools
import json
import os
import re
import sys
import traceback
from collections import defaultdict

try:
    import lupa.lua54 as lupa
except ImportError:  # pragma: no cover
    sys.exit("lupa is required: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_DIR = os.path.join(ROOT, "Mods", "CompanionRoadmap", "ScriptExtender", "Lua")
MOCK = os.path.join(ROOT, "tools", "mock_se.lua")
FLAGS_LUA = os.path.join(LUA_DIR, "Data", "Flags.lua")

NULL = "00000000-0000-0000-0000-000000000000"
AVATAR = "Tav_11111111-2222-3333-4444-555555555555"
CLIENT_PEER = 65536

UUID = {
    "Shadowheart": "3ed74f06-3c60-42dc-83f6-f034cb47c679",
    "Minthara": "25721313-0c15-4935-8176-9f134385451b",
    "Karlach": "2c76687d-93a2-477b-8b18-8a14b549304c",
    "Laezel": "58a69333-40bf-8358-1d17-fff240d7fb12",
    "Astarion": "c7c13742-bacd-460a-8f65-f864fe41f255",
    "Gale": "ad9af97d-75da-406a-ae13-7071c563f604",
    "Wyll": "c774d764-4a17-48dc-b470-32ace9ce447d",
    "Halsin": "7628bc0e-52b8-42a7-856a-13a6fd413323",
    "Jaheira": "91b6b200-7d00-4d62-8dc9-99e8339dfa1a",
    "Minsc": "0de603c5-42e2-4811-9dad-f652de080eba",
}


def guid(s):
    if s is None:
        return None
    s = str(s)
    return s[-36:].lower() if len(s) >= 36 else s


def load_flag_guids():
    names = {}
    for m in re.finditer(r'^\s+(\w+) = \{ "([0-9a-f-]{36})", (\d+) \},', open(FLAGS_LUA, encoding="utf-8").read(), re.M):
        names[m.group(1)] = m.group(2)
    return names


FLAG = load_flag_guids()


class World:
    """A tiny fake of the parts of Osiris the mod reads."""

    def __init__(self):
        self.flags = set()          # (flag guid, target guid)
        self.quests = set()         # (quest, step)
        self.dbs = defaultdict(list)
        self.approval = {}
        self.dead = set()
        self.statuses = set()
        self.host = AVATAR
        self.set_level("WLD_Main_A")
        self.dbs["DB_Avatars"] = [(AVATAR,)]

    def set_level(self, level):
        self.level = level
        self.dbs["DB_CurrentLevel"] = [(level,)]

    def set_flag(self, name, target=NULL):
        self.flags.add((FLAG[name], guid(target)))

    def clear_flag(self, name, target=NULL):
        self.flags.discard((FLAG[name], guid(target)))

    def quest(self, quest, step):
        self.quests.add((quest, step))

    def call(self, name, args):
        if name == "GetFlag":
            return 1 if (guid(args[0]), guid(args[1])) in self.flags else 0
        if name == "QuestUpdateIsUnlocked":
            return 1 if (args[1], args[2]) in self.quests else 0
        if name == "GetApprovalRating":
            return self.approval.get(guid(args[0]), 0)
        if name == "IsDead":
            return 1 if guid(args[0]) in self.dead else 0
        if name == "HasActiveStatus":
            return 1 if (guid(args[0]), args[1]) in self.statuses else 0
        if name == "GetHostCharacter":
            return self.host
        if name == "GetRegion":
            return self.level
        if name == "GetReservedUserID":
            return 65537
        if name == "GetCurrentCharacter":
            return self.host
        raise RuntimeError(f"Osiris function {name} is not mocked")

    def db_get(self, name, args):
        out = []
        for row in self.dbs.get(name, []):
            ok = True
            for i, a in enumerate(args):
                if a is None:
                    continue
                if i >= len(row):
                    ok = False
                    break
                lhs, rhs = row[i], a
                if isinstance(lhs, str) and isinstance(rhs, str) and len(lhs) >= 36 and len(rhs) >= 36:
                    ok = guid(lhs) == guid(rhs)
                else:
                    ok = lhs == rhs
                if not ok:
                    break
            if ok:
                out.append(row)
        return out


class Sim:
    """Clock, timers and the message bus shared by both Lua states."""

    def __init__(self, world):
        self.world = world
        self.now = 0
        self.timers = []
        self.seq = itertools.count(1)
        self.cancelled = set()
        self.messages = []
        self.runtimes = {}

    def add_timer(self, ms, fn):
        h = next(self.seq)
        heapq.heappush(self.timers, (self.now + int(ms), h, fn))
        return h

    def run(self, max_ms=60000):
        guard = 0
        while True:
            guard += 1
            if guard > 10000:
                raise RuntimeError("simulation did not settle")
            if self.messages:
                target, channel, payload, user = self.messages.pop(0)
                self.runtimes[target].deliver(channel, payload, user)
                continue
            if self.timers and self.timers[0][0] <= self.now + max_ms:
                due, h, fn = heapq.heappop(self.timers)
                self.now = max(self.now, due)
                if h not in self.cancelled:
                    fn()
                continue
            break


class Runtime:
    def __init__(self, name, is_server, sim):
        self.name = name
        self.sim = sim
        self.is_server = is_server
        self.handlers = {}
        self.logs = []
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua = self.lua
        sim.runtimes[name] = self

        def to_lua(obj):
            if isinstance(obj, dict):
                return lua.table_from({k: to_lua(v) for k, v in obj.items()})
            if isinstance(obj, (list, tuple)):
                return lua.table_from([to_lua(v) for v in obj])
            return obj
        self.to_lua = to_lua

        host = lua.table()
        host.is_server = is_server
        host.log = lambda _s, kind, msg: self.logs.append((kind, str(msg)))
        host.now = lambda _s: sim.now
        host.read_lua = lambda _s, path: open(os.path.join(LUA_DIR, str(path)), encoding="utf-8").read()
        host.json_parse = lambda _s, s: to_lua(json.loads(s))
        host.add_timer = lambda _s, ms, fn: sim.add_timer(ms, fn)
        host.cancel_timer = lambda _s, h: sim.cancelled.add(h) or True
        host.set_handler = lambda _s, ch, fn: self.handlers.__setitem__(str(ch), fn)
        host.send = lambda _s, ch, payload, target, user: sim.messages.append(
            ("server" if target == "server" else "client", str(ch), str(payload), user))

        def osi_call(_s, name, args, n):
            vals = [args[i] for i in range(1, int(n) + 1)]
            return sim.world.call(str(name), vals)

        def db_get(_s, name, args, n):
            vals = [args[i] for i in range(1, int(n) + 1)]
            return to_lua([list(r) for r in sim.world.db_get(str(name), vals)])
        host.osi_call = osi_call
        host.db_get = db_get
        lua.globals().Host = host
        self.mock = lua.execute(open(MOCK, encoding="utf-8").read())

    def boot(self, bootstrap):
        self.env = self.mock.Env()
        self.lua.globals().Ext.Require(bootstrap)

    def deliver(self, channel, payload, user):
        fn = self.handlers.get(channel)
        if fn is None:
            raise RuntimeError(f"{self.name}: no handler for channel {channel}")
        msg = self.to_lua(json.loads(payload))
        fn(msg, CLIENT_PEER if self.is_server else user)

    def errors(self):
        bad = [m for k, m in self.logs if k == "error" or ("failed" in m and "[CompanionRoadmap]" in m)]
        # IMGUI misuse is recorded by the mock even when the mod's pcall swallowed it
        violations = self.mock.Violations
        bad += ["IMGUI: " + str(violations[i]) for i in range(1, len(violations) + 1)]
        return bad

    def eval(self, code, *args):
        """Runs `code` inside the mod environment (where CR lives), like a mod file would."""
        runner = self.lua.eval("""function(code, env, ...)
            local f, err = load(code, "=test", "t", env)
            if not f then error(err, 2) end
            return f(...)
        end""")
        return runner(code, self.mock.Env(), *args)


# ----------------------------------------------------------------------------- tests
class Failure(Exception):
    pass


def check(cond, msg):
    if not cond:
        raise Failure(msg)


def step_status(client, step_id):
    return client.eval(f"""
        local s = CR.Client.Snapshot
        local r = s and s.steps and s.steps["{step_id}"]
        return r and r[1] or nil
    """)


def make():
    world = World()
    sim = Sim(world)
    server = Runtime("server", True, sim)
    client = Runtime("client", False, sim)
    server.boot("BootstrapServer.lua")
    client.boot("BootstrapClient.lua")
    for rt in (server, client):
        rt.lua.globals().Ext.Events.SessionLoaded.Throw(rt.lua.globals().Ext.Events.SessionLoaded, rt.lua.table())
    sim.run()
    return world, sim, server, client


def fire_running(client, sim):
    ev = client.lua.globals().Ext.Events.GameStateChanged
    ev.Throw(ev, client.to_lua({"FromState": "PrepareRunning", "ToState": "Running"}))
    sim.run()


def press(client, sim, key, mods=()):
    ev = client.lua.globals().Ext.Events.KeyInput
    e = client.to_lua({"Event": "KeyDown", "Key": key, "Repeat": False, "Modifiers": list(mods), "Pressed": True})
    client.eval("local e = ... ; e.PreventAction = function() end", e)
    ev.Throw(ev, e)
    sim.run()


def test_boot_and_snapshot():
    world, sim, server, client = make()
    check(not server.errors(), f"server errors: {server.errors()}")
    check(not client.errors(), f"client errors: {client.errors()}")
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    world.approval[UUID["Shadowheart"]] = 25
    fire_running(client, sim)
    press(client, sim, "F7")
    check(client.eval("return CR.UI.IsOpen()") is True, "F7 should open the overlay")
    check(step_status(client, "SH_A1_RECRUIT") == "D", "Shadowheart recruited flag should mark the step done")
    check(step_status(client, "MIN_A2_TRIAL") == "U", "Act 2 steps are upcoming in Act 1")
    check(step_status(client, "SH_P_POD") == "X", "optional prologue step not done becomes N/A in Act 1")
    nxt = client.eval("""
        local n = 0
        for id, r in pairs(CR.Client.Snapshot.steps) do
            if r[1] == "N" and CR.Guides.StepOwner[id].id == "Shadowheart" then n = n + 1 end
        end
        return n
    """)
    check(nxt == 1, f"exactly one NEXT step per companion (got {nxt})")
    check(not client.errors(), f"client errors after open: {client.errors()}")
    return world, sim, server, client


def test_live_update_and_toast():
    world, sim, server, client = test_boot_and_snapshot()
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_State_DatingShadowheart_" + FLAG["ORI_State_DatingShadowheart"], AVATAR, 0)
    sim.run(max_ms=1000)  # long enough for the debounce, shorter than the toast lifetime
    check(step_status(client, "SH_A1_PARTY") == "D", "dating flag should complete the waterfall romance step")
    rel = client.eval('return CR.Client.Snapshot.comps.Shadowheart.rel')
    check(rel == "dating", f"relationship should be dating (got {rel})")
    toasts = client.eval("local n = 0 for _ in ipairs(CR.Toasts.queue) do n = n + 1 end return n")
    check(toasts >= 1, "a toast should be queued for the completed romance step")
    # irrelevant flags must not trigger refreshes
    timers_before, messages_before = len(sim.timers), len(sim.messages)
    server.mock.FireOsiris("FlagSet", "SOME_Flag_" + "deadbeef-dead-beef-dead-beefdeadbeef", AVATAR, 0)
    check(len(sim.timers) == timers_before and len(sim.messages) == messages_before, "unwatched flags should be ignored")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_ui_interactions():
    world, sim, server, client = test_boot_and_snapshot()
    # visit every companion page and toggle every option
    client.eval("""
        for _, comp in ipairs(CR.Guides.Companions) do CR.UI.Select(comp.id) end
        CR.UI.Select("Shadowheart")
        for _, key in ipairs({ "hideCompleted", "romanceOnly", "showTracking", "notifyAll" }) do
            CR.Settings.Set(key, true)
            CR.Settings.Set(key, false)
        end
        for _, k in ipairs(CR.Settings.SpoilerKeys) do CR.Settings.Set("spoilers", k) end
        CR.Settings.Set("opacity", 0.8)
        CR.UI.SetAllOpen(true)
        CR.UI.SetAllOpen(false)
    """)
    sim.run()
    # manual check-off round trip
    client.eval('CR.Client.SetOverride("SH_A1_IDOL", true)')
    sim.run()
    check(step_status(client, "SH_A1_IDOL") == "O", "manual check-off should mark the step as checked")
    stored = server.eval("return CR.Server.GetOverrides().SH_A1_IDOL")
    check(stored is True, "override must be stored server side (mod variable)")
    client.eval('CR.Client.SetOverride("*", false)')
    sim.run()
    check(step_status(client, "SH_A1_IDOL") != "O", "clearing all check-offs should work")
    # hotkey capture + persistence
    client.eval("CR.Hotkey.BeginCapture(nil)")
    press(client, sim, "F9", ["LCtrl"])
    desc = client.eval("return CR.Hotkey.Describe()")
    check(desc == "CTRL + F9", f"captured hotkey should be CTRL + F9 (got {desc})")
    saved = client.eval('return Mock and true')
    press(client, sim, "F9", ["LCtrl"])
    check(client.eval("return CR.UI.IsOpen()") is False, "the new hotkey should close the overlay")
    press(client, sim, "F9", ["LCtrl"])
    check(client.eval("return CR.UI.IsOpen()") is True, "the new hotkey should reopen the overlay")
    files = client.mock.Files
    check(files["CompanionRoadmap/settings.json"] is not None, "settings must be written to disk")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_act2_point_of_no_return():
    world, sim, server, client = test_boot_and_snapshot()
    world.set_flag("GLO_Origin_PartOfTheTeam_Karlach")
    world.quest("ORI_COM_Karlach", "Recruited_PaladinsNotDefeated")
    world.set_flag("VISITEDREGION_SCL_Main_A")
    world.set_level("SCL_Main_A")
    server.mock.FireOsiris("LevelGameplayStarted", "SCL_Main_A", False)
    sim.run()
    act = client.eval("return CR.Client.Snapshot.act")
    check(act == 2, f"act should be 2 in the Shadow-Cursed Lands (got {act})")
    check(step_status(client, "SH_A1_NOBLESTALK") in ("A", "N"), "Act 1 steps stay available until the Shadowfell")
    world.set_flag("Act2_PointOfNoReturnReached")
    server.mock.FireOsiris("FlagSet", "Act2_PointOfNoReturnReached_" + FLAG["Act2_PointOfNoReturnReached"], NULL, 0)
    sim.run()
    check(step_status(client, "SH_A1_NOBLESTALK") == "M", "Act 1 steps close when Act 1 locks")
    check(step_status(client, "KAR_A1_DAMMON") == "I", "Karlach's heart can still be fixed later (unconfirmed, not missed)")
    check(step_status(client, "KAR_A2_UPGRADE") in ("A", "N"), "her Act 2 upgrade is available")
    check(step_status(client, "WYLL_A1_PARTY") == "M", "Wyll's romance (party only) is missed once Act 1 locks")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_minthara_knockout_and_dependencies():
    world, sim, server, client = test_boot_and_snapshot()
    world.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    server.mock.FireOsiris("Died", "S_GOB_DrowCommander_" + UUID["Minthara"])
    sim.run()
    check(step_status(client, "MIN_A1_KO") == "D", "knocked-out Minthara should complete the KO step")
    check(step_status(client, "MIN_A1_RAID") == "X", "the raid route is N/A once she is knocked out")
    # killing her instead
    world2, sim2, server2, client2 = test_boot_and_snapshot()
    world2.dead.add(UUID["Minthara"])
    world2.dbs["DB_PermaDefeated"] = [(UUID["Minthara"],)]
    server2.mock.FireOsiris("Died", "S_GOB_DrowCommander_" + UUID["Minthara"])
    sim2.run()
    check(step_status(client2, "MIN_A1_KO") == "M", "a dead Minthara fails the KO step")
    check(step_status(client2, "MIN_A2_ROMANCE") == "M", "and everything after it is missed")
    check(not server2.errors() and not client2.errors(), f"errors: {server2.errors()} {client2.errors()}")


def test_origin_avatar_and_console():
    world = World()
    world.host = "S_Player_ShadowHeart_" + UUID["Shadowheart"]
    world.dbs["DB_Avatars"] = [(world.host,)]
    sim = Sim(world)
    server = Runtime("server", True, sim)
    client = Runtime("client", False, sim)
    server.boot("BootstrapServer.lua")
    client.boot("BootstrapClient.lua")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    you = client.eval("return CR.Client.Snapshot.comps.Shadowheart.you")
    check(you is True, "playing as Shadowheart should be detected")
    check(step_status(client, "SH_A1_PARTY") == "X", "you cannot romance yourself")
    server.mock.ConsoleCommands.roadmap("roadmap", "diag")
    server.mock.ConsoleCommands.roadmap("roadmap", "steps", "Minthara")
    client.mock.ConsoleCommands.roadmap("roadmap", "hotkey")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_mcm_integration():
    world = World()
    sim = Sim(world)
    server = Runtime("server", True, sim)
    client = Runtime("client", False, sim)
    server.boot("BootstrapServer.lua")
    # Inject a fake MCM API the way MCM does (into this mod's table) before the session loads.
    client.lua.execute("""
        local Mock = ...
        _G.__mcm = { values = {}, keyCb = nil, buttonCb = nil, closed = false }
        local api = {
            Get = function(id) return __mcm.values[id] end,
            Set = function(id, v) __mcm.values[id] = v return true end,
            Keybinding = { SetKeyDownCallback = function(id, cb) assert(id == "toggle_roadmap") __mcm.keyCb = cb end },
            EventButton = { RegisterCallback = function(id, cb) assert(id == "open_roadmap") __mcm.buttonCb = cb end },
            CloseMCMWindow = function() __mcm.closed = true end,
        }
        Mods.CompanionRoadmap.MCM = api
        local handlers = {}
        Ext.ModEvents.BG3MCM = { MCM_Setting_Saved = { Subscribe = function(self, fn) table.insert(handlers, fn) end } }
        _G.__mcmFire = function(payload) for _, fn in ipairs(handlers) do fn(payload) end end
    """, client.mock)
    client.boot("BootstrapClient.lua")
    ev = client.lua.globals().Ext.Events.SessionLoaded
    ev.Throw(ev, client.lua.table())
    fire_running(client, sim)
    check(client.eval("return CR.Settings.HasMCM()") is True, "MCM should be detected")
    check(client.eval("return CR.Hotkey.useMCM") is True, "the toggle key should be handed to MCM")
    pushed = client.lua.eval("__mcm.values.spoilers")
    check(pushed == "Show everything", f"local settings should be pushed into MCM (got {pushed})")
    press(client, sim, "F7")
    check(client.eval("return CR.UI.IsOpen()") is False, "raw F7 must be ignored when MCM owns the keybinding")
    client.lua.eval("__mcm.keyCb")()
    sim.run()
    check(client.eval("return CR.UI.IsOpen()") is True, "the MCM keybinding should toggle the overlay")
    client.lua.eval("__mcm.keyCb")()
    client.lua.eval("__mcm.buttonCb")()
    sim.run()
    check(client.eval("return CR.UI.IsOpen()") is True, "the MCM button should open the overlay")
    check(client.lua.eval("__mcm.closed") is True, "the MCM window should close when the roadmap opens")
    client.lua.eval("__mcmFire")(client.to_lua({"modUUID": "9f8b2c41-7a63-4d8e-9b5a-1c8e5f2a3d4e",
                                                "settingId": "hide_completed", "value": True}))
    client.lua.eval("function() __mcm.values.hide_completed = true end")()
    check(client.eval('return CR.Settings.Get("hideCompleted")') is True, "MCM changes should apply")
    client.eval('CR.Settings.Set("spoilers", "titles")')
    check(client.lua.eval("__mcm.values.spoilers") == "Titles only for future acts", "settings set in the overlay go to MCM")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


GAME_FONTS = {
    # verified against the file listing of Game.pak (Patch 8)
    "Public/Game/GUI/Assets/Fonts/QuadraatOffcPro/" + f for f in (
        "QuadraatOffcPro.ttf", "QuadraatOffcPro-Italic.ttf", "QuadraatOffcPro-Demibold.ttf",
        "QuadraatOffcPro-DemiboldItalic.ttf", "QuadraatOffcPro-Bold.ttf", "QuadraatOffcPro-BoldItalic.ttf")
}


def test_ui_layout():
    """The roadmap window: fonts, act sections, NEXT highlight, warnings links and filters."""
    world, sim, server, client = make()
    for f in ("GLO_Origin_PartOfTheTeam_Shadowheart", "GLO_Origin_PartOfTheTeam_Karlach",
              "VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A", "NIGHT_GoblinHunt_TieflingCelebration"):
        world.set_flag(f)
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    world.set_level("SCL_Main_A")
    world.approval[UUID["Shadowheart"]] = 47
    world.quest("ORI_COM_ShadowHeart", "Recruited_Beach")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    fonts = client.mock.Fonts
    loaded = {str(k): str(v.path) for k, v in fonts.items()}
    check(len(loaded) == 4, f"the four Quadraat cuts should be loaded (got {loaded})")
    check(all(p in GAME_FONTS for p in loaded.values()), f"font paths must exist in the game: {loaded}")
    check(client.eval("return CR.Theme.Fonts.title") == "CompanionRoadmap_Title", "titles should use the loaded font")

    # every step shows a real status, with an explanation on hover
    bad = client.eval("""
        local bad = {}
        for id, s in pairs(CR.UI.page.steps) do
            local known = false
            for _, st in pairs(CR.Theme.Status) do if st.label == s.status.Label and s.status.Label ~= "..." then known = true end end
            if not known or s.tip == nil or s.tip.Label == "" then table.insert(bad, id) end
        end
        return table.concat(bad, ",")
    """)
    check(bad == "", f"steps without a status or tooltip: {bad}")

    # Act 2 is current; Act 1 stays open because Shadowheart still has a NEXT step there; Act 3 is folded
    opened = client.eval("""
        local out = {}
        for k = 1, 3 do out[k] = rawget(CR.UI.page.acts[k].header, "__open") and "open" or "closed" end
        return table.concat(out, ",")
    """)
    next_act = client.eval("""
        for id, s in pairs(CR.UI.page.steps) do
            if s.status.Label == "NEXT" then return s.step.act end
        end
    """)
    check(next_act is not None, "Shadowheart should have a NEXT step")
    expected_first = "open" if next_act <= 1 else "closed"
    check(opened == f"{expected_first},open,closed", f"act sections open state (NEXT in act {next_act}): {opened}")
    band = client.eval("""
        for id, s in pairs(CR.UI.page.steps) do
            if s.status.Label == "NEXT" then return rawget(s.row, "__colors").TableRowBg[4] end
        end
    """)
    check(band and band > 0, "the NEXT row should get a highlight band")

    # warnings: tab label, banner and click-through
    count = client.eval("return CR.UI.h.warnCount")
    check(count > 0, "an Act 2 save with open Act 1 steps should have warnings")
    tab = client.eval("return CR.UI.h.tabWarn.Label")
    check(tab == f"Before you move on ({count})###crTabWarn", f"warnings tab label: {tab}")
    check(client.eval("return CR.UI.h.alert.Visible") is True, "the warnings banner should be visible")
    link = client.eval("""
        local body = CR.UI.h.warnBody
        for _, c in ipairs(rawget(body, "__children")) do
            if rawget(c, "__type") == "Selectable" and not rawget(c, "__destroyed") then
                c.OnClick(c)
                return c.Label
            end
        end
    """)
    check(link is not None and "###w_" in link, "the warnings tab should list clickable steps")
    step_id = link.split("###w_")[1]
    owner = client.eval(f'return CR.Guides.StepOwner["{step_id}"].id')
    check(client.eval("return CR.UI.selected") == owner, "clicking a warning should open its companion")
    check(client.eval(f'return rawget(CR.UI.page.steps["{step_id}"].tree, "__open")') is True,
          "clicking a warning should expand that step")
    check(client.eval("return CR.UI.h.tabRoadmap.SetSelected") is True, "clicking a warning should switch tabs")
    sim.run()
    check(client.eval("return CR.UI.h.tabRoadmap.SetSelected") is False, "the forced tab selection must be released")

    # filters
    client.eval('CR.UI.Select("Shadowheart") CR.Settings.Set("spoilers", "hide")')
    check(client.eval("return CR.UI.page.acts[3].header.Visible") is False, "hidden spoilers should hide later acts")
    client.eval('CR.Settings.Set("spoilers", "full") CR.Settings.Set("romanceOnly", true)')
    leaks = client.eval("""
        local n = 0
        for _, s in pairs(CR.UI.page.steps) do if s.row.Visible and not s.step.romance then n = n + 1 end end
        return n
    """)
    check(leaks == 0, f"romance-only should hide {leaks} non-romance steps")
    client.eval('CR.Settings.Set("romanceOnly", false)')
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_data_integrity():
    _, _, server, client = make()
    errs = client.eval("return #CR.Guides.Errors")
    check(errs == 0, f"data errors: {list(client.eval('return CR.Guides.Errors').values())}")
    n = client.eval("local n = 0 for _ in pairs(CR.Guides.StepById) do n = n + 1 end return n")
    check(n > 90, f"expected a full data set, got {n} steps")
    comps = client.eval("return #CR.Guides.Companions")
    check(comps == 10, f"expected 10 companions, got {comps}")


TESTS = [
    test_data_integrity,
    test_boot_and_snapshot,
    test_live_update_and_toast,
    test_ui_interactions,
    test_ui_layout,
    test_act2_point_of_no_return,
    test_minthara_knockout_and_dependencies,
    test_origin_avatar_and_console,
    test_mcm_integration,
]


def main():
    failed = 0
    for t in TESTS:
        try:
            t()
            print(f"PASS  {t.__name__}")
        except Failure as e:
            failed += 1
            print(f"FAIL  {t.__name__}: {e}")
        except Exception:
            failed += 1
            print(f"ERROR {t.__name__}")
            traceback.print_exc()
    print(f"\n{len(TESTS) - failed}/{len(TESTS)} tests passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

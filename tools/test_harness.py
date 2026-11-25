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
TEXTURE_BANK = os.path.join(ROOT, "Public", "CompanionRoadmap", "Content", "UI", "[PAK]_UI", "_merged.lsx")
FIXTURES = os.path.join(ROOT, "tests", "fixtures")

NULL = "00000000-0000-0000-0000-000000000000"
AVATAR = "Tav_11111111-2222-3333-4444-555555555555"

# Tags the story puts on a companion it removes for good
# (PROC_Origins_CompanionLeavePermanently / PROC_Origins_RemoveFromTeam in _GLO_Shared_Origins).
TAG_NO_RESURRECTION = "22a75dbb-1588-407e-b559-5aa4e6d4e6a6"   # BLOCK_RESURRECTION
TAG_DOWNED_DISABLED = "7095912e-fcb9-41dd-aec3-3cf7803e4b22"   # DOWNED_DISABLED
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
        self.tags = set()           # (character guid, tag guid)
        self.enemies = set()        # (character guid, character guid): IsEnemy
        self.names = {}             # character guid -> GetDisplayName result
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
        if name == "IsTagged":
            return 1 if (guid(args[0]), guid(args[1])) in self.tags else 0
        if name == "GetHostCharacter":
            return self.host
        if name == "GetRegion":
            return self.level
        if name == "GetReservedUserID":
            return 65537
        if name == "GetCurrentCharacter":
            return self.host
        if name == "IsEnemy":
            return 1 if (guid(args[0]), guid(args[1])) in self.enemies else 0
        if name == "GetDisplayName":
            return self.names.get(guid(args[0]))
        raise RuntimeError(f"Osiris function {name} is not mocked")

    def db_get(self, name, args):
        out = []
        for row in self.dbs.get(name, []):
            # Osiris databases are separate per arity (DB_X/2 is not DB_X/3)
            if len(row) != len(args):
                continue
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
        # the textures and game icons the mod declares are the only ones AddImage may use
        for texture in declared_textures():
            self.mock.Textures[texture] = True
        for icon in declared_game_icons():
            self.mock.Icons[icon] = True

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


def declared_textures():
    """Texture resource ids declared in the mod's texture bank (the companion portraits)."""
    if not os.path.exists(TEXTURE_BANK):
        return []
    text = open(TEXTURE_BANK, encoding="utf-8").read()
    return re.findall(r'<attribute id="ID" type="FixedString" value="([0-9a-f-]{36})"', text)


def declared_game_icons():
    """Names of the game's own UI icons the mod uses (T.GameIcons in UI/Theme.lua).
    tools/build_data.py checks them against the game's icon atlases."""
    text = open(os.path.join(LUA_DIR, "UI", "Theme.lua"), encoding="utf-8").read()
    block = re.search(r'T\.GameIcons = \{(.*?)\n\}', text, re.S)
    return re.findall(r'=\s*"([^"]+)"', block.group(1)) if block else []


def world_from_report(report):
    """Rebuilds the fake game world from a report file written by `!roadmap report`.

    This is how a bug report becomes a regression test: the report lists every flag
    and journal step that was set, plus the per-companion facts the tracker reads."""
    world = World()
    avatar = report.get("avatar") or guid(AVATAR)
    world.host = avatar
    world.dbs["DB_Avatars"] = [(avatar,)]
    if report.get("level"):
        world.set_level(report["level"])
    raw = report["raw"]
    for entry in raw.get("flags") or []:
        flag, target = entry.split("@", 1)
        world.flags.add((flag, guid(target)))
    for entry in raw.get("quests") or []:
        quest, step = entry.split("/", 1)
        world.quests.add((quest, step))
    for comp in (raw.get("companions") or {}).values():
        uuid = comp["uuid"]
        if comp.get("dead"):
            world.dead.add(uuid)
        if comp.get("perma"):
            world.dbs["DB_PermaDefeated"].append((uuid,))
        if comp.get("team"):
            world.dbs["DB_PartOfTheTeam"].append((uuid,))
        if comp.get("ko"):
            world.dbs["DB_KnockedOut"].append((uuid,))
        if comp.get("noRes"):
            world.tags.add((uuid, TAG_NO_RESURRECTION))
        if comp.get("downed"):
            world.tags.add((uuid, TAG_DOWNED_DISABLED))
        if comp.get("approval") is not None:
            world.approval[uuid] = comp["approval"]
        if comp.get("dating"):
            world.dbs["DB_ORI_Dating"].append((avatar, uuid))
        if comp.get("partnered"):
            world.dbs["DB_ORI_Partnered"].append((avatar, uuid))
    # the camp-scene scheduler (1.2): its tables, and the requirement flags that were set
    for name, rows in (report.get("scheduler") or {}).items():
        if name == "flags":
            for g in rows:
                world.flags.add((g, NULL))
            continue
        if name == "playerFlags":
            for entry in rows:
                flag, target = entry.split("@", 1)
                world.flags.add((flag, guid(target)))
            continue
        db = name.split("/")[0]          # "DB_CampNight_Requirement/3" -> DB_CampNight_Requirement
        for row in rows:
            world.dbs[db].append(tuple(row))
    return world


CHAR = {   # story names of the companions, as camp tables hold them
    "Shadowheart": "S_Player_ShadowHeart_" + UUID["Shadowheart"], "Karlach": "S_Player_Karlach_" + UUID["Karlach"],
    "Laezel": "S_Player_Laezel_" + UUID["Laezel"], "Gale": "S_Player_Gale_" + UUID["Gale"],
    "Halsin": "S_GLO_Halsin_" + UUID["Halsin"], "Wyll": "S_Player_Wyll_" + UUID["Wyll"],
    "Astarion": "S_Player_Astarion_" + UUID["Astarion"],
}
NULL_FLAG = "NULL_" + NULL


def add_scene(world, name, guid_, prio, camps, crd=(), req=(), approval=(), partner=(), dating=(), start=(),
              romance=(), cfm=False, dream=False, expires=None, expiring=None, exclusive=False):
    """Declares a camp scene the way the story goals do (DB_CampNight and friends, GLO_CampNights).
    Flags are (name, guid) pairs; companions are keys of CHAR."""
    flag = f"{name}_{guid_}"
    dbs = world.dbs
    dbs["DB_CampNight"].append((flag, prio))
    for camp in camps:
        dbs["DB_CampNight_Camp"].append((flag, camp))
    for who in crd:
        dbs["DB_CampNight_CRD"].append((flag, CHAR[who] if who else NULL_FLAG, f"CAMP_{name}_CRD", NULL_FLAG))
    for flags in req:
        dbs["DB_CampNight_Requirement"].append((flag, *[f"{n}_{g}" for n, g in flags]))
    for who, minimum in approval:
        dbs["DB_CampNight_Requirement_Approval"].append((flag, CHAR[who], minimum))
    for who in partner:
        dbs["DB_CampNight_Requirement_Partner"].append((flag, CHAR[who]))
    for who in dating:
        dbs["DB_CampNight_Requirement_Dating"].append((flag, CHAR[who]))
    for who in start:
        dbs["DB_CampNight_Requirement_CanStartDating"].append((flag, CHAR[who]))
    for who, rflag in romance:
        dbs["DB_CampNight_RomanceNight"].append((flag, CHAR[who], f"CAMP_{name}_SD_ROM",
                                                 f"{rflag[0]}_{rflag[1]}" if rflag else NULL_FLAG))
    if cfm:
        dbs["DB_CampNight_CFM"].append((flag, f"CAMP_{name}_CFM"))
    if dream:
        dbs["DB_CampNight_AvatarDream"].append((flag, f"CAMP_{name}_AvD"))
    if expires is not None:
        dbs["DB_CampNight_ExpiresAfter"].append((flag, expires))
    if expiring is not None:
        dbs["DB_CampNight_StartedExpiring"].append((flag, expiring))
    if exclusive:
        dbs["DB_CampNight_ExclusiveMoment"].append((flag,))
    return flag


def replay_report(report):
    """Boots the mod on the world described by a report and opens the roadmap."""
    world, sim, server, client = make(world_from_report(report), memory=report.get("memory"))
    for step_id in report.get("overrides") or []:
        server.eval(f'CR.Server.SetOverride("{step_id}", true)')
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    return world, sim, server, client


def all_statuses(client):
    """{ stepId: status } from the client's current snapshot."""
    text = client.eval("""
        local out = {}
        for id, r in pairs(CR.Client.Snapshot.steps) do out[#out + 1] = id .. "=" .. r[1] end
        return table.concat(out, ";")
    """)
    return dict(item.split("=") for item in str(text).split(";") if item)


def make(world=None, memory=None, saved=None):
    """Boots server and client on a world. `memory` is what the save already holds in
    the mod's "Memory" variable (the choice memory), as a report file exports it;
    `saved` presets any other mod variables ({ name: value })."""
    world = world or World()
    sim = Sim(world)
    server = Runtime("server", True, sim)
    client = Runtime("client", False, sim)
    if memory:
        server.lua.globals().Ext.Vars.vars.Memory = server.to_lua(memory)
    for name, value in (saved or {}).items():
        server.lua.globals().Ext.Vars.vars[name] = server.to_lua(value)
    server.boot("BootstrapServer.lua")
    client.boot("BootstrapClient.lua")
    for rt in (server, client):
        rt.lua.globals().Ext.Events.SessionLoaded.Throw(rt.lua.globals().Ext.Events.SessionLoaded, rt.lua.table())
    sim.run()
    return world, sim, server, client


def click(client, sim, label):
    """Clicks the button (or other clickable element) with exactly this label."""
    element = client.mock.FindClickable(label)
    check(element is not None, f"no clickable UI element labelled '{label}'")
    element.OnClick(element)
    sim.run()


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


def test_steps_wait_for_recruitment():
    """Romance and approval steps wait for the companion to join, and are missed with the recruit step."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    # nobody but Shadowheart has joined: their romance steps wait, hers are open
    for step_id in ("KAR_A1_ROMANCE", "WYLL_A1_PARTY", "GALE_A1_WEAVE", "GALE_A1_TRUTH", "AST_A1_ROMANCE", "LAE_A1_ROMANCE"):
        check(step_status(client, step_id) == "P", f"{step_id} should wait for recruitment, got {step_status(client, step_id)}")
    check(step_status(client, "SH_A1_PARTY") in ("A", "N"), "a recruited companion's romance step is open")
    check(step_status(client, "WYLL_A1_DUKE") in ("A", "N"), "a step that does not need the companion stays open")

    # joining opens them, with no journal entry needed
    world.set_flag("GLO_Origin_PartOfTheTeam_Karlach")
    server.mock.FireOsiris("FlagSet", "GLO_Origin_PartOfTheTeam_Karlach_" + FLAG["GLO_Origin_PartOfTheTeam_Karlach"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "KAR_A1_ROMANCE") in ("A", "N"), f"Karlach joined: {step_status(client, 'KAR_A1_ROMANCE')}")

    # Act 1 locks with Gale never recruited: his recruit step is missed, and his romance with it
    world.set_flag("Act2_PointOfNoReturnReached")
    world.set_flag("VISITEDREGION_SCL_Main_A")
    world.set_level("SCL_Main_A")
    server.mock.FireOsiris("FlagSet", "Act2_PointOfNoReturnReached_" + FLAG["Act2_PointOfNoReturnReached"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "GALE_A1_PORTAL") == "M", "an unrecruited Gale is missed once Act 1 locks")
    check(step_status(client, "GALE_A2_STARS") == "M", f"his Act 2 romance must not stay open: {step_status(client, 'GALE_A2_STARS')}")
    check(step_status(client, "GALE_A3_MYSTRA") == "M", f"nor his Act 3 steps: {step_status(client, 'GALE_A3_MYSTRA')}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_two_companion_steps():
    """The night Lae'zel and Shadowheart fight no longer stays open when one of them is gone."""
    world, sim, server, client = make()
    for name in ("Shadowheart", "Laezel"):
        world.set_flag("GLO_Origin_PartOfTheTeam_" + name)
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    check(step_status(client, "SH_A1_LAEZEL") in ("A", "N"), "both are here: the step is open")
    check(step_status(client, "LAE_A1_SHADOWHEART") in ("A", "N"), "both are here: the step is open")

    # Lae'zel turns on the party at the githyanki patrol
    world.clear_flag("GLO_Origin_PartOfTheTeam_Laezel")
    world.quest("ORI_COM_Laezel", "TurnedHostileAtChokepoint")
    server.mock.FireOsiris("FlagCleared", "GLO_Origin_PartOfTheTeam_Laezel_" + FLAG["GLO_Origin_PartOfTheTeam_Laezel"], "NULL_" + NULL, 0)
    server.eval("CR.Server.MarkDirty()")
    sim.run(max_ms=1000)
    check(step_status(client, "LAE_A1_SHADOWHEART") == "M", "Lae'zel is gone: her own step is missed")
    check(step_status(client, "SH_A1_LAEZEL") == "X", f"Shadowheart's side no longer applies: {step_status(client, 'SH_A1_LAEZEL')}")
    client.eval("CR.UI.SetOpen(true)")
    client.eval('CR.UI.Select("Shadowheart")')
    sim.run()
    state = str(client.eval("return CR.UI.page.steps.SH_A1_LAEZEL.state.Label"))
    check(state == "Not needed: Lae'zel is gone for this playthrough", f"the reason is given in plain words: {state}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_left_for_good_without_journal():
    """A companion the game removed for good is lost even when the journal says nothing.

    The story routine behind every permanent departure takes the companion out of the
    team and tags them; Halsin staying behind in Act 2 is one case with no journal entry."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    halsin, minsc, laezel = UUID["Halsin"], UUID["Minsc"], UUID["Laezel"]
    for tag in (TAG_NO_RESURRECTION, TAG_DOWNED_DISABLED):
        world.tags.add((halsin, tag))       # removed by the game, nothing in the journal
        world.tags.add((minsc, tag))        # Minsc carries both tags until he joins
    world.tags.add((laezel, TAG_DOWNED_DISABLED))   # one tag alone means nothing (left the tutorial ship)
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def comp(name):
        return str(client.eval(f"""
            local c = CR.Client.Snapshot.comps.{name}
            return tostring(c.lost) .. "/" .. tostring(c.why)
        """))
    check(comp("Halsin") == "true/left", f"Halsin should be lost: {comp('Halsin')}")
    check(step_status(client, "HAL_A3_ROMANCE") == "M", "and his steps missed")
    check(comp("Minsc") == "false/nil", f"Minsc has not joined yet, so his tags mean nothing: {comp('Minsc')}")
    check(comp("Laezel") == "false/nil", f"one tag is not enough: {comp('Laezel')}")
    check(client.eval("return CR.UI.sidebar.Halsin.info.Label") == "Lost for this playthrough", "sidebar text for Halsin")

    # a companion who is in the team is never lost, whatever tags they carry
    world.set_flag("GLO_Origin_PartOfTheTeam_Halsin")
    server.mock.FireOsiris("FlagSet", "GLO_Origin_PartOfTheTeam_Halsin_" + FLAG["GLO_Origin_PartOfTheTeam_Halsin"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(comp("Halsin") == "false/nil", f"in the team means not lost: {comp('Halsin')}")

    # once Minsc has joined and is then removed, the tags count
    world.quest("ORI_HighHarper", "RecruitedMinsc")
    server.eval("CR.Server.MarkDirty()")
    sim.run(max_ms=1000)
    check(comp("Minsc") == "true/left", f"Minsc joined and was then removed: {comp('Minsc')}")

    # the report file carries the tags, so a report replays to the same result
    server.mock.ConsoleCommands["roadmap"]("roadmap", "report")
    report = json.loads(str(server.mock.Files["CompanionRoadmap/report.json"]))
    check(report["raw"]["companions"]["Minsc"].get("noRes") and report["raw"]["companions"]["Minsc"].get("downed"),
          "the report should record the two tags")
    world2, sim2, server2, client2 = replay_report(report)
    lost = str(client2.eval("return tostring(CR.Client.Snapshot.comps.Minsc.lost)"))
    check(lost == "true", f"replaying the report should reproduce the lost state: {lost}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")
    check(not server2.errors() and not client2.errors(), f"errors: {server2.errors()} {client2.errors()}")


def test_scheduler_facts():
    """Facts taken from the game's camp-scene scheduler in 1.0.2."""
    world, sim, server, client = make()
    for name in ("Shadowheart", "Wyll", "Gale"):
        world.set_flag("GLO_Origin_PartOfTheTeam_" + name)
    for f in ("VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A", "VISITEDREGION_BGO_Main_A",
              "ORI_Shadowheart_State_SharPath", "NIGHT_Wyll_Act3Romance"):
        world.set_flag(f)
    world.set_level("BGO_Main_A")
    world.set_flag("ORI_State_DatingGale", AVATAR)
    world.set_flag("ORI_State_WasPartneredWithWyll", AVATAR)
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    # Wyll's Act 3 night also plays as his goodbye when the Duke is dead: not a proposal
    check(step_status(client, "WYLL_A3_PROPOSAL") == "M", f"a goodbye is not a proposal: {step_status(client, 'WYLL_A3_PROPOSAL')}")
    # Gale's starry night needs Elminster's message first
    check(step_status(client, "GALE_A2_STARS") in ("P", "M", "I"), f"no Elminster, no night: {step_status(client, 'GALE_A2_STARS')}")
    # the Dark Justiciar's night only plays for her partner (1.1: the scheduler cross-check found this)
    check(step_status(client, "SH_A3_SHARNIGHT") == "M", f"not her partner, no Shar night: {step_status(client, 'SH_A3_SHARNIGHT')}")
    world.set_flag("ORI_State_PartneredWithShadowheart", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_State_PartneredWithShadowheart_" + FLAG["ORI_State_PartneredWithShadowheart"], AVATAR, 0)
    sim.run(max_ms=1000)
    # ... and is cancelled once the House of Grief is concluded
    check(step_status(client, "SH_A3_SHARNIGHT") in ("A", "N"), f"Shar path night is open: {step_status(client, 'SH_A3_SHARNIGHT')}")
    world.set_flag("ORI_Shadowheart_State_ConcludedGrotto")
    server.mock.FireOsiris("FlagSet", "ORI_Shadowheart_State_ConcludedGrotto_" + FLAG["ORI_Shadowheart_State_ConcludedGrotto"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "SH_A3_SHARNIGHT") == "M", f"cancelled by the House of Grief: {step_status(client, 'SH_A3_SHARNIGHT')}")

    # the proposal itself: the night played and you are still his partner
    world.clear_flag("ORI_State_WasPartneredWithWyll", AVATAR)
    world.set_flag("ORI_State_PartneredWithWyll", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_State_PartneredWithWyll_" + FLAG["ORI_State_PartneredWithWyll"], AVATAR, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "WYLL_A3_PROPOSAL") == "D", f"partnered after the night: {step_status(client, 'WYLL_A3_PROPOSAL')}")
    check(client.eval('return CR.Guides.StepById.KAR_A3_DATE.approval') == 30, "Karlach's date needs 30 approval")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_paths_are_equal_choices():
    """Alternative paths (an `alt` group) are shown side by side as CHOOSE, never as NEXT plus OPTIONAL."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    check(step_status(client, "MIN_A1_KO") == "C", f"good path: {step_status(client, 'MIN_A1_KO')}")
    check(step_status(client, "MIN_A1_RAID") == "C", f"evil path: {step_status(client, 'MIN_A1_RAID')}")
    statuses = all_statuses(client)
    minthara_next = [k for k, v in statuses.items() if k.startswith("MIN_") and v == "N"]
    check(not minthara_next, f"no single Minthara step is NEXT while the paths are open: {minthara_next}")

    client.eval('CR.UI.Select("Minthara")')
    sim.run()
    for step_id, other in (("MIN_A1_KO", "Evil path"), ("MIN_A1_RAID", "Good path")):
        label = client.eval(f"return CR.UI.page.steps.{step_id}.status.Label")
        check(label == "CHOOSE", f"{step_id} should read CHOOSE, got {label}")
        state = str(client.eval(f"return CR.UI.page.steps.{step_id}.state.Label"))
        check(state.startswith("Or instead: " + other), f"{step_id} should point at the other path: {state}")
        band = client.eval(f"return CR.UI.page.steps.{step_id}.row:GetColor('TableRowBg')[4]")
        check(band > 0, f"{step_id} should be highlighted like a next step")
    details = visible_labels(client, "CR.UI.page.steps.MIN_A1_RAID.details").upper()   # labels are drawn in capitals
    check("WHAT IT CHANGES" in details and "AVOID" not in details,
          f"the evil path's costs are information, not a warning: {details!r}")
    note = str(client.eval("return CR.Guides.Get('Minthara').romanceNotes[2].text"))
    check("does not close" in note, f"the evil-path night must not read as closing her romance: {note}")

    # the warnings list the decision once, with both paths
    warnings = visible_labels(client, "CR.UI.h.warnBody")
    minthara = [line for line in warnings.split("\n") if "Minthara" in line]
    check(len(minthara) == 1 and "choose a path" in minthara[0] and "Good path" in minthara[0] and "Evil path" in minthara[0],
          f"one warning entry for Minthara's paths: {minthara}")

    # taking the evil path: the good one no longer applies, and her Act 2 recruitment stays open
    world.set_flag("NIGHT_GoblinHunt_RaiderCelebration")
    server.mock.FireOsiris("FlagSet", "NIGHT_GoblinHunt_RaiderCelebration_" + FLAG["NIGHT_GoblinHunt_RaiderCelebration"],
                           "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "MIN_A1_RAID") == "D" and step_status(client, "MIN_A1_KO") == "X",
          f"raid taken: {step_status(client, 'MIN_A1_RAID')} / {step_status(client, 'MIN_A1_KO')}")
    world.set_flag("Act2_PointOfNoReturnReached")
    world.set_flag("VISITEDREGION_SCL_Main_A")
    world.set_level("SCL_Main_A")
    server.mock.FireOsiris("FlagSet", "Act2_PointOfNoReturnReached_" + FLAG["Act2_PointOfNoReturnReached"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "MIN_A2_TRIAL") in ("A", "N"), f"evil path still leads to her trial: {step_status(client, 'MIN_A2_TRIAL')}")
    check(step_status(client, "MIN_A2_ROMANCE") == "P", f"and her romance waits for her: {step_status(client, 'MIN_A2_ROMANCE')}")

    # the good path, in another save
    world2, sim2, server2, client2 = make()
    world2.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world2.set_flag("VISITEDREGION_WLD_Main_A")
    world2.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    fire_running(client2, sim2)
    client2.eval("CR.UI.SetOpen(true)")
    sim2.run()
    check(step_status(client2, "MIN_A1_KO") == "D" and step_status(client2, "MIN_A1_RAID") == "X", "knockout taken")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")
    check(not server2.errors() and not client2.errors(), f"errors: {server2.errors()} {client2.errors()}")


def test_notice_position():
    """Where notices appear is a setting, with presets, a custom position and a preview."""
    world, sim, server, client = make()
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def placed():
        return str(client.eval("""
            local p = rawget(CR.Toasts.win, "__pos")
            return string.format("%d,%d|%.2f,%.2f", p.pos[1], p.pos[2], p.pivot[1], p.pivot[2])
        """))

    # the default is where notices always were: right edge, under the minimap (mock viewport 2560 x 1440)
    client.eval('CR.Settings.Set("notifications", false)')
    client.eval("CR.Toasts.Preview()")
    check(client.eval("return CR.Toasts.win.Open") is True, "the preview shows even with notices switched off")
    check(placed() == "2536,441|1.00,0.00", f"default position: {placed()}")

    # a preset moves the notice at once (the settings change shows a preview)
    client.eval('CR.Settings.Set("toastPosition", "left-middle")')
    check(placed() == "24,720|0.00,0.50", f"left, middle: {placed()}")
    check(client.eval("return CR.UI.h.toastX.Visible") is False, "the custom sliders are hidden for a preset")

    # custom: the sliders appear, and moving them moves the notice
    client.eval('CR.Settings.Set("toastPosition", "custom")')
    check(client.eval("return CR.UI.h.toastX.Visible and CR.UI.h.toastY.Visible") is True, "custom shows the sliders")
    client.eval("local s = CR.UI.h.toastX s.OnChange(s, { 50, 0, 0, 0 })")
    client.eval("local s = CR.UI.h.toastY s.OnChange(s, { 0, 0, 0, 0 })")
    check(client.eval('return CR.Settings.Get("toastX")') == 50, "the slider sets the setting")
    check(placed() == "1280,24|0.50,0.00", f"custom 50 / 0: {placed()}")

    # the combo in the Options tab follows changes made elsewhere (MCM)
    client.eval('CR.Settings.Set("toastPosition", "bottom-centre")')
    index = client.eval("return CR.UI.h.toastPos.SelectedIndex")
    check(index == 5, f"the combo should show 'Bottom centre' (index 5), got {index}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_choice_memory():
    """What the mod saw stays remembered after the save forgets it, and the game's own
    reason for removing a companion is kept (1.1 "Trust")."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    world.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def remembered(step_id):
        return client.eval(f'local r = CR.Client.Snapshot.steps["{step_id}"] return r and r[3]')

    def refresh():
        server.eval("CR.Server.MarkDirty()")
        sim.run(max_ms=1000)

    check(step_status(client, "MIN_A1_KO") == "D" and remembered("MIN_A1_KO") is None, "knocked out: detected in the save")

    # Minthara is moved to Moonrise and the game drops its knocked-out record: the step stays done
    world.dbs["DB_KnockedOut"] = []
    refresh()
    check(step_status(client, "MIN_A1_KO") == "D", f"the knockout is remembered: {step_status(client, 'MIN_A1_KO')}")
    check(remembered("MIN_A1_KO") == 1, f"remembered from Act 1: {remembered('MIN_A1_KO')}")
    client.eval('CR.UI.Select("Minthara")')
    sim.run()
    state = str(client.eval("return CR.UI.page.steps.MIN_A1_KO.state.Label"))
    check(state.startswith("Remembered:") and "in Act 1" in state, f"the step says it is remembered: {state}")

    # a flag seen in an ordinary snapshot, cleared later (a breakup purges the dating flag)
    world.clear_flag("ORI_State_DatingShadowheart", AVATAR)
    refresh()
    check(step_status(client, "SH_A1_PARTY") == "D" and remembered("SH_A1_PARTY") == 1,
          f"the wine scene happened, even though the save no longer says dating: {step_status(client, 'SH_A1_PARTY')}")

    # a flag set and cleared again inside one conversation: the event itself is written down
    server.mock.FireOsiris("FlagSet", "ORI_State_DatingKarlach_" + FLAG["ORI_State_DatingKarlach"], AVATAR, 7)
    sim.run(max_ms=1000)
    check(step_status(client, "KAR_A1_ROMANCE") == "D", f"a flag seen only in its event counts: {step_status(client, 'KAR_A1_ROMANCE')}")
    # but a failure the save records still wins over anything remembered
    world.set_flag("ORI_State_ChosePartnerOverKarlach", AVATAR)
    refresh()
    check(step_status(client, "KAR_A1_ROMANCE") == "M", "a recorded failure beats memory")
    # ... also when another path makes the step unnecessary at the same time
    server.eval('CR.Guides.StepById.KAR_A1_ROMANCE.skip = { CR.Cond.G("VISITEDREGION_WLD_Main_A") }')
    refresh()
    check(step_status(client, "KAR_A1_ROMANCE") == "X", f"failure and skip: not done, not missed: {step_status(client, 'KAR_A1_ROMANCE')}")
    server.eval("CR.Guides.StepById.KAR_A1_ROMANCE.skip = nil")
    world.clear_flag("ORI_State_ChosePartnerOverKarlach", AVATAR)
    refresh()
    check(step_status(client, "KAR_A1_ROMANCE") == "D", f"no failure: remembered again: {step_status(client, 'KAR_A1_ROMANCE')}")

    # the memory travels with the save: a new session given only what is IN the save variable
    server.mock.ConsoleCommands["roadmap"]("roadmap", "report")
    report = json.loads(str(server.mock.Files["CompanionRoadmap/report.json"]))
    stored = json.loads(str(server.eval("return Ext.Json.Stringify(Ext.Vars.vars.Memory or {})")))
    check(stored.get("facts"), f"the memory is written into the save variable: {stored}")
    world2, sim2, server2, client2 = make(world_from_report(report), memory=stored)
    fire_running(client2, sim2)
    client2.eval("CR.UI.SetOpen(true)")
    sim2.run()
    check(step_status(client2, "MIN_A1_KO") == "D" and step_status(client2, "KAR_A1_ROMANCE") == "D",
          "after loading the save, remembered steps are still done")
    # and the report carries it too, so a bug report replays to the same statuses
    check(report.get("memory") and len(report["memory"]["facts"]) > 0, "the report carries the memory")
    world3, sim3, server3, client3 = replay_report(report)
    expected = {k: v[0] for k, v in report["steps"].items()}
    actual = all_statuses(client3)
    diff = {k: (expected[k], actual.get(k)) for k in expected if actual.get(k) != expected[k]}
    check(not diff, f"a report with memory replays to the same statuses: {diff}")

    # the game removes Karlach for good and says why; nothing reaches the journal
    karlach = "S_Player_Karlach_" + UUID["Karlach"]
    world.set_flag("GLO_Origin_PartOfTheTeam_Karlach")
    refresh()
    world.clear_flag("GLO_Origin_PartOfTheTeam_Karlach")
    server.mock.FireOsiris("PROC_Origins_CompanionLeavePermanently", karlach, "ORI_Karlach_LeftPrisonAlone")
    sim.run(max_ms=1000)
    info = str(client.eval("local c = CR.Client.Snapshot.comps.Karlach return tostring(c.lost) .. '/' .. tostring(c.why) .. '/' .. tostring(c.lb)"))
    check(info == "true/left/ORI_Karlach_LeftPrisonAlone", f"Karlach is gone, with the game's reason: {info}")
    client.eval('CR.UI.Select("Karlach")')
    sim.run()
    notice = str(client.eval("return CR.UI.page.notice.Label"))
    check("left behind in the prison at Wyrm's Rock" in notice, f"the page says why: {notice}")
    # she comes back after all (another mod, a reload trick): she is not gone
    world.set_flag("GLO_Origin_PartOfTheTeam_Karlach")
    refresh()
    check(client.eval("return CR.Client.Snapshot.comps.Karlach.lost") is False, "back in the team means not lost")
    check(server.eval('return CR.Memory.Left("' + UUID["Karlach"] + '") == nil') is True, "and the departure is forgotten")

    # Options shows how much is remembered, and '!roadmap forget' clears it
    label = str(client.eval("return CR.UI.h.memory.Label"))
    check(label.startswith("The roadmap remembers ") and "moments" in label, f"Options shows the memory: {label}")
    server.mock.ConsoleCommands["roadmap"]("roadmap", "forget")
    sim.run(max_ms=1000)
    check(step_status(client, "MIN_A1_KO") != "D", "after forgetting, the knockout is no longer known")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")
    check(not server2.errors() and not client2.errors(), f"errors: {server2.errors()} {client2.errors()}")


def test_patch_day_check():
    """After a game update, flags the guide watches that no longer exist are reported."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    check(client.eval("return CR.UI.h.gone.Visible") is False, "nothing to report on an unchanged game")

    def recheck():
        server.eval("CR.Server.GameDataChecked = nil CR.Server.CheckGameData() CR.Server.MarkDirty()")
        sim.run(max_ms=1000)

    gone = ("NIGHT_Karlach_ANightAtTheTown", "ORI_Shadowheart_State_SharPath")
    for name in gone:
        server.mock.MissingFlags[FLAG[name]] = True
    recheck()
    check(server.eval("return #CR.Server.MissingFlags") == 2, "two watched flags are gone")
    label = str(client.eval("return CR.UI.h.gone.Label"))
    check(client.eval("return CR.UI.h.gone.Visible") is True and "2 of the things" in label, f"the window says so: {label}")
    warned = " ".join(msg for kind, msg in server.logs if kind == "warn")
    check(all(name in warned for name in gone), "the console names them")

    # if the lookup itself does not work, the mod claims nothing
    server.mock.StaticDataWorks = False
    recheck()
    check(server.eval("return #CR.Server.MissingFlags") == 0, "an unusable lookup reports nothing")
    check(client.eval("return CR.UI.h.gone.Visible") is False, "and the warning disappears")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


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

    # where notices appear: MCM keeps the choice text, the mod its own key; numbers are clamped
    client.lua.eval("function() __mcm.values.notify_position = 'Left, middle' __mcm.values.notify_x = 250 end")()
    client.lua.eval("__mcmFire")(client.to_lua({"modUUID": "9f8b2c41-7a63-4d8e-9b5a-1c8e5f2a3d4e",
                                                "settingId": "notify_position", "value": "Left, middle"}))
    check(client.eval('return CR.Settings.Get("toastPosition")') == "left-middle", "MCM's position choice should apply")
    check(client.eval('return CR.Settings.Get("toastX")') == 100, "an out-of-range MCM slider value is clamped")
    client.eval('CR.Settings.Set("toastPosition", "custom")')
    check(client.lua.eval("__mcm.values.notify_position") == "Custom (use the sliders)", "the overlay's choice goes to MCM")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def visible_labels(client, element_expr):
    """Labels of the live children of a UI element, one per line."""
    return str(client.eval(f"""
        local out = {{}}
        for _, c in ipairs(rawget({element_expr}, "__children")) do
            if not rawget(c, "__destroyed") and c.Visible then out[#out + 1] = c.Label end
        end
        return table.concat(out, "\\n")
    """))


def test_dead_before_joining():
    """A companion killed before recruitment is lost (bg3.wiki 'Dead'), except Wyll and Lae'zel."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    world.dead.add(UUID["Astarion"])    # killed on the beach, never recruited
    world.dead.add(UUID["Wyll"])        # fell at the Grove gate: can still be revived
    world.dead.add(UUID["Minthara"])    # "dead" flag but knocked out: the good-path route
    world.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def comp(name):
        return str(client.eval(f"""
            local c = CR.Client.Snapshot.comps.{name}
            return tostring(c.lost) .. "/" .. tostring(c.dead) .. "/" .. tostring(c.why)
        """))
    check(comp("Astarion") == "true/true/died", f"Astarion should be lost because he died: {comp('Astarion')}")
    check(comp("Wyll") == "false/true/nil", f"Wyll can be revived before joining: {comp('Wyll')}")
    check(comp("Minthara") == "false/true/nil", f"a knocked-out Minthara is not lost: {comp('Minthara')}")
    check(step_status(client, "AST_A1_RECRUIT") == "M", "Astarion's recruitment should be missed")
    check(client.eval("return CR.UI.sidebar.Astarion.info.Label") == "Died before joining", "sidebar text for Astarion")
    check(client.eval("return CR.UI.sidebar.Wyll.info.Label") == "Dead - can be revived", "sidebar text for Wyll")

    # the warnings no longer ask to recruit Astarion, and explain how to get Wyll back
    warnings = visible_labels(client, "CR.UI.h.warnBody")
    check("Astarion" not in warnings, "a dead, never-recruited Astarion must not be listed as recruitable")
    check("Wyll is dead" in warnings and "Scroll of Revivify" in warnings, f"Wyll's revival hint is missing: {warnings}")

    client.eval('CR.UI.Select("Astarion")')
    notice = str(client.eval("return CR.UI.page.notice.Label"))
    check("died before joining you" in notice, f"page notice for Astarion: {notice}")
    state = str(client.eval("return CR.UI.page.steps.AST_A1_RECRUIT.state.Label"))
    check(state == "Missed: Astarion died before joining you", f"step explanation: {state}")
    client.eval('CR.UI.Select("Wyll")')
    check("goblin attack" in str(client.eval("return CR.UI.page.notice.Label")), "Wyll's page should explain the revival")

    # a recruited companion who dies and is revived: the Resurrected event refreshes the state
    name = "S_Player_ShadowHeart_" + UUID["Shadowheart"]
    world.dead.add(UUID["Shadowheart"])
    server.mock.FireOsiris("Died", name)
    sim.run(max_ms=1000)
    check(comp("Shadowheart") == "false/true/nil", "a dead recruited companion is dead, not lost")
    check(client.eval("return CR.UI.sidebar.Shadowheart.info.Label").startswith("Dead - revive"), "sidebar: revive")
    world.dead.discard(UUID["Shadowheart"])
    server.mock.FireOsiris("Resurrected", name)
    sim.run(max_ms=1000)
    check(comp("Shadowheart") == "false/false/nil", "the Resurrected event should clear the dead state")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_spoiler_setting():
    """Golden rules, romance notes and tracker details respect the spoiler setting."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def notes(which):
        return str(client.eval(f"""
            local g, shown, hidden = CR.UI.page.{which}, {{}}, 0
            for _, it in ipairs(g.items) do
                if it.line.Visible and it.mark.Visible then shown[#shown + 1] = it.note.act else hidden = hidden + 1 end
            end
            return table.concat(shown, ",") .. "|" .. hidden .. "|" .. (g.hidden.Visible and g.hidden.Label or "")
        """))

    # nothing from later acts is revealed before the player has chosen
    hidden = "1|6|6 more for later acts are hidden by your spoiler setting."
    check(client.eval("return CR.UI.h.firstRun.Visible") is True, "the first-run spoiler question should be shown")
    check(notes("rules") == hidden, f"unanswered: later-act rules must stay hidden: {notes('rules')}")

    # answering "Everything" reveals all of it and removes the question
    click(client, sim, "Everything")
    check(client.eval('return CR.Settings.Get("spoilers")') == "full", "the answer should set the spoiler level")
    check(client.eval("return CR.UI.h.firstRun.Visible") is False, "the question should disappear once answered")
    check(notes("rules") == "1,2,2,2,2,3,3|0|", f"'Everything' shows every rule: {notes('rules')}")
    check(notes("common") == "0,0,1,2,2,3,3|0|", f"'Everything' shows every shared rule: {notes('common')}")

    # "titles": only what the player has reached
    client.eval('CR.Settings.Set("spoilers", "titles")')
    check(notes("rules") == hidden, f"Act 1: only the Act 1 rule may be visible: {notes('rules')}")
    check(notes("common") == "0,0,1|4|4 more for later acts are hidden by your spoiler setting.", f"Act 1 shared rules: {notes('common')}")
    check(notes("notes").startswith("1,1|4|"), f"Act 1: only Act 1 romance notes: {notes('notes')}")
    counter = str(client.eval("return CR.UI.page.counters[1].label.Label"))
    check(counter.startswith("A hidden score"), f"the tracker's name is a spoiler in Act 1: {counter}")
    check(client.eval("return CR.UI.page.counters[1].items[4].line.Label") == "A later moment", "Act 2 tracker items are masked")
    check(client.eval("return CR.UI.page.counters[1].items[1].line.Label") != "A later moment", "Act 1 tracker items are shown")

    # reaching Act 2 reveals the Act 2 entries, still not Act 3
    world.set_flag("VISITEDREGION_SCL_Main_A")
    world.set_level("SCL_Main_A")
    server.mock.FireOsiris("FlagSet", "VISITEDREGION_SCL_Main_A_" + FLAG["VISITEDREGION_SCL_Main_A"], "NULL_" + NULL, 0)
    sim.run(max_ms=1000)
    check(client.eval("return CR.Client.Snapshot.act") == 2, "the save should now be in Act 2")
    check(notes("rules") == "1,2,2,2,2|2|2 more for later acts are hidden by your spoiler setting.", f"Act 2 rules: {notes('rules')}")
    check(notes("common") == "0,0,1,2,2|2|2 more for later acts are hidden by your spoiler setting.", f"Act 2 shared rules: {notes('common')}")
    check(str(client.eval("return CR.UI.page.counters[1].label.Label")).startswith("Nightsong points"), "Act 2 reveals the tracker")

    client.eval('CR.Settings.Set("spoilers", "full")')
    check(notes("rules") == "1,2,2,2,2,3,3|0|", "showing everything brings all rules back")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_notices_wait_for_conversations():
    world, sim, server, client = test_boot_and_snapshot()

    def toasts():
        return client.eval("local n = 0 for _ in ipairs(CR.Toasts.queue) do n = n + 1 end return n")

    world.dbs["DB_DialogPlayers"] = [(7, AVATAR, 1)]   # the player is in a conversation
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_State_DatingShadowheart_" + FLAG["ORI_State_DatingShadowheart"], AVATAR, 7)
    sim.run(max_ms=2500)
    check(step_status(client, "SH_A1_PARTY") == "D", "the step itself updates at once")
    check(toasts() == 0, "no notice may pop up during a conversation")
    world.dbs["DB_DialogPlayers"] = []
    server.mock.FireOsiris("DialogEnded", "CAMP_Shadowheart_Dialog_" + "0" * 36, 7)
    sim.run(max_ms=2500)
    check(toasts() >= 1, "the notice should arrive once the conversation has ended")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_plain_words_and_optional_label():
    """'Detected' lines quote the journal in plain words; optional steps get their own label."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    target = str(client.eval("""
        for _, step in ipairs(CR.Guides.Get("Shadowheart").steps) do
            local c = step.done[1]
            if c and c.k == "q" and step.act <= 1 then return step.id .. "|" .. c.quest .. "|" .. c.step end
        end
    """))
    step_id, quest, step = target.split("|")
    world.quest(quest, step)
    # the game's text has typographic characters the IMGUI font cannot draw, and markup
    client.mock.Loca["htest"] = "Shadowheart’s wound — it… <i>hurts</i>. A second sentence that is not needed here."
    client.eval(f'CR.JournalHandles["{quest}/{step}"] = "htest"')
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    check(step_status(client, step_id) == "D", f"{step_id} should be detected through its journal step")
    line = str(client.eval(f'return CR.UI.page.steps["{step_id}"].state.Label'))
    check(line.startswith('Detected: your journal says "Shadowheart\'s wound - it... hurts.'), f"journal quote: {line}")
    check("_" not in line and "ORI_" not in line, f"no internal names in the explanation: {line}")

    # without a handle the quest title is used; flags get a plain sentence
    client.eval(f'CR.JournalHandles["{quest}/{step}"] = nil CR.UI.Select("Shadowheart")')
    line = str(client.eval(f'return CR.UI.page.steps["{step_id}"].state.Label'))
    check(line.startswith("Detected: an entry in your journal"), f"fallback wording: {line}")
    recruit = str(client.eval('return CR.UI.page.steps.SH_A1_RECRUIT.state.Label'))
    check("_" not in recruit and recruit.startswith("Detected: "), f"flag evidence in plain words: {recruit}")

    # an optional step that can be done now is labelled OPTIONAL, not TO DO
    optional = client.eval("""
        for id, s in pairs(CR.UI.page.steps) do
            if s.step.optional and CR.Client.Snapshot.steps[id][1] == "A" then return s.status.Label end
        end
    """)
    check(optional == "OPTIONAL", f"optional available steps should say OPTIONAL (got {optional})")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_portraits_and_esc():
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    world.dead.add(UUID["Astarion"])
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    def tint(lua_expr):
        return str(client.eval(f"local t = {lua_expr} return string.format('%.2f,%.2f,%.2f,%.2f', t[1], t[2], t[3], t[4])"))

    def shown(name, where="sidebar"):
        """What the picture is: a texture id from the mod's texture bank, or a game icon name."""
        holder = f"CR.UI.sidebar.{name}.img" if where == "sidebar" else "CR.UI.page.portrait"
        return str(client.eval(f"local d = {holder}.img.ImageData return d.Icon or d.TextureResource"))

    def pic(name, mood):
        return str(client.eval(f"return CR.Theme.Portraits.{name}.{mood}"))

    def refresh():
        server.eval("CR.Server.MarkDirty()")
        sim.run(max_ms=1000)

    NORMAL, FADED = tint("CR.Theme.PortraitTint.normal"), tint("CR.Theme.PortraitTint.lost")
    skull = str(client.eval("return CR.Theme.GameIcons.dead"))

    # every companion has a picture, and at the start it is the neutral one
    missing = client.eval("""
        local out = {}
        for _, comp in ipairs(CR.Guides.Companions) do
            local p = CR.UI.sidebar[comp.id].img
            if not (p and p.img) then out[#out + 1] = comp.id end
        end
        return table.concat(out, ",")
    """)
    check(missing == "", f"companions without a portrait: {missing}")
    check(shown("Shadowheart") == pic("Shadowheart", "neutral"), "Shadowheart at 0 approval: neutral")
    check(client.eval("return CR.UI.page.portrait ~= nil") is True, "the page header should have a portrait")

    # Astarion died before joining: the game's own 'dead' icon, at full strength
    check(shown("Astarion") == skull, f"a dead companion without a dead sticker shows the skull: {shown('Astarion')}")
    check(tint("CR.UI.sidebar.Astarion.img.img.Tint") == NORMAL, "the skull is not faded")

    # approval: pleased from the game's 'High' tier up, sour from 'Low' down
    sh = UUID["Shadowheart"]
    for approval, mood in ((40, "neutral"), (41, "high"), (82, "high"), (-19, "neutral"), (-20, "low")):
        world.approval[sh] = approval
        refresh()
        check(shown("Shadowheart") == pic("Shadowheart", mood), f"Shadowheart at {approval} approval should look {mood}")
    check(shown("Shadowheart", "page") == pic("Shadowheart", "low"), "the page header follows the mood too")

    # a romance outranks approval (Shadowheart has no romance sticker: the pleased one is used)
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    refresh()
    check(shown("Shadowheart") == pic("Shadowheart", "high"), "dating, whatever the approval: the warm picture")
    # and death outranks everything
    name = "S_Player_ShadowHeart_" + sh
    world.dead.add(sh)
    server.mock.FireOsiris("Died", name)
    sim.run(max_ms=1000)
    check(shown("Shadowheart") == skull, "dead, even while dating: the skull")
    world.dead.discard(sh)
    server.mock.FireOsiris("Resurrected", name)
    sim.run(max_ms=1000)
    check(shown("Shadowheart") == pic("Shadowheart", "high"), "revived: back to the warm picture")

    # Lae'zel has a 'dead' sticker of her own, and must not show it while alive
    laezel = "S_Player_Laezel_" + UUID["Laezel"]
    world.set_flag("GLO_Origin_PartOfTheTeam_Laezel")
    refresh()
    check(shown("Laezel") == pic("Laezel", "neutral") and pic("Laezel", "neutral") != pic("Laezel", "dead"),
          "a living Lae'zel shows her neutral picture")
    world.dead.add(UUID["Laezel"])
    server.mock.FireOsiris("Died", laezel)
    sim.run(max_ms=1000)
    check(shown("Laezel") == pic("Laezel", "dead"), "a dead Lae'zel shows her own 'dead' sticker, not the skull")
    world.dead.discard(UUID["Laezel"])
    server.mock.FireOsiris("Resurrected", laezel)
    sim.run(max_ms=1000)
    check(shown("Laezel") == pic("Laezel", "neutral"), "a revived Lae'zel shows her neutral picture again")

    # gone for good but alive: the sour picture, faded
    world.quest("ORI_COM_Karlach", "CompanionLowRelation")
    refresh()
    check(shown("Karlach") == pic("Karlach", "low"), "Karlach left for good: her sour picture")
    check(tint("CR.UI.sidebar.Karlach.img.img.Tint") == FADED, "and it is faded")
    check(tint("CR.UI.sidebar.Shadowheart.img.img.Tint") == NORMAL, "others are not")

    # the rules themselves (T.Mood), including the fallbacks for missing stickers
    def mood(lua_table):
        return str(client.eval(f"return CR.Theme.Mood({lua_table})"))
    check(mood("nil") == "neutral" and mood("{ you = true, dead = true }") == "neutral", "no data, or your own character: neutral")
    check(mood("{ rec = false, a = 90 }") == "neutral", "approval only counts for a companion who has joined")
    check(mood("{ rec = true, a = 90, rel = 'partnered' }") == "partnered", "partnered")
    check(mood("{ rec = true, a = 90, rel = 'ex' }") == "high", "an ex is judged by approval")
    for comp, m, expected in (("Astarion", "partnered", "partnered"), ("Astarion", "dating", "dating"), ("Astarion", "high", "neutral"),
                              ("Wyll", "partnered", "dating"), ("Gale", "partnered", "dating"), ("Karlach", "high", "neutral"),
                              ("Minsc", "low", "neutral"), ("Halsin", "dating", "dating")):
        got = str(client.eval(f'return CR.Theme.PortraitFor("{comp}", "{m}")'))
        check(got == pic(comp, expected), f"{comp} when {m} should use the '{expected}' picture")
    check(str(client.eval('return CR.Theme.PortraitFor("Minsc", "dead")')) == skull, "no dead sticker: the skull")
    # portraits can be switched off; the window keeps working
    client.eval('CR.Settings.Set("portraits", false)')
    check(client.eval("return CR.UI.sidebar.Shadowheart.img == nil and CR.UI.page.portrait == nil") is True,
          "switching portraits off should remove the pictures")
    check(client.eval("return CR.UI.sidebar.Shadowheart.info.Label") != "", "the list still shows each companion's state")
    client.eval('CR.Settings.Set("portraits", true)')
    check(client.eval("return CR.UI.sidebar.Shadowheart.img ~= nil") is True, "and back on again")

    # Esc closes the window (and can be turned off)
    press(client, sim, "ESCAPE")
    check(client.eval("return CR.UI.IsOpen()") is False, "Esc should close the roadmap")
    client.eval('CR.Settings.Set("escCloses", false) CR.UI.SetOpen(true)')
    press(client, sim, "ESCAPE")
    check(client.eval("return CR.UI.IsOpen()") is True, "with the option off, Esc leaves the roadmap open")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_report_file_and_replay():
    """The report file contains enough to rebuild the same statuses in a fresh world."""
    world, sim, server, client = make()
    for f in ("GLO_Origin_PartOfTheTeam_Shadowheart", "GLO_Origin_PartOfTheTeam_Karlach", "GLO_Origin_PartOfTheTeam_Gale",
              "VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A", "NIGHT_GoblinHunt_TieflingCelebration",
              "ORI_Shadowheart_State_NightsongPoint_AteNoblestalk", "HAV_PartyProgress_EnteredHaven"):
        world.set_flag(f)
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    world.set_level("SCL_Main_A")
    world.approval[UUID["Shadowheart"]] = 47
    world.approval[UUID["Karlach"]] = -12
    world.quest("ORI_COM_ShadowHeart", "Recruited_Beach")
    world.quest("ORI_COM_Karlach_SUB_ForgingOfTheHeart", "WaitForNextAct")
    world.dead.add(UUID["Astarion"])
    world.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    world.dbs["DB_ORI_Dating"] = [(AVATAR, UUID["Shadowheart"])]
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    client.eval('CR.Client.SetOverride("SH_A1_IDOL", true)')
    sim.run()

    # the Options button asks the server to write the file
    click(client, sim, "Create a report file")
    result = str(client.eval("return CR.UI.h.reportResult.Label"))
    check(result.startswith("Saved (") and "report.json" in result, f"the button should confirm the file: {result}")
    raw = server.mock.Files["CompanionRoadmap/report.json"]
    check(raw is not None, "the server should write CompanionRoadmap/report.json")
    report = json.loads(str(raw))
    for key in ("format", "mod", "level", "act", "avatar", "steps", "raw", "overrides"):
        check(key in report, f"report is missing '{key}'")
    check(report["act"] == 2 and report["level"] == "SCL_Main_A", "report should record where the save is")
    check(report["overrides"] == ["SH_A1_IDOL"], f"report should list manual check-offs: {report['overrides']}")
    check(report["raw"]["companions"]["Astarion"]["dead"] is True, "report should record raw companion facts")
    check("ORI_COM_ShadowHeart/Recruited_Beach" in report["raw"]["quests"], "report should list unlocked journal steps")
    text = json.dumps(report)
    check("Tav" not in text and "\\\\Users" not in text, "the report must not contain names or paths")

    # the console command writes the same file
    server.mock.Files["CompanionRoadmap/report.json"] = None
    server.mock.ConsoleCommands["roadmap"]("roadmap", "report")
    check(server.mock.Files["CompanionRoadmap/report.json"] is not None, "!roadmap report should write the file")

    # replay: a fresh world built only from the report gives the same statuses
    expected = {step: value[0] for step, value in report["steps"].items()}
    _, _, server2, client2 = replay_report(report)
    actual = all_statuses(client2)
    diff = {k: (expected[k], actual.get(k)) for k in expected if actual.get(k) != expected[k]}
    check(not diff, f"replaying the report should reproduce every status; differences: {diff}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")
    check(not server2.errors() and not client2.errors(), f"replay errors: {server2.errors()} {client2.errors()}")


def test_report_fixtures():
    """Real report files (tests/fixtures/*.json) replay without errors and meet their expectations.

    A fixture may contain an "expect" object ({ stepId: status }) written by a maintainer;
    statuses recorded by an older mod version are informational only."""
    if not os.path.isdir(FIXTURES):
        return
    for name in sorted(os.listdir(FIXTURES)):
        if not name.endswith(".json"):
            continue
        report = json.load(open(os.path.join(FIXTURES, name), encoding="utf-8"))
        _, _, server, client = replay_report(report)
        check(not server.errors() and not client.errors(), f"{name}: errors {server.errors()} {client.errors()}")
        actual = all_statuses(client)
        for step_id, status in (report.get("expect") or {}).items():
            check(actual.get(step_id) == status, f"{name}: {step_id} should be {status}, got {actual.get(step_id)}")


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


# Camp scenes as the Patch 8 story declares them (Act3_OriginMoments_*, Act3b_ORI_Halsin,
# Act3_ORI_Gale, GLO_Origin_Laezel_PostEA, Act1_DaisyDreams); GUIDs from the game's flag table.
N_KARLACH_DATE = ("NIGHT_Karlach_ANightAtTheTown", "8d07ffbd-868d-468b-9ac0-84f2d8adaeaa")
N_SWIM = ("NIGHT_Shadowheart_Skinnydipping", "9f583304-0a1a-498c-acf9-3c8dcc30ee3d")
N_HALSIN = ("NIGHT_Halsin_Romance_Execution", "a9634ef4-27ec-4a75-be9d-7c738d9768ed")
N_GALE_GOD = ("NIGHT_Gale_BeMyGod", "2259ec28-b538-4895-a431-30dc7e2ddf66")
N_DAISY = ("NIGHT_DaisyMissionStatement", "287c7434-5031-46f2-9b7b-4999a2349081")
N_VLAAKITH = ("NIGHT_Laezel_VlaakithVisit", "254a4c0b-9fd2-4b41-97e9-5f60e338e062")
N_KARLACH_GORTASH = ("NIGHT_Karlach_AfterDefeatingGortash", "b8e239e4-e73e-433e-9550-e4a56bdbffd1")
F_BARTENDER = ("CAMP_Karlach_State_AnyBartenderAvailable", "63cdf812-c71e-4acb-b161-5893c912a0c2")
F_SHAR_ENEMY = ("ORI_Shadowheart_State_EnemyOfSharPath", "055bbe0f-05f5-444b-a7e2-0f66edd2178c")
F_KNOWS_SWIM = ("ORI_Shadowheart_Knows_PersonalInfo", "abbc836e-07f0-4951-bb7b-beac52d91b2a")
F_SWIM_SCENE = ("ORI_Shadowheart_Event_SkinnyDippingRomanceScene", "3437a073-b92a-4999-b6b9-e7745865a0c2")
F_HALSIN_REQ = ("CAMP_Halsin_SexRequirement", "67e75062-a7a1-0f42-80f3-1cc02ba36fa1")
F_HALSIN_WAIT = ("CAMP_Halsin_State_WaitForKarlachUpgraded", "9e2e8aaa-dcb6-3541-8e51-dd23cdac16b0")
F_KARLACH_UP2 = ("GLO_ForgingOfTheHeart_State_KarlachSecondUpgrade", "f6dc0de4-1089-43c0-b392-306a9a44387c")
F_KARSUS_NOTES = ("ORI_Gale_Knows_ReadKarsusNotes", "2b0e541f-f49e-7e82-27d6-15fccd6ff1ff")
F_GALE_COMPANION = ("GALECOMPANION", "53fe9349-fc4e-433f-8701-e0aabb414906")
F_LAEZEL_COMPANION = ("LAEZELCOMPANION", "9c5bc0ce-cb2e-4685-b597-89a290837535")
F_LAEZEL_CAMP = ("LAEZELCAMP", "3a157c66-db4a-48ad-95e5-9659c42c4aa0")
F_LAEZEL_AVATAR = ("LAEZELAVATAR", "cea30880-6e09-4daa-ad17-5411885097f3")
F_SEND_KARLACH = ("WYR_GortashConfrontation_Event_SendKarlachToCamp", "7a52ef44-835d-4af9-0388-cdd1036a09ed")
ACT1_CAMPS = ("WLDMAIN", "WLDCAVGRN", "WLDCAVSND", "WLDDUNABB", "WLDDUNSHA", "WLDUND", "WLDBAS", "CREMAIN", "CREINSIDE")


def set_global(world, flag):
    """Sets a global flag given as (name, guid), for flags the guide itself does not use."""
    world.flags.add((flag[1], NULL))


def camp_of(client):
    return json.loads(str(client.eval("return Ext.Json.Stringify(CR.Client.Snapshot.camp or {})")))


def act3_camp_world():
    """An Act 3 save at the Elfsong Tavern camp, partnered with Karlach, with the guide's camp scenes declared."""
    world = World()
    for name in ("Shadowheart", "Karlach", "Gale", "Halsin", "Laezel"):
        world.set_flag("GLO_Origin_PartOfTheTeam_" + name)
        world.dbs["DB_PartOfTheTeam"].append((CHAR[name],))
    for f in ("VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A", "VISITEDREGION_BGO_Main_A", "VISITEDREGION_CTY_Main_A"):
        world.set_flag(f)
    world.set_level("CTY_Main_A")
    world.dbs["DB_Camp_Unlocked"] = [(1,)]
    world.dbs["DB_ActiveCamp"] = [("ELFSONG",)]
    world.dbs["DB_ORI_Partnered"] = [(AVATAR, CHAR["Karlach"])]
    world.set_flag("ORI_State_PartneredWithKarlach", AVATAR)
    world.approval[UUID["Karlach"]] = 30          # exactly the date's value: the scheduler asks for at least
    world.approval[UUID["Shadowheart"]] = 31
    set_global(world, F_BARTENDER)
    set_global(world, F_SHAR_ENEMY)
    lower_city = ("SLUMS", "ELFSONG")
    act3 = ("FARM", "SLUMS", "ELFSONG")
    add_scene(world, *N_KARLACH_DATE, 4170, lower_city, crd=["Karlach"], req=[[F_BARTENDER]],
              approval=[("Karlach", 30)], partner=["Karlach"])
    add_scene(world, *N_SWIM, 4110, act3, crd=["Shadowheart"], req=[[F_SHAR_ENEMY, F_KNOWS_SWIM]],
              approval=[("Shadowheart", 40)], partner=["Shadowheart"], romance=[("Shadowheart", F_SWIM_SCENE)])
    add_scene(world, *N_HALSIN, 4240, act3, req=[[F_HALSIN_REQ], [F_HALSIN_WAIT, F_KARLACH_UP2]],
              partner=["Halsin"], romance=[("Halsin", None)], expires=2)
    add_scene(world, *N_GALE_GOD, 4180, act3, crd=["Gale"], req=[[F_KARSUS_NOTES, F_GALE_COMPANION]], partner=["Gale"])
    add_scene(world, *N_DAISY, 7090, ACT1_CAMPS, dream=True)
    return world


def test_tonight_at_camp():
    """'Tonight at camp' repeats the game's own camp-scene selection (GLO_CampNights): the
    most important scene whose requirements hold, then any that do not clash with it."""
    world, sim, server, client = make(act3_camp_world())
    # earlier steps the scenes wait for in the guide, checked off by hand; the wolf talk
    # too, although the game never recorded what the swim needs from it
    for sid in ("HAL_A2_CURSE", "GALE_A2_STARS", "GALE_A3_KARSUS", "SH_A1_WOLF", "SH_A2_PARTNER"):
        server.eval(f'CR.Server.SetOverride("{sid}", true)')
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()

    def refresh():
        server.eval("CR.Server.MarkDirty()")
        sim.run(max_ms=1000)

    camp = camp_of(client)
    check(camp.get("ok") is True and camp.get("at") == "ELFSONG", f"the prediction runs at the active camp: {camp}")
    tonight = [t.get("s") for t in camp["tonight"]]
    check(tonight == ["KAR_A3_DATE"], f"only Karlach's date meets its requirements tonight: {tonight}")
    steps = camp["steps"]
    check(steps["KAR_A3_DATE"].get("t") == 1, "the date is marked as tonight")
    swim = steps["SH_A3_SWIM"]["b"]
    check(["a", "Shadowheart", 40, 31] in swim, f"the swim needs 40 approval, you have 31: {swim}")
    check(["p", "Shadowheart"] in swim, f"... and her partner: {swim}")
    check(["f", 1, "SH_A1_WOLF"] in swim, f"... and the wolf talk (she cannot swim), named as a step: {swim}")
    halsin = steps["HAL_A3_ROMANCE"]["b"]
    check(["p", "Halsin"] in halsin and any(b[0] == "f" for b in halsin), f"Halsin's night: partner and story: {halsin}")
    check("x" not in steps["HAL_A3_ROMANCE"], "its two-night window has not started: requirements are not met")
    check(not any(t.get("d") for t in camp["tonight"]), "an Act 1 dream does not play at an Act 3 camp")

    # Lae'zel's Vlaakith visit (a campfire moment) is more important and plays alongside the date
    add_scene(world, *N_VLAAKITH, 5080, ("FARM", "SLUMS", "ELFSONG"), cfm=True,
              req=[[F_LAEZEL_COMPANION], [F_LAEZEL_CAMP], [F_LAEZEL_AVATAR]])
    world.dbs["DB_CampNight"].insert(0, world.dbs["DB_CampNight"].pop())   # the game's table has no order
    set_global(world, F_LAEZEL_COMPANION)
    refresh()
    tonight = [t.get("s") for t in camp_of(client)["tonight"]]
    check(tonight == ["LAE_A3_VLAAKITH", "KAR_A3_DATE"], f"two scenes that do not clash both play, most important first: {tonight}")

    # a more important conversation with Karlach takes her evening: the date waits for another night
    add_scene(world, *N_KARLACH_GORTASH, 5500, ("FARM", "SLUMS", "ELFSONG"), crd=["Karlach"], req=[[F_SEND_KARLACH]])
    set_global(world, F_SEND_KARLACH)
    refresh()
    camp = camp_of(client)
    tonight = [t.get("s") or t.get("c") for t in camp["tonight"]]
    check(tonight == ["Karlach", "LAE_A3_VLAAKITH"], f"Karlach can only have one conversation a night: {tonight}")
    check(camp["steps"]["KAR_A3_DATE"]["b"] == [["q"]], f"the date is ready but waits: {camp['steps']['KAR_A3_DATE']}")

    # the tab says it in words, and each scene links to its step
    client.eval('CR.UI.Select("Karlach")')
    sim.run()
    tab = visible_labels(client, "CR.UI.h.campBody")
    check("If you rest now" in tab and "A scene with Karlach" in tab and "Vlaakith's visit" in tab,
          f"tonight's scenes in words: {tab!r}")
    check("Ready, but a more important scene comes first" in tab, f"why the date waits: {tab!r}")
    check('Needs 40 approval with Shadowheart (you have 31); you to be Shadowheart\'s partner; '
          '"The wolf memory - learn that she cannot swim" first.' in tab, f"what the swim needs, in words: {tab!r}")
    line = str(client.eval("return CR.UI.page.steps.KAR_A3_DATE.camp.Label"))
    check(line.startswith("Camp scene: Ready, but") and client.eval("return CR.UI.page.steps.KAR_A3_DATE.camp.Visible"),
          f"the step itself says it: {line}")
    link = client.eval("""
        for _, c in ipairs(rawget(CR.UI.h.campBody, "__children")) do
            if rawget(c, "__type") == "Selectable" and string.find(c.Label, "###tw_SH_A3_SWIM", 1, true) then
                c.OnClick(c) return c.Label
            end
        end
    """)
    check(link is not None and client.eval("return CR.UI.selected") == "Shadowheart", "a waiting scene opens its step")
    sim.run()

    # a report replays to the same prediction (the scheduler's tables travel with it)
    server.mock.ConsoleCommands["roadmap"]("roadmap", "report")
    report = json.loads(str(server.mock.Files["CompanionRoadmap/report.json"]))
    check(report.get("scheduler") and report.get("tonight"), "the report carries the scheduler and the prediction")
    _, _, server2, client2 = replay_report(report)
    replayed = camp_of(client2)
    check([t.get("g") for t in replayed["tonight"]] == [t.get("g") for t in report["tonight"]["tonight"]],
          f"replayed prediction: {replayed['tonight']} vs {report['tonight']['tonight']}")
    check(not server2.errors() and not client2.errors(), f"replay errors: {server2.errors()} {client2.errors()}")

    # Halsin's night: a two-night window that started and is nearly over
    world.dbs["DB_CampNight_StartedExpiring"] = [(f"{N_HALSIN[0]}_{N_HALSIN[1]}", 2)]
    refresh()
    check(camp_of(client)["steps"]["HAL_A3_ROMANCE"].get("x") == 1, "one long rest left")
    world.dbs["DB_CampNight_StartedExpiring"] = [(f"{N_HALSIN[0]}_{N_HALSIN[1]}", 1)]
    refresh()
    halsin = camp_of(client)["steps"]["HAL_A3_ROMANCE"]
    check(halsin.get("b") == [["x"]] and halsin.get("x") == 0, f"dropped at the next rest: {halsin}")

    # a romance night needs the companion at camp; a scene the game already played is gone from its tables
    world.dbs["DB_PartOfTheTeam"].remove((CHAR["Karlach"],))
    refresh()
    camp = camp_of(client)
    check(["t", "Karlach"] in camp["steps"]["KAR_A3_DATE"]["b"], f"Karlach is not at camp: {camp['steps']['KAR_A3_DATE']}")
    world.dbs["DB_CampNight"] = [r for r in world.dbs["DB_CampNight"] if not r[0].startswith(N_SWIM[0])]
    refresh()
    check("SH_A3_SWIM" not in camp_of(client)["steps"], "a scene that played or was cancelled is no longer listed")

    # no camp, no prediction
    world.dbs["DB_Camp_Unlocked"] = []
    refresh()
    camp = camp_of(client)
    check(camp.get("ok") is False and camp.get("why") == "locked", f"camp locked: {camp}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_not_interested():
    """A romance marked as not wanted (requested on Nexus): only the moment it can begin stays
    open, as SAY NO; its notices and warnings stop; the choice is kept in the save, per player."""
    world, sim, server, client = make()
    for name in ("Shadowheart", "Karlach"):
        world.set_flag("GLO_Origin_PartOfTheTeam_" + name)
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    client.eval('CR.UI.Select("Shadowheart")')
    sim.run()
    check(step_status(client, "SH_A1_PARTY") in ("N", "A"), f"her romance can begin: {step_status(client, 'SH_A1_PARTY')}")
    nightsong = step_status(client, "SH_A2_NIGHTSONG")
    starts = [l for l in visible_labels(client, "CR.UI.h.warnBody").split("\n") if "Shadowheart" in l]
    check(starts, "before: her romance is among those that can only begin before the Shadowfell")

    # tick the box on her page
    client.eval("local cb = CR.UI.page.noRomance cb.OnChange(cb, true)")
    sim.run()
    check(client.eval("return CR.Client.Snapshot.nr.Shadowheart") is True, "the snapshot says not wanted")
    stored = json.loads(str(server.eval("return Ext.Json.Stringify(Ext.Vars.vars.NoRomance or {})")))
    check(stored == {guid(AVATAR): {"Shadowheart": True}}, f"kept in the save, for this player: {stored}")
    check(step_status(client, "SH_A1_PARTY") == "A", f"the moment it can begin stays open: {step_status(client, 'SH_A1_PARTY')}")
    check(client.eval("return CR.UI.page.steps.SH_A1_PARTY.status.Label") == "SAY NO", "and reads SAY NO")
    state = str(client.eval("return CR.UI.page.steps.SH_A1_PARTY.state.Label"))
    check("turn Shadowheart down" in state, f"it says what to do: {state}")
    check(step_status(client, "SH_A1_WOLF") == "X", f"other romance steps no longer apply: {step_status(client, 'SH_A1_WOLF')}")
    check(step_status(client, "SH_A2_NIGHTSONG") == nightsong, "her story is untouched (Nightsong is a story step)")
    nexts = [k for k, v in all_statuses(client).items() if v == "N" and k.startswith("SH_")]
    check(len(nexts) == 1 and nexts[0] != "SH_A1_PARTY", f"the romance is never the next step: {nexts}")
    starts = [l for l in visible_labels(client, "CR.UI.h.warnBody").split("\n") if "Shadowheart" in l]
    check(not starts, f"no 'can only begin before this point' reminder for her: {starts}")
    check(client.eval("return CR.UI.h.noRomance.Shadowheart.Checked") is True, "Options shows it too")

    # the romance begins anyway (said yes after all): no notice about it
    client.eval("CR.Toasts.queue = {}")
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_State_DatingShadowheart_" + FLAG["ORI_State_DatingShadowheart"], AVATAR, 0)
    sim.run(max_ms=1000)
    check(step_status(client, "SH_A1_PARTY") == "D", "what happened is still shown")
    queued = str(client.eval("local t = {} for _, q in ipairs(CR.Toasts.queue) do t[#t + 1] = q.text end return table.concat(t, '|')"))
    check("wine by the waterfall" not in queued, f"no notice for a romance you did not want: {queued}")

    # untick it in Options: everything is back
    client.eval("local cb = CR.UI.h.noRomance.Shadowheart cb.OnChange(cb, false)")
    sim.run()
    check(client.eval("return CR.Client.Snapshot.nr == nil") is True, "nothing marked any more")
    check(client.eval("return CR.UI.page.noRomance.Checked") is False, "the page checkbox follows")
    check(step_status(client, "SH_A1_WOLF") != "X", "her romance steps are back")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def alert_open(client):
    return client.eval("return CR.Alerts.win ~= nil and CR.Alerts.win.Open") is True


def test_point_of_no_return_alerts():
    """When the game asks 'are you sure?' before a point of no return, a heads-up lists what is
    still open before it, and goes away with the answer."""
    world, sim, server, client = make()
    for f in ("GLO_Origin_PartOfTheTeam_Shadowheart", "GLO_Origin_PartOfTheTeam_Karlach",
              "VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A"):
        world.set_flag(f)
    world.set_flag("ORI_State_DatingShadowheart", AVATAR)
    world.set_level("SCL_Main_A")
    fire_running(client, sim)            # the window stays closed: the heads-up works without it

    # stepping into Nightsong's prison (Act2_SHA_NightsongPrison writes this row with the prompt)
    server.mock.FireOsiris("DB_SHA_NightsongPrison_StartedReadyCheck", AVATAR)
    sim.run(max_ms=1000)
    check(alert_open(client), "the heads-up appears with the game's prompt")
    text = visible_labels(client, "CR.Alerts.win")
    check("Before you go on: Act 1 locks for good when you enter the Shadowfell" in text, f"which point: {text!r}")
    check("Shadowheart  ·  " in text and "Press F7 to review everything" in text, f"what is open, and how to see more: {text!r}")
    client.eval("CR.Toasts.Preview()")
    check(client.eval("return CR.Toasts.win.Open") is False, "notices wait while the heads-up is up")
    server.mock.FireOsiris("ReadyCheckFailed", "ReadyCheck_EnterNightsongPrison")
    sim.run(max_ms=1000)
    check(not alert_open(client), "answering the prompt closes it")
    check(client.eval("return CR.Toasts.win.Open") is True, "and the notice that waited shows")

    # region changes only matter when they are points of no return
    server.mock.FireOsiris("DB_GLO_LevelSwap_ReadyCheck", AVATAR, "WaypointTravel_RegionSwap")
    sim.run(max_ms=1000)
    check(not alert_open(client), "travelling by waypoint is not a point of no return")
    server.mock.FireOsiris("DB_GLO_LevelSwap_ReadyCheck", AVATAR, "ReadyCheck_ToBGFromSCL")
    sim.run(max_ms=1000)
    check(alert_open(client) and "Leaving Act 2 for Baldur's Gate" in visible_labels(client, "CR.Alerts.win"),
          "leaving for Baldur's Gate")
    server.mock.FireOsiris("ReadyCheckPassed", "ReadyCheck_EnterNightsongPrison")   # another prompt's answer
    sim.run(max_ms=1000)
    check(alert_open(client), "only the answer to this prompt closes it")
    server.mock.FireOsiris("ReadyCheckPassed", "ReadyCheck_ToBGFromSCL")
    sim.run(max_ms=1000)
    check(not alert_open(client), "passed: closed")

    # the Colony from Moonrise's roof, and the Morphic Pool
    server.mock.FireOsiris("DB_MOO_Roof_ColonyTeleporterActivator", AVATAR, "MOO_Assault_ReadyCheck")
    sim.run(max_ms=1000)
    check("Act 2 ends when you go down into the Mind Flayer Colony" in visible_labels(client, "CR.Alerts.win"), "the Colony")
    server.mock.FireOsiris("ReadyCheckFailed", "MOO_Assault_ReadyCheck")
    sim.run(max_ms=1000)
    # Wyrm's Rock into the Lower City; once it was entered, that prompt is no longer a point of no return
    world.set_level("BGO_Main_A")
    world.set_flag("VISITEDREGION_BGO_Main_A")
    server.mock.FireOsiris("DB_GLO_LevelSwap_ReadyCheck", AVATAR, "ReadyCheck_ToLOWFromWYR")
    sim.run(max_ms=1000)
    check("Entering the Lower City" in visible_labels(client, "CR.Alerts.win"), "the Lower City")
    server.mock.FireOsiris("ReadyCheckPassed", "ReadyCheck_ToLOWFromWYR")
    sim.run(max_ms=1000)
    world.set_level("CTY_Main_A")
    world.set_flag("VISITEDREGION_CTY_Main_A")
    server.mock.FireOsiris("DB_GLO_LevelSwap_ReadyCheck", AVATAR, "ReadyCheck_ToLOWFromWYR")
    sim.run(max_ms=1000)
    check(not alert_open(client), "a point already passed brings no heads-up")
    server.mock.FireOsiris("ReadyCheckPassed", "ReadyCheck_ToLOWFromWYR")
    sim.run(max_ms=1000)
    server.mock.FireOsiris("DB_END_ToMorphicPool_BoatUser", AVATAR)
    sim.run(max_ms=1000)
    check("The final assault on the Netherbrain" in visible_labels(client, "CR.Alerts.win"), "the Morphic Pool")
    # a prompt whose answer never arrives does not stay forever
    sim.run(max_ms=200000)
    check(not alert_open(client), "the heads-up times out")

    # switched off
    client.eval('CR.Settings.Set("warnReadyChecks", false)')
    server.mock.FireOsiris("DB_SHA_NightsongPrison_StartedReadyCheck", AVATAR)
    sim.run(max_ms=1000)
    check(not alert_open(client), "the setting switches it off")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def test_knockout_reminder():
    """A fight with Minthara or Minsc while knocking them out is still open brings a reminder."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    fire_running(client, sim)
    minthara = "S_GOB_DrowCommander_" + UUID["Minthara"]

    # on the evil path she fights beside you: no reminder
    server.mock.FireOsiris("EnteredCombat", minthara, "combat-1")
    sim.run(max_ms=1000)
    check(not alert_open(client), "no reminder when she is not your enemy")
    world.enemies.add((UUID["Minthara"], guid(AVATAR)))
    server.mock.FireOsiris("EnteredCombat", minthara, "combat-2")
    sim.run(max_ms=1000)
    check(alert_open(client), "a fight against her while the good path is open")
    text = visible_labels(client, "CR.Alerts.win")
    check("Minthara: knock out, do not kill" in text and "Non-Lethal Attacks" in text, f"what to do: {text!r}")
    sim.run(max_ms=31000)
    check(not alert_open(client), "it goes away by itself")

    # knocked out: no more reminders
    world.dbs["DB_KnockedOut"] = [(UUID["Minthara"],)]
    sim.now += 130000                     # past the time a reminder is not repeated
    server.mock.FireOsiris("EnteredCombat", minthara, "combat-3")
    sim.run(max_ms=1000)
    check(not alert_open(client), "nothing to remind once she is knocked out")

    # Minsc in his hideout (Act 3); the setting switches it off
    world.set_flag("VISITEDREGION_BGO_Main_A")
    world.set_flag("VISITEDREGION_CTY_Main_A")
    world.set_level("CTY_Main_A")
    minsc = "S_Player_Minsc_" + UUID["Minsc"]
    world.enemies.add((UUID["Minsc"], guid(AVATAR)))
    server.mock.FireOsiris("EnteredCombat", minsc, "combat-4")
    sim.run(max_ms=1000)
    check(alert_open(client) and "Minsc: knock out" in visible_labels(client, "CR.Alerts.win"), "Minsc too")
    client.eval("CR.Alerts.Hide()")
    client.eval('CR.Settings.Set("koReminder", false)')
    sim.now += 130000
    server.mock.FireOsiris("EnteredCombat", minsc, "combat-5")
    sim.run(max_ms=1000)
    check(not alert_open(client), "the setting switches it off")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")


def tree_texts(client, element_expr):
    """Every live text below a UI element, in order, joined by '|'."""
    return str(client.eval(f"""
        local out = {{}}
        local function walk(e)
            for _, c in ipairs(rawget(e, "__children")) do
                if not rawget(c, "__destroyed") then
                    if rawget(c, "__type") == "Text" then out[#out + 1] = c.Label end
                    walk(c)
                end
            end
        end
        walk({element_expr})
        return table.concat(out, "|")
    """))


def test_approval_log():
    """The last approval changes per companion: by how much, talking with whom, how long ago;
    kept in the save."""
    world, sim, server, client = make()
    world.set_flag("GLO_Origin_PartOfTheTeam_Shadowheart")
    world.set_flag("VISITEDREGION_WLD_Main_A")
    world.approval[UUID["Shadowheart"]] = 20
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    client.eval('CR.UI.Select("Shadowheart")')
    sim.run()
    check(client.eval("return CR.UI.page.alog.Visible") is False, "nothing logged yet: no section")
    shadowheart = CHAR["Shadowheart"]

    def change(value):
        world.approval[UUID["Shadowheart"]] = value
        server.mock.FireOsiris("ApprovalRatingChanged", shadowheart, AVATAR, value)
        sim.run(max_ms=1000)

    # in a conversation with Karlach (DB_DialogPlayers / DB_DialogNPCs, as the story keeps them)
    world.dbs["DB_DialogPlayers"] = [(7, AVATAR, 1)]
    world.dbs["DB_DialogNPCs"] = [(7, CHAR["Karlach"], 1)]
    change(22)
    # with someone who is not a companion: the game's own name for them, in the player's language
    zevlor = "abcdefab-1234-5678-9abc-def012345678"
    handle = "h11111111g2222g3333g4444g555555555555"
    world.dbs["DB_DialogPlayers"] = [(8, AVATAR, 1)]
    world.dbs["DB_DialogNPCs"] = [(8, "S_DEN_Zevlor_" + zevlor, 2), (8, CHAR["Karlach"], 3)]
    world.names[zevlor] = handle + ";1"
    client.mock.Loca[handle] = "Zevlor"
    change(17)
    # a long rest later, outside any conversation
    world.dbs["DB_DialogPlayers"] = []
    server.mock.FireOsiris("LongRestFinished")
    sim.run(max_ms=1000)
    change(19)
    check(client.eval("return CR.UI.page.alog.Visible") is True, "the section appears")
    dot = "  ·  "
    expected = "|".join([
        "+2", f"outside a conversation{dot}since your last long rest{dot}now 19",
        "-5", f"talking with Zevlor{dot}1 long rest ago{dot}now 17",
        "+2", f"talking with Karlach{dot}1 long rest ago{dot}now 22",
    ])
    got = tree_texts(client, "CR.UI.page.alogBody")
    check(got == expected, f"newest first, in words:\n{got}\n{expected}")

    # kept in the save: a reloaded save shows the same entries
    stored = json.loads(str(server.eval("return Ext.Json.Stringify(Ext.Vars.vars.Log or {})")))
    check(stored.get("rests") == 1 and len(stored["approval"][guid(AVATAR)][UUID["Shadowheart"]]) == 3,
          f"the log is in the save: {stored}")
    world2, sim2, server2, client2 = make(world, saved={"Log": stored})
    fire_running(client2, sim2)
    client2.eval("CR.UI.SetOpen(true)")
    sim2.run()
    client2.eval('CR.UI.Select("Shadowheart")')
    sim2.run()
    client2.mock.Loca[handle] = "Zevlor"
    check(tree_texts(client2, "CR.UI.page.alogBody").count("now ") == 3, "the entries survive a reload")
    # the first change after loading is measured against the game's value, not the log's
    world.approval[UUID["Shadowheart"]] = 30          # changed while the mod was not looking
    server2.eval("CR.ALog.Baseline(CR.Server.Players())")
    world.approval[UUID["Shadowheart"]] = 31
    server2.mock.FireOsiris("ApprovalRatingChanged", shadowheart, AVATAR, 31)
    sim2.run(max_ms=1000)
    check(tree_texts(client2, "CR.UI.page.alogBody").startswith("+1|"), "measured from the value at load")

    # only the last ten are kept
    for v in range(40, 52):
        change(v)
    kept = json.loads(str(server.eval("return Ext.Json.Stringify(Ext.Vars.vars.Log)")))["approval"][guid(AVATAR)][UUID["Shadowheart"]]
    check(len(kept) == 10 and kept[-1]["v"] == 51, f"at most ten entries: {len(kept)}")
    check(not server.errors() and not client.errors(), f"errors: {server.errors()} {client.errors()}")
    check(not server2.errors() and not client2.errors(), f"errors: {server2.errors()} {client2.errors()}")


def test_item_awareness():
    """A step that needs an item says whether the party has it, from the flags the story keeps on
    every player who can reach the item (DB_HasItemEvent / DB_PlayerHasTemplateItem)."""
    world, sim, server, client = make()
    for name in ("Shadowheart", "Karlach"):
        world.set_flag("GLO_Origin_PartOfTheTeam_" + name)
    for f in ("VISITEDREGION_WLD_Main_A", "VISITEDREGION_SCL_Main_A"):
        world.set_flag(f)
    world.set_level("SCL_Main_A")
    fire_running(client, sim)
    client.eval("CR.UI.SetOpen(true)")
    sim.run()
    client.eval('CR.UI.Select("Shadowheart")')
    sim.run()

    def line(step_id):
        if not client.eval(f"return CR.UI.page.steps.{step_id}.item.Visible"):
            return None
        return str(client.eval(f"return CR.UI.page.steps.{step_id}.item.Label"))

    check(line("SH_A2_ORCHID") == "You do not have a Night Orchid yet.", f"no orchid: {line('SH_A2_ORCHID')}")
    world.set_flag("ORI_Shadowheart_State_HasNightOrchid", AVATAR)
    server.mock.FireOsiris("FlagSet", "ORI_Shadowheart_State_HasNightOrchid_" + FLAG["ORI_Shadowheart_State_HasNightOrchid"],
                           AVATAR, 0)
    sim.run(max_ms=1000)
    check(line("SH_A2_ORCHID") == "You have a Night Orchid.", f"picked one: {line('SH_A2_ORCHID')}")
    check(line("SH_A2_NIGHTSONG") == "You do not have the Spear of Night yet.", f"the spear for the Shadowfell: {line('SH_A2_NIGHTSONG')}")
    # once the step is done, the line goes away
    world.quest("ORI_COM_ShadowHeart", "GaveNightOrchid")
    server.mock.FireOsiris("QuestUpdateUnlocked", "", "ORI_COM_ShadowHeart", "GaveNightOrchid")
    sim.run(max_ms=1000)
    check(line("SH_A2_ORCHID") is None, "no item line on a finished step")

    # Infernal Iron: any of its three templates
    client.eval('CR.UI.Select("Karlach")')
    sim.run()
    world.set_flag("GLO_ForgingOfTheHeart_State_HasInfernalMetal_C", AVATAR)
    server.eval("CR.Server.MarkDirty()")
    sim.run(max_ms=1000)
    check(line("KAR_A2_UPGRADE") == "You have Infernal Iron.", f"a piece of the third kind counts: {line('KAR_A2_UPGRADE')}")
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
    test_dead_before_joining,
    test_spoiler_setting,
    test_notices_wait_for_conversations,
    test_plain_words_and_optional_label,
    test_portraits_and_esc,
    test_report_file_and_replay,
    test_report_fixtures,
    test_act2_point_of_no_return,
    test_minthara_knockout_and_dependencies,
    test_steps_wait_for_recruitment,
    test_two_companion_steps,
    test_left_for_good_without_journal,
    test_scheduler_facts,
    test_paths_are_equal_choices,
    test_notice_position,
    test_choice_memory,
    test_patch_day_check,
    test_origin_avatar_and_console,
    test_mcm_integration,
    test_tonight_at_camp,
    test_not_interested,
    test_point_of_no_return_alerts,
    test_knockout_reminder,
    test_approval_log,
    test_item_awareness,
]


def main():
    failed = 0
    # optional: only the tests whose name contains one of the arguments
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")]
    tests = [t for t in TESTS if not wanted or any(w in t.__name__ for w in wanted)]
    for t in tests:
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
    print(f"\n{len(tests) - failed}/{len(tests)} tests passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

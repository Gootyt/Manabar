-- Offline test suite for Manabar. Run from the repository root:
--   lua5.1 tests/run_tests.lua
-- It loads the addon into tests/wow_mock.lua (a strict WoW API stand-in that
-- also simulates Midnight's secret values) and drives it through events,
-- slash commands and clicks.

local here = (arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "./"
package.path = here .. "?.lua;" .. package.path
local M = require("wow_mock")
local ADDON_DIR = here .. "../Manabar"

-------------------------------------------------------------------------------
-- Tiny test framework
-------------------------------------------------------------------------------

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function fail(msg) error(msg, 3) end
local function eq(actual, expected, what)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)))
    end
end
local function near(actual, expected, what, eps)
    if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
        fail(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)))
    end
end
local function truthy(v, what) if not v then fail((what or "condition") .. " should be true") end end
local function falsy(v, what) if v then fail((what or "condition") .. " should be false") end end
local function contains(text, needle, what)
    if not tostring(text):find(needle, 1, true) then
        fail(string.format("%s: %q not found in %q", what or "text", needle, tostring(text)))
    end
end
local function notContains(text, needle, what)
    if tostring(text):find(needle, 1, true) then
        fail(string.format("%s: %q should not be in %q", what or "text", needle, tostring(text)))
    end
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

-- A party of five: Holy Priest (you), Resto Shaman (drinking), Warrior tank,
-- Resto Druid, Frost Mage.
local function party5()
    return {
        { name = "Myra", class = "PRIEST", role = "HEALER", spec = 257, mana = 8000, maxMana = 10000, isPlayer = true },
        { name = "Thalia", class = "SHAMAN", role = "HEALER", spec = 264, mana = 4500, maxMana = 10000, auras = { "Drink" } },
        { name = "Brug", class = "WARRIOR", role = "TANK" },
        { name = "Fern", class = "DRUID", role = "HEALER", spec = 105, mana = 2900, maxMana = 10000 },
        { name = "Zed", class = "MAGE", role = "DAMAGER", spec = 64, mana = 9000, maxMana = 10000 },
    }
end

-- The same party, but the druid has no group role: her spec is unknown until
-- she is inspected.
local function partyNoRole(spec)
    local members = party5()
    members[4].role = "NONE"
    members[4].spec = spec
    return members
end

local function start(opts)
    opts = opts or {}
    M.install(opts)
    if opts.db ~= false then
        ManabarDB = opts.db or { welcomed = true, debug = true }
    end
    if opts.group then M.setGroup(opts.group, opts.members or party5()) end
    local ns = M.loadAddon(ADDON_DIR)
    M.fire("ADDON_LOADED", "Manabar")
    M.fire("PLAYER_ENTERING_WORLD")
    M.run(0.5)
    return ns
end

local function slash(text) SlashCmdList.MANABAR(text) end

local function describe(bar)
    local tex = bar.status:GetStatusBarTexture()
    local c = tex.__color or {}
    return {
        name = bar.name.__text, perc = bar.perc.__text, value = bar.status.__value,
        r = c[1], g = c[2], b = c[3],
        drinking = (bar.drinkIcon.__shown and bar.drinkText.__shown) and true or false,
        icon = bar.iconShown and bar.specIcon.__texture or nil,
        shown = bar.__shown, unit = bar.unit,
        secretText = bar.perc.__textSecret, secretValue = bar.status.__valueSecret, secretColor = tex.__colorSecret,
    }
end

local function rows(ns)
    local out = {}
    for i = 1, ns.GetActiveBars() do out[i] = describe(ns.bars[i]) end
    return out
end

local function names(ns)
    local t = {}
    for i, r in ipairs(rows(ns)) do t[i] = r.name end
    return table.concat(t, ",")
end

local function byName(ns, name)
    for _, r in ipairs(rows(ns)) do
        if r.name == name then return r end
    end
    fail("no bar for " .. name)
end

local function color(r, rr, gg, bb, what)
    near(r.r, rr, (what or "") .. " red", 1e-3)
    near(r.g, gg, (what or "") .. " green", 1e-3)
    near(r.b, bb, (what or "") .. " blue", 1e-3)
end

-- What the summary bar draws while the mana is secret: the filled fraction of
-- its width, and the color of the additive paint layers (summed, clamped).
local function visualAverage(ns)
    local sb = ns.GetSummaryBar()
    truthy(sb.stack:IsShown(), "visual average shown")
    local width = ManabarDB.width - 2
    local length, r, g, b, n = 0, 0, 0, 0, 0
    for i, seg in ipairs(sb.segments) do
        if seg:IsShown() then
            n = n + 1
            if i > 1 then -- every segment starts where the previous fill ends
                local _, rel, relPoint = seg:GetPoint(1)
                eq(rel, sb.segments[i - 1]:GetStatusBarTexture(), "segment " .. i .. " anchor")
                eq(relPoint, "TOPRIGHT", "segment " .. i .. " anchor point")
            end
            length = length + seg:GetWidth() * seg.__value
            local paint = sb.paints[i]
            eq(paint.__blend, "ADD", "additive paint")
            local _, endRel = paint:GetPoint(2)
            truthy(endRel ~= nil, "paint anchored to the fill end")
            local c, a = paint.__color, paint.__alpha
            r, g, b = r + c[1] * a, g + c[2] * a, b + c[3] * a
        end
    end
    local _, lastFill = sb.paints[1]:GetPoint(2)
    eq(lastFill, sb.segments[n]:GetStatusBarTexture(), "paints end at the last segment's fill")
    return length / width, math.min(r, 1), math.min(g, 1), math.min(b, 1), n
end

local function noDebugErrors()
    notContains(M.chatText(), "debug:", "chat")
end

local function openOptions(ns)
    slash("")
    local win, optionChecks, roleChecks = ns.GetOptionsFrame()
    truthy(win and win:IsShown(), "options window shown")
    return win, optionChecks, roleChecks
end

local function roleCheck(ns, role)
    local _, _, roleChecks = ns.GetOptionsFrame()
    for _, e in ipairs(roleChecks) do
        if e[2] == role then return e[1] end
    end
    fail("no checkbox for role " .. role)
end

local function optionCheck(ns, key)
    local _, optionChecks = ns.GetOptionsFrame()
    for _, e in ipairs(optionChecks) do
        if e[2] == key then return e[1] end
    end
    fail("no checkbox for option " .. key)
end

local function findButton(win, label)
    for _, child in ipairs(win.__children) do
        if child.__type == "Button" and child.label and child.label.__text == label then return child end
    end
    fail("no button " .. label)
end

-------------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------------

test("first run: frame unlocked with placeholder, welcome message, gear icon", function()
    local ns = start({ db = false })
    truthy(type(ManabarDB) == "table", "SavedVariables created")
    truthy(ManabarFrame:IsShown(), "frame shown")
    eq(ns.GetActiveBars(), 0, "bars")
    truthy(ManabarFrame:IsMouseEnabled(), "draggable while unlocked")
    contains(M.chatText(), "betöltve", "welcome")
    truthy(ns.GetGearButton():IsVisible(), "gear visible")
    truthy(M.isRegistered("UNIT_POWER_FREQUENT"), "mana events registered")
    truthy(M.isRegistered("PLAYER_REGEN_DISABLED"), "combat events registered")
end)

test("party: healer specs by default, you first, name + % + gradient color", function()
    local ns = start({ group = "party" })
    noDebugErrors()
    eq(names(ns), "Myra,Fern,Thalia", "shown bars")
    local myra, fern, thalia = byName(ns, "Myra"), byName(ns, "Fern"), byName(ns, "Thalia")
    eq(myra.perc, "80%", "Myra %")
    eq(fern.perc, "29%", "Fern % (no float rounding error)")
    eq(thalia.perc, "45%", "Thalia %")
    near(myra.value, 0.8, "Myra bar value")
    color(myra, 0.4, 1, 0, "80%")
    color(fern, 1, 0.58, 0, "29%")
    color(thalia, 1, 0.9, 0, "45%")
    truthy(thalia.drinking, "Thalia drinking")
    falsy(myra.drinking, "Myra not drinking")
    eq(myra.icon, M.specIcon(257), "own spec icon (Holy)")
    eq(thalia.icon, M.specIcon(264), "Resto Shaman icon (from the healer role)")
    eq(fern.icon, M.specIcon(105), "Resto Druid icon (from the healer role)")
    M.run(3)
    eq(#M.inspectRequests, 0, "roles were enough, no inspection")
end)

test("color gradient: 100% green, 50% yellow, 0% red", function()
    local ns = start()
    local r, g, b = ns.GradientRGB(1)
    eq(r .. "," .. g .. "," .. b, "0,1,0", "100%")
    r, g, b = ns.GradientRGB(0.5)
    eq(r .. "," .. g .. "," .. b, "1,1,0", "50%")
    r, g, b = ns.GradientRGB(0)
    eq(r .. "," .. g .. "," .. b, "1,0,0", "0%")
    r, g, b = ns.GradientRGB(0.25)
    eq(r .. "," .. g .. "," .. b, "1,0.5,0", "25%")
end)

test("full and empty mana through the curve path", function()
    local members = party5()
    members[1].mana = 10000
    members[2].mana = 0
    local ns = start({ group = "party", members = members })
    local myra, thalia = byName(ns, "Myra"), byName(ns, "Thalia")
    eq(myra.perc, "100%", "full")
    color(myra, 0, 1, 0, "full")
    eq(thalia.perc, "0%", "empty")
    color(thalia, 1, 0, 0, "empty")
end)

test("drinking indicator follows UNIT_AURA", function()
    local ns = start({ group = "party" })
    M.member("party1").auras = {}
    M.member("party3").auras = { "Mark of the Wild", "Drink" }
    M.fire("UNIT_AURA", "party1")
    M.fire("UNIT_AURA", "party3")
    M.run(0.15)
    falsy(byName(ns, "Thalia").drinking, "Thalia stopped drinking")
    truthy(byName(ns, "Fern").drinking, "Fern drinking")
    noDebugErrors()
end)

test("secret mana in combat: no Lua errors, bars still show % and color", function()
    local ns = start({ group = "party" })
    M.flags.restricted = true
    M.setCombat(true)
    M.member("party1").mana = 1000
    M.fire("UNIT_POWER_FREQUENT", "party1", "MANA")
    M.run(0.15)
    local thalia = byName(ns, "Thalia")
    eq(thalia.perc, "10%", "secret % shown")
    truthy(thalia.secretText, "text came from a secret value")
    truthy(thalia.secretValue, "bar value came from a secret value")
    truthy(thalia.secretColor, "color came from a secret value")
    color(thalia, 1, 0.2, 0, "10%")
    eq(byName(ns, "Myra").perc, "80%", "own mana")
    local length, _, _, _, n = visualAverage(ns)
    eq(n, 3, "one segment per bar")
    near(length, (0.8 + 0.29 + 0.10) / 3, "the game draws the average", 1e-9)
    eq(ns.GetSummaryBar().perc.__text, "", "no number while the values are secret")
    M.run(1)
    noDebugErrors()
end)

test("secret color objects that cannot be indexed fall back to EvaluateUnpacked", function()
    local ns = start({ group = "party", db = { welcomed = true } })
    M.flags.restricted = true
    M.flags.colorMode = "opaque"
    M.member("party3").mana = 7500
    M.fire("UNIT_POWER_FREQUENT", "party3", "MANA")
    M.run(0.15)
    local fern = byName(ns, "Fern")
    eq(fern.perc, "75%", "%")
    color(fern, 0.5, 1, 0, "75%")
    truthy(fern.secretColor, "secret color applied")
end)

test("client without curve objects: plain math, and secrets still reach the bar", function()
    local ns = start({ group = "party", noCurves = true })
    noDebugErrors()
    eq(byName(ns, "Fern").perc, "29%", "plain %")
    color(byName(ns, "Myra"), 0.4, 1, 0, "plain color")
    M.flags.restricted = true
    M.fire("UNIT_POWER_FREQUENT", "party1", "MANA")
    M.run(0.15)
    local thalia = byName(ns, "Thalia")
    truthy(thalia.secretValue, "secret value passed to the bar")
    eq(thalia.perc, "4500", "the raw mana instead of a % without curves")
    color(thalia, 0.3, 0.55, 1, "neutral mana color")
    M.run(0.5)
    eq(ns.GetSummaryBar().perc.__text, "?", "no average without curves")
    noDebugErrors()
end)

test("raid: your bar also reacts to events for the 'player' token", function()
    local members = {
        { name = "Ansel", class = "PRIEST", role = "HEALER", spec = 256, mana = 5000, maxMana = 10000 },
        { name = "Zara", class = "MAGE", role = "DAMAGER", mana = 5000, maxMana = 10000 },
        { name = "Me", class = "PALADIN", role = "HEALER", spec = 65, mana = 6000, maxMana = 10000, isPlayer = true },
        { name = "Bram", class = "DRUID", role = "HEALER", mana = 3000, maxMana = 10000 },
        { name = "Grom", class = "WARRIOR", role = "TANK" },
        { name = "Sela", class = "SHAMAN", role = "DAMAGER", mana = 5000, maxMana = 10000 },
        { name = "Vex", class = "WARLOCK", role = "DAMAGER", mana = 5000, maxMana = 10000 },
        { name = "Umbra", class = "PRIEST", role = "DAMAGER", mana = 5000, maxMana = 10000 },
    }
    local ns = start({ group = "raid", members = members })
    eq(names(ns), "Me,Ansel,Bram", "raid healers")
    eq(byName(ns, "Me").unit, "raid3", "your raid token")
    M.member("raid3").mana = 2500
    M.fire("UNIT_POWER_FREQUENT", "player", "MANA")
    M.run(0.15)
    eq(byName(ns, "Me").perc, "25%", "updated via 'player'")
    eq(byName(ns, "Me").icon, M.specIcon(65), "Holy Paladin")
    eq(byName(ns, "Bram").icon, M.specIcon(105), "druid healer = Restoration")
    eq(byName(ns, "Ansel").icon, ICON_UNKNOWN, "priest healer: Discipline or Holy")
    M.run(3)
    eq(table.concat(M.inspectRequests, ","), "Ansel", "only the priest is inspected (for the icon)")
    eq(byName(ns, "Ansel").icon, M.specIcon(256), "Discipline after inspection")
    noDebugErrors()
end)

test("offline, dead and no-mana states; average ignores them", function()
    local members = party5()
    members[2].connected = false
    members[4].dead = true
    local ns = start({ group = "party", members = members })
    eq(byName(ns, "Thalia").perc, "Offline", "offline")
    eq(byName(ns, "Fern").perc, "Halott", "dead")
    color(byName(ns, "Fern"), 0.4, 0.4, 0.4, "gray")
    eq(ns.GetSummaryBar().perc.__text, "80%", "average of the living, online ones")
    M.member("party3").dead = false
    M.member("party3").maxMana = 0
    M.run(0.6)
    eq(byName(ns, "Fern").perc, "--", "no mana data")
end)

test("secret names, flags and unit comparison in combat do not break the roster", function()
    local ns = start({ group = "party" })
    M.flags.restricted = true
    M.flags.secretNames = true
    M.flags.secretFlags = true
    M.flags.secretCompare = true
    M.setCombat(true)
    M.fire("GROUP_ROSTER_UPDATE")
    M.run(0.6)
    eq(ns.GetActiveBars(), 3, "bars")
    eq(rows(ns)[1].name, "Myra", "you are still first")
    truthy(rows(ns)[2].name ~= nil, "secret names are displayed")
    noDebugErrors()
end)

test("combat: hidden names / classes / GUIDs do not make the bars disappear", function()
    local ns = start({ group = "party" })
    M.setCombat(true)
    for _, flag in ipairs({ "restricted", "secretNames", "secretClass", "secretGuid", "secretExists",
        "secretCompare", "secretFlags" }) do
        M.flags[flag] = true
    end
    M.fire("GROUP_ROSTER_UPDATE")
    M.fire("UNIT_NAME_UPDATE", "party1")
    M.run(0.6)
    eq(names(ns), "Myra,Fern,Thalia", "bars kept through roster events")
    eq(byName(ns, "Thalia").perc, "45%", "mana still shown")
    openOptions(ns)
    M.click(roleCheck(ns, "DAMAGER")) -- settings changes rebuild at once, from remembered data
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "DPS ticked in combat: the mage appears")
    M.click(roleCheck(ns, "DAMAGER"))
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia", "and is gone again")
    eq(byName(ns, "Thalia").icon, M.specIcon(264), "remembered spec icon")
    M.member("party1").mana = 2000
    M.run(0.6)
    eq(byName(ns, "Thalia").perc, "20%", "mana keeps updating in combat")
    noDebugErrors()
end)

test("combat: someone leaves, the remaining bars follow their players", function()
    local ns = start({ group = "party" })
    M.setCombat(true)
    M.flags.restricted = true
    M.flags.secretNames = true
    M.flags.secretClass = true
    local members = party5()
    table.remove(members, 3) -- Brug leaves: Fern becomes party2, Zed party3
    M.setGroup("party", members)
    M.fire("GROUP_ROSTER_UPDATE")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia", "same players")
    eq(byName(ns, "Fern").unit, "party2", "Fern's new unit")
    eq(byName(ns, "Fern").perc, "29%", "her mana")
    M.setCombat(false)
    M.flags.secretNames, M.flags.secretClass = false, false
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia", "after the fight")
end)

test("combat: a delayed inspection retry waits for the end of the fight", function()
    local ns = start({ group = "party", members = partyNoRole(105) })
    M.flags.inspectNeverAnswers = true
    M.run(8) -- request sent, timed out: a retry rebuild is due in ~31 s
    eq(#M.inspectRequests, 1, "first request")
    M.setCombat(true)
    M.flags.secretClass = true
    M.flags.inspectNeverAnswers = false
    M.run(40)
    eq(#M.inspectRequests, 1, "nothing in combat")
    eq(names(ns), "Myra,Thalia", "list untouched in combat")
    M.flags.secretClass = false
    M.setCombat(false)
    M.run(5)
    eq(#M.inspectRequests, 2, "retried after the fight")
    eq(names(ns), "Myra,Fern,Thalia", "resolved")
end)

test("addon curves refused: Blizzard's CurveConstants keep the bars working", function()
    local ns = start({ group = "party", db = { welcomed = true } })
    M.flags.restricted = true
    M.flags.customCurvesFail = true
    M.run(0.6)
    local fern = byName(ns, "Fern")
    eq(fern.perc, "29%", "rounded percentage")
    near(fern.value, 0.29, "bar value")
    truthy(fern.secretValue, "secret value on the bar")
    color(fern, 1, 0.58, 0, "color from our curve object")
    local length = visualAverage(ns)
    near(length, (0.8 + 0.29 + 0.45) / 3, "visual average still drawn", 1e-9)
end)

test("all curves refused: the raw mana is shown", function()
    local ns = start({ group = "party", db = { welcomed = true } })
    M.flags.restricted = true
    M.flags.allCurvesFail = true
    M.run(0.6)
    local thalia = byName(ns, "Thalia")
    eq(thalia.perc, "4500", "raw mana")
    near(thalia.value, 4500, "bar value")
    truthy(thalia.secretValue, "secret value on the bar")
    color(thalia, 0.3, 0.55, 1, "neutral color")
    eq(byName(ns, "Myra").perc, "80%", "own readable mana")
end)

test("/manabar diag reports what the game lets the addon read", function()
    local ns = start({ group = "party" })
    M.setCombat(true)
    M.flags.restricted = true
    M.flags.secretNames = true
    M.clearChat()
    slash("diag")
    local text = M.chatText()
    contains(text, "IN COMBAT", "combat state")
    contains(text, "player: name=Myra class=PRIEST", "readable values")
    contains(text, "party1: name=secret", "secret name")
    contains(text, "mana=secret", "secret mana")
    contains(text, "max=1e+04", "readable max mana")
    noDebugErrors()
end)

test("summary bar: average of the shown bars, toggle, hidden with a single bar", function()
    local ns = start({ group = "party" })
    local summary = ns.GetSummaryBar()
    truthy(summary:IsShown(), "summary shown")
    eq(summary.name.__text, "Átlag", "label")
    eq(summary.perc.__text, "51%", "(80 + 29 + 45) / 3")
    near(summary.status.__value, (0.8 + 0.29 + 0.45) / 3, "value")
    -- layout: 3 bars (18 px + 2 px gap) under a 16 px header, the summary 4 px below
    local _, _, _, _, lastY = ns.bars[3]:GetPoint(1)
    local _, _, _, _, sumY = summary:GetPoint(1)
    eq(lastY, -56, "third bar")
    eq(sumY, -78, "summary bar 4 px below the last bar")
    eq(ManabarFrame:GetHeight(), 100, "frame height")
    eq(#summary.ticks, 3, "25 / 50 / 75 % marks")
    local _, _, _, tickX = summary.ticks[2]:GetPoint(1)
    near(tickX, (180 - 2) * 0.5, "50% mark")
    falsy(summary.stack:IsShown(), "exact number, no visual layer")
    slash("summary")
    falsy(summary:IsShown(), "summary hidden")
    falsy(ManabarDB.summary, "saved")
    slash("summary")
    truthy(summary:IsShown(), "summary back")
    slash("ignore Fern")
    slash("ignore Thalia")
    M.run(0.3)
    eq(ns.GetActiveBars(), 1, "one bar")
    falsy(summary:IsShown(), "no summary for a single bar")
end)

test("secret mana: the summary bar draws the exact average, length and color", function()
    local ns = start({ group = "party" })
    M.flags.restricted = true
    M.run(0.6)
    local summary = ns.GetSummaryBar()
    local length, r, g, b, n = visualAverage(ns)
    local avg = (0.8 + 0.29 + 0.45) / 3
    eq(n, 3, "segments")
    near(length, avg, "drawn length", 1e-9)
    local er, eg, eb = ns.GradientRGB(avg)
    near(r, er, "red", 1e-9)
    near(g, eg, "green", 1e-9)
    near(b, eb, "blue", 1e-9)
    eq(summary.status.__value, 0, "the summary's own fill is empty")
    eq(summary.name.__text, "Átlag", "label")

    M.member("party1").mana = 10000
    M.member("party3").mana = 10000
    M.fire("UNIT_POWER_FREQUENT", "party1", "MANA")
    M.fire("UNIT_POWER_FREQUENT", "party3", "MANA")
    M.run(0.15)
    length, r, g = visualAverage(ns)
    near(length, (0.8 + 1 + 1) / 3, "follows mana changes", 1e-9)
    near(g, 1, "green when almost full", 1e-9)

    M.flags.restricted = false
    M.run(0.6)
    falsy(summary.stack:IsShown(), "visual layer hidden once readable")
    eq(summary.perc.__text, "93%", "exact average when readable")
    noDebugErrors()
end)

test("visual average with a single counted bar", function()
    local members = party5()
    members[4].connected = false -- Fern offline: only Thalia counts
    local ns = start({ group = "party", members = members, db = { welcomed = true, debug = true, showSelf = false } })
    M.flags.restricted = true
    M.run(0.6)
    local length, r, g, _, n = visualAverage(ns)
    eq(n, 1, "one segment")
    near(length, 0.45, "Thalia's mana", 1e-9)
    near(ns.GetSummaryBar().paints[1].__alpha, 1, "full strength")
    local er, eg = ns.GradientRGB(0.45)
    near(r, er, "red", 1e-9)
    near(g, eg, "green", 1e-9)
    noDebugErrors()
end)

test("visual average when the secret colors cannot be indexed", function()
    local ns = start({ group = "party", db = { welcomed = true } })
    M.flags.restricted = true
    M.flags.colorMode = "opaque"
    M.run(0.6)
    local length, r, g = visualAverage(ns)
    local avg = (0.8 + 0.29 + 0.45) / 3
    near(length, avg, "length", 1e-9)
    local er, eg = ns.GradientRGB(avg)
    near(r, er, "red", 1e-9)
    near(g, eg, "green", 1e-9)
end)

test("visual average follows the group: segments are reused", function()
    local ns = start({ group = "party" })
    M.flags.restricted = true
    M.run(0.6)
    local _, _, _, _, n = visualAverage(ns)
    eq(n, 3, "three")
    slash("ignore Fern")
    M.run(0.6)
    local length
    length, _, _, _, n = visualAverage(ns)
    eq(n, 2, "two")
    near(length, (0.8 + 0.45) / 2, "average of two", 1e-9)
    falsy(ns.GetSummaryBar().segments[3]:IsShown(), "spare segment hidden")
    slash("width 250")
    M.run(0.6)
    length = visualAverage(ns)
    near(length, (0.8 + 0.45) / 2, "still exact after resizing", 1e-9)
end)

test("options window: opens with /manabar and the gear, reflects and changes settings", function()
    local ns = start({ group = "party" })
    local win = openOptions(ns)
    truthy(roleCheck(ns, "HEALER"):GetChecked(), "Healer on by default")
    falsy(roleCheck(ns, "DAMAGER"):GetChecked(), "DPS off by default")
    falsy(roleCheck(ns, "TANK"):GetChecked(), "Tank off by default")
    local _, _, roleChecks = ns.GetOptionsFrame()
    eq(#roleChecks, 3, "three roles")
    eq(roleCheck(ns, "HEALER").label.__text, "Healer", "label")
    eq(roleCheck(ns, "TANK").icon.__texture, "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", "role icon")
    truthy(optionCheck(ns, "summary"):GetChecked(), "summary option")
    falsy(optionCheck(ns, "showUnknown"):GetChecked(), "strict by default")
    truthy(optionCheck(ns, "specIcons"):GetChecked(), "spec icons by default")
    falsy(optionCheck(ns, "hideInCombat"):GetChecked(), "combat option")
    M.click(findButton(win, "X"))
    falsy(win:IsShown(), "closed with X")
    M.click(ns.GetGearButton())
    truthy(win:IsShown(), "opened with the gear")
    M.click(ns.GetGearButton())
    falsy(win:IsShown(), "gear toggles")
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "ManabarOptionsFrame" then found = true end
    end
    truthy(found, "Escape closes the window")
    noDebugErrors()
end)

test("roles: DPS shows the mage at once; a warrior tank never shows up", function()
    local ns = start({ group = "party" })
    openOptions(ns)
    M.click(roleCheck(ns, "DAMAGER"))
    eq(ManabarDB.roles.DAMAGER, true, "saved")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "the mage (dps in the group) is shown")
    eq(byName(ns, "Zed").icon, ICON_UNKNOWN, "his spec is not known yet")
    M.run(3)
    eq(table.concat(M.inspectRequests, ","), "Zed", "inspected, only for the icon")
    eq(byName(ns, "Zed").icon, M.specIcon(64), "Frost icon")
    M.click(roleCheck(ns, "TANK"))
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "the warrior tank has no mana: no bar")
    M.click(roleCheck(ns, "HEALER"))
    M.run(0.3)
    eq(names(ns), "Zed", "healers hidden")
    eq(M.checkInteractCalls, 0, "no range check API used")
    eq(#M.blocked, 0, "no protected calls")
    noDebugErrors()
end)

test("roles: a paladin tank is shown with Tank ticked", function()
    local members = party5()
    members[3] = { name = "Bulwark", class = "PALADIN", role = "TANK", spec = 66, mana = 5000, maxMana = 10000 }
    local ns = start({ group = "party", members = members })
    eq(names(ns), "Myra,Fern,Thalia", "Tank off by default")
    openOptions(ns)
    M.click(roleCheck(ns, "TANK"))
    M.run(0.3)
    eq(names(ns), "Myra,Bulwark,Fern,Thalia", "paladin tank shown")
    eq(byName(ns, "Bulwark").icon, M.specIcon(66), "Protection: the only paladin tank spec")
    eq(byName(ns, "Bulwark").perc, "50%", "his mana")
end)

test("the role set in the group decides, even against the spec", function()
    local members = party5()
    members[2].role = "DAMAGER" -- a Resto Shaman who joined as dps
    local ns = start({ group = "party", members = members })
    eq(names(ns), "Myra,Fern", "counts as dps")
end)

test("no group role: the spec decides after a short inspection", function()
    local ns = start({ group = "party", members = partyNoRole(105) })
    eq(names(ns), "Myra,Thalia", "druid without role hidden while unknown")
    M.run(3)
    eq(names(ns), "Myra,Fern,Thalia", "Restoration = healer: shown")
    eq(byName(ns, "Fern").icon, M.specIcon(105), "Resto icon")

    ns = start({ group = "party", members = partyNoRole(102) })
    M.run(3)
    eq(table.concat(M.inspectRequests, ","), "Fern", "inspected")
    eq(names(ns), "Myra,Thalia", "Balance = dps: stays hidden")
end)

test("no group role, but every spec of the class gives the same answer: no inspection", function()
    local members = party5()
    members[5].role = "NONE" -- the mage: all mage specs are dps
    local ns = start({ group = "party", members = members, db = { welcomed = true, debug = true, specIcons = false } })
    eq(names(ns), "Myra,Fern,Thalia", "hidden at once with Healer only")
    openOptions(ns)
    M.click(roleCheck(ns, "DAMAGER"))
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "shown at once with DPS")
    M.run(3)
    eq(#M.inspectRequests, 0, "no inspection needed")
end)

test("'show unknown' option: shown with a question mark until the role is known", function()
    local ns = start({ group = "party", members = partyNoRole(102) })
    openOptions(ns)
    M.click(optionCheck(ns, "showUnknown"))
    eq(ManabarDB.showUnknown, true, "saved")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia", "shown while unknown")
    eq(byName(ns, "Fern").icon, ICON_UNKNOWN, "question mark icon")
    M.run(3)
    eq(names(ns), "Myra,Thalia", "hidden once known as Balance (dps)")
end)

test("your own spec decides without a group role; found by index if its ID is unknown", function()
    local members = party5()
    members[1].role = "NONE"
    members[1].reportedSpecID = 99999
    members[1].specIndex = 3 -- Shadow
    local ns = start({ group = "party", members = members })
    eq(names(ns), "Fern,Thalia", "Shadow = dps: hidden with Healer only")
    openOptions(ns)
    M.click(roleCheck(ns, "DAMAGER"))
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "shown with DPS")
    eq(byName(ns, "Myra").icon, M.specIcon(258), "Shadow via the spec index")
end)

test("an inspected spec ID outside the class list is matched by name", function()
    local ns = start({ group = "party", members = partyNoRole(9105) })
    M.extraSpecs[9105] = { 9105, "Restoration", "HEALER", "DRUID" }
    M.run(3.5)
    eq(names(ns), "Myra,Fern,Thalia", "mapped to Restoration by name")
    eq(byName(ns, "Fern").icon, M.specIcon(105), "Resto icon")
end)

test("unticking Healer hides the healers, you included", function()
    local ns = start({ group = "party" })
    openOptions(ns)
    M.click(roleCheck(ns, "HEALER"))
    eq(ManabarDB.roles.HEALER, false, "saved")
    M.run(0.3)
    eq(ns.GetActiveBars(), 0, "nobody")
    truthy(ManabarFrame:IsShown(), "placeholder while unlocked")
    M.click(roleCheck(ns, "HEALER"))
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia", "back")
end)

test("settings of the old class / spec filter are dropped", function()
    local ns = start({ group = "party", db = { welcomed = true, specs = { [64] = true, [257] = false } } })
    eq(ManabarDB.specs, nil, "old setting removed")
    eq(ManabarDB.roles.HEALER, true, "healers by default")
    eq(ManabarDB.roles.DAMAGER, false, "no dps by default")
    eq(names(ns), "Myra,Fern,Thalia", "healers")
end)

test("spec icons can be turned off", function()
    local ns = start({ group = "party" })
    truthy(byName(ns, "Myra").icon, "icon shown by default")
    openOptions(ns)
    M.click(optionCheck(ns, "specIcons"))
    M.run(0.3)
    eq(byName(ns, "Myra").icon, nil, "no icon")
    local _, rel = ns.bars[1].name:GetPoint(1)
    eq(rel, ns.bars[1].status, "name back at the bar's left edge")
end)

test("inspection is never started in combat", function()
    local ns = start({ group = "party", members = partyNoRole(102) })
    M.setCombat(true)
    M.run(10)
    eq(#M.inspectRequests, 0, "no inspect in combat")
    eq(#M.blocked, 0, "no protected call in combat")
    M.setCombat(false)
    M.run(3)
    eq(#M.inspectRequests, 1, "inspected after combat")
    eq(ns.specCache[M.member("party3").guid], 102, "resolved")
    eq(names(ns), "Myra,Thalia", "Balance druid hidden")
end)

test("inspection timeout is retried later", function()
    local ns = start({ group = "party", members = partyNoRole(105) })
    M.flags.inspectNeverAnswers = true
    M.run(3)
    eq(#M.inspectRequests, 1, "first request")
    M.run(10)
    eq(#M.inspectRequests, 1, "waits after a timeout")
    M.flags.inspectNeverAnswers = false
    M.run(40)
    eq(#M.inspectRequests, 2, "retried")
    eq(names(ns), "Myra,Fern,Thalia", "Resto druid shown after the retry")
end)

test("only out of combat option", function()
    local ns = start({ group = "party" })
    M.setCombat(true)
    truthy(ManabarFrame:IsShown(), "visible in combat by default")
    M.setCombat(false)
    openOptions(ns)
    M.click(optionCheck(ns, "hideInCombat"))
    eq(ManabarDB.hideInCombat, true, "saved")
    M.setCombat(true)
    falsy(ManabarFrame:IsShown(), "hidden in combat")
    M.setCombat(false)
    truthy(ManabarFrame:IsShown(), "back after combat")
    slash("combat")
    eq(ManabarDB.hideInCombat, false, "slash toggle")
    falsy(optionCheck(ns, "hideInCombat"):GetChecked(), "checkbox follows the slash command")
end)

test("lock, drag, right-click, scale and reset", function()
    local ns = start({ group = "party" })
    local onDragStart = ManabarFrame:GetScript("OnDragStart")
    local onDragStop = ManabarFrame:GetScript("OnDragStop")
    onDragStart(ManabarFrame)
    M.dragTo = { 300, 500 }
    onDragStop(ManabarFrame)
    near(ManabarDB.pos.x, 300, "x")
    near(ManabarDB.pos.y, 500, "y")
    local point, rel, relPoint, x, y = ManabarFrame:GetPoint(1)
    eq(point .. " " .. relPoint, "TOPLEFT BOTTOMLEFT", "anchored by the top left corner")
    falsy(ManabarFrame:IsUserPlaced(), "no layout-cache placement")

    slash("lock")
    falsy(ManabarFrame:IsMouseEnabled(), "click-through when locked")
    onDragStart(ManabarFrame)
    M.dragTo = { 10, 10 }
    onDragStop(ManabarFrame)
    near(ManabarDB.pos.x, 300, "locked frame did not move")
    truthy(ns.GetGearButton():IsVisible(), "gear still usable")

    slash("unlock")
    truthy(ManabarFrame:IsMouseEnabled(), "unlocked")
    ManabarFrame:GetScript("OnMouseUp")(ManabarFrame, "RightButton")
    truthy(ManabarDB.locked, "right-click locks")

    slash("scale 1,5")
    near(ManabarDB.scale, 1.5, "scale with decimal comma")
    near(ManabarDB.pos.x, 200, "x kept on screen")
    near(ManabarDB.pos.y, 500 / 1.5, "y kept on screen")
    slash("scale 9")
    contains(M.chatText(), "Érvénytelen", "invalid scale rejected")
    slash("width 250")
    eq(ns.bars[1]:GetWidth(), 250, "bar width")
    eq(ManabarFrame:GetWidth(), 258, "frame width")
    slash("reset")
    eq(ManabarDB.pos, nil, "position reset")
    eq(ManabarDB.scale, 1, "scale reset")
    eq(ns.bars[1]:GetWidth(), 180, "width reset")
end)

test("locked and nothing to show: frame hidden; visible again when a healer joins", function()
    local ns = start({ db = { welcomed = true, locked = true } })
    falsy(ManabarFrame:IsShown(), "hidden while solo and locked")
    M.setGroup("party", party5())
    M.fire("GROUP_ROSTER_UPDATE")
    M.run(0.3)
    truthy(ManabarFrame:IsShown(), "shown with healers")
    eq(ns.GetActiveBars(), 3, "bars")
end)

test("test mode: animated sample healers, drinking, offline, average", function()
    local ns = start()
    slash("test")
    eq(ns.GetActiveBars(), 5, "sample bars")
    local before = rows(ns)[1].value
    M.run(1)
    truthy(rows(ns)[1].value < before, "values animate")
    truthy(byName(ns, "Borak").drinking, "drinking sample")
    eq(byName(ns, "Aelinor").icon, M.specIcon(257), "sample spec icon")
    eq(byName(ns, "Elyra").perc, "Offline", "offline sample")
    truthy(ns.GetSummaryBar():IsShown(), "average shown")
    contains(ns.GetSummaryBar().perc.__text, "%", "average %")
    slash("test")
    eq(ns.GetActiveBars(), 0, "back to the real (solo) roster")
end)

test("manual lists: add / ignore / remove / list", function()
    local ns = start({ group = "party" })
    slash("add Zed")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "added")
    eq(byName(ns, "Zed").icon, ICON_UNKNOWN, "spec not known yet")
    slash("ignore thalia")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Zed", "ignored (case-insensitive)")
    M.state.target = M.member("party1")
    slash("remove")
    M.run(0.3)
    eq(names(ns), "Myra,Fern,Thalia,Zed", "target removed from the ignore list")
    slash("list")
    contains(M.chatText(), "Mindig megjelenik: Zed", "list")
end)

test("own bar can be hidden", function()
    local ns = start({ group = "party" })
    slash("self")
    M.run(0.3)
    eq(names(ns), "Fern,Thalia", "own bar hidden")
    eq(ManabarDB.showSelf, false, "saved")
end)

test("language switch updates bars and the options window", function()
    local members = party5()
    members[4].dead = true
    local ns = start({ group = "party", members = members })
    local win = openOptions(ns)
    slash("lang en")
    eq(byName(ns, "Fern").perc, "Dead", "state text")
    eq(byName(ns, "Thalia").drinking, true, "still drinking")
    eq(ns.bars[1].drinkText.__text, "Drinking", "drinking label")
    eq(ns.GetSummaryBar().name.__text, "Average", "summary label")
    eq(optionCheck(ns, "summary").label.__text, "Summary bar at the bottom (average)", "options translated")
    slash("lang xx")
    contains(M.chatText(), "Usage: /manabar lang", "unknown language")
end)

test("localized drink names, and the aura index fallback", function()
    local ns = start({ group = "party", spellNames = true })
    M.spellNames[430] = "Trinken"
    M.fire("PLAYER_ENTERING_WORLD")
    M.member("party3").auras = { "Trinken" }
    M.fire("UNIT_AURA", "party3")
    M.run(0.3)
    truthy(byName(ns, "Fern").drinking, "localized name via GetAuraDataBySpellName")

    ns = start({ group = "party", noAuraByName = true })
    truthy(byName(ns, "Thalia").drinking, "found by index")
    M.flags.auraRestricted = true
    M.fire("UNIT_AURA", "party1")
    M.run(0.15)
    falsy(byName(ns, "Thalia").drinking, "restricted aura names are skipped safely")
    noDebugErrors()
end)

test("no text uses letters the game font cannot draw", function()
    for _, file in ipairs({ "Locales.lua", "Manabar.lua", "Options.lua" }) do
        local f = assert(io.open(ADDON_DIR .. "/" .. file, "rb"))
        local s = f:read("*a")
        f:close()
        -- UTF-8 of o/u with double acute (U+0150, U+0151, U+0170, U+0171)
        for _, seq in ipairs({ "\197\144", "\197\145", "\197\176", "\197\177" }) do
            falsy(s:find(seq, 1, true), file .. " contains an o/u with double acute")
        end
    end
end)

-------------------------------------------------------------------------------
-- Run
-------------------------------------------------------------------------------

local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        M.realPrint("ok   " .. t.name)
    else
        failed = failed + 1
        M.realPrint("FAIL " .. t.name .. "\n     " .. tostring(err))
        if M.chat and #M.chat > 0 then
            M.realPrint("     chat: " .. table.concat(M.chat, " | "))
        end
    end
end
M.realPrint(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

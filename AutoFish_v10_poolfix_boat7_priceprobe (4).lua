--[[
  autofish_v6.lua - auto fishing for the Roblox game "Fisch"

  Runtime : Roblox client, Luau, through an executor (written for Delta, phone or PC)
  Run     : stand at the water's edge with your rod equipped (or in the hotbar), paste this
            whole file into Delta and press Execute. A small panel shows up: drag the title bar
            to move it, tap "-" to shrink it to a pill. Executing again replaces the old copy.

  How it plays: no remotes, only inputs a player has - hold to cast, press the shake button,
            hold / release to keep the white bar under the fish.

  v6-11: Halloween "Frightful Pool" (a pool spawns every 45 min at Moosewood / Statue of Sovereignty /
         Terrapin Island / Harvesters Spike). The alert is caught with goblin_25's method (game remotes +
         on-screen text + chat), the character teleports next to the pool, faces it and keeps fishing, and
         after CFG.POOL_STAY seconds from the alert (pool lifetime) it goes back to the old spot. Pool control is halved, so the reel brain
         keeps a separate calibration while you are at a pool. Settings: CFG.POOL*. Test it right now with
         getgenv().__autofish_pool("Moosewood"). Everything is in the "Frightful Pool" section above cycle().
  v6-9 : from the v6-8 report: (1) hold method "mouse2" is gone from HOLD_ORDER and the hold chooser needs
         more evidence before it switches: both fish that got away at 41-42% came right after a mid-reel
         "switching to mouse2"; (2) ping is sampled every 2s: the report gets a "ping now / avg / max" line and
         the "diag" and "nothing after 20s" log lines show the ping at that moment.
  v6-8 : from the v6-7 report: (1) a bobber that stays after a catch is re-equipped away at once instead of
         losing 20-50s to casts that do nothing; (2) COOLDOWN is 4.0-5.5s, because casts within ~3s of a catch
         failed about half the time and casts after 4s+ did not; (3) the cast check with the bobber off waits
         8s, not 20s. The re-equip after a failed cast (v6-6b) stays: it fixed 7 of 9 failures.
  v6-7 : the report title and the start log line now say v6-7, so you can tell which copy ran. A failed
         cast also logs "diag new text": any text on screen that was not there at the last good cast.
  v6-6b: a failed cast now re-equips the rod (twice) before the input method gets blamed and rotated, and logs
         one "diag" line (rod equipped, bobber, humanoid state, distance from home, Roblox menu open, chat box
         focused, click spot blocked, new GUIs since the last good cast). LOG_KEEP is 140 so it all fits in the report.
  v6-6 : the shake press never happened ("shake presses 0"): the script looked for a child called
         "button" but the game's is "default", so it now falls back to any visible button in the shake GUI.
         Also fixes casts that stopped registering after "bobber stays after a catch". With the bobber
         check off, a cast was judged on a 5s window but the bite takes 12-20s, so every working cast
         read as "did nothing" and got recast on top of the live line. Now the window matches the bite
         wait, a fresh bobber counts as proof, the check turns itself back on once the bobber is gone,
         and a slow bobber cleanup gets 5s instead of 2s before the check is switched off.

  v6-5 : never stops on its own. The session limit, catch target and breaks are gone, repairs
         rest a few seconds instead of minutes, losing the panel no longer kills the script,
         can't-walk-back now fishes from where it stands, and the bobber check heals itself
         instead of staying off after one slow catch.

  New in v6 (all of it wrapped so a bug in it cannot stop the fishing loop)
   Copy report : panel button. Puts a text dump on the clipboard: settings, which input methods
                 won, bite-wait and reel stats, learned bar response, the PlayerGui list, GUI
                 trees the script saw, the last 80 log lines. Paste it into a chat and whoever
                 helps sees exactly what the script saw.
   GUI recorder: the first shake / reel GUI, and any new ScreenGui that appears while you play,
                 are saved as trees for the report. That is how you find new names after a
                 game update.
   Calibration : the reel brain's learned bar response is kept per rod and saved (REMEMBER_CAL),
                 so a fresh execute starts calibrated instead of relearning.
   Notify      : optional Discord webhook (NOTIFY_URL). Pings when the watchdog repairs;
                 NOTIFY_EVERY adds a status line every N min.
   Lifetime    : total catches and running time are kept across executes (shown in the report).
  Earlier: v5 target counter, walk home, watchdog. v4 reel brain, human timing, panel.

  Where things are (search for the banner text)
   local CFG = {  ........ every setting you are meant to touch
   ---- helpers .......... log (keeps the report's log lines), random, find / getGui
   ---- settings + session  save file: settings, panel spot, calibration, lifetime
   ---- panel ............ buildPanel, paint, chips, report button
   ---- input ............ PRESS / SHAKE tables, chooser (picks the input method that works)
   ---- game logic ....... getRod, getReel, castLine, shakeOnce
   ---- reel brain ....... newBrain (pure maths), memFor (per-rod memory), playReel
   ---- self-repair ...... report + notify, goHome, recover, failed
   local function cycle() . one fish: cast, wait, shake, reel, cooldown
   ---- go ............... the loops that run it, plus the watchdog

  Quick fixes
   Broke after a game update   : tap Debug, cast once, tap Copy report, read the PlayerGui line
                                 and the GUI trees, then fix GUI_SHAKE / SHAKE_BUTTON / GUI_REEL /
                                 BAR_NAME / FISH_NAME in CFG.
   Too slow / too fast         : CAST_HOLD, COOLDOWN, SHAKE_FIRST, SHAKE_GAP.
   Counts fish it lost         : raise CATCH_MIN_ACC (changes counting only, not catching).
   Uses the wrong rod          : ROD_NAME = "Exact Rod Name".
   Keeps walking back / pauses : bigger GUARD_STUDS, or GUARD = false.
   Reel feels off after a swap : REMEMBER_CAL = false (or delete autofish_v6.json).

  Stuck?  : tap the Debug chip (or set DEBUG = true) and read the [autofish] lines in the console.
  Risk    : nothing here is ban-proof. Fisch staff are banning macro/exploit users right now,
            so use an alt account and don't leave it running for hours.
]]

local CFG = {
    -- names the game uses (case doesn't matter, a close match is tried too)
    GUI_SHAKE    = "shakeui",
    SHAKE_BUTTON = "button",
    GUI_REEL     = "reel",
    BAR_NAME     = "playerbar",   -- the white bar you control
    FISH_NAME    = "fish",        -- the fish icon it has to cover
    ROD_NAME     = nil,           -- exact rod name, e.g. "Training Rod"; nil = first rod found

    -- input methods, tried in this order; the one that works is kept
    CAST_ORDER   = { "mouse", "mouse2", "touch", "activate" },
    SHAKE_ORDER  = { "nav", "click", "tap", "signal" },
    HOLD_ORDER   = { "mouse" },   -- reel: holding moves the bar right (mouse only: "space" is the jump key and jumped you out of the boat, "touch" left the bar stuck)

    -- timing in seconds; { min, max } is re-rolled every time
    CAST_HOLD    = { 1.0, 1.5 },
    CAST_VERIFY  = 5,             -- how long to wait for the bobber / shake GUI after a cast
    SHAKE_FIRST  = { 0.20, 0.55 },-- reaction time before the first shake press
    SHAKE_GAP    = { 0.10, 0.28 },
    REEL_START   = { 0.15, 0.45 },-- reaction time before the reel starts (Human on)
    COOLDOWN     = { 4.0, 5.5 },   -- was 1.5-3.5: casts under ~3s after a catch failed about half the time
    TIMEOUT      = 20,            -- no bite after this long -> pull the line back and recast
    REEL_TIMEOUT = 60,
    REEL_LAT     = 0.03,

    HUMAN        = true,          -- skewed timing, mood/tiredness, bar a bit off-centre; off = max precision
    PERFECT      = true,
    LAPSE        = 0.04,          -- chance of a short "looked away" pause before a shake press
    GUARD        = true,          -- walk back if the character gets moved off the spot (fishes from there if it can't)
    GUARD_STUDS  = 18,
    MAX_FAILS    = 6,             -- failed casts / no bites in a row before a repair step (it never stops)
    CATCH_MIN_ACC = 0.5,  -- a reel counts as caught if the fish was in the bar this much
    WALK_HOME     = true, -- when moved away from the spot, walk back instead of pausing
    WATCHDOG      = 240,  -- seconds without a finished reel before self-repair starts (0 = off)
    REMEMBER_CAL  = true, -- keep the reel brain's learned bar response between executes (false = relearn)
    NOTIFY_URL    = "",   -- Discord webhook URL, "" = off (don't share the script with it filled in)
    NOTIFY_EVERY  = 0,    -- minutes between status pings; 0 = only ping on watchdog repairs
    LOG_KEEP      = 400,   -- log lines kept in memory (oldest dropped after this)
    REPORT_CHUNK  = 800,   -- Copy report puts this many characters on the clipboard per tap (tap again = next part; 0 = all at once)
    REPORT_LINES  = 400,   -- how many of the newest log lines "Copy report" prints (was fixed at 61)

    -- Frightful Pool (Halloween event): warp to it when the alert shows up, fish there, then go back
    POOL         = true,
    POOL_STAY    = 600,           -- a pool lives 10 min from the moment it spawns: counted from the alert, not from arrival
    POOL_BACK    = true,          -- go back to the old spot after POOL_STAY (false = keep fishing at the pool)
    POOL_STAY_IN_BOAT = true,     -- after the boat is back home, stay seated and keep fishing (false = get out and walk to the old spot)
    POOL_BOAT    = true,          -- go to the pool IN YOUR BOAT (spawn it before the pool shows up). Casting only works from something the server knows
    POOL_BOAT_NAME = "",          -- optional: part of the boat's full name (see the "POOL: boat candidates" lines) if it is not found by owner
    POOL_PLATFORM = false,        -- (does not help: casts fail on a client-side pad) invisible pad under the feet when hovering
    POOL_FLOAT   = false,         -- (does not help: casts fail while hovering) true = hover over the water anyway instead of skipping the pool
    POOL_DIST    = 18,            -- studs from the pool centre when hovering
    POOL_LIFT    = 2,             -- studs the boat is dropped ABOVE its normal floating height (it settles by itself). Boat sinks at the pool -> raise it (4, 6)
    POOL_REACH   = 60,            -- ground further than this from the pool centre is not used

    ANTI_AFK     = true,
    RECOVER      = true,
    SAVE         = true,          -- remember panel position and chips (needs writefile)
    DEBUG        = false,         -- print [autofish] lines (the game can read the output log)
}

local Players      = game:GetService("Players")
local VIM          = game:GetService("VirtualInputManager")
local VU           = game:GetService("VirtualUser")
local GuiService   = game:GetService("GuiService")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService  = game:GetService("HttpService")
local lp           = Players.LocalPlayer
local pg           = lp:WaitForChild("PlayerGui")

-- executing again (any version) shuts the old copy down first
local env = (getgenv and getgenv()) or _G
if type(env.__autofish_stop) == "function" then pcall(env.__autofish_stop) end

local running, count, stage, stopped = true, 0, "start", false
local gui, ui, afk, dbg, recorder
local note = ""
local sessionStart, restedAt = os.clock(), os.clock()
local curAcc, lastAcc, accHit, accAll = nil, nil, 0, 0
local fails, home, mood = 0, nil, 1
local POOL = { pending = nil, active = nil }   -- Frightful Pool state (see the section above cycle())

-- network ping in ms (Player:GetNetworkPing is the round trip in seconds), sampled every 2s for the report
local PING = { now = nil, sum = 0, n = 0, max = 0, at = 0 }
local function samplePing()
    local ok, v = pcall(function() return lp:GetNetworkPing() end)
    if ok and type(v) == "number" then
        local ms = v * 1000
        PING.now, PING.sum, PING.n = ms, PING.sum + ms, PING.n + 1
        if ms > PING.max then PING.max = ms end
    end
end
local function pingText()
    return PING.now and string.format("%dms", math.floor(PING.now + 0.5)) or "?"
end

-- counters for the report; LIFE and cal are also saved to disk
local ST = { casts = 0, castMiss = 0, shakeHit = 0, shakeMiss = 0, reels = 0, reelSecs = 0,
             away = 0, errors = 0, waitSum = 0, waitN = 0, lastErr = "", fixes = 0, lastFish = os.clock() }
local LIFE = { catches = 0, secs = 0, runs = 0 }
local cal = {}          -- per rod: what the reel brain learned about the bar (see memFor)
local copyReport        -- assigned in the report section; the panel button calls it
local HK = { q = {}, tally = {}, n5 = 0, away5 = 0, winUntil = 0, keys = {}, txt = {}, conns = {},
             catches = {}, sentN = 0, scriptUntil = 0 }
if CFG.NOTIFY_FISH == nil then CFG.NOTIFY_FISH = true end        -- fish list every FISH_EVERY minutes
if CFG.NOTIFY_EVENTS == nil then CFG.NOTIFY_EVENTS = true end    -- live events
CFG.FISH_EVERY = 3
pcall(function()   -- webhook settings get their own file, so the URL never ends up in the main save or the report
    if type(isfile) == "function" and isfile("autofish_hook.json") then
        local d = HttpService:JSONDecode(readfile("autofish_hook.json"))
        if type(d.hook) == "string" and d.hook ~= "" then CFG.NOTIFY_URL = d.hook end
        if type(d.fish) == "boolean" then CFG.NOTIFY_FISH = d.fish end
        if type(d.events) == "boolean" then CFG.NOTIFY_EVENTS = d.events end
    end
end)

---------------------------------------------------------------- helpers

local logbuf, t00 = {}, os.clock()   -- the last CFG.LOG_KEEP lines, for "Copy report"

-- the last line shows in the panel; it only reaches the console when Debug is on
local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    note = table.concat(parts, " ")
    logbuf[#logbuf + 1] = string.format("%5ds  %s", math.floor(os.clock() - t00), note)
    if note:find("POOL", 1, true) or note:find("price scan", 1, true) or note:find("tool: ", 1, true) then   -- POOL lines also go to a separate buffer (logbuf.pool, not part of the array)
        local pl = logbuf.pool or {}
        logbuf.pool = pl
        pl[#pl + 1] = logbuf[#logbuf]
        if #pl > 60 then table.remove(pl, 1) end
    end
    if #logbuf > (tonumber(CFG.LOG_KEEP) or 80) then table.remove(logbuf, 1) end
    if CFG.DEBUG then print("[autofish]", note) end
end

local function rand(t)
    if type(t) == "table" then return t[1] + math.random() * (t[2] - t[1]) end
    return t
end

local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

local function gauss()
    return math.sqrt(-2 * math.log(math.random() + 1e-9)) * math.cos(2 * math.pi * math.random())
end

-- a delay in { min, max }: uniform with Human off; with Human on it is right-skewed like a real
-- reaction time (most near the low-middle, the odd slow one), scaled by mood and tiredness
local function human(t)
    if type(t) ~= "table" then return t end
    local lo, hi = t[1], t[2]
    if not CFG.HUMAN then return lo + math.random() * (hi - lo) end
    local x = 0.32 + 0.17 * gauss()
    if math.random() < 0.06 then x = x + 0.3 + math.random() * 0.4 end
    x = clamp(x, 0, 1.3)
    local tired = 1 + 0.2 * math.min(1, (os.clock() - restedAt) / 7200)
    return (lo + (hi - lo) * x) * mood * tired
end

local function pause(t) task.wait(human(t)) end

-- now and then a person looks away for a moment
local function lapse(extra)
    if CFG.HUMAN and not CFG.PERFECT and math.random() < CFG.LAPSE then
        local t = 0.6 + math.random() * extra
        log(string.format("lapse %.1fs", t))
        task.wait(t)
    end
end

local function px(v) return math.floor(v + 0.5) end

-- exists, is parented and, for a ScreenGui, is switched on
local function up(g)
    return g ~= nil and g.Parent ~= nil and (not g:IsA("ScreenGui") or g.Enabled)
end

-- false only once this copy has been shut down (executing again); losing the panel does not stop it
local function alive()
    return not stopped
end

local function names(inst)
    local t = {}
    for _, c in ipairs(inst:GetChildren()) do t[#t + 1] = c.Name end
    return table.concat(t, ", ")
end

local function tree(inst, depth, budget)
    for _, c in ipairs(inst:GetChildren()) do
        if budget[1] <= 0 then return end
        budget[1] = budget[1] - 1
        log(string.rep("  ", depth) .. c.Name .. " (" .. c.ClassName .. ")")
        tree(c, depth + 1, budget)
    end
end

-- FindFirstChild that ignores case
local function find(parent, name, deep)
    local c = parent:FindFirstChild(name, deep)
    if c then return c end
    local want = name:lower()
    for _, d in ipairs(deep and parent:GetDescendants() or parent:GetChildren()) do
        if d.Name:lower() == want then return d end
    end
    return nil
end

-- first GuiObject below parent whose name contains key
local function like(parent, key)
    for _, d in ipairs(parent:GetDescendants()) do
        if d:IsA("GuiObject") and d.Name:lower():find(key, 1, true) then return d end
    end
    return nil
end

-- an enabled ScreenGui in PlayerGui: exact name first, then one that merely contains it
local function getGui(key)
    local k, close = key:lower(), nil
    for _, c in ipairs(pg:GetChildren()) do
        if c:IsA("ScreenGui") and c.Enabled then
            local n = c.Name:lower()
            if n == k then return c end
            if not close and n:find(k, 1, true) then close = c end
        end
    end
    return close
end

local function viewport()
    local c = workspace.CurrentCamera
    return c and c.ViewportSize or Vector2.new(1280, 720)
end

local function inset()
    local ok, v = pcall(function() return (GuiService:GetGuiInset()) end)
    return ok and v or Vector2.zero
end

local function randName()
    local t = {}
    for i = 1, 10 + math.random(0, 6) do
        local r = math.random(1, 3)
        t[i] = string.char(r == 1 and math.random(65, 90) or r == 2 and math.random(97, 122) or math.random(48, 57))
    end
    return table.concat(t)
end

---------------------------------------------------------------- settings + session

local SAVE_FILE, OLD_FILE = "autofish_v6.json", "autofish_v4.json"
local saved = {}
if CFG.SAVE and type(isfile) == "function" and type(readfile) == "function" then
    pcall(function()
        local f = isfile(SAVE_FILE) and SAVE_FILE or (isfile(OLD_FILE) and OLD_FILE or nil)   -- v4 / v5 settings carry over
        if f then
            local d = HttpService:JSONDecode(readfile(f))
            if type(d) == "table" then saved = d end
        end
    end)
end
for _, k in ipairs({ "HUMAN", "RECOVER" }) do
    if type(saved[k]) == "boolean" then CFG[k] = saved[k] end
end
if type(saved.life) == "table" then
    for _, k in ipairs({ "catches", "secs", "runs" }) do
        if type(saved.life[k]) == "number" then LIFE[k] = saved.life[k] end
    end
end
LIFE.runs = LIFE.runs + 1
if CFG.REMEMBER_CAL and type(saved.cal) == "table" then   -- per rod, as a multiple of the track length
    for rodName, c in pairs(saved.cal) do
        if type(rodName) == "string" and type(c) == "table" and type(c.h) == "number" and type(c.r) == "number" then
            cal[rodName] = { nh = c.h, nr = c.r, n = tonumber(c.n) or 0 }
        end
    end
    -- a reel played with the wrong hold input (space) saved a bogus pool calibration (hold 2.72 x track, normal ~1.0);
    -- drop it so it is learned again. Only fires while the saved value is still the bad one.
    local pc = cal["Eldritch Rod|pool"]
    if pc and (tonumber(pc.nh) or 0) > 2 then cal["Eldritch Rod|pool"] = nil end
end

local function save()
    if not (CFG.SAVE and type(writefile) == "function") then return end
    pcall(function()
        local c = ui and ui.card
        local calOut = {}
        if CFG.REMEMBER_CAL then
            for rodName, m in pairs(cal) do
                if m.aHold and m.aRel and m.len and m.len > 50 then
                    calOut[rodName] = { h = m.aHold / m.len, r = m.aRel / m.len, n = m.n or 0 }
                elseif m.nh and m.nr then
                    calOut[rodName] = { h = m.nh, r = m.nr, n = m.n or 0 }
                end
            end
        end
        writefile(SAVE_FILE, HttpService:JSONEncode({
            HUMAN = CFG.HUMAN, RECOVER = CFG.RECOVER,
            min = ui and ui.collapsed or false,
            x = c and c.Position.X.Offset, y = c and c.Position.Y.Offset,
            life = LIFE, cal = calOut,
        }))
    end)
end

local function newSession()
    sessionStart, restedAt = os.clock(), os.clock()
    count, lastAcc, curAcc, accHit, accAll, fails = 0, nil, nil, 0, 0, 0
end
newSession()

---------------------------------------------------------------- panel

local PAL = {
    bg0   = Color3.fromRGB(19, 39, 59),    bg1   = Color3.fromRGB(7, 14, 24),       -- card: shallows -> deep
    line  = Color3.fromRGB(47, 74, 98),    cell  = Color3.fromRGB(23, 41, 59),
    cell2 = Color3.fromRGB(33, 57, 80),    track = Color3.fromRGB(34, 55, 76),
    text  = Color3.fromRGB(234, 243, 250), dim   = Color3.fromRGB(138, 164, 186),
    faint = Color3.fromRGB(88, 114, 136),
    -- severity (accuracy, ping, last fish, log line): green = good, orange = watch it, red = bad
    good  = Color3.fromRGB(84, 214, 120),  warn  = Color3.fromRGB(252, 134, 24),    bad = Color3.fromRGB(251, 78, 90),
    onBtn = Color3.fromRGB(16, 120, 80),   offBtn = Color3.fromRGB(176, 44, 62),    chipOn = Color3.fromRGB(20, 150, 98),
}

-- one colour per state, no two alike (the closest pair is still dE 24 apart for normal vision)
--   [1] full name (the log, the report and the Discord embed use it)   [2] colour   [3] short name for the panel
local STAGES = {
    start    = { "Starting",           Color3.fromRGB(206, 201, 196), "Starting"  },   -- grey: nothing started yet
    cast     = { "Casting",            Color3.fromRGB(30, 150, 235),  "Casting"   },   -- blue: line going into the water
    wait     = { "Waiting for a bite", Color3.fromRGB(250, 226, 50),  "Waiting"   },   -- yellow: patience (yellow means nothing else)
    shake    = { "Shaking",            Color3.fromRGB(238, 70, 200),  "Shaking"   },   -- magenta: a bite, press fast
    reel     = { "Reeling",            Color3.fromRGB(84, 214, 120),  "Reeling"   },   -- green: fish on the line
    cooldown = { "Cooldown",           Color3.fromRGB(194, 172, 255), "Cooldown"  },   -- lavender: resting
    paused   = { "Paused",             Color3.fromRGB(251, 78, 90),   "Paused"    },   -- red: stopped
    walk     = { "Walking back",       Color3.fromRGB(74, 228, 238),  "Walking"   },   -- cyan: moving
    fix      = { "Repairing",          Color3.fromRGB(252, 134, 24),  "Repairing" },   -- orange: something needed fixing
}

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function round(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end

local function label(parent, s, size, font, color, pos, sz, align)
    return mk("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Text = s, TextSize = size, Font = font,
        TextColor3 = color, Position = pos, Size = sz, TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = align or Enum.TextXAlignment.Left,
    }, parent)
end

local function tween(o, props, t, style, dir)
    local tw
    pcall(function()
        tw = TweenService:Create(o, TweenInfo.new(t or 0.22, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
        tw:Play()
    end)
    return tw
end

local shownText = setmetatable({}, { __mode = "k" })
local function setText(o, s)       -- only touch the property when it changed
    if shownText[o] ~= s then
        shownText[o] = s
        o.Text = s
    end
end

local function fmtTime(s)
    s = math.max(0, math.floor(s))
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

local function accColor(a)
    if a == nil then return PAL.dim end
    if a >= 0.9 then return PAL.good elseif a >= 0.75 then return PAL.warn end
    return PAL.bad
end

local function buildPanel(root)
    local W, WM, HM = 232, 204, 36              -- width, shrunk width, header height
    local BASE_H, TOOLS_H = 228, 133            -- card height without / with the tools drawer
    local u = { collapsed = saved.min == true, tools = false }
    local BOLD, MED, REG = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.Gotham
    local LEFT, MID, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
    local QUINT, BORDER = Enum.EasingStyle.Quint, Enum.ApplyStrokeMode.Border
    local touchOnly = UIS.TouchEnabled and not UIS.MouseEnabled

    -- set properties now, or ease to them
    local function put(o, props, instant)
        if instant then
            for k, val in pairs(props) do o[k] = val end
        else
            tween(o, props, 0.18)
        end
    end

    -- hover / press feedback laid over a button, whatever colour the button is
    local function feel(btn, r)
        local ov = mk("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 30,
        }, btn)
        round(ov, r)
        local over, down = false, false
        local function show()
            tween(ov, { BackgroundTransparency = down and 0.8 or (over and 0.92 or 1) }, 0.1)
        end
        if not touchOnly then
            btn.MouseEnter:Connect(function() over = true; show() end)
        end
        btn.MouseLeave:Connect(function() over, down = false, false; show() end)
        btn.MouseButton1Down:Connect(function() down = true; show() end)
        btn.MouseButton1Up:Connect(function() down = false; show() end)
    end

    local sg = mk("ScreenGui", {
        Name = randName(), ResetOnSpawn = false, DisplayOrder = 999,
        IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local v = viewport()
    local x0 = clamp(tonumber(saved.x) or 10, 0, math.max(0, v.X - 120))
    local y0 = clamp(tonumber(saved.y) or 58, 0, math.max(0, v.Y - 60))

    local card = mk("Frame", {
        Name = "c", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = true,
        ClipsDescendants = true, Position = UDim2.fromOffset(x0, y0 - 10),
        Size = UDim2.fromOffset(u.collapsed and WM or W, u.collapsed and HM or BASE_H),
    }, sg)
    round(card, 16)
    mk("UIGradient", { Color = ColorSequence.new(PAL.bg0, PAL.bg1), Rotation = 90 }, card)
    u.stroke = mk("UIStroke", { Color = PAL.line, Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = BORDER }, card)

    ------------------------------------------------ header: status dot, title (or the pill when shrunk), tools, shrink; drag handle
    local head = mk("Frame", { BackgroundTransparency = 1, Active = true, Size = UDim2.new(1, 0, 0, HM) }, card)
    u.dot = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PAL.dim, BorderSizePixel = 0,
        Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(8, 8),
    }, head)
    round(u.dot, 99)
    u.title = label(head, "AutoFish", 14, BOLD, PAL.text, UDim2.fromOffset(32, 0), UDim2.fromOffset(66, HM))
    u.tag   = label(head, "v6-11", 10, REG, PAL.faint, UDim2.fromOffset(98, 1), UDim2.fromOffset(34, HM))
    u.pill  = mk("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, RichText = true, Text = "", TextSize = 12, Font = BOLD,
        TextColor3 = PAL.text, TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -76, 1, 0), Visible = false,
    }, head)

    u.toolsBtn = mk("TextButton", {
        AutoButtonColor = false, BackgroundColor3 = PAL.cell2, BorderSizePixel = 0, Text = "",
        Position = UDim2.new(1, -100, 0, 5), Size = UDim2.fromOffset(58, 26),
    }, head)
    round(u.toolsBtn, 9)
    local toolsLab = label(u.toolsBtn, "Tools", 11, MED, PAL.dim, UDim2.fromOffset(11, 0), UDim2.fromOffset(32, 26))
    u.chev = mk("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, Text = ">",
        TextSize = 11, Font = BOLD, TextColor3 = PAL.dim, Rotation = 90,
        Position = UDim2.fromOffset(46, 13), Size = UDim2.fromOffset(10, 10),
    }, u.toolsBtn)
    feel(u.toolsBtn, 9)

    u.min = mk("TextButton", {
        AutoButtonColor = false, BackgroundColor3 = PAL.cell2, BorderSizePixel = 0, Text = "-",
        TextSize = 16, Font = BOLD, TextColor3 = PAL.dim,
        Position = UDim2.new(1, -36, 0, 5), Size = UDim2.fromOffset(28, 26),
    }, head)
    round(u.min, 9)
    feel(u.min, 9)

    ------------------------------------------------ body
    local body = mk("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HM), Size = UDim2.fromOffset(W, 300),
    }, card)
    u.body = body
    mk("Frame", {
        BackgroundColor3 = PAL.line, BackgroundTransparency = 0.5, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(208, 1),
    }, body)

    -- what it is doing now: the stage name, the clock, the latest log line
    u.stage = label(body, "Starting", 17, BOLD, PAL.dim, UDim2.fromOffset(12, 7), UDim2.fromOffset(140, 24))
    u.stagePos = u.stage.Position
    u.time  = label(body, "00:00:00", 11, MED, PAL.dim, UDim2.new(1, -88, 0, 9), UDim2.fromOffset(76, 20), RIGHT)
    u.note  = label(body, "", 10, REG, PAL.dim, UDim2.fromOffset(12, 33), UDim2.fromOffset(208, 14))

    -- the line: one segment per step of a catch, each in its own colour; the bobber rides it
    u.railKeys = { "cast", "wait", "shake", "reel", "cooldown" }
    u.rail = {}
    u.segW = (208 - 4 * 4) / 5
    for i = 1, 5 do
        local seg = mk("Frame", {
            BackgroundColor3 = PAL.track, BackgroundTransparency = 0, BorderSizePixel = 0,
            Position = UDim2.fromOffset(12 + (i - 1) * (u.segW + 4), 54), Size = UDim2.fromOffset(u.segW, 4),
        }, body)
        round(seg, 2)
        u.rail[i] = seg
    end
    u.bob = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 56), Size = UDim2.fromOffset(12, 12), ZIndex = 5,
    }, body)
    u.bobDot = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PAL.dim, BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 5,
    }, u.bob)
    round(u.bobDot, 99)
    mk("UIStroke", { Color = PAL.text, Thickness = 1.5, ApplyStrokeMode = BORDER }, u.bobDot)
    u.bobT = TweenService:Create(u.bobDot,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Position = UDim2.new(0.5, 0, 0.5, 2) })

    -- three numbers, separated by hairlines instead of boxes
    local function stat(i, caption)
        local x = 12 + (i - 1) * 73
        local val = label(body, "-", 18, BOLD, PAL.text, UDim2.fromOffset(x, 72), UDim2.fromOffset(62, 22))
        label(body, caption, 10, REG, PAL.dim, UDim2.fromOffset(x, 95), UDim2.fromOffset(62, 12))
        if i > 1 then
            mk("Frame", {
                BackgroundColor3 = PAL.line, BackgroundTransparency = 0.45, BorderSizePixel = 0,
                Position = UDim2.fromOffset(x - 8, 74), Size = UDim2.fromOffset(1, 34),
            }, body)
        end
        return val
    end
    u.caught = stat(1, "Caught")
    u.rate   = stat(2, "Per hour")
    u.acc    = stat(3, "Accuracy")
    u.caughtScale = mk("UIScale", { Scale = 1 }, u.caught)
    local bar = mk("Frame", {
        BackgroundColor3 = PAL.track, BorderSizePixel = 0, ClipsDescendants = true,
        Position = UDim2.fromOffset(158, 111), Size = UDim2.fromOffset(50, 3),
    }, body)
    round(bar, 2)
    u.fill = mk("Frame", { BackgroundColor3 = PAL.dim, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, bar)
    round(u.fill, 2)

    -- the one big control
    u.btn = mk("TextButton", {
        AutoButtonColor = false, BackgroundColor3 = PAL.onBtn, BorderSizePixel = 0, Text = "",
        Position = UDim2.fromOffset(12, 124), Size = UDim2.fromOffset(208, 34),
    }, body)
    round(u.btn, 11)
    u.btnText = mk("TextLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0, RichText = true, Text = "", TextSize = 14, Font = BOLD,
        TextColor3 = PAL.text, TextXAlignment = MID, Size = UDim2.fromScale(1, 1), ZIndex = 2,
    }, u.btn)
    feel(u.btn, 11)

    -- health readouts under it: time since the last fish, repairs so far, network ping
    local function readout(x, w, align)
        return mk("TextLabel", {
            BackgroundTransparency = 1, BorderSizePixel = 0, RichText = true, Text = "", TextSize = 10, Font = REG,
            TextColor3 = PAL.dim, TextXAlignment = align, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(x, 166), Size = UDim2.fromOffset(w, 14),
        }, body)
    end
    u.rAge  = readout(12, 86, LEFT)
    u.rFix  = readout(98, 48, MID)
    u.rPing = readout(146, 74, RIGHT)

    ------------------------------------------------ tools drawer (opens under the readouts)
    local drawer = mk("Frame", {
        BackgroundTransparency = 1, Visible = false, ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 188), Size = UDim2.fromOffset(W, 137),
    }, body)
    mk("Frame", {
        BackgroundColor3 = PAL.line, BackgroundTransparency = 0.5, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 2), Size = UDim2.fromOffset(208, 1),
    }, drawer)
    local pages = mk("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 10), Size = UDim2.fromOffset(W, 117),
    }, drawer)
    local page1 = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(W, 117) }, pages)
    local page2 = mk("Frame", { BackgroundTransparency = 1, Visible = false, Position = UDim2.fromOffset(W, 0), Size = UDim2.fromOffset(W, 117) }, pages)
    local page3 = mk("Frame", { BackgroundTransparency = 1, Visible = false, Position = UDim2.fromOffset(W, 0), Size = UDim2.fromOffset(W, 117) }, pages)

    -- a switch row: label on the left, switch on the right
    local function toggle(parent, x, y, text, key, after)
        local b = mk("TextButton", {
            AutoButtonColor = false, BackgroundColor3 = PAL.cell, BorderSizePixel = 0, Text = "",
            Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(101, 24),
        }, parent)
        round(b, 8)
        local lab = label(b, text, 10, MED, PAL.dim, UDim2.fromOffset(9, 0), UDim2.new(1, -46, 1, 0))
        local track = mk("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = PAL.track, BorderSizePixel = 0,
            Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(26, 14),
        }, b)
        round(track, 99)
        local knob = mk("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = PAL.dim, BorderSizePixel = 0,
            Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(10, 10),
        }, track)
        round(knob, 99)
        feel(b, 8)
        local function look(instant)
            local on = CFG[key] and true or false
            put(track, { BackgroundColor3 = on and PAL.chipOn or PAL.track }, instant)
            put(knob, { Position = UDim2.new(0, on and 14 or 2, 0.5, 0), BackgroundColor3 = on and PAL.text or PAL.dim }, instant)
            put(lab, { TextColor3 = on and PAL.text or PAL.dim }, instant)
        end
        look(true)
        b.Activated:Connect(function()
            CFG[key] = not CFG[key]
            look()
            after()
        end)
        return b
    end

    -- an action button: outlined, label centred
    local function button(parent, x, y, text)
        local b = mk("TextButton", {
            AutoButtonColor = false, BackgroundColor3 = PAL.cell, BorderSizePixel = 0, Text = "",
            Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(101, 24),
        }, parent)
        round(b, 8)
        mk("UIStroke", { Color = PAL.line, Thickness = 1, Transparency = 0.5, ApplyStrokeMode = BORDER }, b)
        local lab = label(b, text, 10, MED, PAL.text, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), MID)
        feel(b, 8)
        return b, lab
    end

    -- page 1: settings and the two actions
    toggle(page1, 12, 0,   "Human",   "HUMAN",   save)
    toggle(page1, 119, 0,  "Auto-fix", "RECOVER", save)
    toggle(page1, 12, 29,  "Debug",   "DEBUG",   save)
    toggle(page1, 119, 29, "Perfect", "PERFECT", save)
    local rep, repLab = button(page1, 12, 62, "Copy report")
    u.rep = rep
    local hookBtn = button(page1, 119, 62, "Webhook")
    u.hookDot = mk("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = PAL.faint, BorderSizePixel = 0,
        Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(6, 6),
    }, hookBtn)
    round(u.hookDot, 99)
    local fishBtn, fishLab = button(page1, 12, 91, "Fish list")
    fishBtn.Size = UDim2.fromOffset(208, 24)

    rep.Activated:Connect(function()
        local ok, how, info = pcall(function() return copyReport() end)
        local copied = ok and how == "clipboard"
        repLab.Text = copied and (info and ("Copied " .. info) or "Copied") or ((ok and how == "console") and "See console" or "Failed")
        repLab.TextColor3 = copied and PAL.good or ((ok and how == "console") and PAL.warn or PAL.bad)
        task.delay(2.2, function()
            if repLab.Parent then
                repLab.Text = "Copy report"
                tween(repLab, { TextColor3 = PAL.text }, 0.2)
            end
        end)
    end)

    -- page 2: webhook (URL box, what to send, test)
    local hasUrl = (CFG.NOTIFY_URL or "") ~= ""
    u.hookBox = mk("TextBox", {
        BackgroundColor3 = PAL.cell, BorderSizePixel = 0, ClearTextOnFocus = false, ClipsDescendants = true,
        PlaceholderText = "paste Discord webhook URL", PlaceholderColor3 = PAL.dim,
        Text = hasUrl and ("webhook saved  ..." .. CFG.NOTIFY_URL:sub(-6)) or "",
        TextSize = 10, Font = REG, TextColor3 = PAL.text, TextXAlignment = LEFT,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(208, 26),
    }, page2)
    round(u.hookBox, 9)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, u.hookBox)
    local boxRing = mk("UIStroke", { Color = PAL.line, Thickness = 1, Transparency = 0.5, ApplyStrokeMode = BORDER }, u.hookBox)
    u.hookBox.Focused:Connect(function()
        u.hookBox.Text, u.hookBox.PlaceholderText = "", "paste Discord webhook URL"
        tween(boxRing, { Color = PAL.dim, Transparency = 0.1 }, 0.15)
        task.delay(30, function()   -- a box that keeps the keyboard focus would swallow the script's own key presses
            if u.hookBox.Parent and u.hookBox:IsFocused() then u.hookBox:ReleaseFocus() end
        end)
    end)
    u.hookBox.FocusLost:Connect(function()
        tween(boxRing, { Color = PAL.line, Transparency = 0.5 }, 0.2)
        pcall(HK.typed, u.hookBox.Text)
    end)
    local hookSave = function() pcall(HK.save) end
    toggle(page2, 12, 32,  "Catches", "NOTIFY_FISH",   hookSave)
    toggle(page2, 119, 32, "Events",  "NOTIFY_EVENTS", hookSave)
    local testBtn = button(page2, 12, 62, "Send test")
    local backBtn = button(page2, 119, 62, "Back")
    testBtn.Activated:Connect(function() task.spawn(function() pcall(HK.test) end) end)

    -- a dot on the Webhook button: lit once a URL is saved (HK.typed calls this after the URL box changes)
    function u.hookLook()
        local has = (CFG.NOTIFY_URL or "") ~= ""
        tween(u.hookDot, { BackgroundColor3 = has and PAL.good or PAL.faint }, 0.18)
    end
    u.hookLook()

    -- page 3: every fish caught in this server (by hand or script), oldest first. "12h" = caught by hand
    do
        local list = mk("ScrollingFrame", {
            BackgroundColor3 = PAL.cell, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = PAL.dim,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(208, 86),
        }, page3)
        round(list, 9)
        mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)
        mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6),
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, list)
        local empty = mk("TextLabel", {
            BackgroundTransparency = 1, BorderSizePixel = 0, Text = "no fish yet", TextSize = 10, Font = REG,
            TextColor3 = PAL.dim, TextXAlignment = LEFT, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 14),
        }, list)
        local dim, good = "#" .. PAL.dim:ToHex(), "#" .. PAL.good:ToHex()
        local rows = {}
        local function rowText(i, e)
            local nm = (e.name:gsub("[<>&]", ""))
            local st = (e.mut == nil or e.mut == "") and "-" or e.mut
            return string.format('<font color="%s">%d%s</font> %s <font color="%s">%s</font> <font color="%s">%s</font>',
                dim, i, e.src == "hand" and "h" or "", nm, dim, (e.kg and string.format("%.1fkg", e.kg) or "-") .. ((e.price and HK.money) and (" " .. HK.money(e.price)) or ""),
                (st == "-" or st == "Normal") and dim or good, (st:gsub("[<>&]", "")))
        end
        function u.fishRefresh()
            local n = #HK.catches
            empty.Visible = (n == 0)
            local atEnd = list.CanvasPosition.Y >= list.AbsoluteCanvasSize.Y - list.AbsoluteSize.Y - 24
            for i = math.min(#rows + 1, math.max(1, n - 5)), n do   -- new rows + the last few (a merge can fill them in late)
                local r = rows[i]
                if not r then
                    r = mk("TextLabel", {
                        BackgroundTransparency = 1, BorderSizePixel = 0, RichText = true, TextSize = 10, Font = REG,
                        TextColor3 = PAL.text, TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd,
                        LayoutOrder = i, Size = UDim2.new(1, 0, 0, 14),
                    }, list)
                    rows[i] = r
                end
                r.Text = rowText(i, HK.catches[i])
            end
            fishLab.Text = n > 0 and ("Fish list  (" .. n .. ")") or "Fish list"
            if atEnd then task.defer(function() list.CanvasPosition = Vector2.new(0, 1e5) end) end
        end
        u.fishBack = button(page3, 12, 91, "Back")
        u.fishAll = button(page3, 119, 91, "Send all")
        u.fishRefresh()
    end

    ------------------------------------------------ behaviour: pages, drawer, shrink
    local function showPage(n)
        u.pk = (u.pk or 0) + 1
        local token = u.pk
        for i, p in ipairs({ page1, page2, page3 }) do
            if i == n then
                p.Visible = true
                tween(p, { Position = UDim2.fromOffset(0, 0) }, 0.26, QUINT)
            else
                tween(p, { Position = UDim2.fromOffset(i < n and -W or W, 0) }, 0.26, QUINT)
                task.delay(0.3, function()
                    if u.pk == token then p.Visible = false end
                end)
            end
        end
    end
    hookBtn.Activated:Connect(function() showPage(2) end)
    backBtn.Activated:Connect(function() showPage(1) end)
    fishBtn.Activated:Connect(function() showPage(3) end)
    u.fishBack.Activated:Connect(function() showPage(1) end)
    u.fishAll.Activated:Connect(function() task.spawn(function() pcall(HK.sendAll) end) end)

    local function applySize(instant)
        local w = u.collapsed and WM or W
        local h = u.collapsed and HM or (BASE_H + (u.tools and TOOLS_H or 0))
        if instant then
            card.Size = UDim2.fromOffset(w, h)
            return
        end
        tween(card, { Size = UDim2.fromOffset(w, h) }, 0.26, QUINT)
        if not u.collapsed then                    -- keep the bottom edge on screen
            local maxY = math.max(0, viewport().Y - h - 6)
            if card.Position.Y.Offset > maxY then
                u.posT = tween(card, { Position = UDim2.fromOffset(card.Position.X.Offset, maxY) }, 0.26, QUINT)
            end
        end
    end

    local function setTools(open)
        u.tools = open
        u.tk = (u.tk or 0) + 1
        local token = u.tk
        if open then
            drawer.Visible = true
        else
            task.delay(0.3, function()
                if u.tk == token then drawer.Visible = false end
            end)
        end
        tween(u.chev, { Rotation = open and -90 or 90 }, 0.2)
        tween(u.toolsBtn, { BackgroundColor3 = open and PAL.line or PAL.cell2 }, 0.18)
        tween(toolsLab, { TextColor3 = open and PAL.text or PAL.dim }, 0.18)
        applySize()
    end
    u.toolsBtn.Activated:Connect(function() setTools(not u.tools) end)

    local function setCollapsed(c, instant)
        u.collapsed = c
        u.ck = (u.ck or 0) + 1
        local token = u.ck
        u.title.Visible, u.tag.Visible, u.pill.Visible = not c, not c, c
        u.toolsBtn.Visible = not c
        u.min.Text = c and "+" or "-"
        if c and not instant then
            task.delay(0.3, function()             -- let the card roll up before the body is hidden
                if u.ck == token then body.Visible = false end
            end)
        else
            body.Visible = not c
        end
        applySize(instant)
    end
    u.min.Activated:Connect(function()
        setCollapsed(not u.collapsed)
        save()
    end)
    setCollapsed(u.collapsed, true)

    ------------------------------------------------ drag by the header
    local dragging, from, startPos = false, nil, nil
    head.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if u.posT then pcall(function() u.posT:Cancel() end) end      -- a drag beats a slide that is still running
            dragging, from, startPos = true, i.Position, card.Position
            tween(u.stroke, { Thickness = 2.4, Transparency = 0.1 }, 0.12)
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    tween(u.stroke, { Thickness = 1.5, Transparency = 0.35 }, 0.2)
                    save()
                end
            end)
        end
    end)
    u.conn = UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d, vp = i.Position - from, viewport()
            card.Position = UDim2.fromOffset(
                clamp(startPos.X.Offset + d.X, 0, math.max(0, vp.X - 80)),
                clamp(startPos.Y.Offset + d.Y, 0, math.max(0, vp.Y - 40)))
        end
    end)

    sg.Destroying:Connect(function() pcall(function() u.bobT:Cancel() end) end)
    u.card, u.gui = card, sg
    sg.Parent = root
    u.posT = tween(card, { Position = UDim2.fromOffset(x0, y0) }, 0.45, QUINT)   -- slides down into place
    return u
end

local paint
do
    -- colour of the log line, by what it says (first rule that matches wins; Lua patterns on the lower-cased text):
    --   red = something failed or needs you, orange = the script is correcting itself or lost a fish,
    --   green = good news, grey = routine
    local TONES = {
        { "bad",  { "^error", "^panel failed", "^reel: ", "method failed", "send failed", "test: failed",
                    "not a discord", "^no rod", "^no hidden", "never registers", "^reel gui is up" } },
        { "fix",  { "^walking back", "repair step", "^still stuck", " %- waiting %d", "can't walk back",
                    "^idle %d", "^nothing after", "^bobber stays", "^re%-equipping", "did nothing",
                    "had no effect", "^switching to", "^watchdog", "not found %- using", "^fish got away" } },
        { "good", { "^reel done", "^fish: ", "^back on the spot", "bobber check back on", "started %- tap",
                    "test: sent" } },
    }
    local TONE_COL = { bad = PAL.bad, fix = STAGES.fix[2], good = PAL.good }
    local function tone(s)
        s = tostring(s):lower()
        for _, rule in ipairs(TONES) do
            for _, pat in ipairs(rule[2]) do
                if s:find(pat) then return rule[1] end
            end
        end
        return nil
    end

    local function hex(c)
        return string.format("#%02X%02X%02X", px(c.R * 255), px(c.G * 255), px(c.B * 255))
    end

    local function fmtAge(s)
        s = math.max(0, math.floor(s))
        if s < 60 then return string.format("%ds", s) end
        return string.format("%dm%02ds", math.floor(s / 60), s % 60)
    end

    local HINT_ON, HINT_OFF = Color3.fromRGB(214, 247, 232), Color3.fromRGB(255, 224, 228)
    local warned = false

    local function inner()
        -- while paused the panel says "Paused", even if the loop is still finishing its last step
        local sk = running and stage or "paused"
        local st = STAGES[sk] or STAGES.start
        local col, name = st[2], st[3] or st[1]
        local now = os.clock()

        -- the stage changed: colour, name, line segments, bobber
        if ui.sk ~= sk then
            ui.sk = sk
            tween(ui.dot, { BackgroundColor3 = col }, 0.25)
            tween(ui.stroke, { Color = col }, 0.3)
            ui.stage.Text = name
            ui.stage.TextColor3 = col
            ui.stage.TextTransparency = 1
            ui.stage.Position = UDim2.fromOffset(ui.stagePos.X.Offset + 10, ui.stagePos.Y.Offset)
            tween(ui.stage, { TextTransparency = 0, Position = ui.stagePos }, 0.25, Enum.EasingStyle.Quint)
            local idx = 0
            for i, k in ipairs(ui.railKeys) do
                if k == sk then idx = i end
            end
            -- in a catch the bobber sits on that step; for paused / repairing / walking / starting it is reeled in
            local bx = (idx > 0) and (12 + (idx - 1) * (ui.segW + 4) + ui.segW / 2) or 12
            tween(ui.bob, { Position = UDim2.fromOffset(bx, 56) }, 0.5, Enum.EasingStyle.Quint)
            tween(ui.bobDot, { BackgroundColor3 = col }, 0.25)
            for i, seg in ipairs(ui.rail) do
                local c, t = col, (sk == "start") and 0.75 or 0.45
                if idx > 0 then                                              -- now / done / still to come
                    if i > idx then
                        c, t = PAL.track, 0
                    else
                        c, t = STAGES[ui.railKeys[i]][2], (i == idx) and 0 or 0.55
                    end
                end
                tween(seg, { BackgroundColor3 = c, BackgroundTransparency = t }, 0.3)
            end
        end

        -- running <-> paused: button colour; the bobber bobs only while running
        if ui.run ~= running then
            ui.run = running
            tween(ui.btn, { BackgroundColor3 = running and PAL.onBtn or PAL.offBtn }, 0.25)
            pcall(function()
                if running then
                    ui.bobT:Play()
                else
                    ui.bobT:Cancel()
                    ui.bobDot.Position = UDim2.fromScale(0.5, 0.5)
                end
            end)
        end
        setText(ui.btnText, running
            and string.format('Running  <font size="11" color="%s">tap to pause</font>', hex(HINT_ON))
            or string.format('Paused  <font size="11" color="%s">tap to resume</font>', hex(HINT_OFF)))

        -- numbers
        local el = now - sessionStart
        local a = (stage == "reel" and curAcc) or lastAcc
        setText(ui.time, fmtTime(el))
        setText(ui.caught, tostring(count))
        if ui.n ~= count then
            if ui.n and count > ui.n then          -- a fish was counted: the number lights up and pops
                ui.caught.TextColor3 = PAL.good
                tween(ui.caught, { TextColor3 = PAL.text }, 0.9)
                ui.caughtScale.Scale = 1.3
                tween(ui.caughtScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
            end
            ui.n = count
        end
        setText(ui.rate, (count > 0 and el > 90) and tostring(px(count / (el / 3600))) or "-")
        setText(ui.acc, a and string.format("%d%%", px(a * 100)) or "-")
        local ac = accColor(a)
        if ui.ac ~= ac then
            ui.ac = ac
            tween(ui.acc, { TextColor3 = ac }, 0.2)
            tween(ui.fill, { BackgroundColor3 = ac }, 0.2)
        end
        local fa = clamp(a or 0, 0, 1)
        if not ui.fa or math.abs(ui.fa - fa) > 0.004 then
            ui.fa = fa
            tween(ui.fill, { Size = UDim2.new(fa, 0, 1, 0) }, 0.2)
        end
        setText(ui.pill, string.format('<font color="%s">%s</font>  <font size="11" color="%s">%d fish</font>',
            hex(col), name, hex(PAL.dim), count))

        -- latest log line, coloured by what it says
        if ui.noteSrc ~= note then
            ui.noteSrc = note
            ui.note.Text = note
            tween(ui.note, { TextColor3 = TONE_COL[tone(note)] or PAL.dim }, 0.2)
        end

        -- health readouts: coloured only when they mean something
        --   last fish: yellow past half of CFG.WATCHDOG, red past 80% (never while walking / repairing, like the watchdog)
        local age, wd = now - ST.lastFish, tonumber(CFG.WATCHDOG) or 0
        local ageCol = PAL.dim
        if running and wd > 0 and sk ~= "walk" and sk ~= "fix" then
            if age > wd * 0.8 then ageCol = PAL.bad elseif age > wd * 0.5 then ageCol = PAL.warn end
        end
        local pingCol = PAL.dim
        if PING.now then pingCol = PING.now < 120 and PAL.good or (PING.now < 250 and PAL.warn or PAL.bad) end
        setText(ui.rAge, string.format('Last fish <font color="%s">%s</font>', hex(ageCol), fmtAge(age)))
        setText(ui.rFix, string.format('Fixes <font color="%s">%d</font>', hex(ST.fixes > 0 and STAGES.fix[2] or PAL.dim), ST.fixes))
        setText(ui.rPing, string.format('Ping <font color="%s">%s</font>', hex(pingCol), pingText()))
    end

    -- a slip in the drawing code must never take the fishing loop down with it
    paint = function()
        if not ui then return end
        local ok, err = pcall(inner)
        if not ok and not warned then
            warned = true
            log("panel paint error: " .. tostring(err))
        end
    end
end

local function setRunning(v)
    if v == running then return end
    local midReel = (stage == "reel")
    running = v
    if v then
        fails, home, ST.lastFish = 0, nil, os.clock()
        stage = "start"
    else
        stage = "paused"
        if midReel then log("finishing this reel, then pausing") end
    end
    paint()
end

-- the panel lives in a hidden UI container, never inside PlayerGui
local okHost, root = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
if okHost and root then
    pcall(function()
        local old = root:FindFirstChild("AutoFishToggle")   -- left behind by v3
        if old then old:Destroy() end
    end)
    local okUi, res = pcall(buildPanel, root)
    if okUi then
        ui, gui = res, res.gui
        ui.btn.Activated:Connect(function() setRunning(not running) end)
    else
        log("panel failed: " .. tostring(res))
    end
else
    log("no hidden UI container on this executor - running without the panel")
end
paint()

if CFG.ANTI_AFK then
    afk = lp.Idled:Connect(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end

if CFG.DEBUG then
    local seen = {}
    dbg = pg.ChildAdded:Connect(function(c)
        if not seen[c.Name] then
            seen[c.Name] = true
            log("new GUI:", c.Name, c.ClassName)
        end
    end)
    local okx, ex = pcall(function() return identifyexecutor() end)
    log("v6 | executor:", okx and ex or "?", "| touch:", UIS.TouchEnabled,
        "| keyboard:", UIS.KeyboardEnabled, "| firesignal:", type(firesignal) == "function")
    log("PlayerGui right now:", names(pg))
end

env.__autofish_stop = function()
    stopped, running = true, false
    if afk then afk:Disconnect() end
    if dbg then dbg:Disconnect() end
    if ui and ui.conn then ui.conn:Disconnect() end
    if recorder then recorder:Disconnect() end
    if gui then pcall(function() gui:Destroy() end) end
end

---------------------------------------------------------------- input

-- is something that swallows clicks (a button, an Active frame) drawn at this spot?
local function blocked(x, y)
    local ins = inset()
    for _, yy in ipairs({ y, px(y - ins.Y) }) do
        local ok, list = pcall(function() return pg:GetGuiObjectsAtPosition(x, yy) end)
        if ok then
            for _, o in ipairs(list) do
                if o.Visible and (o.Active or o:IsA("GuiButton") or o:IsA("TextBox")) then return true end
            end
        end
    end
    return false
end

-- is our own panel in the way? (it is not in PlayerGui, so blocked() cannot see it)
local function overUs(x, y)
    if not (ui and ui.card and ui.card.Parent) then return false end
    local p, s, ins = ui.card.AbsolutePosition, ui.card.AbsoluteSize, inset()
    for _, yy in ipairs({ y, y - ins.Y }) do
        if x >= p.X - 12 and x <= p.X + s.X + 12 and yy >= p.Y - 12 and yy <= p.Y + s.Y + 12 then return true end
    end
    return false
end

local SPOTS = {
    { 0.5, 0.42 }, { 0.5, 0.30 }, { 0.36, 0.40 }, { 0.64, 0.40 }, { 0.5, 0.58 },
    { 0.75, 0.5 }, { 0.62, 0.30 }, { 0.25, 0.5 }, { 0.72, 0.62 },
}

-- a spot on the 3D world that no GUI covers, a little different every time
local function point()
    local v = viewport()
    for _, s in ipairs(SPOTS) do
        local x = px(v.X * (s[1] + (math.random() - 0.5) * 0.04))
        local y = px(v.Y * (s[2] + (math.random() - 0.5) * 0.04))
        if not blocked(x, y) and not overUs(x, y) then return x, y end
    end
    return px(v.X * 0.5), px(v.Y * 0.45)
end

-- press / release, one function per way of sending it
local PRESS = {
    mouse  = function(down, x, y) VIM:SendMouseButtonEvent(x, y, 0, down, game, 1) end,
    mouse2 = function(down, x, y) VIM:SendMouseButtonEvent(x, y, 0, down, lp, 0) end,
    touch  = function(down, x, y) VIM:SendTouchEvent(5, down and 0 or 2, x, y) end,
    space  = function(down) VIM:SendKeyEvent(down, Enum.KeyCode.Space, false, game) end,
}

-- somewhere inside a GUI button, in screen coordinates (the top-bar inset is added when needed)
local function btnPoint(b)
    local sg = b:FindFirstAncestorOfClass("ScreenGui")
    local ins = (sg and sg.IgnoreGuiInset) and Vector2.zero or inset()
    local p, s = b.AbsolutePosition, b.AbsoluteSize
    return px(p.X + s.X * (0.3 + math.random() * 0.4) + ins.X),
           px(p.Y + s.Y * (0.3 + math.random() * 0.4) + ins.Y)
end

local SHAKE = {
    nav = function(b)      -- select the button and hit Enter, no coordinates involved
        GuiService.SelectedObject = b
        VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        task.wait(0.03)
        GuiService.SelectedObject = nil
    end,
    click = function(b)
        local x, y = btnPoint(b)
        PRESS.mouse(true, x, y)
        task.wait(0.03 + math.random() * 0.05)
        PRESS.mouse(false, x, y)
    end,
    tap = function(b)
        local x, y = btnPoint(b)
        PRESS.touch(true, x, y)
        task.wait(0.04 + math.random() * 0.04)
        PRESS.touch(false, x, y)
    end,
    signal = function(b)   -- only if the executor has firesignal
        firesignal(b.MouseButton1Click)
        firesignal(b.Activated)
    end,
}

local function castWith(name, rod, x, y)
    if name == "activate" then
        rod:Activate()
        task.wait(rand(CFG.CAST_HOLD))
        pcall(function() rod:Deactivate() end)
    else
        PRESS[name](true, x, y)
        task.wait(rand(CFG.CAST_HOLD))
        PRESS[name](false, x, y)
    end
end

-- keeps one working method per job; after `need` misses in a row it moves to the next one
local function chooser(list, need)
    local c = { i = 1, wins = {}, fails = {} }
    function c.cur() return list[c.i] end
    function c.ok()
        local k = list[c.i]
        c.wins[k] = (c.wins[k] or 0) + 1
        c.fails[k] = 0
    end
    function c.bad()
        local k = list[c.i]
        c.fails[k] = (c.fails[k] or 0) + 1
        if c.fails[k] >= need + ((c.wins[k] or 0) > 0 and 2 or 0) then
            c.fails[k] = 0
            c.i = c.i % #list + 1
            log("switching to", list[c.i])
        end
    end
    return c
end

local C = chooser(CFG.CAST_ORDER, 1)
local S = chooser(CFG.SHAKE_ORDER, 3)
local H = chooser(CFG.HOLD_ORDER, 3)

---------------------------------------------------------------- game logic

local function isRod(t)
    if not t:IsA("Tool") then return false end
    local n = t.Name:lower()
    if CFG.ROD_NAME then return n == CFG.ROD_NAME:lower() end
    if n:find("rod", 1, true) then return true end
    return t:FindFirstChild("events") ~= nil and t:FindFirstChild("values") ~= nil
        and not n:find("harpoon", 1, true) and not n:find("spear", 1, true)
end

-- the rod in your hand, or the first one in the backpack (gets equipped)
local function getRod()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if isRod(t) then return t, hum end
    end
    local bp = lp:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if isRod(t) then
                hum:EquipTool(t)
                task.wait(0.5)
                return t, hum
            end
        end
    end
    return nil
end

local useBobber = true

-- the game puts a "bobber" inside the rod while the line is out
local function lineOut(rod)
    return useBobber and rod.Parent ~= nil and rod:FindFirstChild("bobber") ~= nil
end

local function getShake()
    return getGui(CFG.GUI_SHAKE)
end

-- visible all the way up to its ScreenGui?
local function shown(o)
    while o and not o:IsA("ScreenGui") do
        if o:IsA("GuiObject") and not o.Visible then return false end
        o = o.Parent
    end
    return o ~= nil
end

-- returns the reel GUI plus the white bar and the fish icon (nil while they aren't on screen)
local function getReel()
    local g = getGui(CFG.GUI_REEL)
    if not g then return nil end
    local bar  = find(g, CFG.BAR_NAME, true) or like(g, "player")
    local fish = find(g, CFG.FISH_NAME, true) or like(g, "fish")
    if bar and not (shown(bar) and bar.AbsoluteSize.X > 2) then bar = nil end
    if fish and not shown(fish) then fish = nil end
    return g, bar, fish
end

local function reelReady()
    local g, bar, fish = getReel()
    return g ~= nil and bar ~= nil and fish ~= nil
end

local okGuis, okTexts = nil, nil   -- enabled ScreenGuis / visible texts around the last cast that worked

-- every visible piece of text on screen (counters and clocks left out), to spot a new message
local function visibleTexts()
    local t = {}
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and #d.Text < 80
            and not d.Text:match("^[%d%s:%.,%%/%-+$]*$") and shown(d) then
            t[d.Text] = true
        end
    end
    return t
end

local function enabledGuis()
    local t = {}
    for _, c in ipairs(pg:GetChildren()) do
        if c:IsA("ScreenGui") and c.Enabled then t[c.Name] = true end
    end
    return t
end

-- one line that says what is different now compared with the last cast that worked
local function castDiag(rod, m, x, y)
    pcall(function()
        local ch = lp.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local fresh = {}
        if okGuis then
            for n in pairs(enabledGuis()) do
                if not okGuis[n] then fresh[#fresh + 1] = n end
            end
            table.sort(fresh)
        end
        local texts = {}
        if okTexts then
            for tx in pairs(visibleTexts()) do
                if not okTexts[tx] and #texts < 12 then texts[#texts + 1] = tx:gsub("[\r\n]+", " "):sub(1, 40) end
            end
        end
        local away = (home and root) and tostring(math.floor((root.Position - home).Magnitude)) or "?"
        log(string.format("diag %s: equipped=%s bobber=%s state=%s fromHome=%s menu=%s typing=%s blocked=%s ping=%s newGui=[%s]",
            m, tostring(rod.Parent == ch), tostring(rod:FindFirstChild("bobber") ~= nil),
            hum and tostring(hum:GetState()):gsub("Enum.HumanoidStateType.", "") or "?",
            away, tostring(GuiService.MenuIsOpen), tostring(UIS:GetFocusedTextBox() ~= nil),
            tostring(blocked(x, y)), pingText(), table.concat(fresh, ",")))
        if #texts > 0 then log("diag new text: " .. table.concat(texts, " | ")) end
    end)
end

-- cast and wait until something proves it worked; otherwise try the next method
local function castLine(rod)
    local resets = 0   -- rod re-equips tried in this call, before any input method gets blamed
    for _ = 1, #CFG.CAST_ORDER * 2 do
        if not (alive() and running) then return false end
        local m = C.cur()
        local x, y = point()
        log("cast via", m)
        local pre = enabledGuis()
        local before = rod:FindFirstChild("bobber")
        local stale = before ~= nil   -- a bobber already there before the cast proves nothing
        -- with the bobber check off, the only proof is the shake / reel GUI; in the logs it shows up
        -- about 1s after a real cast, so 8s is plenty (waiting the full TIMEOUT cost 20s per miss)
        local window = useBobber and CFG.CAST_VERIFY or math.max(CFG.CAST_VERIFY, 8)
        local ok, err = pcall(castWith, m, rod, x, y)
        if not ok then
            ST.castMiss = ST.castMiss + 1
            log("cast method failed:", m, err)
            if m ~= "activate" then pcall(PRESS[m], false, x, y) end
            C.bad()
        else
            local t, seen = os.clock(), false
            while alive() and running and os.clock() - t < window do
                if lineOut(rod) or getShake() or reelReady() then
                    seen = true
                    break
                end
                local now = rod:FindFirstChild("bobber")
                if not useBobber and now and (not stale or now ~= before) then
                    useBobber = true
                    log("bobber check back on")
                    seen = true
                    break
                end
                task.wait(0.1)
            end
            if seen then
                ST.casts = ST.casts + 1
                C.ok()
                okGuis = pre
                pcall(function() okTexts = visibleTexts() end)
                return true
            end
            ST.castMiss = ST.castMiss + 1
            log("cast via", m, "did nothing")
            castDiag(rod, m, x, y)
            -- in the logs all four methods failed one after another, which points at the rod / game state
            -- and not at the input, so reset the rod first and only then blame (and rotate) the method
            local ch = lp.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if resets < 2 and hum then
                resets = resets + 1
                log("re-equipping the rod before blaming '" .. m .. "'")
                pcall(function()
                    hum:UnequipTools()
                    task.wait(0.5)
                    hum:EquipTool(rod)
                    task.wait(0.8)
                end)
            else
                C.bad()
            end
            task.wait(0.6)
        end
    end
    return false
end

-- one shake press; counts as a hit if the button vanished, closed or moved
local shakeNamed = false
local function findShakeButton(shake)
    local b = find(shake, CFG.SHAKE_BUTTON, true)
    if b and b:IsA("GuiObject") and b.Visible and b.AbsoluteSize.X > 2 then return b end
    -- the game's button is not called "button" any more (the GUI dump shows "default", an ImageButton),
    -- so fall back to the first visible button anywhere inside the shake GUI
    for _, d in ipairs(shake:GetDescendants()) do
        if d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 2 and shown(d) then
            if not shakeNamed then
                shakeNamed = true
                log("shake button '" .. CFG.SHAKE_BUTTON .. "' not found - using '" .. d.Name .. "'")
            end
            return d
        end
    end
    return nil
end

local function shakeOnce(shake)
    local b = findShakeButton(shake)
    if not b then return end
    local m = S.cur()
    local p0 = b.AbsolutePosition
    local ok, err = pcall(SHAKE[m], b)
    if not ok then
        log("shake method failed:", m, err)
        S.bad()
        return
    end
    local t, hit = os.clock(), false
    while os.clock() - t < 0.4 do
        task.wait(0.03)
        if not up(shake) or not b.Parent or not b.Visible or (b.AbsolutePosition - p0).Magnitude > 2 then
            hit = true
            break
        end
    end
    if hit then
        ST.shakeHit = ST.shakeHit + 1
        S.ok()
    else
        ST.shakeMiss = ST.shakeMiss + 1
        log("shake via", m, "had no effect")
        S.bad()
    end
end

---------------------------------------------------------------- reel brain
-- Pure maths, no Roblox calls. Each frame it gets where the fish and the bar are and answers
-- "hold or release?". It learns how fast the bar speeds up (hold) and slows down (release), keeps
-- track of the commands still in flight (input lag), aims at where the fish will be, stays inside
-- the track and brakes early enough not to overshoot.
local function newBrain(opts)
    opts = opts or {}
    local human = opts.human
    local B = {}
    local clamp = function(v, a, b) if v < a then return a elseif v > b then return b end return v end

    local ts, fs, bs, n = {}, {}, {}, 0          -- recent samples
    local aHold, aRel = nil, nil                 -- learned accelerations (px/s^2), kept between reels
    if opts.mem then aHold, aRel = opts.mem.aHold, opts.mem.aRel end
    local holdNow, since, lastSwitch = false, 0, -1
    local fv, bv, avgDt = 0, 0, 1 / 60
    local vmax, vR, vL = 0, 0, 0
    local wob, wobT = 0, 0
    local stable = 0                              -- seconds the command has been unchanged
    local hist = {}                               -- { time, command } every time the command changed
    local function cmdAt(tau)
        for i = #hist, 1, -1 do
            if hist[i][1] <= tau then return hist[i][2] end
        end
        return false
    end

    local function slope(arr, from)
        -- least squares slope of arr[from..n] against ts
        local cnt = n - from + 1
        if cnt < 2 then return 0 end
        local mt, mx = 0, 0
        for i = from, n do mt = mt + ts[i]; mx = mx + arr[i] end
        mt, mx = mt / cnt, mx / cnt
        local num, den = 0, 0
        for i = from, n do
            local dt = ts[i] - mt
            num = num + dt * (arr[i] - mx)
            den = den + dt * dt
        end
        if den < 1e-9 then return 0 end
        return num / den
    end

    -- now, fish centre, bar centre, bar width, fish width, track left, track right
    function B.step(now, f, b, bw, fw, L, R)
        n = n + 1
        ts[n], fs[n], bs[n] = now, f, b
        if n > 8 then
            table.remove(ts, 1); table.remove(fs, 1); table.remove(bs, 1); n = 8
        end
        if n >= 2 then
            local d = ts[n] - ts[n - 1]
            if d > 0 and d < 0.25 then avgDt = avgDt * 0.9 + d * 0.1 end
        end
        -- window: last ~80 ms, at least 3 samples when available
        local from = n
        local win, cap = 0.085, 5
        if not human then win, cap = 0.05, 3 end
        while from > 1 and (ts[n] - ts[from - 1]) <= win and n - from < cap do from = from - 1 end
        if n - from < 2 and from > 1 then from = math.max(1, n - 2) end
        local newFv, newBv = slope(fs, from), slope(bs, from)
        local prevBv = bv
        fv, bv = newFv, newBv
        if math.abs(bv) > vmax then vmax = math.abs(bv) end
        if bv > vR then vR = bv end
        if -bv > vL then vL = -bv end

        local len = math.max(R - L, 50)
        local a0 = len * 4
        if not aHold and opts.mem and opts.mem.nh then   -- calibration loaded from disk, stored as a multiple of the track
            aHold = clamp(opts.mem.nh * len, a0 * 0.15, a0 * 12)
            aRel  = clamp(opts.mem.nr * len, a0 * 0.15, a0 * 12)
        end
        if not aHold then aHold, aRel = a0, a0 end

        -- learn the bar's response from stretches where the command was stable
        stable = stable + avgDt
        local dtv = (n >= 2) and (ts[n] - ts[n - 1]) or avgDt
        if stable > (0.04 + 2.5 * avgDt) and dtv > 0 then
            local acc = (bv - prevBv) / dtv
            local pinned = (b - bw / 2 <= L + 2) or (b + bw / 2 >= R - 2)
            if not pinned and math.abs(bv) < 0.8 * math.max(vmax, 1) + 1 then
                if holdNow and acc > 0 then
                    aHold = clamp(aHold * 0.93 + acc * 0.07, a0 * 0.15, a0 * 12)
                elseif (not holdNow) and acc < 0 then
                    aRel = clamp(aRel * 0.93 - acc * 0.07, a0 * 0.15, a0 * 12)
                end
            end
        end

        -- where do we want the bar? the fish, nudged a little inside the safe margin
        local margin = math.max(0, bw / 2 - fw / 2)
        if human then
            if now > wobT then
                wob = (math.random() * 2 - 1) * 0.35 * margin
                wobT = now + 0.35 + math.random() * 0.8
            end
        else
            wob = 0
        end
        local lat = clamp((CFG.REEL_LAT or 0.03) + 1.6 * avgDt, 0.02, 0.17)
        local lo, hi = L + bw / 2, R - bw / 2
        local fP = f + fv * lat
        local comfort = clamp(1 - math.abs(f - b) / math.max(margin * 0.7, 1), 0, 1)
        local raw = fP + wob * comfort
        local tgt = clamp(raw, lo, hi)
        local tv = (raw < lo or raw > hi) and 0 or fv      -- a target pinned to a wall stands still

        -- where the bar will be once the commands already in flight have landed
        local capR = (vR > len * 0.15) and vR * 1.03 or len * 0.8
        local capL = (vL > len * 0.15) and vL * 1.03 or len * 0.8
        local steps, h = 6, lat / 6
        local bP, bvP = b, bv
        for i = 1, steps do
            local c = cmdAt(now + (i - 1) * h - lat)
            bvP = clamp(bvP + (c and aHold or -aRel) * h, -capL, capR)
            bP = bP + bvP * h
        end
        local rv = bvP - tv
        local stop
        if rv > 0 then stop = rv * rv / (2 * aRel) else stop = -rv * rv / (2 * aHold) end
        stop = clamp(stop, -len * 0.6, len * 0.6)
        local e = tgt - (bP + stop)               -- >0: bar will stop short of the target -> hold

        local band = math.max(1, bw * 0.03)
        local want = holdNow
        if e > band then want = true elseif e < -band then want = false end
        -- sitting on a wall with the target beyond it: just keep pushing
        if tgt >= hi - 0.5 and fP >= hi then want = true end
        if tgt <= lo + 0.5 and fP <= lo then want = false end
        if want ~= holdNow then
            lastSwitch = now; stable = 0
            hist[#hist + 1] = { now, want }
            if #hist > 24 then table.remove(hist, 1) end
        end
        holdNow = want
        if opts.mem then opts.mem.aHold, opts.mem.aRel, opts.mem.len = aHold, aRel, len end
        return want, { zone = math.abs(f - b) <= bw / 2, bv = bv, fv = fv, aHold = aHold, aRel = aRel }
    end
    return B
end

-- what the brain learned about your bar, one entry per rod (rods differ in control);
-- save() writes it to disk and it comes back here as nh / nr
local function memFor(rod)
    local k = ((rod and rod.Name) or "?") .. (POOL.active and "|pool" or "")   -- pool: control is halved, learn it apart
    cal[k] = cal[k] or {}
    return cal[k]
end

-- the minigame: keep the white bar under the fish icon until the GUI closes
local function playReel(reel, bar, fish, rod)
    local track = bar.Parent
    local hx, hy = point()
    local function mid(g) return g.AbsolutePosition.X + g.AbsoluteSize.X / 2 end

    local cur, down, holdT, peak = nil, false, 0, 0
    local function setHold(want)
        local name = H.cur()
        if down and (not want or name ~= cur) then
            pcall(PRESS[cur], false, hx, hy)
            down = false
        end
        if want and not down and up(reel) then
            cur = name
            if pcall(PRESS[name], true, hx, hy) then
                down, holdT, peak = true, os.clock(), 0
            else
                H.bad()
            end
        end
    end

    if CFG.HUMAN and not CFG.PERFECT then pause(CFG.REEL_START) end
    local mem = memFor(rod)
    local brain = newBrain({ human = CFG.HUMAN and not CFG.PERFECT, mem = mem })
    local t0 = os.clock()
    local last, lastPaint, hit, all, fvTop = t0, t0, 0, 0, 0
    local slipT = nil
    local ok, err = pcall(function()
        while alive() and up(reel) and os.clock() - t0 < CFG.REEL_TIMEOUT do   -- finishes even if paused mid-reel
            if not (bar.Parent and fish.Parent) then break end
            local now = os.clock()
            local bw, fw = bar.AbsoluteSize.X, fish.AbsoluteSize.X
            local f, b = mid(fish), mid(bar)
            local L, R
            if track and track.AbsoluteSize.X > 2 then
                L = track.AbsolutePosition.X
                R = L + track.AbsoluteSize.X
            else
                L, R = 0, viewport().X
            end

            local want, info = brain.step(now, f, b, bw, fw, L, R)
            if math.abs(info.fv) > fvTop then fvTop = math.abs(info.fv) end
            setHold(want)
            if not info.zone and not slipT then
                slipT = now - t0
                log(string.format("SLIP at %.2fs | off %dpx | bar %dpx | fish v %d | bar v %d",
                    slipT, px(f - b), px(bw), px(info.fv), px(info.bv)))
            end

            local dt = now - last
            last = now
            if dt > 0 and dt < 0.5 then
                all = all + dt
                if info.zone then hit = hit + dt end
            end
            if now - lastPaint > 0.25 and all > 0 then
                curAcc, lastPaint = hit / all, now
            end

            -- is the hold doing anything? if the bar never speeds up to the right, switch input method
            if down then
                if info.bv > peak then peak = info.bv end
                if now - holdT > 0.6 then
                    local edge = b + bw / 2 >= R - 3
                    if peak > math.max(40, (R - L) * 0.1) then H.ok()
                    elseif not edge and not next(H.wins) then
                        log(string.format("hold '%s' not moving the bar (peak %d px/s)", tostring(H.cur()), px(peak)))
                        H.bad()
                    end
                    holdT, peak = now, 0
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)
    setHold(false)
    if all > 0.5 then
        lastAcc = hit / all
        accHit, accAll = accHit + hit, accAll + all
        ST.reels, ST.reelSecs = ST.reels + 1, ST.reelSecs + all
        mem.n = (tonumber(mem.n) or 0) + 1
        log(string.format("reel done - accuracy %d%%", px(lastAcc * 100)))
        if lastAcc < 0.85 then
            log(string.format("low acc %d%% | fish top %d px/s | aHold %d aRel %d | track %d",
                px(lastAcc * 100), px(fvTop), px(mem.aHold or 0), px(mem.aRel or 0), px(mem.len or 0)))
        end
        save()          -- keeps calibration and lifetime numbers current
    end
    curAcc = nil
    if not ok then log("reel: " .. tostring(err)) end
end

---------------------------------------------------------------- self-repair

local homeLook, pulse, rung = nil, os.clock(), 0

---------------------------------------------------------------- report + notify
-- Optional extras. They only read state; none of them can stop the fishing loop.

-- a GUI's children as indented text, capped so a report stays pasteable
local function treeText(inst, maxLines)
    local out, n = {}, 0
    local function walk(o, depth)
        for _, c in ipairs(o:GetChildren()) do
            if n >= maxLines then return end
            n = n + 1
            local extra = ""
            if c:IsA("GuiObject") then
                extra = string.format(" vis=%s %dx%d", tostring(c.Visible), px(c.AbsoluteSize.X), px(c.AbsoluteSize.Y))
                if c:IsA("TextLabel") or c:IsA("TextButton") then
                    extra = extra .. ' "' .. string.sub((c.Text:gsub("%s+", " ")), 1, 24) .. '"'
                end
            end
            out[#out + 1] = string.rep("  ", depth) .. c.Name .. " [" .. c.ClassName .. "]" .. extra
            walk(c, depth + 1)
        end
    end
    walk(inst, 0)
    if n >= maxLines then out[#out + 1] = "  ... (cut)" end
    return table.concat(out, "\n")
end

local SNAP, snapOrder = {}, {}

-- remember what a GUI looked like the first time it showed up (one entry per key)
local function snapOnce(key, g)
    if SNAP[key] or not g or #snapOrder >= 16 then return end
    snapOrder[#snapOrder + 1] = key
    local ok, txt = pcall(treeText, g, 60)
    SNAP[key] = g.Name .. " [" .. g.ClassName .. "]\n" .. (ok and txt or ("snapshot failed: " .. tostring(txt)))
end

-- GUIs that appear while you play (cast bar, shake, reel, popups) are saved for the report
local pgSeen = {}
for _, c in ipairs(pg:GetChildren()) do pgSeen[c.Name] = true end
recorder = pg.ChildAdded:Connect(function(c)
    if not c:IsA("ScreenGui") or pgSeen[c.Name] then return end
    pgSeen[c.Name] = true
    task.delay(0.4, function()     -- give it a moment to fill with children
        if alive() and c.Parent then pcall(snapOnce, "new " .. c.Name, c) end
    end)
end)

local function pct(a) return a and string.format("%d%%", px(a * 100)) or "-" end

local function span(t)
    if type(t) == "table" then return string.format("%.2f-%.2f", t[1], t[2]) end
    return tostring(t)
end

local function statusLine()
    local el = os.clock() - sessionStart
    return string.format("%s | caught %d | %s/h | accuracy %s | session %s",
        (STAGES[stage] or STAGES.start)[1], count,
        (count > 0 and el > 90) and tostring(px(count / (el / 3600))) or "-",
        pct(accAll > 0 and accHit / accAll or nil), fmtTime(el))
end

local function buildReport()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
    local v, el = viewport(), os.clock() - sessionStart
    local okx, ex = pcall(function() return identifyexecutor() end)
    add("AutoFish v6-11 report")
    out[#out + 1] = "--- POOL lines (oldest first) ---"
    for _, s in ipairs(logbuf.pool or {}) do out[#out + 1] = s end
    out[#out + 1] = "--- last log lines (NEWEST FIRST) ---"
    for i = #logbuf, math.max(1, #logbuf - (tonumber(CFG.REPORT_LINES) or 400) + 1), -1 do out[#out + 1] = logbuf[i] end
    add("executor %s | touch %s | keyboard %s | screen %dx%d | place %s",
        okx and tostring(ex) or "?", tostring(UIS.TouchEnabled), tostring(UIS.KeyboardEnabled),
        px(v.X), px(v.Y), tostring(game.PlaceId))
    add("stage %s | running %s | session %s | caught %d | accuracy %s | fails %d | repair step %d",
        stage, tostring(running), fmtTime(el), count, pct(accAll > 0 and accHit / accAll or nil), fails, rung)
    add("lifetime %d catches | %s running | %d executes", LIFE.catches, fmtTime(LIFE.secs), LIFE.runs)
    add("input methods: cast=%s shake=%s hold=%s | bobber check %s",
        C.cur(), S.cur(), H.cur(), useBobber and "on" or "off")
    add("names: shake=%s button=%s reel=%s bar=%s fish=%s rod=%s",
        CFG.GUI_SHAKE, CFG.SHAKE_BUTTON, CFG.GUI_REEL, CFG.BAR_NAME, CFG.FISH_NAME, tostring(CFG.ROD_NAME or "auto"))
    add("settings: HUMAN=%s GUARD=%s WALK_HOME=%s DEBUG=%s",
        tostring(CFG.HUMAN), tostring(CFG.GUARD), tostring(CFG.WALK_HOME), tostring(CFG.DEBUG))
    add("timing: CAST_HOLD=%s COOLDOWN=%s TIMEOUT=%s REEL_TIMEOUT=%s",
        span(CFG.CAST_HOLD), span(CFG.COOLDOWN), tostring(CFG.TIMEOUT), tostring(CFG.REEL_TIMEOUT))
    add("casts %d (misses %d) | shake presses %d ok, %d no effect | got away %d | errors %d",
        ST.casts, ST.castMiss, ST.shakeHit, ST.shakeMiss, ST.away, ST.errors)
    add("self-repairs %d | last fish %ds ago", ST.fixes, px(os.clock() - ST.lastFish))
    add("reels %d%s | bite wait %s", ST.reels,
        ST.reels > 0 and string.format(" (avg %.0fs)", ST.reelSecs / ST.reels) or "",
        ST.waitN > 0 and string.format("avg %.1fs over %d", ST.waitSum / ST.waitN, ST.waitN) or "-")
    add("ping now %s | avg %dms | max %dms", pingText(),
        PING.n > 0 and math.floor(PING.sum / PING.n + 0.5) or 0, math.floor(PING.max + 0.5))
    if ST.lastErr ~= "" then add("last error: %s", ST.lastErr) end
    for k, m in pairs(cal) do
        local h = (m.aHold and m.len and m.len > 50) and m.aHold / m.len or m.nh
        local r = (m.aRel and m.len and m.len > 50) and m.aRel / m.len or m.nr
        if h and r then
            add("calibration %s: hold %.2f release %.2f (x track), %d reels", k, h, r, math.floor(tonumber(m.n) or 0))
        end
    end
    local gl = {}
    for _, c in ipairs(pg:GetChildren()) do
        gl[#gl + 1] = c.Name .. (c:IsA("ScreenGui") and (c.Enabled and "" or "(off)") or ("[" .. c.ClassName .. "]"))
    end
    out[#out + 1] = "PlayerGui: " .. table.concat(gl, ", ")
    for _, k in ipairs(snapOrder) do
        out[#out + 1] = "--- GUI " .. k .. " ---"
        out[#out + 1] = SNAP[k]
    end
    out[#out + 1] = string.format("--- fish list (%d in this server, last 10) ---", #HK.catches)
    for i = math.max(1, #HK.catches - 9), #HK.catches do
        local e = HK.catches[i]
        out[#out + 1] = string.format("#%d %s | %s | %s | %s | %s", i, e.name,
            e.kg and string.format("%.1fkg", e.kg) or "-", (e.mut ~= "" and e.mut or "-"),
            tostring(e.rar or "-"), tostring(e.src))
    end
    out[#out + 1] = "--- new labels after a catch (last 3 failed name lookups) ---"
    for _, s in ipairs(HK.dumps or {}) do out[#out + 1] = s end
    return table.concat(out, "\n")
end

HK.RP = { parts = nil, i = 0, t = 0 }   -- the report split into clipboard-sized parts

function HK.splitReport(text, size)
    local parts, cur = {}, ""
    for line in (text .. "\n"):gmatch("(.-)\n") do
        while #line > size do
            if cur ~= "" then parts[#parts + 1] = cur; cur = "" end
            parts[#parts + 1] = line:sub(1, size)
            line = line:sub(size + 1)
        end
        if cur ~= "" and #cur + #line + 1 > size then parts[#parts + 1] = cur; cur = "" end
        cur = (cur == "") and line or (cur .. "\n" .. line)
    end
    if cur ~= "" then parts[#parts + 1] = cur end
    return parts
end

copyReport = function()
    local set = setclipboard or toclipboard or set_clipboard
    local size = tonumber(CFG.REPORT_CHUNK) or 0
    -- a part is still waiting (tapped again within 2 min): copy the next one, keep the same report
    if size > 0 and HK.RP.parts and HK.RP.i < #HK.RP.parts and os.clock() - HK.RP.t < 120 then
        HK.RP.i, HK.RP.t = HK.RP.i + 1, os.clock()
        if type(set) == "function" and pcall(set, HK.RP.parts[HK.RP.i]) then
            return "clipboard", HK.RP.i .. "/" .. #HK.RP.parts
        end
    end
    local okb, text = pcall(buildReport)
    if not okb then text = "report failed: " .. tostring(text) .. "\n" .. table.concat(logbuf, "\n") end
    if size > 0 and #text > size then
        HK.RP.parts, HK.RP.i, HK.RP.t = HK.splitReport(text, size), 1, os.clock()
        if type(set) == "function" and pcall(set, HK.RP.parts[1]) then return "clipboard", "1/" .. #HK.RP.parts end
    else
        HK.RP.parts = nil
        if type(set) == "function" and pcall(set, text) then return "clipboard" end
    end
    print(text)          -- no clipboard on this executor: the report is in the console now
    return "console"
end

---------------------------------------------------------------- webhook v2: Discord embeds (replaces the old notify + webhook block)
-- system / script lines are not sent any more. The watchdog and NOTIFY_EVERY still call this, so it stays (does nothing)
local function notify() end

---------------------------------------------------------------- webhook: events + catch report (Discord embeds)
-- Only reads state and posts to the webhook. Nothing in here can stop the fishing loop.

HK.seen = setmetatable({}, { __mode = "k" })
HK.hosts = { "https://discord.com/api/webhooks/", "https://discordapp.com/api/webhooks/",
             "https://ptb.discord.com/api/webhooks/", "https://canary.discord.com/api/webhooks/" }
HK.newTools, HK.pop = {}, {}   -- what showed up around a catch (new Tools / short on-screen texts); used to find the fish name

-- game announcements. The first match wins, so specific ones go first. Add / edit freely.
-- { words to look for, icon, title, colour, optional pattern that pulls a better title out of the text }
HK.kinds = {
    { "goblin",         "\u{1F47A}", "Goblin",         0x22C55E },
    { "frightful pool", "\u{1F30A}", "Frightful Pool", 0x06B6D4, "(%a+%s+Frightful Pool)" },
}

-- words that are never a fish name (rarity tags, buttons ...)
HK.skip = { common = 1, uncommon = 1, unusual = 1, rare = 1, legendary = 1, mythical = 1, exotic = 1, secret = 1,
            relic = 1, fragment = 1, gemstone = 1, limited = 1, apex = 1, special = 1, trash = 1, new = 1,
            caught = 1, weight = 1, kg = 1, close = 1, sell = 1, ok = 1 }

function HK.okUrl(u)
    if type(u) ~= "string" then return false end
    for _, h in ipairs(HK.hosts) do
        if u:sub(1, #h) == h and #u > #h + 8 then return true end
    end
    return false
end

function HK.save()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile("autofish_hook.json", HttpService:JSONEncode({
            hook = CFG.NOTIFY_URL or "", fish = CFG.NOTIFY_FISH, events = CFG.NOTIFY_EVENTS,
        }))
    end)
end

-- one POST; returns ok, code-or-reason. Discord's 429 sets HK.cool so the queue backs off
function HK.post(data)
    local url = CFG.NOTIFY_URL
    local req = request or http_request or (syn and syn.request) or (http and http.request)
    if not HK.okUrl(url) then return false, "no webhook url" end
    if type(req) ~= "function" then return false, "executor has no request()" end
    data.allowed_mentions = { parse = {} }
    local ok, res = pcall(function()
        return req({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(data),
        })
    end)
    if not ok then return false, (tostring(res):gsub("https?://%S+", "<url>")) end
    local code = type(res) == "table" and tonumber(res.StatusCode or res.status_code) or nil
    if code == 429 then
        local okj, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
        HK.cool = os.clock() + math.min(30, (okj and type(j) == "table" and tonumber(j.retry_after)) or 5) + 0.5
    end
    return code == nil or (code >= 200 and code < 300), code or "ok"
end

-- embeds go out together (max 10 per message); a rate-limit puts them back in the queue
function HK.send(embeds)
    local ok, why = HK.post({ embeds = embeds })
    if not ok then
        if why == 429 then
            for i = #embeds, 1, -1 do table.insert(HK.q, 1, embeds[i]) end
        elseif os.clock() - (HK.errAt or -99) > 60 then
            HK.errAt = os.clock()
            log("webhook: send failed - " .. tostring(why))
        end
    end
    return ok, why
end

function HK.now() return os.date("!%Y-%m-%dT%H:%M:%SZ") end

-- the same few numbers under every embed
function HK.stats()
    local el = os.clock() - sessionStart
    return {
        { name = "Status",   value = (STAGES[stage] or STAGES.start)[1], inline = true },
        { name = "Total",    value = tostring(count), inline = true },
        { name = "Rate",     value = (count > 0 and el > 90) and (px(count / (el / 3600)) .. "/h") or "-", inline = true },
        { name = "Accuracy", value = pct(accAll > 0 and accHit / accAll or nil), inline = true },
        { name = "Session",  value = fmtTime(el), inline = true },
    }
end

function HK.test()
    local ok, why = HK.send({ {
        title = "\u{2705}  Webhook connected",
        description = "Game events and catch reports will show up here.",
        color = 0x57F287,
        fields = HK.stats(),
        footer = { text = "AutoFish" },
        timestamp = HK.now(),
    } })
    log("webhook test: " .. (ok and "sent" or ("failed - " .. tostring(why))))
end

-- the URL box lost focus: save it, clear it ("off"), or reject it
function HK.typed(s)
    s = tostring(s or ""):gsub("%s+", "")
    local box = ui and ui.hookBox
    local function show()
        local u = CFG.NOTIFY_URL or ""
        if box then box.Text = (u ~= "") and ("webhook saved  ..." .. u:sub(-6)) or "" end
        if ui and ui.hookLook then ui.hookLook() end
    end
    if s == "" then show() return end
    if s:lower() == "off" then
        CFG.NOTIFY_URL = ""
        HK.save()
        show()
        log("webhook removed")
    elseif HK.okUrl(s) then
        CFG.NOTIFY_URL = s
        HK.save()
        show()
        task.spawn(function() pcall(HK.test) end)
    else
        if box then box.Text, box.PlaceholderText = "", "not a Discord webhook URL" end
        log("webhook: that is not a discord webhook url")
    end
end

---------------------------------------------------------------- text helpers

-- no rich-text tags, one space between words
function HK.plain(s)
    s = tostring(s or ""):gsub("<[^>]+>", ""):gsub("%s+", " ")
    return (s:match("^%s*(.-)%s*$"))
end

-- "5.2 kg" / "1,234.5kg" -> number
function HK.kgOf(s)
    local n = tostring(s):match("([%d%.,]*%d)%s*[kK][gG]")
    return n and tonumber((n:gsub(",", ""))) or nil
end

-- "Salmon (5.2kg)" -> 5.2, "Salmon"      "5.2 kg" -> 5.2, ""      "Weight: 5.2 kg" -> 5.2, ""
function HK.split(s)
    s = HK.plain(s)
    local kg = HK.kgOf(s)
    if not kg then return nil end
    local rest = s:gsub("[%d%.,]*%d%s*[kK][gG]", ""):gsub("[%(%)%[%]:|%-]", " "):gsub("%s+", " ")
    rest = rest:match("^%s*(.-)%s*$")
    if rest:lower() == "weight" or rest:lower() == "wt" then rest = "" end
    return kg, rest
end

-- a usable fish name or nil
function HK.cleanName(s)
    s = HK.plain(s)
    s = s:gsub("%s*[%[%(][^%]%)]*%d[^%]%)]*[%]%)]%s*$", "")   -- drop a trailing "(5.2kg)" / "[12 kg]"
    s = s:gsub("[!%.]+$", ""):sub(1, 40)
    if #s < 2 or not s:find("%a") then return nil end
    return s
end

function HK.kind(s)
    s = tostring(s):lower()
    for _, k in ipairs(HK.kinds) do
        if s:find(k[1], 1, true) then return k end
    end
end

---------------------------------------------------------------- live events: one embed per announcement

function HK.event(text, gap)
    if not (CFG.NOTIFY_EVENTS and HK.okUrl(CFG.NOTIFY_URL)) then return end
    text = HK.plain(text):sub(1, 220)
    if #text < 4 or text:find("^AutoFish") then return end
    local k = HK.kind(text)
    if not k then return end            -- not an in-game event (script lines, world values ...): not sent
    local low = text:lower()
    local status
    if low:find("despawn", 1, true) or low:find("disappear", 1, true) or low:find("ended", 1, true)
        or low:find("finished", 1, true) or low:find("vanish", 1, true) then
        status = "ended"
    elseif low:find("spawn", 1, true) or low:find("appear", 1, true) or low:find("start", 1, true)
        or low:find("begin", 1, true) or low:find("begun", 1, true) or low:find("emerge", 1, true)
        or low:find("arriv", 1, true) or low:find("summon", 1, true) or low:find("awaken", 1, true)
        or low:find("there is", 1, true) or low:find(" near ", 1, true) then
        status = "started"
    end
    if status ~= "started" then return end   -- only spawns go out
    local generic = false
    local title = k[5] and text:match(k[5]) or k[3]
    -- the same text (digits ignored) once per `gap` seconds; the same title + status once per 45s (popup and chat say it twice)
    local now = os.clock()
    local tkey = "t:" .. (low:gsub("%d+", "#"))
    local kkey = generic and tkey or ("k:" .. title .. (status or ""))
    if (HK.keys[tkey] and now - HK.keys[tkey] < (gap or 600)) or (HK.keys[kkey] and now - HK.keys[kkey] < 45) then return end
    HK.keys[tkey], HK.keys[kkey] = now, now
    local body = "> " .. text
    if status then
        body = (status == "started" and "\u{1F7E2} **Started**" or "\u{1F534} **Ended**") .. "\n" .. body
    end
    HK.q[#HK.q + 1] = {
        title = k[2] .. "  " .. title,
        description = body,
        color = (status == "ended") and 0x6B7280 or k[4],
        footer = { text = "AutoFish" },
        timestamp = HK.now(),
    }
    if #HK.q > 20 then table.remove(HK.q, 1) end
end

-- script log lines are not sent (kept as a stub: the log wrapper below still calls it)
function HK.onLog() end

---------------------------------------------------------------- finding the fish name

-- weight / status / rarity of a fish Tool: from its name, attributes and Value children
function HK.toolInfo(t)
    local kg, mut, rar = HK.kgOf(t.Name), nil, nil
    local function look(k, v)
        if type(v) ~= "string" and type(v) ~= "number" then return end
        k = tostring(k):lower()
        local s = tostring(v)
        if k:find("weight", 1, true) or k == "kg" or k == "wt" then
            kg = kg or tonumber(v) or HK.kgOf(s)
        elseif k:find("mutation", 1, true) or k:find("variant", 1, true) or k == "modifier" then
            local l = s:lower()
            if s == "" or l == "none" or l == "normal" or l == "nil" then mut = mut or "Normal" else mut = s end
        elseif k:find("rarity", 1, true) then
            if s ~= "" then rar = rar or s end
        end
    end
    for k, v in pairs(t:GetAttributes()) do look(k, v) end
    for _, d in ipairs(t:GetDescendants()) do
        if d:IsA("ValueBase") then pcall(function() look(d.Name, d.Value) end) end
    end
    return kg, mut, rar
end

function HK.attrText(t)   -- for the log, when the weight is missing
    local p = {}
    for k, v in pairs(t:GetAttributes()) do p[#p + 1] = k .. "=" .. tostring(v) end
    for _, d in ipairs(t:GetDescendants()) do
        if d:IsA("ValueBase") then
            local ok, val = pcall(function() return d.Value end)
            p[#p + 1] = d.Name .. "=" .. tostring(ok and val or "?")
        end
    end
    return table.concat(p, ", "):sub(1, 160)
end

function HK.fishChanged()
    HK.dirty = true
    if ui and ui.fishRefresh then ui.fishRefresh() end
end

-- one entry per fish caught in this server, from the first one on (by hand or by the script)
HK.priceBuf = {}   -- price labels seen: { kg, price }

function HK.money(n)
    local s = tostring(math.floor(n + 0.5))
    local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return r
end

local function sameKg(a, b) return math.abs(a - b) <= math.max(0.06, b * 0.03) end

function HK.priceFor(kg)
    if not kg then return nil end
    for i = #HK.priceBuf, 1, -1 do
        if sameKg(HK.priceBuf[i].kg, kg) then return HK.priceBuf[i].price end
    end
end

-- raw text with every non-ASCII byte shown as \N, so a hidden space or symbol shows up in the report
local function visible(t)
    return (tostring(t):gsub("[^\32-\126]", function(c) return "\\" .. c:byte() end))
end

HK.priceSeen, HK.priceBad, HK.priceMiss = 0, 0, 0

-- label text: "Legendary / Weight: 114kg / Price: 11,053 C$"
function HK.priceText(raw)
    local s = HK.plain(raw)
    s = s:gsub("\194\160", " "):gsub("\226\128[\128-\138\175]", " "):gsub("%s+", " ")   -- non-breaking / thin spaces
    local pr, suf = s:match("[Pp]rice:?%s*([%d%.,]*%d)%s*([KkMmBb]?)%s*[Cc]%$")
    local w = s:match("[Ww]eight:?%s*([%d%.,]*%d)%s*[kK][gG]")
    local price = pr and tonumber((pr:gsub(",", "")))
    local kg = w and tonumber((w:gsub(",", "")))
    if price and suf and suf ~= "" then
        price = price * ({ k = 1e3, m = 1e6, b = 1e9 })[suf:lower()]
    end
    if not (price and kg) then
        HK.priceBad = HK.priceBad + 1
        if HK.priceBad <= 3 then log("price label not parsed: " .. visible(raw):sub(1, 120)) end
        return
    end
    for _, p in ipairs(HK.priceBuf) do
        if p.kg == kg and p.price == price then return end
    end
    HK.priceBuf[#HK.priceBuf + 1] = { kg = kg, price = price }
    if #HK.priceBuf > 60 then table.remove(HK.priceBuf, 1) end
    HK.priceSeen = HK.priceSeen + 1
    log(string.format("price label: %skg = %s C$", tostring(kg), HK.money(price)))
    if (HK.priceAt or 0) < 4 and HK.priceSrc then   -- where the label lives and what was in hand when it showed
        HK.priceAt = (HK.priceAt or 0) + 1
        pcall(function()
            local held = lp.Character and lp.Character:FindFirstChildOfClass("Tool")
            local short = HK.priceSrc:GetFullName():gsub("^Players%.[^%.]+%.PlayerGui%.", "")
            log("price scan: label at " .. short:sub(-90) .. (shown(HK.priceSrc) and " (visible)" or " (hidden)")
                .. " | held: " .. (held and held.Name or "-"))
        end)
    end
    local hit
    for i = #HK.catches, math.max(1, #HK.catches - 20), -1 do
        local e = HK.catches[i]
        if not e.price and e.kg and sameKg(e.kg, kg) then hit = e break end
    end
    if not hit then   -- a catch with no weight yet: the newest unpriced one from the last 8s
        for i = #HK.catches, math.max(1, #HK.catches - 3), -1 do
            local e = HK.catches[i]
            if not e.price and not e.kg and (e.clk or -99) >= os.clock() - 8 then hit = e break end
        end
    end
    if hit then
        hit.price = price
        pcall(HK.fishChanged)
    end
end

-- list PlayerGui texts that look like fish info (Weight / Price / kg / C$); shop buttons and the sell popup are skipped.
-- Also runs by hand:  getgenv().__autofish_pricescan()   (open the backpack and hover a fish first, then Copy report)
function HK.priceScanNow(limit)
    local found = 0
    for _, d in ipairs(pg:GetDescendants()) do
        if found >= (limit or 12) then break end
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = d.Text
            if type(t) == "string" and t ~= "" and #t < 300 and not (gui and d:IsDescendantOf(gui)) then
                local path = d:GetFullName()
                local pl = HK.plain(t)
                if not path:find("SkinCrate", 1, true) and not path:find("Confirmation", 1, true)
                    and (pl:find("[Ww]eight") or pl:lower():find("price", 1, true) or pl:find("%d%s*[kK][gG]") or pl:find("C%$")) then
                    found = found + 1
                    local short = path:gsub("^Players%.[^%.]+%.PlayerGui%.", "")
                    log("price scan: " .. short:sub(-80) .. (shown(d) and " (visible)" or " (hidden)") .. " = " .. visible(t):sub(1, 100))
                end
            end
        end
    end
    if found == 0 then log("price scan: no fish-info text in PlayerGui right now") end
end
env.__autofish_pricescan = function() pcall(HK.priceScanNow, 20) end

-- probe for the price tooltip (PlayerGui.backpack.tooltip): what an inventory card is made of, and whether hovering a card
-- or holding a fish fills the tooltip. Run by hand with fishing idle:  getgenv().__autofish_inv()   then Copy report
function HK.invProbe()
    local function tipText(tip)
        local out = {}
        for _, d in ipairs(tip:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" then out[#out + 1] = visible(HK.plain(d.Text)):sub(1, 40) end
        end
        return table.concat(out, " | ")
    end
    local bpg = pg:FindFirstChild("backpack")
    local inv = bpg and bpg:FindFirstChild("inventory")
    local tip = bpg and bpg:FindFirstChild("tooltip")
    local cont = inv and inv:FindFirstChild("itemContainer")
    log(string.format("price scan: inv=%s tooltip=%s container=%s | firesignal=%s",
        tostring(inv ~= nil), tostring(tip ~= nil), tostring(cont ~= nil), type(firesignal)))
    local item, n = nil, 0
    if cont then
        for _, c in ipairs(cont:GetChildren()) do
            if c.Name == "ItemTemplate" then n = n + 1; item = item or c end
        end
        log("price scan: ItemTemplate x" .. n)
    end
    if item then
        local out = {}
        for _, d in ipairs(item:GetDescendants()) do
            local t = (d:IsA("TextLabel") or d:IsA("TextButton")) and ("=" .. visible(HK.plain(d.Text)):sub(1, 24)) or ""
            out[#out + 1] = d.Name .. ":" .. d.ClassName .. t
            if #out >= 14 then break end
        end
        log("price scan: item " .. item.ClassName .. " > " .. table.concat(out, ", "))
    end
    if tip then log("price scan: tooltip now: " .. tipText(tip)) end
    -- 1) hover event on an inventory card
    if item and tip and type(firesignal) == "function" then
        local btn = item:IsA("GuiButton") and item or item:FindFirstChildWhichIsA("GuiButton", true)
        if btn then
            pcall(firesignal, btn.MouseEnter)
            task.wait(0.4)
            log("price scan: after hover on " .. btn.Name .. ": " .. tipText(tip))
            pcall(firesignal, btn.MouseLeave)
        else
            log("price scan: no button inside ItemTemplate")
        end
    end
    -- 2) hold the first fish in the backpack, read the tooltip, then put the rod back
    local bp = lp:FindFirstChildOfClass("Backpack")
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local rod = getRod()
    if bp and hum and tip then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and not isRod(t) then
                pcall(function() hum:EquipTool(t) end)
                task.wait(0.6)
                log("price scan: held " .. t.Name .. ": " .. tipText(tip))
                pcall(function() hum:UnequipTools() end)
                break
            end
        end
        if rod then
            task.wait(0.3)
            pcall(function() hum:EquipTool(rod) end)
        end
    end
    log("price scan: probe done")
end
env.__autofish_inv = function() task.spawn(function() pcall(HK.invProbe) end) end

function HK.fish(name, kg, how, mut, rar)
    local now, ln = os.clock(), name:lower()
    -- same fish seen twice (its Tool and its popup): fill in what is missing instead of counting again
    for i = #HK.catches, math.max(1, #HK.catches - 3), -1 do
        local e = HK.catches[i]
        local en = e.name:lower()
        if now - (e.clk or -99) < 10 and (en == ln or en:find(ln, 1, true) or ln:find(en, 1, true))
            and (not kg or not e.kg or math.abs(kg - e.kg) < 0.06) then
            e.kg = e.kg or kg
            e.price = e.price or HK.priceFor(e.kg)
            if mut and (e.mut == nil or e.mut == "" or e.mut == "Normal") then e.mut = mut end
            e.rar = e.rar or rar
            pcall(HK.fishChanged)
            return
        end
    end
    HK.catches[#HK.catches + 1] = {
        name = name, kg = kg, mut = mut or "", rar = rar, clk = now, t = os.time(), price = HK.priceFor(kg),
        src = (now < HK.scriptUntil) and "script" or "hand",
    }
    local ce = HK.catches[#HK.catches]
    task.delay(9, function()
        pcall(function()
            if ce.price or HK.priceMiss >= 6 then return end
            HK.priceMiss = HK.priceMiss + 1
            local last = {}
            for i = math.max(1, #HK.priceBuf - 2), #HK.priceBuf do last[#last + 1] = tostring(HK.priceBuf[i].kg) end
            log(string.format("price missing: %s %skg | labels seen %d, unparsed %d | last label kg: %s",
                ce.name, tostring(ce.kg), HK.priceSeen, HK.priceBad, table.concat(last, ", ")))
            if (HK.priceScan or 0) < 2 then
                HK.priceScan = (HK.priceScan or 0) + 1
                HK.priceScanNow(12)
            end
        end)
    end)
    HK.tally[name] = (HK.tally[name] or 0) + 1
    if kg and kg > (HK.best and HK.best.kg or 0) then HK.best = { name = name, kg = kg } end
    log(string.format("fish #%d: %s%s [%s]", #HK.catches, name, kg and string.format(" %.1fkg", kg) or "", how))
    pcall(HK.fishChanged)
end

-- Tools that show up (a caught fish can arrive as a Tool); the rod is ignored
function HK.watchTools()
    local function onAdd(o)
        if not alive() or not o:IsA("Tool") or HK.seen[o] then return end
        HK.seen[o] = true
        if isRod(o) then return end
        local ent = { t = os.clock(), name = o.Name }
        HK.newTools[#HK.newTools + 1] = ent
        if #HK.newTools > 20 then table.remove(HK.newTools, 1) end
        task.delay(0.6, function()          -- let the game fill in the Tool's attributes first
            pcall(function()
                if not alive() or not o.Parent then return end
                local kg, mut, rar = HK.toolInfo(o)
                HK.toolLogged = (HK.toolLogged or 0) + 1
                if CFG.DEBUG or not kg or HK.toolLogged <= 3 then log("tool: " .. o.Name .. " | " .. HK.attrText(o)) end
                local n = HK.cleanName(o.Name)
                -- a Tool is a fish when it has a weight, or it arrived right after a reel
                if n and not HK.skip[n:lower()] and (kg or os.clock() < math.max(HK.winUntil, HK.scriptUntil)) then
                    ent.used = true
                    HK.fish(n, kg, "tool", mut, rar)
                    local pa
                    for k, v in pairs(o:GetAttributes()) do
                        if type(v) == "number" and tostring(k):lower():find("price", 1, true) then pa = v end
                    end
                    local ce = HK.catches[#HK.catches]
                    if pa and ce and not ce.price and (not kg or not ce.kg or math.abs(ce.kg - kg) < 0.06) then
                        ce.price = pa
                        pcall(HK.fishChanged)
                    end
                end
            end)
        end)
    end
    local function hook(c)
        for _, o in ipairs(c:GetChildren()) do HK.seen[o] = true end
        HK.conns[#HK.conns + 1] = c.ChildAdded:Connect(onAdd)
    end
    local bp = lp:FindFirstChildOfClass("Backpack")
    if bp then hook(bp) end
    if lp.Character then hook(lp.Character) end
    HK.conns[#HK.conns + 1] = lp.CharacterAdded:Connect(hook)
    HK.conns[#HK.conns + 1] = lp.ChildAdded:Connect(function(c) if c:IsA("Backpack") then hook(c) end end)
end

-- short texts that appear while a reel is on / just finished (the catch popup); one entry per label
function HK.keep(d, s)
    local now = os.clock()
    for _, e in ipairs(HK.pop) do
        if e.d == d then e.s, e.t, e.used = s, now, nil return end
    end
    HK.pop[#HK.pop + 1] = { d = d, s = s, t = now }
    if #HK.pop > 60 then table.remove(HK.pop, 1) end
end

-- the fish a finished reel gave you -> name, kg, where it was read from (or nothing yet)
function HK.resolve(since)
    -- 1) a Tool that appeared
    for i = #HK.newTools, 1, -1 do
        local e = HK.newTools[i]
        if e.t >= since and not e.used then
            e.used = true
            local n = HK.cleanName(e.name)
            if n then return n, HK.kgOf(e.name), "tool" end
        end
    end
    -- 2) the catch popup: labels that are on screen now and showed up during / after the reel
    local live = {}
    for _, e in ipairs(HK.pop) do
        if e.t >= since and not e.used and e.d.Parent and e.d.Text == e.s and shown(e.d) then live[#live + 1] = e end
    end
    for _, e in ipairs(live) do          -- "You caught a Salmon" / "Caught: Salmon (5.2kg)"
        local s = HK.plain(e.s)
        local n = s:match("[Cc]aught%s+an?%s+(.+)") or s:match("[Cc]aught:?%s+(.+)")
        n = n and HK.cleanName(n)
        if n and not HK.skip[n:lower()] then e.used = true return n, HK.kgOf(s), "popup" end
    end
    for _, w in ipairs(live) do          -- "Salmon (5.2kg)" in one label, or a weight label with the name next to it
        local kg, rest = HK.split(w.s)
        if kg then
            local n = rest ~= "" and HK.cleanName(rest)
            if n and not HK.skip[n:lower()] then w.used = true return n, kg, "popup" end
            local a = w.d.Parent
            for _ = 1, 3 do              -- the biggest text near the weight (name > rarity tag), small containers only
                if not a or a:IsA("ScreenGui") then break end
                local ds = a:GetDescendants()
                if #ds > 30 then break end
                local best, bh = nil, 0
                for _, c in ipairs(ds) do
                    if c ~= w.d and c:IsA("TextLabel") and shown(c) then
                        local nm = HK.cleanName(c.Text)
                        if nm and #nm <= 30 and not HK.skip[nm:lower()] and not nm:find("^[%d%.,%s]")
                            and c.AbsoluteSize.Y > bh then
                            best, bh = nm, c.AbsoluteSize.Y
                        end
                    end
                end
                if best then
                    w.used = true
                    local rar                        -- a rarity tag in the same popup ("Legendary" ...)
                    for _, c in ipairs(ds) do
                        if c:IsA("TextLabel") and shown(c) then
                            local t = HK.plain(c.Text)
                            if HK.rank[t:lower()] then rar = t break end
                        end
                    end
                    return best, kg, "weight label", nil, rar
                end
                a = a.Parent
            end
        end
    end
end

HK.dumps, HK.prevKeys = {}, {}

-- runs ~6s after every counted catch. Nothing found: the labels that are new since the last catch go into Copy report
function HK.lookup()
    local since = os.clock() - 8
    local last = HK.catches[#HK.catches]
    if last and last.clk >= since then return end   -- the Tool path already got it
    local cur, listed, out = {}, {}, {}
    local function snap(tag)
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" and not (gui and d:IsDescendantOf(gui)) and shown(d) then
                local path = (d:GetFullName():gsub("^.-PlayerGui%.", ""))
                if not (path:find("^PlayerList") or path:find("^Topbar") or path:find("^Friends")) then
                    local k = path .. " = " .. HK.plain(d.Text):sub(1, 50)
                    cur[k] = true
                    if not HK.prevKeys[k] and not listed[k] and #out < 40 then
                        listed[k] = true
                        out[#out + 1] = tag .. "  " .. k
                    end
                end
            end
        end
    end
    for n = 1, 16 do
        local l2 = HK.catches[#HK.catches]
        if l2 and l2.clk >= since then return end   -- the catch announcement already got it
        local name, kg, how, mut, rar = HK.resolve(since)
        if name then HK.fish(name, kg, how, mut, rar) return end
        if n == 3 then snap("1.2s") elseif n == 9 then snap("3.6s") end
        task.wait(0.4)
    end
    HK.prevKeys = cur
    HK.dumps[#HK.dumps + 1] = string.format("catch at %s (tools seen %d):\n  %s",
        os.date("%H:%M:%S"), #HK.newTools, table.concat(out, "\n  "))
    if #HK.dumps > 3 then table.remove(HK.dumps, 1) end
    log("fish name not found | tools seen " .. #HK.newTools .. " | " .. #out .. " new labels dumped (see Copy report)")
end

-- words in front of a fish name that are a mutation, not part of the name. Add more when you see them in the list.
HK.mutWords = { webbed = 1, grim = 1, shiny = 1, sparkling = 1, albino = 1, midas = 1,
                possessed = 1, darkened = 1, glossy = 1 }
HK.annLogged = 0

-- the catch announcement label:
--   "You just caught a Webbed Golden Seahorse at 0.3kg! (...)"      your own catch
--   "Extra! Webweaver Spider caught a Webbed Seaweed at 0.3kg!"     a bonus fish from the rod
function HK.catchText(d, raw)
    if gui and d:IsDescendantOf(gui) then return end
    local s = HK.plain(raw)
    s = s:gsub("&apos;", "'"):gsub("&quot;", '"'):gsub("&amp;", "&")
    if not (s:find("^[Yy]ou ") or s:find("^Extra")) then return end   -- not other players' announcements
    local body, w, tail = s:match("[Cc]aught%s+an?%s+(.-)%s+at%s+([%d%.,]*%d)%s*[kK][gG]%s*!?%s*(.*)$")
    if not body then return end
    local kg = tonumber((w:gsub(",", "")))
    local words, mut = body, {}
    while true do                                   -- leading mutation words -> status column
        local first, rest = words:match("^(%S+)%s+(.+)$")
        if first and HK.mutWords[first:lower()] then
            mut[#mut + 1] = first
            words = rest
        else
            break
        end
    end
    local rar
    local inner = tail:match("%((.-)%)")            -- "(Legendary)" style tail, if the game writes one
    if inner and HK.rank and HK.rank[inner:lower()] then rar = inner end
    if HK.annLogged < 8 then                        -- first few raw texts go to the log so the tail / colours can be read
        HK.annLogged = HK.annLogged + 1
        log("catch text: " .. tostring(raw):sub(1, 240))
    end
    HK.fish(HK.cleanName(words) or words, kg, s:find("^Extra") and "extra" or "announce",
        #mut > 0 and table.concat(mut, " ") or "Normal", rar)
end

---------------------------------------------------------------- watchers

-- the game's popups ("Shark Hunt has started" ...): a TextLabel that appears or changes text while it is visible
function HK.watchText()
    local function look(d)
        if not alive() then return end
        local s = d.Text
        if type(s) == "string" and #s < 600 and s:find("aught", 1, true) then pcall(HK.catchText, d, s) end
        if type(s) == "string" and #s < 600 and s:lower():find("price", 1, true) then HK.priceSrc = d; pcall(HK.priceText, s) end
        if type(s) ~= "string" or s == "" or #s > 160 then return end
        if gui and d:IsDescendantOf(gui) then return end                     -- the AutoFish panel's own text
        if #s <= 60 and os.clock() < HK.winUntil then HK.keep(d, s) end   -- fish name hunt
        if #s < 8 then return end
        if HK.poolText and s:lower():find("frightful", 1, true) then   -- Frightful Pool alert (popup text)
            task.delay(0.3, function()
                if alive() and d.Parent then pcall(HK.poolText, s, "screen text") end
            end)
        end
        if CFG.DEBUG and shown(d) then            -- Debug on: every new text is logged as "txt:" (see Copy report)
            local k = s:lower():gsub("%d+", "#")
            if not HK.txt[k] then HK.txt[k] = true; log("txt: " .. s:sub(1, 70)) end
        end
        if not (CFG.NOTIFY_EVENTS and HK.kind(s)) then return end
        task.delay(0.4, function()                -- the text is often set just before the popup is switched on
            if alive() and d.Parent and shown(d) then HK.event(s) end
        end)
    end
    local function hook(d)
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            look(d)
            d:GetPropertyChangedSignal("Text"):Connect(function() look(d) end)
        end
    end
    task.spawn(function()                         -- labels that already exist: only a later change counts
        local n = 0
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then d:GetPropertyChangedSignal("Text"):Connect(function() look(d) end) end
            n = n + 1
            if n % 400 == 0 then task.wait() end
        end
    end)
    HK.conns[#HK.conns + 1] = pg.DescendantAdded:Connect(hook)
end

-- server messages in the chat box (system messages have no TextSource)
function HK.watchChat()
    local tcs = game:GetService("TextChatService")
    HK.conns[#HK.conns + 1] = tcs.MessageReceived:Connect(function(m)
        if alive() and m.TextSource == nil then
            HK.event(m.Text)
            if HK.poolText then pcall(HK.poolText, m.Text, "chat") end
        end
    end)
end

-- world values (weather, day / night ...) are not sent any more; kept so the starter line below still works
function HK.watchWorld() end

---------------------------------------------------------------- catch report (every CFG.FISH_EVERY minutes)

function HK.fishEmbed(mins)
    local rows, named = {}, 0
    for name, n in pairs(HK.tally) do rows[#rows + 1] = { name, n }; named = named + n end
    table.sort(rows, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local total = math.max(HK.n5, named)
    local lost = ST.away - HK.away5
    local span = string.format("%g", mins)
    local lines = {}
    for i, r in ipairs(rows) do
        if i > 20 then lines[#lines + 1] = "*+" .. (#rows - 20) .. " more kinds*"; break end
        lines[#lines + 1] = string.format("`x%-2d` %s", r[2], r[1])
    end
    if total > named then lines[#lines + 1] = string.format("`x%-2d` *name not read*", total - named) end
    local fields = HK.stats()
    if lost > 0 then table.insert(fields, 1, { name = "Got away", value = tostring(lost), inline = true }) end
    if HK.best then
        table.insert(fields, 1, { name = "Biggest", value = string.format("%s - %.1f kg", HK.best.name, HK.best.kg), inline = true })
    end
    return {
        title = total > 0 and ("\u{1F3A3}  " .. total .. " caught in " .. span .. " min")
                           or ("\u{26A0}\u{FE0F}  No catches in " .. span .. " min"),
        description = #lines > 0 and table.concat(lines, "\n") or "Nothing landed this round.",
        color = total > 0 and 0x2ECC71 or 0xE67E22,
        fields = fields,
        footer = { text = "AutoFish" },
        timestamp = HK.now(),
    }
end

---------------------------------------------------------------- fish list (this server, from the first fish on)

HK.icon = { script = "\u{1F916}", hand = "\u{270B}" }
-- ORIGINAL ends with:    the "end" of  function HK.pushCatches(mins)   (just above  function HK.sendCatches)
-- v6: the fish list is grouped by kind ("x3 Salmon"), the normal report lists only fish caught since the last report (HK.LIST_MAX kinds), "Send all" gives the full grouped list.

HK.icon = { script = "\u{1F916}", hand = "\u{270B}" }

-- rarity order, lowest -> highest. Change the numbers if the game's order is different.
-- A fish whose rarity was not read counts as 0 and sits at the bottom (then heaviest first).
HK.rank = { trash = 1, common = 2, uncommon = 3, unusual = 4, rare = 5, legendary = 6, mythical = 7,
            exotic = 8, secret = 9, relic = 10, fragment = 11, gemstone = 12, limited = 13, apex = 14, special = 15 }

-- optional by-hand fallback for fish whose rarity the script cannot read:  HK.rarFish["Fish Name"] = "Legendary"
HK.rarFish = {}

function HK.rarOf(e)
    local r = (e.rar and e.rar ~= "") and e.rar or HK.rarFish[e.name]
    return r, HK.rank[tostring(r or ""):lower()] or 0
end

-- one row per KIND of fish (name + status), not one per fish: "x3 Salmon" instead of three lines
function HK.group(from)
    local map, rows = {}, {}
    for i = from, #HK.catches do
        local e = HK.catches[i]
        local st = (e.mut and e.mut ~= "") and e.mut or "-"
        local key = e.name .. "|" .. st
        local g = map[key]
        if not g then
            g = { name = e.name, st = st, n = 0, kg = nil, rar = nil, rk = 0, val = 0 }
            map[key] = g
            rows[#rows + 1] = g
        end
        g.n = g.n + 1
        g.val = g.val + (e.price or 0)
        if e.kg and (not g.kg or e.kg > g.kg) then g.kg = e.kg end
        local r, rk = HK.rarOf(e)
        if rk > g.rk or (not g.rar and r) then g.rar, g.rk = r, rk end
    end
    table.sort(rows, function(a, b)
        if a.rk ~= b.rk then return a.rk > b.rk end
        local ka, kb = a.kg or 0, b.kg or 0
        if ka ~= kb then return ka > kb end
        return a.name < b.name
    end)
    return rows
end

-- rarity -> icon and embed colour (names are the game's own; an unknown rarity gets a "?" icon)
HK.rarIcon = { trash = "\u{1F5D1}", common = "\u{26AA}", uncommon = "\u{1F7E2}", unusual = "\u{1F537}", rare = "\u{1F535}",
               legendary = "\u{1F7E1}", mythical = "\u{1F7E3}", exotic = "\u{1F534}", secret = "\u{26AB}", relic = "\u{1F7E4}",
               fragment = "\u{1F7E0}", gemstone = "\u{1F48E}", limited = "\u{2B50}", apex = "\u{1F451}", special = "\u{2728}" }
HK.rarColor = { trash = 0x6B7280, common = 0x9CA3AF, uncommon = 0x22C55E, unusual = 0x14B8A6, rare = 0x3B82F6,
                legendary = 0xF59E0B, mythical = 0xA855F7, exotic = 0xEF4444, secret = 0x6366F1, relic = 0x92400E,
                fragment = 0xF97316, gemstone = 0x06B6D4, limited = 0xEAB308, apex = 0xEC4899, special = 0xF472B6 }

-- section header: "🟡 **Legendary**"
function HK.rarHead(r)
    local k = tostring(r or ""):lower()
    local name = (k ~= "") and (k:sub(1, 1):upper() .. k:sub(2)) or "Unknown"
    return (HK.rarIcon[k] or "\u{2754}") .. " **" .. name .. "**"
end

-- one kind of fish:  `x3 ` **Golden Seahorse** · best 4.2 kg · Webbed     (status left out when Normal)
function HK.line(g)
    local nm = (g.name:gsub("[%*_`~]", ""))
    local out = string.format("`x%-2d` **%s**", g.n, nm)
    if g.kg then out = out .. string.format("  \u{00B7}  %s%.1f kg", g.n > 1 and "best " or "", g.kg) end
    if g.st ~= "-" and g.st ~= "Normal" then out = out .. "  \u{00B7}  *" .. g.st .. "*" end
    if g.val and g.val > 0 then out = out .. "  \u{00B7}  " .. HK.money(g.val) .. " C$" end
    return out
end

-- how many kinds of fish the normal report lists (the rest become one "+N more" line). "Send all" is not capped.
HK.LIST_MAX = 15

-- Normal report: only the fish caught SINCE the last report, grouped by rarity (rarest section first), capped.
-- full = true ("Send all" button): every fish of this server from the first one, split over messages if long.
function HK.pushCatches(mins, full)
    local total = #HK.catches
    if total <= HK.sentN and not full then
        HK.send({ HK.fishEmbed(mins) })      -- nothing new since the last list: the usual short notice
        return
    end
    local from = full and 1 or (HK.sentN + 1)
    local rows = HK.group(from)
    local function rkey(g) return tostring(g.rar or ""):lower() end
    local shownN, hiddenKinds, hiddenFish = #rows, 0, 0
    if not full and #rows > HK.LIST_MAX then
        shownN = HK.LIST_MAX
        hiddenKinds = #rows - HK.LIST_MAX
        for i = HK.LIST_MAX + 1, #rows do hiddenFish = hiddenFish + rows[i].n end
    end
    local anyRar = false                     -- the game's catch text carries no rarity: then no sections, just a list by weight
    for i = 1, shownN do if rows[i].rar then anyRar = true break end end
    local fishIn = {}                        -- fish per rarity, for the section headers
    for i = 1, shownN do
        local k = rkey(rows[i])
        fishIn[k] = (fishIn[k] or 0) + rows[i].n
    end
    -- sections: a header, then its kinds. A section that runs into the next message gets its header again.
    local chunks, cur, len, head = {}, {}, 0, nil
    for i = 1, shownN do
        local g = rows[i]
        local k = rkey(g)
        local hdr = (anyRar and k ~= head) and string.format("%s  \u{00B7}  %d fish", HK.rarHead(g.rar), fishIn[k]) or nil
        local s = HK.line(g)
        if len + #s + (hdr and #hdr + 2 or 0) + 1 > 3800 and #cur > 0 then
            chunks[#chunks + 1] = cur
            cur, len = {}, 0
            if not hdr and anyRar then hdr = HK.rarHead(g.rar) .. "  \u{00B7}  continued" end
        end
        if hdr then
            if #cur > 0 then cur[#cur + 1] = ""; len = len + 1 end    -- blank line between sections
            cur[#cur + 1] = hdr
            len = len + #hdr + 1
            head = k
        end
        cur[#cur + 1] = s
        len = len + #s + 1
    end
    if hiddenKinds > 0 then
        cur[#cur + 1] = ""
        cur[#cur + 1] = string.format("*+%d more kinds (%d fish)*", hiddenKinds, hiddenFish)
    end
    chunks[#chunks + 1] = cur
    -- stats as ONE line, biggest fish as one line (six stacked fields took half a phone screen)
    local st = HK.stats()
    local function sv(i) return st[i] and st[i].value or "-" end
    local statLine = string.format("*%s  \u{00B7}  total %s  \u{00B7}  %s  \u{00B7}  acc %s  \u{00B7}  %s*",
        sv(1), sv(2), sv(3), sv(4), sv(5))
    local worth, priced = 0, 0
    for i = from, total do
        local e = HK.catches[i]
        if e.price then worth, priced = worth + e.price, priced + 1 end
    end
    if priced > 0 then
        statLine = statLine .. string.format("\n*worth %s C$  \u{00B7}  %d/%d priced*", HK.money(worth), priced, total - from + 1)
    end
    if ST.away > 0 then statLine = statLine .. "\n*got away " .. ST.away .. "*" end
    local big
    for i = from, total do
        local e = HK.catches[i]
        if e.kg and (not big or e.kg > big.kg) then big = e end
    end
    if big then
        local bm = (big.mut and big.mut ~= "" and big.mut ~= "Normal") and ("  \u{00B7}  *" .. big.mut .. "*") or ""
        table.insert(chunks[1], 1, string.format("\u{1F3C6}  **Biggest**  \u{00B7}  %s  \u{00B7}  %.1f kg%s", big.name, big.kg, bm))
        table.insert(chunks[1], 2, "")
    end
    local lastc = chunks[#chunks]
    lastc[#lastc + 1] = ""
    lastc[#lastc + 1] = statLine
    local color = (rows[1] and HK.rarColor[rkey(rows[1])]) or 0x2ECC71    -- the border takes the rarest fish's colour
    local nNew = total - from + 1
    for ci, lines in ipairs(chunks) do
        local title
        if ci > 1 then
            title = string.format("\u{1F3A3}  continued (%d/%d)", ci, #chunks)
        elseif full then
            title = string.format("\u{1F3A3}  %d fish in this server  \u{00B7}  %s first", total, anyRar and "rarest" or "heaviest")
        else
            title = string.format("\u{1F3A3}  %d new fish  \u{00B7}  %d in this server", nNew, total)
        end
        local e = {
            title = title,
            description = table.concat(lines, "\n"),
            color = color,
            footer = { text = "AutoFish | server " .. tostring(game.JobId):sub(1, 8) },
            timestamp = HK.now(),
        }
        -- HK.post, not HK.send: a rate-limited list must not be re-queued and arrive stale later
        local ok, why = HK.post({ embeds = { e } })
        if not ok then
            if os.clock() - (HK.errAt or -99) > 60 then
                HK.errAt = os.clock()
                log("webhook: fish list failed - " .. tostring(why))
            end
            return                           -- sentN stays, the next round sends these fish again
        end
        if ci < #chunks then task.wait(0.6) end
    end
    HK.sentN, HK.dirty = total, true
end

function HK.sendCatches(mins, full)
    if HK.sending then return end
    HK.sending = true
    local ok, err = pcall(HK.pushCatches, mins, full)
    HK.sending = false
    if not ok then log("webhook: " .. tostring(err)) end
end

function HK.sendAll()   -- the "Send all" button: every fish of this server again, from #1 (grouped)
    if not HK.okUrl(CFG.NOTIFY_URL) then log("webhook: no url saved") return end
    if #HK.catches == 0 then log("fish list is empty") return end
    HK.sendCatches(0, true)
end

-- the list survives re-executing the script in the same server
function HK.saveLog()
    if type(writefile) ~= "function" then return end
    pcall(function()
        local list = {}
        for i, e in ipairs(HK.catches) do
            list[i] = { n = e.name, k = e.kg, m = e.mut, r = e.rar, s = e.src, t = e.t, p = e.price }
        end
        writefile("autofish_fishlog.json", HttpService:JSONEncode({ job = game.JobId, sent = HK.sentN, list = list }))
    end)
end

function HK.loadLog()
    pcall(function()
        if type(isfile) ~= "function" or not isfile("autofish_fishlog.json") then return end
        local d = HttpService:JSONDecode(readfile("autofish_fishlog.json"))
        if type(d) ~= "table" or game.JobId == "" or d.job ~= game.JobId or type(d.list) ~= "table" then return end
        for _, x in ipairs(d.list) do
            local nm, mt, fromName = tostring(x.n), x.m or "", {}
            while true do                    -- written before a mutation word was known: move it out of the name
                local first, rest = nm:match("^(%S+)%s+(.+)$")
                if first and HK.mutWords[first:lower()] then
                    fromName[#fromName + 1] = first
                    nm = rest
                else
                    break
                end
            end
            if #fromName > 0 then
                for w in tostring(mt):gmatch("%S+") do
                    local dup = w:lower() == "normal"
                    for _, f in ipairs(fromName) do if f:lower() == w:lower() then dup = true end end
                    if not dup then fromName[#fromName + 1] = w end
                end
                mt = table.concat(fromName, " ")
            end
            HK.catches[#HK.catches + 1] = { name = nm, kg = tonumber(x.k), mut = mt,
                rar = x.r, src = x.s, t = x.t, clk = -99, price = tonumber(x.p) }
        end
        HK.sentN = math.min(tonumber(d.sent) or 0, #HK.catches)
    end)
end
HK.loadLog()
pcall(HK.fishChanged)

-- fish caught BY HAND: the reel GUI opens and closes without the script playing it -> look for the fish then
task.spawn(function()
    local was, byHand = false, false
    while alive() do
        task.wait(0.4)
        local ok, g, b, f = pcall(getReel)
        local isUp = (ok and g and b and f) and true or false
        if isUp and not was then
            task.wait(0.6)                       -- the script flags its own reels (stage "reel") a moment after they open
            byHand = not (running and stage == "reel")
        end
        if byHand and isUp then HK.winUntil = os.clock() + 70 end
        if was and not isUp and byHand then
            byHand = false
            HK.winUntil = os.clock() + 12
            task.spawn(function() pcall(HK.lookup) end)
        end
        was = isUp
    end
end)

---------------------------------------------------------------- senders

-- a counted catch (HK.n5 goes up) starts a short hunt for its name
task.spawn(function()
    local last = HK.n5
    while alive() do
        task.wait(0.3)
        local cur = HK.n5
        if cur ~= last then
            if cur > last then task.spawn(function() pcall(HK.lookup) end) end
            last = cur
        end
    end
end)

-- queued events go out every ~2s (up to 5 embeds per message); the catch report every CFG.FISH_EVERY minutes
HK.nextFish = os.clock() + CFG.FISH_EVERY * 60
task.spawn(function()
    while alive() do
        task.wait(2)
        pcall(function()
            local now = os.clock()
            for k, t in pairs(HK.keys) do if now - t > 600 then HK.keys[k] = nil end end
            local ready = HK.okUrl(CFG.NOTIFY_URL)
            if not (CFG.NOTIFY_EVENTS and ready) then
                HK.q = {}
            elseif #HK.q > 0 and now >= (HK.cool or 0) then
                local list = {}
                while #HK.q > 0 and #list < 5 do list[#list + 1] = table.remove(HK.q, 1) end
                HK.send(list)
            end
            local per = (tonumber(CFG.FISH_EVERY) or 5) * 60
            if not running then
                HK.nextFish = now + per                      -- paused: the clock waits (fish caught by hand still go out)
                if now >= (HK.nextHand or 0) then
                    HK.nextHand = now + per
                    if CFG.NOTIFY_FISH and ready and #HK.catches > HK.sentN and now >= (HK.cool or 0) then
                        HK.sendCatches(per / 60)
                    end
                end
            elseif now >= HK.nextFish and now >= (HK.cool or 0) then
                HK.nextFish = now + per
                if CFG.NOTIFY_FISH and ready then HK.sendCatches(per / 60) end
                HK.tally, HK.n5, HK.away5, HK.best = {}, 0, ST.away, nil
            end
            if HK.dirty and now - (HK.savedAt or 0) > 20 then
                HK.dirty, HK.savedAt = false, now
                HK.saveLog()
            end
        end)
    end
end)
do  -- every log line goes past HK.onLog; stopping the script also drops the watchers
    local baseLog, baseStop = log, env.__autofish_stop
    log = function(...)
        baseLog(...)
        pcall(HK.onLog, note)
    end
    env.__autofish_stop = function()
        for _, c in ipairs(HK.conns) do pcall(function() c:Disconnect() end) end
        if baseStop then baseStop() end
    end
end

for _, f in ipairs({ HK.watchTools, HK.watchText, HK.watchChat, HK.watchWorld }) do task.spawn(pcall, f) end

local function releaseAll()
    local x, y = point()
    for _, m in ipairs({ "mouse", "mouse2", "touch", "space" }) do
        pcall(PRESS[m], false, x, y)
    end
end

-- walk back to the spot, ending up facing the way you started; true if it got there
local function goHome(hum, root)
    if not (home and hum and root) then return false end
    stage = "walk"
    log("walking back to the spot")
    local function walk(to, tol, secs)
        local t0 = os.clock()
        while alive() and running and os.clock() - t0 < secs do
            if (root.Position - to).Magnitude <= tol then return true end
            hum:MoveTo(to)
            task.wait(0.3)
        end
        return (root.Position - to).Magnitude <= tol
    end
    local look = homeLook and Vector3.new(homeLook.X, 0, homeLook.Z) or Vector3.zero
    if look.Magnitude > 0.1 and not walk(home - look.Unit * 6, 4, 40) then return false end
    return walk(home, 2.5, 10)
end

-- one repair step per call, each step stronger; true only when it gives up for good
local function recover(why)
    rung = rung + 1
    ST.fixes = ST.fixes + 1
    stage = "fix"
    log(string.format("%s - repair step %d", why, rung))
    releaseAll()
    if rung >= 2 then
        for _, c in ipairs({ C, S, H }) do c.i, c.wins, c.fails = 1, {}, {} end
        useBobber = true
    end
    local rod, hum = getRod()
    if rod and hum then
        pcall(function()
            hum:UnequipTools()
            task.wait(0.6)
            hum:EquipTool(rod)
            task.wait(0.6)
        end)
        if rung >= 3 and home then
            local c = lp.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if r and (r.Position - home).Magnitude > 4 then goHome(hum, r) end
        end
    end
    if rung >= 4 then
        local t = 6 + math.random() * 4   -- a short breather so a stuck spot can't spin the repairs flat out
        log(string.format("still stuck - trying again in %ds", math.floor(t)))
        local t0 = os.clock()
        while alive() and running and os.clock() - t0 < t do task.wait(0.5) end
        rung = 0
        return false
    end
    return false
end

-- one miss; after CFG.MAX_FAILS in a row it runs a repair step (it never gives up)
local function failed(why)
    fails = fails + 1
    if fails >= CFG.MAX_FAILS then
        fails = 0
        return recover(why)
    end
    if fails >= 3 then
        local t = 2 + math.random() * 3
        log(string.format("%s - waiting %ds", why, math.floor(t)))
        local t0 = os.clock()
        while alive() and running and os.clock() - t0 < t do task.wait(0.5) end
    end
    return false
end

---------------------------------------------------------------- Frightful Pool (Halloween event)
-- Every 45 min a Frightful Pool spawns at one of four places. The alert is caught the way goblin_25 does it
-- (game remotes + on-screen text + chat), then the character is teleported next to the pool, faces it and keeps
-- fishing. After CFG.POOL_STAY seconds it goes back to the old spot. The ground search, stream-in wait and
-- teleport are ported from goblin_25 (goTo / landAt).
-- Test without waiting for the event:  getgenv().__autofish_pool("Moosewood")
--   (Moosewood / Statue / Terrapin / Harvesters)
local POOLS = {
    { name = "Moosewood",             key = { "moosewood" },           pos = Vector3.new(546, 74.25, -191.25) },
    { name = "Statue of Sovereignty", key = { "sovereign", "statue" }, pos = Vector3.new(-14, 74.25, -660.25) },
    { name = "Terrapin Island",       key = { "terrapin" },            pos = Vector3.new(-373, 74, 2227.25) },
    { name = "Harvesters Spike",      key = { "harvester", "spike" },  pos = Vector3.new(-832, 74.25, 1243.75) },
}

local function poolRoot()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function poolUnanchor()
    local root = poolRoot()
    if root then pcall(function() root.Anchored = false end) end
end

-- invisible pad under the feet (client-side only): the character stands on it instead of hanging anchored in
-- the air, so its state is Landed / Running and not Freefall (casts did nothing while in Freefall)
local function poolPadClear()
    local pad = POOL.pad
    POOL.pad = nil
    if pad then pcall(function() pad:Destroy() end) end
end

local function poolPadMake(at)   -- at = where the character's root goes; the feet end up ~3.2 studs below it
    poolPadClear()
    local pad = Instance.new("Part")
    pad.Name = "AutoFishPoolPad"
    pad.Anchored = true
    pad.CanCollide = true
    pad.Transparency = 1
    pad.Size = Vector3.new(14, 1, 14)
    pad.CFrame = CFrame.new(at.X, at.Y - 3.7, at.Z)
    pad.Parent = workspace
    POOL.pad = pad
    return pad
end

-- goblin_25 landAt: solid ground (not water, not a character) within maxDy of height y at x, z
local function poolLandAt(x, z, y, maxDy, rp)
    local skip, best = { lp.Character }, nil
    for _ = 1, 14 do
        rp.FilterDescendantsInstances = skip
        local hit = workspace:Raycast(Vector3.new(x, y + maxDy + 10, z), Vector3.new(0, -(maxDy * 2 + 20), 0), rp)
        if not hit then break end
        local inst = hit.Instance
        local d = math.abs(hit.Position.Y - y)
        if inst:IsA("Terrain") then
            if hit.Material ~= Enum.Material.Water and d <= maxDy and (not best or d < best.d) then
                best = { pos = hit.Position, inst = inst, d = d }
            end
            break
        end
        local mdl = inst:FindFirstAncestorOfClass("Model")
        local isChar = mdl and mdl:FindFirstChildOfClass("Humanoid") ~= nil
        if not isChar and inst.Transparency < 0.95 and d <= maxDy and (not best or d < best.d) then
            best = { pos = hit.Position, inst = inst, d = d }
        end
        skip[#skip + 1] = inst
    end
    return best
end

-- height of the water surface above x, z (nil when there is no water there or it is not streamed in yet)
local function poolSurface(x, z, y0)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.RespectCanCollide = true
    local skip = { lp.Character }
    for _ = 1, 12 do
        rp.FilterDescendantsInstances = skip
        local hit = workspace:Raycast(Vector3.new(x, y0 + 400, z), Vector3.new(0, -900, 0), rp)
        if not hit then return nil end
        if hit.Instance:IsA("Terrain") then
            if hit.Material == Enum.Material.Water then return hit.Position.Y end
            return nil
        end
        skip[#skip + 1] = hit.Instance
    end
    return nil
end

-- the pool's own model / part, if the game names it "...frightful..." (only what is streamed in around us)
local function poolFindObject(center)
    local best, bd, n = nil, 150, 0
    local me = lp.Character
    for _, d in ipairs(workspace:GetDescendants()) do
        n = n + 1
        if n % 2000 == 0 then task.wait() end
        if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():find("frightful", 1, true)
            and not (me and d:IsDescendantOf(me)) then
            local ok, p = pcall(function() return d:GetPivot().Position end)
            if ok and p then
                local dist = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
                if dist < bd then best, bd = d, dist end
            end
        end
    end
    return best
end

-- teleport back to where we were fishing before the pool
local function poolReturn(back, why)
    local root, hum = poolRoot()
    if not (root and hum and back) then return false end
    local rod = getRod()
    stage = "walk"
    releaseAll()
    log("POOL: " .. why .. " - back to the old spot")
    pcall(function() hum:UnequipTools() end)
    task.wait(0.4)
    pcall(function() lp:RequestStreamAroundAsync(back.pos) end)
    root.Anchored = true
    root.CFrame = CFrame.new(back.pos + Vector3.new(0, 60, 0))
    root.AssemblyLinearVelocity = Vector3.zero
    poolPadClear()   -- anchored high above the old spot, so removing the pad drops nothing
    task.wait(1.5)
    root = poolRoot()
    if not root then return false end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.RespectCanCollide = true
    local land
    for _ = 1, 5 do
        land = poolLandAt(back.pos.X, back.pos.Z, back.pos.Y - 3, 14, rp)
        if land then break end
        task.wait(0.5)
    end
    local at = land and (land.pos + Vector3.new(0, 3.2, 0)) or (back.pos + Vector3.new(0, 1, 0))
    local lk = Vector3.new(back.look.X, 0, back.look.Z)
    if lk.Magnitude < 0.1 then lk = Vector3.new(0, 0, -1) end
    root.CFrame = CFrame.lookAt(at, at + lk)
    root.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.3)
    root.Anchored = false
    task.wait(0.3)
    if rod then pcall(function() hum:EquipTool(rod) end) end
    home, homeLook = back.pos, back.look
    fails, rung = 0, 0
    pulse = os.clock()
    stage = "start"
    return true
end

-- ================= boat route =================
-- Casting at the pool only works when you stand / sit on something the SERVER knows about (a boat). A pad or
-- hovering that only exists on this client does not work. So: find your boat, sit in it, move the whole boat to
-- the pool, fish from the seat, and bring the boat back afterwards.
local function poolSame(v)
    if v == nil then return false end
    if typeof(v) == "Instance" then return v == lp end
    local sv = tostring(v):lower()
    return sv == lp.Name:lower() or sv == tostring(lp.UserId) or sv == lp.DisplayName:lower()
end

-- why a model counts as ours ("" = it does not)
local function poolBoatOwner(m)
    for _, k in ipairs({ "Owner", "owner", "OwnerId", "OwnerID", "OwnerName", "UserId", "Player", "PlayerName" }) do
        if poolSame(m:GetAttribute(k)) then return "attribute " .. k end
        local c = m:FindFirstChild(k)
        if c and c:IsA("ValueBase") and poolSame(c.Value) then return "value " .. k end
    end
    local me, dn = lp.Name:lower(), lp.DisplayName:lower()
    local a = m
    while a and a ~= workspace do
        local nm = a.Name:lower()
        if nm == me or nm == dn then return "name " .. a.Name end
        a = a.Parent
    end
    if m.Name:lower():find(me, 1, true) then return "model name" end
    return ""
end

local function poolDesc(m)
    local bits = {}
    for k, v in pairs(m:GetAttributes()) do
        if #bits < 6 then bits[#bits + 1] = k .. "=" .. tostring(v) end
    end
    for _, c in ipairs(m:GetChildren()) do
        if c:IsA("ValueBase") and #bits < 10 then bits[#bits + 1] = c.Name .. "=" .. tostring(c.Value) end
    end
    return m:GetFullName() .. " {" .. table.concat(bits, ", ") .. "}"
end

local function poolSeatedIn(info)
    local _, hum = poolRoot()
    local sp = hum and hum.SeatPart
    if sp and info and sp:IsDescendantOf(info.model) then return sp end
    return nil
end

-- your boat: a model with a seat that says it is yours (owner value / name), the one you sit in, or POOL_BOAT_NAME
local function poolFindBoat()
    local root, hum = poolRoot()
    if not (root and hum) then return nil end
    local want = tostring(CFG.POOL_BOAT_NAME or ""):lower()
    local best, bd, all, seen, n = nil, math.huge, {}, {}, 0
    local sitting = hum.SeatPart
    local fast = POOL.fastBoat(root, hum)   -- workspace.active.boats.<you>.<boat>
    if fast then return fast end
    for _, d in ipairs(workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then task.wait() end
        if (d:IsA("VehicleSeat") or d:IsA("Seat")) and d.Disabled == false then
            local top = d:FindFirstAncestorOfClass("Model")
            if top and not top:FindFirstChildOfClass("Humanoid") then
                while top.Parent and top.Parent:IsA("Model") and top.Parent ~= workspace do top = top.Parent end
                if not seen[top] then
                    seen[top] = true
                    local why = ""
                    if sitting and sitting:IsDescendantOf(top) then
                        why = "you are sitting in it"
                    elseif want ~= "" and top:GetFullName():lower():find(want, 1, true) then
                        why = "POOL_BOAT_NAME"
                    else
                        why = poolBoatOwner(top)
                    end
                    local okp, piv = pcall(function() return top:GetPivot().Position end)
                    local dist = okp and (piv - root.Position).Magnitude or math.huge
                    all[#all + 1] = { m = top, dist = dist }
                    if why ~= "" and dist < bd then best, bd = { model = top, why = why }, dist end
                end
            end
        end
    end
    if best then
        local seat = sitting and sitting:IsDescendantOf(best.model) and sitting or nil
        if not seat then
            local first
            for _, d in ipairs(best.model:GetDescendants()) do
                if d:IsA("VehicleSeat") and d.Disabled == false then seat = d break end
                if d:IsA("Seat") and d.Disabled == false and not first then first = d end
            end
            seat = seat or first
        end
        best.seat = seat
        log(string.format("POOL: boat = %s | seat = %s | match: %s | %d studs away", best.model:GetFullName(),
            seat and seat.Name or "none", best.why, math.floor(bd)))
        return seat and best or nil
    end
    table.sort(all, function(x, y) return x.dist < y.dist end)
    log(string.format("POOL: no boat of yours found (%d models with a seat). boat candidates, nearest first:", #all))
    for i = 1, math.min(4, #all) do
        log(string.format("POOL: candidate %d studs: %s", math.floor(all[i].dist), poolDesc(all[i].m)))
    end
    return nil
end

-- ================= boat scan / watch (look only, nothing is moved) =================
POOL.words = { "boat", "ship", "raft", "canoe", "dinghy", "skiff", "yacht", "vessel", "kayak", "sail", "vehicle" }
POOL.boatish = function(s)
    s = tostring(s):lower()
    for _, w in ipairs(POOL.words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end
POOL.dist = function(d, root)
    local ok, p = pcall(function()
        if d:IsA("Model") then return d:GetPivot().Position end
        if d:IsA("BasePart") then return d.Position end
    end)
    return (ok and p) and (p - root.Position).Magnitude or math.huge
end

POOL.boatScan = function()
    local root, hum = poolRoot()
    if not (root and hum) then log("POOL: boatscan - no character") return end
    local sp = hum.SeatPart
    log("POOL: boatscan - sitting in: " .. (sp and sp:GetFullName() or "nothing"))
    local seats, named, n = {}, {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then task.wait() end
        if d:IsA("Seat") or d:IsA("VehicleSeat") then
            seats[#seats + 1] = { d = d, dist = POOL.dist(d, root) }
        elseif (d:IsA("Model") or d:IsA("Folder")) and POOL.boatish(d.Name) then
            named[#named + 1] = { d = d, dist = POOL.dist(d, root) }
        end
    end
    local function byDist(a, b) return a.dist < b.dist end
    table.sort(seats, byDist)
    table.sort(named, byDist)
    log(string.format("POOL: boatscan - %d seats (any kind), %d boat-named models/folders", #seats, #named))
    for i = 1, math.min(6, #seats) do
        local s = seats[i].d
        log(string.format("POOL: seat %dst: %s [%s] disabled=%s", math.floor(seats[i].dist),
            s:GetFullName(), s.ClassName, tostring(s.Disabled)))
    end
    for i = 1, math.min(8, #named) do
        log(string.format("POOL: named %dst: %s", math.floor(named[i].dist), poolDesc(named[i].d)))
    end
    local tools = {}
    for _, t in ipairs(lp.Backpack:GetChildren()) do tools[#tools + 1] = t.Name end
    log("POOL: backpack: " .. table.concat(tools, ", "):sub(1, 300))
    local top = {}
    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Folder") or c:IsA("Model") then top[#top + 1] = c.Name .. "(" .. #c:GetChildren() .. ")" end
    end
    log("POOL: workspace: " .. table.concat(top, ", "):sub(1, 400))
end

-- logs whatever appears while you buy / spawn the boat, plus the prompt you press
POOL.boatWatch = function(secs)
    secs = tonumber(secs) or 180
    local t0 = os.clock()
    log(string.format("POOL: boatwatch ON for %ds - buy / spawn / sit in your boat now", secs))
    local c1 = workspace.DescendantAdded:Connect(function(d)
        if os.clock() - t0 > secs then return end
        if d:IsA("Seat") or d:IsA("VehicleSeat") or ((d:IsA("Model") or d:IsA("Folder")) and POOL.boatish(d.Name)) then
            log(string.format("POOL: boatwatch NEW %s [%s]", d:GetFullName(), d.ClassName))
        end
    end)
    local c2 = game:GetService("ProximityPromptService").PromptTriggered:Connect(function(p, who)
        if who == lp then
            log(string.format("POOL: boatwatch PROMPT %s | action=%s | object=%s", p:GetFullName(), p.ActionText, p.ObjectText))
        end
    end)
    task.delay(secs, function()
        pcall(function() c1:Disconnect() end)
        pcall(function() c2:Disconnect() end)
        log("POOL: boatwatch OFF")
    end)
end

-- water height under (x, z): looks down from topY through docks / pool effects until it hits water.
-- returns y, what-it-hit  (nil = no water found)
POOL.waterAt = function(x, z, topY, ignore)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = false
    local ex = {}
    for _, i in pairs(ignore or {}) do
        if typeof(i) == "Instance" then ex[#ex + 1] = i end
    end
    for _ = 1, 6 do
        rp.FilterDescendantsInstances = ex
        local hit = workspace:Raycast(Vector3.new(x, topY, z), Vector3.new(0, -700, 0), rp)
        if not hit then return nil end
        if hit.Material == Enum.Material.Water then return hit.Position.Y, "water" end
        if hit.Instance:IsA("Terrain") then return nil end   -- sea floor / land: no water here
        local nm = hit.Instance.Name:lower()
        if nm:find("water", 1, true) or nm:find("ocean", 1, true) or nm:find("sea", 1, true) then
            return hit.Position.Y, hit.Instance.Name
        end
        ex[#ex + 1] = hit.Instance   -- dock / pool effect / decoration: look through it
    end
    return nil
end

-- keeps the boat afloat at the pool: if the seat drops under its normal height above the water, lift the boat
POOL.afloat = function(a)
    local b = a and a.boat
    if not (b and b.seat and b.seat.Parent and b.model and b.model.Parent and a.waterY) then return end
    if os.clock() - (a.floatAt or 0) < 4 then return end
    a.floatAt = os.clock()
    local off = a.offset or 3
    local y = b.seat.Position.Y
    if y >= a.waterY + math.max(off * 0.4, 0.5) then return end
    a.lifts = (a.lifts or 0) + 1
    if a.lifts > 6 then
        if a.lifts == 7 then log("POOL: boat keeps sinking - stopped lifting it (raise CFG.POOL_LIFT)") end
        return
    end
    log(string.format("POOL: boat is sinking (seat y %.1f, water %.1f) - lifting it, try %d", y, a.waterY, a.lifts))
    b.model:PivotTo(b.model:GetPivot() + Vector3.new(0, a.waterY + off + (tonumber(CFG.POOL_LIFT) or 2) - y, 0))
    pcall(function()
        b.seat.AssemblyLinearVelocity = Vector3.zero
        b.seat.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- fast path: Fisch keeps every player's boat at workspace.active.boats.<PlayerName>.<BoatName>
-- (seat "owner" = VehicleSeat, "passanger" = Seat). The game seats you itself when you summon the boat.
POOL.fastBoat = function(root, hum)
    local act = workspace:FindFirstChild("active")
    local boats = act and act:FindFirstChild("boats")
    local mine = boats and (boats:FindFirstChild(lp.Name) or boats:FindFirstChild(lp.DisplayName))
    if not mine then return nil end
    local sitting = hum.SeatPart
    local best, bd
    for _, m in ipairs(mine:GetChildren()) do
        if m:IsA("Model") then
            local okp, piv = pcall(function() return m:GetPivot().Position end)
            local dist = okp and (piv - root.Position).Magnitude or math.huge
            local seat = sitting and sitting:IsDescendantOf(m) and sitting or nil
            if not seat then
                local o = m:FindFirstChild("owner", true)
                if o and (o:IsA("VehicleSeat") or o:IsA("Seat")) then seat = o end
            end
            if not seat then
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("VehicleSeat") or d:IsA("Seat") then seat = d break end
                end
            end
            if seat and (bd == nil or dist < bd) then
                best, bd = { model = m, seat = seat, why = "workspace.active.boats." .. mine.Name }, dist
            end
        end
    end
    if best then
        log(string.format("POOL: boat = %s | seat = %s | match: %s | %d studs away", best.model:GetFullName(),
            best.seat.Name, best.why, math.floor(bd)))
    end
    return best
end

-- optional: find out HOW the game summons the boat (so the script can summon it itself later)
--   1) lists remotes whose names sound like boats / spawning
--   2) while it is on, logs the first call of every remote YOU fire (needs hookmetamethod on the executor)
-- pause AutoFish first, run getgenv().__autofish_spy(60), then summon the boat from the game's own menu
POOL.spy = function(secs)
    secs = tonumber(secs) or 60
    local t0 = os.clock()
    local shown = 0
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local l = d.Name:lower()
            if POOL.boatish(l) or l:find("spawn", 1, true) or l:find("summon", 1, true) then
                if shown < 12 then
                    shown = shown + 1
                    log("POOL: spy remote: " .. d:GetFullName():sub(1, 110))
                end
            end
        end
    end
    log(string.format("POOL: spy - %d boat/spawn-like remotes listed", shown))
    POOL.spyUntil, POOL.spySeen, POOL.spyN = t0 + secs, {}, 0
    if POOL.spyHooked then
        log(string.format("POOL: spy ON for %ds - summon the boat now", secs))
        task.delay(secs, function() log("POOL: spy OFF") end)
        return
    end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        log("POOL: spy - no hookmetamethod on this executor, only the remote list above")
        return
    end
    local old
    local okh, errh = pcall(function()
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local m = getnamecallmethod()
            if (m == "FireServer" or m == "InvokeServer") and os.clock() < (POOL.spyUntil or 0)
                    and not (checkcaller and checkcaller()) then
                local a = table.pack(...)
                task.defer(function()
                    local okk, full = pcall(function() return self:GetFullName() end)
                    full = okk and full or tostring(self)
                    local parts = {}
                    for i = 1, math.min(a.n, 4) do parts[i] = tostring(a[i]):sub(1, 40) end
                    local key = full .. "|" .. (parts[1] or "")
                    if POOL.spySeen[key] or POOL.spyN >= 30 then return end
                    POOL.spySeen[key] = true
                    POOL.spyN = POOL.spyN + 1
                    log(string.format("POOL: spy %s %s | args: %s", m, full:sub(-70), table.concat(parts, " , ")))
                end)
            end
            return old(self, ...)
        end)
    end)
    if not okh then
        log("POOL: spy hook failed: " .. tostring(errh))
        return
    end
    POOL.spyHooked = true
    log(string.format("POOL: spy ON for %ds - summon the boat now", secs))
    task.delay(secs, function() log("POOL: spy OFF") end)
end

local function poolBoard(info)
    for _ = 1, 4 do
        local root, hum = poolRoot()
        if not (root and hum) then return false end
        if poolSeatedIn(info) then return true end
        pcall(function() lp:RequestStreamAroundAsync(info.seat.Position) end)
        root.Anchored = false
        root.CFrame = info.seat.CFrame * CFrame.new(0, 2.2, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.8)
        if poolSeatedIn(info) then return true end
        if fireproximityprompt then   -- some boats use a prompt instead of touch-to-sit
            for _, d in ipairs(info.model:GetDescendants()) do
                if d:IsA("ProximityPrompt") and d.Enabled then pcall(fireproximityprompt, d) break end
            end
            task.wait(0.8)
            if poolSeatedIn(info) then return true end
        end
    end
    return false
end

local function poolUnseat()
    local root, hum = poolRoot()
    if not (root and hum) then return end
    for _ = 1, 5 do
        if not hum.SeatPart then return end
        pcall(function() hum.Sit = false end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        task.wait(0.5)
    end
end

-- sit in the boat, carry the whole boat to the pool, equip the rod. true = we are at the pool and fishing
local function poolGoBoat(w, back)
    local P = POOL
    local info = poolFindBoat()
    if not info then
        log("POOL: no boat found - spawn your boat before the pool shows up (or set CFG.POOL_BOAT_NAME)")
        return false
    end
    local root, hum = poolRoot()
    if not (root and hum) then return false end
    local rod = getRod()
    stage = "walk"
    releaseAll()
    log("POOL: taking the boat to " .. w.name)
    pcall(function() hum:UnequipTools() end)
    task.wait(0.4)
    if not poolBoard(info) then
        log("POOL: could not sit in the boat")
        return false
    end
    local seat = poolSeatedIn(info) or info.seat
    info.seat = seat
    local keep = P.active and P.active.boat and P.active.boat.back   -- already on a boat trip: keep the first home
    local boatBack = keep or info.model:GetPivot()

    local center = w.pos
    pcall(function() lp:RequestStreamAroundAsync(center) end)
    local dir = Vector3.new(back.pos.X - center.X, 0, back.pos.Z - center.Z)
    dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(1, 0, 0)
    local dist = math.max(CFG.POOL_DIST, 6)
    -- measure the real water height at the pool and how high this boat's seat normally rides above the water
    local atX, atZ = center.X + dir.X * dist, center.Z + dir.Z * dist
    local ign = { lp.Character, info.model }
    local surfaceY, how
    for _ = 1, 3 do
        surfaceY, how = POOL.waterAt(atX, atZ, center.Y + 120, ign)
        if surfaceY then break end
        task.wait(0.6)
    end
    local here = POOL.waterAt(seat.Position.X, seat.Position.Z, seat.Position.Y + 40, ign)
    local offset = here and (seat.Position.Y - here) or nil
    if not offset or offset < 0.3 or offset > 15 then offset = 3 end
    local lift = tonumber(CFG.POOL_LIFT) or 2
    if not surfaceY then surfaceY, how = w.pos.Y, "no water found - wiki y" end
    local seatY = surfaceY + offset + lift
    log(string.format("POOL: water y %.2f (%s) | seat rides %.1f above water (%s) | placing seat at y %.2f",
        surfaceY, tostring(how), offset, here and "measured" or "default", seatY))
    local at = Vector3.new(atX, seatY, atZ)
    local face = CFrame.lookAt(at, Vector3.new(center.X, seatY, center.Z))   -- the seat looks at the pool
    local rel = seat.CFrame:ToObjectSpace(info.model:GetPivot())
    info.model:PivotTo(face * rel)
    pcall(function()
        seat.AssemblyLinearVelocity = Vector3.zero
        seat.AssemblyAngularVelocity = Vector3.zero
    end)
    task.wait(2)
    for i = 1, 4 do   -- sunk anyway? lift it again
        local y = seat.Position.Y
        if y >= surfaceY + offset - 1.5 then break end
        log(string.format("POOL: boat sank to seat y %.1f (water %.1f) - lifting it, try %d", y, surfaceY, i))
        info.model:PivotTo(info.model:GetPivot() + Vector3.new(0, surfaceY + offset + lift - y, 0))
        pcall(function()
            seat.AssemblyLinearVelocity = Vector3.zero
            seat.AssemblyAngularVelocity = Vector3.zero
        end)
        task.wait(1.5)
    end
    log(string.format("POOL: boat settled: seat y %.1f = %.1f above the water", seat.Position.Y, seat.Position.Y - surfaceY))

    local r2, h2 = poolRoot()
    if not (r2 and h2) then P.pending = w return true end
    if not h2.SeatPart then
        log("POOL: fell out of the boat on the way")
        return false
    end
    local inHand = false
    for _ = 1, 4 do
        pcall(function() h2:EquipTool(rod) end)
        task.wait(0.5)
        local ch2 = lp.Character
        if rod and ch2 and rod.Parent == ch2 then inHand = true break end
    end
    log(string.format("POOL: rod in hand = %s | state = %s | seated = %s | boat %d studs from the pool centre",
        tostring(inHand), tostring(h2:GetState()):gsub("Enum.HumanoidStateType.", ""), tostring(h2.SeatPart ~= nil),
        math.floor(Vector3.new(seat.Position.X - center.X, 0, seat.Position.Z - center.Z).Magnitude)))

    home, homeLook = seat.Position, seat.CFrame.LookVector
    P.active = { name = w.name, center = center, since = os.clock(), back = back,
                 endAt = (w.at or os.clock()) + CFG.POOL_STAY,
                 boat = { model = info.model, seat = seat, back = boatBack }, waterY = surfaceY, offset = offset }
    P.pending = nil
    fails, rung = 0, 0
    pulse = os.clock()
    stage = "start"
    log(string.format("POOL: at %s in the boat, fishing for %ds", w.name, math.floor(math.max(P.active.endAt - os.clock(), 0))))
    return true
end

-- time is up: carry the boat home first, then get out of the seat (poolReturn moves the character itself)
local function poolBoatBack(b)
    local root, hum = poolRoot()
    if b and b.model and b.model.Parent and b.back and root and hum and hum.SeatPart then
        log("POOL: bringing the boat back")
        b.model:PivotTo(b.back)
        pcall(function()
            b.seat.AssemblyLinearVelocity = Vector3.zero
            b.seat.AssemblyAngularVelocity = Vector3.zero
        end)
        task.wait(1.5)
    end
    if not CFG.POOL_STAY_IN_BOAT then poolUnseat() end
end

-- teleport to the pool, stand on the nearest ground (or hover over the water), face it
local function poolGo(w)
    local P = POOL
    w.tries = (w.tries or 0) + 1
    if w.tries > 3 then
        log("POOL: giving up on " .. w.name .. " after 3 tries")
        return false
    end
    local left = (w.at or os.clock()) + CFG.POOL_STAY - os.clock()   -- seconds until the pool is gone
    if left < 30 then
        log(string.format("POOL: %s has only %ds left - not worth the trip", w.name, math.floor(math.max(left, 0))))
        return false
    end
    local root, hum = poolRoot()
    if not (root and hum) then P.pending = w return false end   -- no character right now: try again next cycle
    local rod = getRod()
    stage = "walk"
    releaseAll()
    local center = w.pos
    local back = (P.active and P.active.back) or { pos = home or root.Position, look = homeLook or root.CFrame.LookVector }
    if CFG.POOL_BOAT then
        local okB, doneB = pcall(poolGoBoat, w, back)
        if okB and doneB then return true end
        if not okB then
            log("POOL error (boat): " .. tostring(doneB))
            poolUnanchor()
        end
        log("POOL: boat route did not work - trying ground near the pool")
    end
    log("POOL: teleporting to " .. w.name)
    pcall(function() hum:UnequipTools() end)
    task.wait(0.4)

    -- stream the area in while hovering high above it (anchored), like goblin_25's goTo
    pcall(function() lp:RequestStreamAroundAsync(center) end)
    root.Anchored = true
    root.CFrame = CFrame.new(center + Vector3.new(0, 150, 0))
    root.AssemblyLinearVelocity = Vector3.zero
    poolPadClear()   -- the pad of an earlier pool, if any (we are anchored high up now, so nothing falls)
    task.wait(1.5)
    if not poolRoot() then P.pending = w return true end

    -- the pool's real centre, if the game names the object (otherwise the coordinates from the wiki are used)
    local obj
    for _ = 1, 3 do
        local okO, o = pcall(poolFindObject, center)
        if okO and o then obj = o break end
        task.wait(1)
    end
    if obj then
        local okP, p = pcall(function() return obj:GetPivot().Position end)
        if okP and p then
            log(string.format("POOL: found %s at %.0f, %.0f, %.0f", obj:GetFullName(), p.X, p.Y, p.Z))
            center = Vector3.new(p.X, center.Y, p.Z)
        end
    else
        log("POOL: no object named 'frightful' near the spot - using the wiki coordinates")
    end

    -- water surface (the wiki's Y is not always the sea level)
    local surf
    for _ = 1, 4 do
        surf = poolSurface(center.X, center.Z, center.Y)
        if surf then break end
        task.wait(0.6)
    end
    surf = surf or center.Y

    -- nearest solid ground around the pool, rings of growing radius
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.RespectCanCollide = true
    local stand
    for _, r in ipairs({ 6, 12, 18, 26, 36, 48, 60, 80 }) do
        if r > CFG.POOL_REACH then break end
        for i = 0, 15 do
            local a = math.rad(i * 22.5)
            local f = poolLandAt(center.X + math.cos(a) * r, center.Z + math.sin(a) * r, surf, 30, rp)
            if f then stand = { pos = f.pos, r = r } break end
        end
        if stand then break end
    end

    local pos, floating
    if stand then
        pos = stand.pos + Vector3.new(0, 3.2, 0)
        log(string.format("POOL: standing on ground %d studs from the pool centre", stand.r))
    elseif CFG.POOL_FLOAT then
        local dir = Vector3.new(back.pos.X - center.X, 0, back.pos.Z - center.Z)
        dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(1, 0, 0)
        local dist = math.max(CFG.POOL_DIST, 6)
        pos = Vector3.new(center.X + dir.X * dist, surf + 4, center.Z + dir.Z * dist)
        floating = true
        log(string.format("POOL: no ground within %d studs - hovering over the water (anchored), %d studs from the centre",
            CFG.POOL_REACH, dist))
    else
        log("POOL: no ground near the pool and POOL_FLOAT is off - skipping this pool")
        poolReturn(back, "no spot at the pool")
        return true
    end

    local root2, hum2 = poolRoot()
    if not root2 then P.pending = w return true end
    local look = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
    local pad
    if floating and CFG.POOL_PLATFORM then
        pad = poolPadMake(pos)
        log("POOL: standing on an invisible pad over the water")
    end
    root2.CFrame = look
    root2.AssemblyLinearVelocity = Vector3.zero
    root2.Anchored = (floating and not pad) and true or false
    task.wait(0.5)
    -- equip the rod and check it really is in the hand (a report showed equipped=false right after arriving)
    local inHand = false
    for _ = 1, 4 do
        if not (rod and hum2) then break end
        pcall(function() hum2:EquipTool(rod) end)
        task.wait(0.5)
        local ch2 = lp.Character
        if ch2 and rod.Parent == ch2 then inHand = true break end
        root2, hum2 = poolRoot()
        if not hum2 then break end
    end
    log(string.format("POOL: rod in hand = %s | state = %s | anchored = %s", tostring(inHand),
        hum2 and tostring(hum2:GetState()):gsub("Enum.HumanoidStateType.", "") or "?", tostring(root2 and root2.Anchored)))

    home, homeLook = pos, look.LookVector
    P.active = { name = w.name, center = center, since = os.clock(), floating = floating, obj = obj, back = back,
                 endAt = (w.at or os.clock()) + CFG.POOL_STAY }
    P.pending = nil
    fails, rung = 0, 0
    pulse = os.clock()
    stage = "start"
    log(string.format("POOL: at %s, fishing for %ds (control is halved there, so the bar response is learned separately)",
        w.name, math.floor(math.max(P.active.endAt - os.clock(), 0))))
    return true
end

-- called at the top of every cycle(): true = it moved us, so the cycle should start over
local function poolTick()
    local P = POOL
    if P.pending then
        local w = P.pending
        if reelReady() or getShake() then return false end   -- finish the fish on the line first
        P.pending = nil
        local ok, res = pcall(poolGo, w)
        if not ok then
            log("POOL error: " .. tostring(res))
            poolUnanchor()
            stage = "start"
            return true
        end
        return res and true or false
    end
    local a = P.active
    if a and a.boat then   -- the boat drifts: move "home" with it so GUARD does not drag us off
        local r = poolRoot()
        if r then home = r.Position end
        pcall(POOL.afloat, a)
    end
    if a and os.clock() > (a.endAt or (a.since + CFG.POOL_STAY)) then
        P.active = nil
        if CFG.POOL_BACK then
            if a.boat then pcall(poolBoatBack, a.boat) end
            local r0, h0 = poolRoot()
            if CFG.POOL_STAY_IN_BOAT and a.boat and r0 and h0 and h0.SeatPart then
                local rod0 = getRod()
                if rod0 and rod0.Parent ~= lp.Character then pcall(function() h0:EquipTool(rod0) end) end
                home, homeLook = r0.Position, r0.CFrame.LookVector
                fails, rung = 0, 0
                pulse = os.clock()
                stage = "start"
                log("POOL: time is up - boat is back, staying in it")
                return true
            end
            local ok, res = pcall(poolReturn, a.back, "time is up")
            if not ok then
                log("POOL error: " .. tostring(res))
                poolUnanchor()
                stage = "start"
            end
            return true
        end
        log("POOL: time is up - POOL_BACK is off, staying here")
    end
    return false
end

-- an alert text: "...frightful pool ... <place>..." (spaces, case and tags do not matter)
function HK.poolText(raw, src)   -- src = which path saw it ("screen text" / "chat" / "remote <name>")
    local P = POOL
    if not (CFG.POOL and alive()) then return end
    local ok, s = pcall(function() return (tostring(raw):gsub("<[^>]+>", "")) end)
    if not ok or type(s) ~= "string" or #s > 600 then return end
    local flat = s:lower():gsub("[%s_%-]+", "")
    if not flat:find("frightfulpool", 1, true) then return end
    -- not a catch popup ("you caught ..."), not a countdown label ("12:30")
    if flat:find("caught", 1, true) or flat:find("obtained", 1, true) or s:find("%d%d?:%d%d") then return end
    local which
    for _, p in ipairs(POOLS) do
        for _, k in ipairs(p.key) do
            if flat:find(k, 1, true) then which = p break end
        end
        if which then break end
    end
    if not which then
        if not P.noPlace or os.clock() - P.noPlace > 30 then
            P.noPlace = os.clock()
            log("POOL: alert without a place I know" .. (src and (" (via " .. src .. ")") or "") .. ": " .. s:sub(1, 300))
        end
        return
    end
    local now = os.clock()
    if P.lastName == which.name and now - P.lastAt < 120 then return end
    if P.active and P.active.name == which.name and now < (P.active.endAt or (P.active.since + CFG.POOL_STAY)) then return end
    if P.pending and P.pending.name == which.name and now - (P.pending.at or now) < CFG.POOL_STAY then return end
    P.lastName, P.lastAt = which.name, now
    -- the full alert text and the path that caught it, so the report shows exactly what the game sent
    log("POOL alert" .. (src and (" via " .. src) or "") .. ": " .. which.name .. " | " .. s:sub(1, 300))
    P.pending = { name = which.name, pos = which.pos, at = now }   -- 'at' = the alert, the pool lives POOL_STAY from here
    if not running then
        -- poolTick only runs while AutoFish is running: the alert stays queued and the trip starts on resume
        log(string.format("POOL: AutoFish is PAUSED - %s is queued, resume within %ds and it goes there",
            which.name, math.floor(CFG.POOL_STAY - 30)))
    end
end

-- goblin_25's first path: game remotes (ReplicatedStorage.events + packages.Net) that carry the alert text
function HK.poolRemotes()
    local RS = game:GetService("ReplicatedStorage")
    local function collect(v, d, out)
        if type(v) == "string" then
            if #v < 300 then out[#out + 1] = v end
        elseif type(v) == "table" and d < 3 then
            local n = 0
            for _, x in pairs(v) do
                n = n + 1
                if n > 30 then break end
                collect(x, d + 1, out)
            end
        end
    end
    local hooked = 0
    local function hook(r)
        if not r:IsA("BaseRemoteEvent") then return end
        hooked = hooked + 1
        HK.conns[#HK.conns + 1] = r.OnClientEvent:Connect(function(...)
            if not CFG.POOL then return end
            local a, out = table.pack(...), {}
            for i = 1, a.n do collect(a[i], 0, out) end
            if #out == 0 then return end
            local s = table.concat(out, " ")
            if s:lower():find("frightful", 1, true) then pcall(HK.poolText, s, "remote " .. r.Name) end
        end)
    end
    local ev = RS:FindFirstChild("events")
    local pk = RS:FindFirstChild("packages")
    local net = pk and pk:FindFirstChild("Net")
    for _, root in ipairs({ ev, net }) do
        if root then
            for _, r in ipairs(root:GetChildren()) do hook(r) end
        end
    end
    log(string.format("POOL: listening on %d game remotes + screen text + chat", hooked))
end

do
    local prevStop = env.__autofish_stop
    env.__autofish_stop = function(...)
        pcall(poolPadClear)
        if type(prevStop) == "function" then return prevStop(...) end
    end
end

-- look for your boat without moving anything:  getgenv().__autofish_boat()   (result is in the POOL lines of the report)
env.__autofish_boat = function()
    task.spawn(function()
        local ok, err = pcall(poolFindBoat)
        if not ok then log("POOL: boat search failed: " .. tostring(err)) end
    end)
    return true
end

-- boat scan:   getgenv().__autofish_boatscan()      (sit in your boat first, then Copy report -> POOL lines)
-- boat watch:  getgenv().__autofish_boatwatch(180)   (then buy / spawn the boat; logs what appears)
env.__autofish_boatscan = function()
    task.spawn(function()
        local ok, err = pcall(POOL.boatScan)
        if not ok then log("POOL: boatscan failed: " .. tostring(err)) end
    end)
    return true
end
env.__autofish_boatwatch = function(secs)
    local ok, err = pcall(POOL.boatWatch, secs)
    if not ok then log("POOL: boatwatch failed: " .. tostring(err)) end
    return true
end
env.__autofish_spy = function(secs)
    task.spawn(function()
        local ok, err = pcall(POOL.spy, secs)
        if not ok then log("POOL: spy failed: " .. tostring(err)) end
    end)
    return true
end

env.__autofish_pool = function(name)
    local l = tostring(name or ""):lower()
    for _, p in ipairs(POOLS) do
        for _, k in ipairs(p.key) do
            if l:find(k, 1, true) then
                POOL.pending = { name = p.name, pos = p.pos, at = os.clock() }
                log("POOL: manual test -> " .. p.name)
                if not running then
                    log("POOL: AutoFish was paused - resuming so the test can run")
                    setRunning(true)
                end
                return true
            end
        end
    end
    log("POOL: unknown place '" .. l .. "' (Moosewood / Statue / Terrapin / Harvesters)")
    return false
end
task.spawn(pcall, HK.poolRemotes)

-- logs "SEAT LOST ..." the moment the character leaves its seat (boat), with what the script was doing then
task.spawn(function()
    local was = false
    while alive() do
        local c = lp.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local now = (h ~= nil and h.SeatPart ~= nil)
        if was and not now then
            local st = h and tostring(h:GetState()):gsub("Enum.HumanoidStateType.", "") or "?"
            log(string.format("SEAT LOST | stage=%s | hold=%s | state=%s | pool=%s",
                tostring(stage), tostring(H.cur()), tostring(st), tostring(POOL.active ~= nil)))
        end
        was = now
        task.wait(0.2)
    end
end)

local function cycle()
    local rod, hum = getRod()
    if not rod then
        log("no rod in your hands or backpack - equip one and I'll carry on")
        task.wait(3)
        return
    end

    if CFG.POOL and poolTick() then return end   -- a Frightful Pool alert came in (or the stay is over): moved, start over

    if CFG.GUARD then
        local c = lp.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if r then
            if not home then
                home, homeLook = r.Position, r.CFrame.LookVector
            elseif (r.Position - home).Magnitude > CFG.GUARD_STUDS then
                local far = math.floor((r.Position - home).Magnitude)
                if CFG.WALK_HOME and goHome(hum, r) then
                    log("back on the spot")
                else
                    -- can't get back: fish from where we stand instead of repairing in a loop
                    log("moved " .. far .. " studs and can't walk back - fishing from here")
                    home, homeLook = r.Position, r.CFrame.LookVector
                end
            end
        end
    end

    mood = clamp(mood + (math.random() - 0.5) * 0.14, 0.85, 1.25)

    -- the bobber check was switched off after a slow catch: turn it back on as soon as the bobber is gone
    if not useBobber and not reelReady() and not getShake() and not rod:FindFirstChild("bobber") then
        useBobber = true
        log("bobber check back on - the bobber is gone")
    end

    if not (reelReady() or getShake()) then
        if lineOut(rod) then pause({ 1.0, 1.6 }) end   -- may still be reeling in the last catch
        if not lineOut(rod) then                        -- (a line already out = script started mid-cast)
            stage = "cast"
            if not castLine(rod) then
                if alive() and running then
                    log("the cast never registers - face the water and check the rod")
                    failed("cast failed")
                end
                task.wait(3)
                return
            end
        end
    end

    stage = "wait"
    local t0, done, warned, shaken, bitten = os.clock(), false, false, false, false
    local idleAt = nil
    while alive() and running and os.clock() - t0 < CFG.TIMEOUT do
        local reel, bar, fish = getReel()
        if reel and bar and fish then
            if not bitten then
                bitten = true
                ST.waitSum, ST.waitN = ST.waitSum + (os.clock() - t0), ST.waitN + 1
            end
            pcall(snapOnce, "reel", reel)
            stage = "reel"
            log("reel minigame")
            local a0, h0 = accAll, accHit
            HK.winUntil = os.clock() + CFG.REEL_TIMEOUT + 10
            HK.scriptUntil = HK.winUntil
            playReel(reel, bar, fish, rod)
            if CFG.PERFECT then
                for _ = 1, 6 do
                    if not (alive() and running) then break end
                    task.wait()
                    local g2, b2, f2 = getReel()
                    if not (g2 and b2 and f2) then break end
                    playReel(g2, b2, f2, rod)
                end
            end
            local acc = (accAll > a0) and (accHit - h0) / (accAll - a0) or nil
            HK.winUntil = os.clock() + 12
            HK.scriptUntil = HK.winUntil
            pulse = os.clock()
            if acc == nil or acc >= CFG.CATCH_MIN_ACC then
                count, rung = count + 1, 0
                ST.lastFish = os.clock()
                LIFE.catches = LIFE.catches + 1
                HK.n5 = HK.n5 + 1
            else
                ST.away = ST.away + 1
                log(string.format("fish got away (%d%%) - not counted", px(acc * 100)))
            end
            done = true
            local t1 = os.clock()
            while up(reel) and os.clock() - t1 < 8 do task.wait(0.2) end
            break
        else
            if reel and not warned then
                warned = true
                log("reel GUI is up but '" .. CFG.BAR_NAME .. "' / '" .. CFG.FISH_NAME .. "' not found, GUI tree below")
                tree(reel, 0, { 40 })
            end
            local shake = getShake()
            if shake then
                stage = "shake"
                if not shaken then
                    shaken = true
                    if not bitten then
                        bitten = true
                        ST.waitSum, ST.waitN = ST.waitSum + (os.clock() - t0), ST.waitN + 1
                    end
                    t0 = os.clock()
                    pcall(snapOnce, "shake", shake)
                    pause(CFG.SHAKE_FIRST)   -- nobody presses the instant it shows up
                    lapse(1.2)
                end
                shakeOnce(shake)
                if CFG.PERFECT then
                    local tg = os.clock() + human(CFG.SHAKE_GAP)
                    repeat task.wait() until os.clock() >= tg or reelReady()
                else
                    pause(CFG.SHAKE_GAP)
                end
            else
                local away = CFG.RECOVER ~= false and (rod.Parent ~= lp.Character
                    or (useBobber and not lineOut(rod)))
                if away then
                    idleAt = idleAt or os.clock()
                    if os.clock() - idleAt > 10 then
                        log("idle 10s - re-equip and recast")
                        ST.fixes = ST.fixes + 1
                        pcall(function() hum:EquipTool(rod) end)
                        task.wait(0.8)
                        return
                    end
                else
                    idleAt = nil
                end
                task.wait(CFG.PERFECT and 0.01 or 0.1)
            end
        end
    end

    if alive() and running then
        if done then
            fails = 0
        else
            log("nothing after " .. CFG.TIMEOUT .. "s - pulling the line back (ping " .. pingText() .. ")")
            pcall(function()
                hum:UnequipTools()
                task.wait(0.5)
                hum:EquipTool(rod)
                task.wait(0.5)
            end)
            if failed("no bite") then return end
        end
    end

    stage = "cooldown"
    pause(CFG.COOLDOWN)
    if done then   -- a catch just ended, so the line is in: a bobber that stays is a stale one
        local t2 = os.clock()
        while lineOut(rod) and os.clock() - t2 < 5 do task.wait(0.2) end
        if lineOut(rod) then
            -- in the logs a bobber that stayed meant casts did nothing for 20-50s until the rod was re-equipped
            log("bobber stays after a catch - re-equipping the rod")
            pcall(function()
                hum:UnequipTools()
                task.wait(0.5)
                hum:EquipTool(rod)
                task.wait(0.8)
            end)
            if lineOut(rod) then
                useBobber = false
                log("bobber stays after a catch - ignoring the bobber check until a cast proves it again")
            end
        end
    end
end

---------------------------------------------------------------- go

task.spawn(function()
    local last, lastSave = os.clock(), os.clock()
    while alive() do
        paint()
        local now = os.clock()
        if now - PING.at > 2 then
            PING.at = now
            samplePing()
        end
        if running then LIFE.secs = LIFE.secs + (now - last) end
        last = now
        if now - lastSave > 60 then
            lastSave = now
            save()
        end
        task.wait(0.25)
    end
end)

local main
local function startMain()
    main = task.spawn(function()
        while alive() do
            if running then
                local ok, err = pcall(cycle)
                if not ok then
                    log("error: " .. tostring(err))
                    ST.errors, ST.lastErr = ST.errors + 1, tostring(err)
                    task.wait(2)
                end
            else
                task.wait(0.3)
            end
        end
        if afk then afk:Disconnect() end
        if dbg then dbg:Disconnect() end
        if ui and ui.conn then ui.conn:Disconnect() end
        if recorder then recorder:Disconnect() end
    end)
end
startMain()

-- watchdog: no finished reel for CFG.WATCHDOG seconds -> kill the loop, repair, restart it
local nextPing = os.clock() + (tonumber(CFG.NOTIFY_EVERY) or 0) * 60
task.spawn(function()
    while alive() do
        task.wait(2)
        if running and (tonumber(CFG.NOTIFY_EVERY) or 0) > 0 and os.clock() >= nextPing then
            nextPing = os.clock() + CFG.NOTIFY_EVERY * 60
            pcall(function() notify(statusLine(), true) end)
        end
        local idle = (not running) or stage == "walk" or stage == "fix"
        if idle or CFG.WATCHDOG <= 0 then
            pulse = os.clock()
        elseif os.clock() - pulse > CFG.WATCHDOG then
            log("watchdog: nothing finished for " .. CFG.WATCHDOG .. "s")
            notify("watchdog: nothing finished for " .. CFG.WATCHDOG .. "s - repairing", true)
            if main then pcall(task.cancel, main) end
            recover("watchdog")
            pulse = os.clock()
            if alive() then startMain() end
        end
    end
end)

log("v6-11 started - tap the panel button to pause" .. (CFG.POOL and " | Frightful Pool watcher on" or ""))

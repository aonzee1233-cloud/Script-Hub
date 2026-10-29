--[[
Goblin Auto v11 | Fisch - FischFright 3 | Delta
Run it once while the event is on. Re-running replaces the previous instance.

Flow per goblin (nearest first):
TP -> Talk -> pick difficulty -> read objective -> do it -> TP back -> Talk -> claim

Auto objectives : type in chat, dance, jump, walk
Skipped + logged: catch / perfect catch / drown / burn / freeze / trick-or-treat / guess / insult

v11 = v10 logic untouched, new UI only (nothing overlaps the game view anymore).

What changed vs v9 (self-heal)
 * No more standing still after a quest ends or is skipped: the old code waited up to 120s
   before looking for the next goblin. Now every goblin outcome (done / skipped / failed /
   error) triggers a sweep within CFG.sweepGap seconds, and idle sweeps run every CFG.sweepEvery.
 * A goblin that keeps failing is put on a cooldown (40s, 80s, 160s ... max 300s) and the bot
   goes to other goblins instead of retrying the same one forever.
 * Supervisor thread: restarts a dead / hung loop, unfreezes anchored / sitting / ragdolled
   characters, closes a dialog left open, forces a sweep when nothing happened for
   CFG.idleLimit seconds, teleports to Moosewood if stuck or out of the world, and as a last
   resort respawns the character (CFG.hardResetAfter).
 * Dying during any objective (not only walking) is detected and the try is refunded.
 * New button: Fix now (runs the same repair by hand).

UI v11: one draggable window (header also shows a countdown to the next goblin round). Header = Auto ON/OFF + fold. Tabs: Main (levels, options) | Warp (islands) |
Goblins (grouped by island + last spawn alert, tap to warp) | Tools (Fix now, Copy report, Clear, Dump UI, Dump islands).
If something still fails: open the dialog by hand, press Dump UI, then Copy report.

v13/v14 (patch on v12)
 * Trick-or-Treat: after the Treat/Trick choice the bot now waits at the house until the NPC has closed the
   door (door parts back at their start pose + no NPC showing) before walking to the next house.
   A house that gives no Visit event is retried once after 2.5s instead of being skipped for good.
 * Hand-in after a far objective (Insult Beatrix): when the goblin streamed out while we were away, the bot flies
   back to where it stood, finds the new model (same UID) and turns the quest in BEFORE it follows a new spawn
   alert. Unfinished hand-ins are retried 3x within 14 min. Log lines: "RETURN to turn in ..." then "DONE ...".
 * Trick-or-Treat choice buttons (Main tab): Treat / Trick / Random. The Trick remote name is a guess
   (RF/TrickOrTreat/Trick, or any TrickOrTreat remote with "trick" in its name); the "TRICK REMOTES:" log line
   lists what exists. If none is found the bot falls back to Treat and says so in the log.
 * Warp tab: "Halloween (sail)" button = go to the Dutchman and sail to Caustic Hallow.
 * Insult Beatrix: talking to her now accepts a dialog that starts with US as the speaker (not only one on the
   Witch model), no longer presses Nevermind between tries, and waits out a disabled prompt.
   Failed tries print "WITCH try N: no dialog | prompt.Enabled=.. dist=.. lastDialog=.." for debugging.

v16 (patch on v15)
 * Repeat counts: Insult Beatrix = 1 / 2 / 3 / 10 / 50 and Trick-or-Treat = 1 / 3 / 7 / 15 (easy .. extreme),
   table QCOUNT. Order of trust: HUD "(a/b)" counter > count in the quest text ("twice", "3 times", "(0/2)")
   > QCOUNT by the difficulty that was picked > 1. Log: "INSULT need=.." / "TRICK need=..".
 * Insult Beatrix, 2nd+ insult never happened ("WITCH try 1: no dialog | dist=5"): the first conversation stayed
   open on the server and blocked the prompt. Now the bot walks out of her range (leaveDialog) after every insult
   and also when a try fails right next to her, then comes back. It waits for the HUD to count each insult.
 * Trick-or-Treat: the quest is complete when the HUD says so (a >= b, or the line is gone), not only when an
   Outcome event arrives. A house also counts when the HUD moved but no Outcome event was seen, so the bot no longer
   knocks on extra doors. If a door has no NPC under it the whole house is searched and its children are logged.

v17 (patch on v16)
 * Trick-or-Treat: the bot now presses the real on-screen "Trick" / "Treat" button (what the game's own client
   script answers). Before, it only called the remote, so the choice words stayed on screen and the NPC never
   walked into the house. The remote is kept as a fallback when no button shows up within 6s; in that case the
   new UI text is logged as "TRICK UI ..." lines. "TRICK: ... pressed on-screen ..." = the button was found.
   "the Trick/Treat words are still on screen after this house" = it still did not close, send the report.

v18 (patch on v17)
 * Trick-or-Treat choice is a numbered list of plain labels (1. ["Treat!"]  2. ["Trick!"]), not buttons, so v17 never
   found a button. Now the bot finds those labels and presses the NUMBER KEY (Treat = 1, Trick = 2, or the number
   written in the label / its position in the list), then tries a button press and a mouse click as backups.
   Log: 'TREAT: pressed on-screen "1. ["treat!"]" via key 1'.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local TCS = game:GetService("TextChatService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local genv = (getgenv and getgenv()) or _G
if genv.GoblinAutoStop then pcall(genv.GoblinAutoStop) end

local okVim, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
if not okVim then VIM = nil end

local CFG = {
	difficulty = "Easy",     -- Easy | Normal | Hard | Extreme | Ultimate
	scanDelay = 0.25,        -- seconds between goblin scans
	dialogWait = 1.1,        -- seconds between dialog clicks
	tpOffset = CFrame.new(0, 3, 6),
	fastJump = false,        -- true = fire the Jump quest remote directly (faster, riskier)
	clickMode = "conn",      -- "conn" = fire button connections | "vim" = real click
	useDisplayName = false,  -- fills <player> if it ever shows up literally in a sentence
	resumeActive = true,     -- if a goblin quest is already active, do it instead of failing
	warpOnSpawn = true,      -- ดักแจ้งเตือน "goblins have spawned at X!" แล้ววาร์ปไปเกาะนั้น (ต้อง Auto ON)
	arriveWait = 3,          -- รอกี่วิหลังถึงเกาะ ให้ goblin stream เข้ามา
	acceptFirst = false,     -- true = รับเควสให้ครบก่อน แล้วค่อยทำเรียงจากรับมานานสุด | false = ทำทีละตัวแบบเดิม
	acceptBatch = 3,         -- รับค้างไว้ได้สูงสุดกี่เควสก่อนเริ่มทำ
	acceptFailMax = 4,       -- รับเควสไม่สำเร็จครบกี่ครั้ง -> พัก goblin ตัวนั้น ไปรับตัวอื่นก่อน
	acceptCool = 60,         -- พักกี่วินาที (x2 ทุกรอบ สูงสุด 300)
	deathCoolAfter = 3,      -- ตายซ้ำที่ goblin ตัวเดียวกันกี่ครั้ง -> พักตัวนั้นเหมือนกัน
	esp = true,              -- ไฮไลต์ goblin + บอกระยะ (false = ซ่อน)
	spawnEvery = 300,        -- goblin รอบใหม่เกิดทุกกี่วินาที (ใช้นับถอยหลังที่หัวหน้าต่าง; เกมบอกทุก 5 นาที)
	retryAfter = 300,        -- a finished goblin that stays in place is retried after this long
	talk = true,             -- false = ไม่คุยกับ goblin เลย
	levels = { easy = true, normal = false, hard = false, extreme = false, ultimate = false },
	fishSpots = {
		perfect = { pos = Vector3.new(357.5, 133.7, 235.6), look = Vector3.new(-0.79, -0.61, -0.01) },
		fcatch  = { pos = Vector3.new(-14509.1, 143.6, -9556.2), look = Vector3.new(0.08, -0.70, 0.71) },
	},
	fishMax = 720,   -- ตกนานสุดกี่วินาทีต่อเควส (เผื่อเวลากลับไปส่ง)
	fishStall = 300, -- ตัวนับ HUD ไม่ขยับกี่วินาที -> เลิก
	fishLast = true,      -- เควสตกปลาไว้ท้ายสุด
	fishLaterMax = 240,   -- เลื่อนได้นานสุดกี่วิหลังรับ แล้วบังคับทำ
	fallbackDown = true,     -- goblin ไม่มีระดับที่เลือก -> ลงไปใช้ระดับต่ำกว่าที่มี
	quests = { chat = true, dance = true, jump = true, walk = true, guess = true, insult = false, trick = false, perfect = false, fcatch = false },
	trickChoice = "treat",   -- trick-or-treat: "treat" | "trick" | "random" (buttons at Main > TRICK-OR-TREAT CHOICE)
	trickUseUI = true,
	scanOnJoin = true,       -- เข้าเซิฟใหม่: ไล่ขอ stream ทีละเกาะเพื่อหา goblin โดยไม่ต้องรอแจ้งเตือน (เปิด/ปิดได้ที่แท็บ Main > Scan islands)
	watchdog = true,
	failCool = 40,           -- goblin ที่ทำไม่สำเร็จครบ 4 ครั้ง พักกี่วินาที (x2 ทุกรอบ สูงสุด 300) แล้วไปหาตัวอื่นก่อน
	returnOnDeath = true,  -- ตายแล้วเกิดไกล: วาปกลับไปหา goblin ที่ยังค้างอยู่
	returnWindow = 600,    -- จำตำแหน่ง goblin ไว้กี่วินาทีนับจากเห็นครั้งสุดท้าย
	hardResetAfter = 4,      -- ซ่อมแบบเบากี่รอบติดแล้วยังไม่หาย -> รีเซ็ตตัวละคร (0 = ปิด)
	hallowDeck = Vector3.new(381, 142, 384), -- ดาดฟ้าเรือ Reaping Dutchman ที่ Moosewood: ยืนตรงนี้คุยกับกัปตันแล้วเลือก Set sail! ไป Caustic Hallow (ที่อยู่ของ Beatrix)
	islandPos = {
		["Moosewood"]       = Vector3.new(380, 135, 234),
		["Roslit Bay"]      = Vector3.new(-1473, 133, 708),
		["Forsaken Shores"] = Vector3.new(-2491, 133, 1561),
		["Sunstone Island"] = Vector3.new(-913, 138, -1133),
		["Sunstone"]        = Vector3.new(-913, 138, -1133),
		["Castaway Cliffs"] = Vector3.new(657, 134, -1623),
		["Statue of Sovereignty"] = Vector3.new(35, 135, -1010),
		["Harvesters Spike"] = Vector3.new(-1260, 135, 1550),
		["The Arch"]        = Vector3.new(1100, 130, -1250),
		["Birch Cay"]       = Vector3.new(1650, 130, -2350),
		["Haddock Rock"]    = Vector3.new(-500, 125, -505),
		["Earmark Island"]  = Vector3.new(1200, 130, 530),
		["Terrapin Island"] = Vector3.new(-193, 135, 1951),
		["Mushgrove Swamp"] = Vector3.new(2434, 132, -692),
		["Ancient Isle"]    = Vector3.new(6056, 195, 307),
		["Lost Jungle"]     = Vector3.new(-2589, 158, -2194),
		["Scoria Reach"]    = Vector3.new(-4976, 145, -1577),
		["Snowcap Island"]  = Vector3.new(2607, 135, 2436),
	},
}

local running, enabled = true, true
local lines, seen, conns = {}, {}, {}

---------------------------------------------------------------- state
local state = setmetatable({}, { __mode = "k" })      -- goblin model -> status table
local mem, needReturn = {}, false -- mem: uid -> { pos, at, name }
local stats = { done = {}, skip = {}, fail = {}, died = 0 }
local function bump(t, k) k = tostring(k or "?"); t[k] = (t[k] or 0) + 1 end
local function sumOf(t)
	local n = 0
	for _, v in pairs(t) do n = n + v end
	return n
end
local function dumpOf(t)
	local p = {}
	for k, v in pairs(t) do p[#p + 1] = k .. "=" .. v end
	table.sort(p)
	return #p > 0 and table.concat(p, ",") or "-"
end
local function statsLine()
	return ("done %d [%s] | skip %d [%s] | fail %d [%s] | died %d"):format(
		sumOf(stats.done), dumpOf(stats.done), sumOf(stats.skip), dumpOf(stats.skip),
		sumOf(stats.fail), dumpOf(stats.fail), stats.died)
end
local dialogAt = setmetatable({}, { __mode = "k" })   -- npc -> time of last dialogstart
local dialogCfg = setmetatable({}, { __mode = "k" })
local lastClick = setmetatable({}, { __mode = "k" })  -- button -> { t = text, at = time }
local pendingWarp = nil -- { name, cf, at } ใส่โดยตัวดักแจ้งเตือน spawn / tickOnce เป็นคนเอาไปใช้
local spawnInfo = nil   -- { name, at, pos } last "goblins have spawned at X!" alert (shown in the Goblins tab)
local dialogRoot = nil
local statusLbl = nil
local working = false         -- true while a goblin / sweep is being processed
local lastWork = os.clock()   -- last time the loop did something real
local recoverNow = nil        -- set by the supervisor (used by the Fix now button)

-- watchdog: ทุก step ใหญ่เรียก touch() ถ้าเงียบเกิน limit วินาที = ค้าง
local wd = { beat = os.clock(), limit = 60, owed = {} } -- owed: uid -> { pos, name, at } quests finished but not handed in yet
local lastDied = false -- doWalk2 ตั้งเป็น true ตอนตัวละครตายระหว่างทำเควส
local function touch(limit)
	wd.beat = os.clock()
	wd.limit = limit or 60
end

local function setStatus(s)
	touch(60)
	if statusLbl then statusLbl.Text = s end
end

local function log(s)
	if #lines < 1500 then lines[#lines + 1] = s end
	print("[GA] " .. s)
end

local function fmt(a, d, maxd)
	d = d or 0
	maxd = maxd or 2
	if typeof(a) == "Instance" then return a:GetFullName() end
	if type(a) == "table" then
		if d >= maxd then return "{...}" end
		local p = {}
		for k, v in pairs(a) do p[#p + 1] = tostring(k) .. "=" .. fmt(v, d + 1, maxd) end
		return "{" .. table.concat(p, ", ") .. "}"
	end
	return tostring(a)
end


local HP = {}
local HP_ORDER = { "find", "warp", "talk", "accept", "chat", "dance", "jump",
	"walk", "guess", "insult", "trick", "perfect", "fcatch", "sail", "turnin" }
local HP_NAME = {
	find = "หา goblin", warp = "วาป", talk = "เปิด dialog", accept = "รับเควส",
	chat = "Chat", dance = "Dance", jump = "Jump", walk = "Walk", guess = "Guess",
	insult = "Insult", trick = "Trick-or-Treat", perfect = "Perfect Catch", fcatch = "Catch FischFright",
	sail = "Sail Hallow", turnin = "ส่งเควส",
}

-- sys = ชื่อระบบ | ok = ผ่านไหม | note = หมายเหตุสั้นๆ | secs = ใช้เวลากี่วิ (ไม่ใส่ก็ได้)
local function hp(sys, ok, note, secs)
	local e = HP[sys]
	if not e then
		e = { ok = 0, bad = 0, recent = {}, at = 0, lastOk = nil, tsum = 0, tn = 0 }
		HP[sys] = e
	end
	if ok then e.ok = e.ok + 1; e.lastOk = os.clock() else e.bad = e.bad + 1 end
	e.recent[#e.recent + 1] = ok and 1 or 0
	if #e.recent > 3 then table.remove(e.recent, 1) end
	if secs then e.tsum, e.tn = e.tsum + secs, e.tn + 1 end
	e.note, e.at = note, os.clock()
	if not ok then e.failNote = note end
end

-- "none" = ยังไม่เคยรัน | "good" = 3 รอบหลังผ่านหมด | "warn" = ปนกัน | "bad" = พลาด 2 รอบติด
local function hpState(e)
	if not e or #e.recent == 0 then return "none" end
	local r, n, s = e.recent, #e.recent, 0
	for _, v in ipairs(r) do s = s + v end
	if n >= 2 and r[n] == 0 and r[n - 1] == 0 then return "bad" end
	return s == n and "good" or "warn"
end

local function hpDiag(sys, e) -- ข้อความวินิจฉัยสั้นๆ
	if not e or hpState(e) ~= "bad" then return nil end
	if sys == "dance" then return "เช็คของในมือ / ยืนทับ goblin" end
	if sys == "trick" then return "ดูบรรทัด pressed on-screen / Outcome" end
	if sys == "find" then return "แจ้งเตือนมา แต่ goblin ไม่โหลด" end
	if sys == "warp" then return "หาพื้นไม่เจอ ลองปุ่ม Mark spot" end
	if sys == "turnin" then return "goblin หลุด stream / ส่งไม่ทัน" end
	return "พลาดติดกัน ดู log ล่าสุด"
end

---------------------------------------------------------------- helpers
local function hrpOf()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function clean(s)
	s = tostring(s or "")
	local nm = CFG.useDisplayName and lp.DisplayName or lp.Name
	s = s:gsub("<[Pp]layer>", function() return nm end)
	s = s:gsub("<[^>]+>", "")
	s = s:gsub("\226\128\156", '"'):gsub("\226\128\157", '"'):gsub("\226\128\153", "'")
	return s
end

local function goblins()
	local out = {}
	local w = workspace:FindFirstChild("world")
	local npcs = w and w:FindFirstChild("npcs")
	local folder = npcs and npcs:FindFirstChild("FischfrightGoblins")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local loaded = m:FindFirstChildWhichIsA("BasePart", true) ~= nil
				local p = m:GetPivot().Position
				local ok = loaded or (p.Y > 100 and Vector3.new(p.X, 0, p.Z).Magnitude > 150)
				if not loaded then
					local d = ("FAR %s | %.0f, %.0f, %.0f | %s"):format(m.Name, p.X, p.Y, p.Z, ok and "use" or "ignored")
					if not seen[d] then seen[d] = true; log(d) end
				end
				if ok then out[#out + 1] = m end
			end
		end
	end
	return out
end

local function promptPos(m)
	local pp = m:FindFirstChildWhichIsA("ProximityPrompt", true)
	local par = pp and pp.Parent
	if par and par:IsA("Attachment") then return par.WorldPosition end
	if par and par:IsA("BasePart") then return par.Position end
	return m:GetPivot().Position
end

local function standCF(m)
	local gp = promptPos(m)
	local root = m:FindFirstChild("RootPart") or m.PrimaryPart
	local look = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local side = Vector3.new(-look.Z, 0, look.X)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lp.Character, m }
	rp.IgnoreWater = true
	for _, d in ipairs({ look, side, -side, -look }) do
		local p = gp + d * 5
		local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -25, 0), rp)
		if hit and math.abs(hit.Position.Y - gp.Y) < 8 then
			local pos = hit.Position + Vector3.new(0, 3.2, 0)
			return CFrame.lookAt(pos, Vector3.new(gp.X, pos.Y, gp.Z))
		end
	end
	local pos = gp + look * 5 + Vector3.new(0, 2, 0)
	return CFrame.lookAt(pos, Vector3.new(gp.X, pos.Y, gp.Z))
end

local function tpTo(model)
	local hrp = hrpOf()
	if not hrp or not model.Parent then return false end
	local cf = model:GetPivot()
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		pcall(function() lp:RequestStreamAroundAsync(cf.Position, 2) end)
		hrp.Anchored = true -- ลอยรอให้ goblin โหลด
		hrp.CFrame = cf + Vector3.new(0, 40, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		local t0 = os.clock()
		while model.Parent and os.clock() - t0 < 8
			and not model:FindFirstChildWhichIsA("BasePart", true) do
			task.wait(0.1)
		end
		hrp.Anchored = false
		if not model.Parent or not model:FindFirstChildWhichIsA("BasePart", true) then
			log("NOTE: " .. model.Name .. " did not load at its saved spot")
			return false
		end
		cf = model:GetPivot()
	end
	hrp.CFrame = CFrame.new(model:GetPivot().Position + Vector3.new(0, 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
	task.wait(0.5)
	return model.Parent ~= nil
end

local function tap(key, t)
	if not VIM then return end
	pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
	task.wait(t or 0.15)
	pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
end

local function cancelEmote()
	local e = RS:FindFirstChild("events")
	local r = e and e:FindFirstChild("CancelEmote")
	if r then pcall(function() r:FireServer() end) end
end

local function exitEmote(stay)
	cancelEmote()
	local hrp, hum = hrpOf()
	if not hrp or not hum then return end
	local n = 0
	for _, tr in ipairs(hum:GetPlayingAnimationTracks()) do
		n = n + 1
		pcall(function() tr:Stop(0.1) end)
	end
	-- restart the Animate script: clears an emote that is stuck in a loop
	local an = lp.Character and lp.Character:FindFirstChild("Animate")
	if an then
		pcall(function() an.Disabled = true end)
		pcall(function() an.Enabled = false end)
		task.wait(0.15)
		pcall(function() an.Disabled = false end)
		pcall(function() an.Enabled = true end)
	end
	if not stay then
		hum:MoveTo(hrp.Position + hrp.CFrame.LookVector * 4)
		tap(Enum.KeyCode.W, 0.35) -- a real key press: most games cancel an emote on input
		tap(Enum.KeyCode.Space, 0.1)
		hum.Jump = true
	end
	task.wait(0.5)
	log("EMOTE stop (" .. n .. " tracks)")
end

local ISLANDS = {
	{ "Ancient Isle", "ancient" }, { "Drylands", "dryland", "dry land" },
	{ "Everturn Forest", "everturn" }, { "Forsaken Shores", "forsaken" },
	{ "Lost Jungle", "lost jungle", "lostjungle" }, { "Moosewood", "moosewood" },
	{ "Mushgrove Swamp", "mushgrove" }, { "Roslit Bay", "roslit" },
	{ "Scoria Reach", "scoria" }, { "Skycrest", "skycrest", "sky crest" },
	{ "Snowcap Island", "snowcap" }, { "Sunstone Island", "sunstone" },
	{ "Terrapin Island", "terrapin" },
	{ "Castaway Cliffs", "castaway" }, { "Statue of Sovereignty", "sovereignty" },
	{ "Harvesters Spike", "harvester" }, { "The Arch", "the arch" },
	{ "Birch Cay", "birch" }, { "Haddock Rock", "haddock" }, { "Earmark Island", "earmark" },
}

local function posOf(o)
	if o:IsA("BasePart") then return o.Position end
	if o:IsA("Model") then
		local ok, cf = pcall(function() return o:GetPivot() end)
		if ok then return cf.Position end
	end
	return nil
end

local function islandRoots()
	local out = {}
	local function add(r) if r then out[#out + 1] = r end end
	local w = workspace:FindFirstChild("world")
	local sp = w and w:FindFirstChild("spawns")
	local z = workspace:FindFirstChild("zones")
	add(sp and sp:FindFirstChild("TpSpots"))
	add(w and w:FindFirstChild("map"))
	add(z and z:FindFirstChild("fishing"))
	return out
end

local islandCache, islandMiss = {}, {}
-- พิกัดสำรอง "ค่าประมาณจากความจำ ไม่ได้เช็คกับเกมนี้" ใช้เมื่อหาด้วยชื่อไม่เจอ; ถ้าตกน้ำให้ใช้ปุ่ม Mark spot
local islandGuess = { ["Snowcap Island"] = Vector3.new(2607, 135, 2436) }

-- ค้นทุกอย่างใต้ workspace.world / workspace.zones หา Model/Part ที่ชื่อมีคีย์เวิร์ดเกาะ (เช่น "Snowcap Shipwright")
local function deepFind(isl)
	local best, bd
	for _, rn in ipairs({ "world", "zones" }) do
		local r = workspace:FindFirstChild(rn)
		if r then
			for _, o in ipairs(r:GetDescendants()) do
				if (o:IsA("Model") or o:IsA("BasePart")) and #o.Name <= 40 then
					local n = o.Name:lower()
					for i = 2, #isl do
						if n:find(isl[i], 1, true) then
							local p = posOf(o)
							local d = #o:GetFullName()
							if p and (not bd or d < bd) then best, bd = p, d end
						end
					end
				end
			end
		end
	end
	return best
end

local function findIsland(isl)
	local name = isl[1]
	if CFG.islandPos[name] then return CFrame.new(CFG.islandPos[name]) end
	if islandCache[name] then return CFrame.new(islandCache[name]) end
	for _, r in ipairs(islandRoots()) do
		local best, bl
		for _, o in ipairs(r:GetChildren()) do
			local n = o.Name:lower()
			for i = 2, #isl do
				if n:find(isl[i], 1, true) and (not bl or #n < bl) and posOf(o) then
					best, bl = o, #n
				end
			end
		end
		if best then return CFrame.new(posOf(best)) end
	end
	if not islandMiss[name] or os.clock() - islandMiss[name] > 90 then
		local p = deepFind(isl)
		if p then
			islandCache[name] = p
			return CFrame.new(p)
		end
		islandMiss[name] = os.clock()
	end
	if islandGuess[name] then return CFrame.new(islandGuess[name]) end
	return nil
end

local MAXTRY = 4
local function stOf(m)
	local pos = m:GetPivot().Position
	local s = state[m]
	local strikes = 0
	if s then
		local age = os.clock() - s.at
		local moved = (s.pos - pos).Magnitude > 25
		local expired = (s.done and age > CFG.retryAfter)
			or (not s.done and s.tries >= MAXTRY and age > (s.cool or 40))
		if expired and not moved then strikes = s.strikes or 0 end
		if moved or expired then s = nil end -- respawned somewhere else / cooldown over
	end
	if not s then
		s = { pos = pos, tries = 0, done = false, claim = false, at = os.clock(), strikes = strikes }
		state[m] = s
	end
	return s
end

local diffByName = { ["goblin"] = "easy", ["ghoulish goblin"] = "normal" }

local function levelOK(lv) -- ระดับนี้อยู่ในช่วงที่ยอมรับไหม
	local names = { "easy", "normal", "hard", "extreme", "ultimate" }
	local top, mine = 0, 0
	for i, d in ipairs(names) do
		if CFG.levels[d] then top = i end
		if d == lv then mine = i end
	end
	if mine == 0 or top == 0 then return false end
	if CFG.fallbackDown then return mine <= top end
	return CFG.levels[lv] == true
end

local function wantsModel(m)
	if not CFG.talk then return false end
	local lv = diffByName[m.Name:lower()]
	return lv == nil or levelOK(lv)
end

local function fresh()
	local out = {}
	for _, m in ipairs(goblins()) do
		local ok, s = pcall(stOf, m)
		if ok and not s.done and s.tries < MAXTRY and wantsModel(m)
			and (s.coolUntil or 0) <= os.clock() then out[#out + 1] = m end
	end
	return out
end

-- goblin ยังอยู่แต่ลองครบแล้ว: อย่าวิ่งหนีไป sweep เกาะอื่น
local function pending()
	for _, m in ipairs(goblins()) do
		local ok, s = pcall(stOf, m)
		if ok and not s.done and wantsModel(m) then return true end
	end
	return false
end

---------------------------------------------------------------- events + remote logging
local function onEvent(name, t)
	if name == "dialogstart" then
		local d = t[1]
		if type(d) == "table" and typeof(d.npc) == "Instance" then
			dialogAt[d.npc] = os.clock()
			dialogCfg[d.npc] = t[3]
			wd.dlgName, wd.dlgAt, wd.dlgCfg = d.npc.Name, os.clock(), t[3] -- last dialogstart of ANY npc (Beatrix can start it with us as the speaker)
		end
	elseif name:find("Goblins/", 1, true) then
		if name:find("Hide", 1, true) then
			for i = 1, t.n do
				local v = t[i]
				if type(v) == "string" then
					mem[v] = nil -- ส่งเควสแล้ว ไม่ต้องกลับไปอีก
					wd.owed[v] = nil
					for _, m in ipairs(goblins()) do
						if m:GetAttribute("UID") == v then
							state[m] = { pos = m:GetPivot().Position, tries = 0, done = true,
								claim = true, at = os.clock() }
						end
					end
				end
			end
		end
	end
end

local skipKeys = { "ClientKit", "Settings/Edit", "ResourceStream", "SetHotbar", "Analytics", "SetZone" }
local function noisy(path)
	for _, k in ipairs(skipKeys) do
		if path:find(k, 1, true) then return true end
	end
	return false
end

genv.GA_CALL = function(line)
	if not seen[line] then
		seen[line] = true
		log(line)
	end
end

if false and hookmetamethod and getnamecallmethod then
	if not genv.GA_HOOKED then
		genv.GA_HOOKED = true
		local nc = newcclosure or function(f) return f end
		local old
		old = hookmetamethod(game, "__namecall", nc(function(self, ...)
			local m = getnamecallmethod()
			if m == "FireServer" or m == "InvokeServer" then
				local t = table.pack(...)
				local remote = self
				task.defer(function()
					local path = fmt(remote)
					if noisy(path) then return end
					local parts = {}
					for i = 1, t.n do parts[i] = fmt(t[i]) end
					local f = genv.GA_CALL
					if f then f("CALL " .. path .. ":" .. m .. "(" .. table.concat(parts, ", ") .. ")") end
				end)
			end
			return old(self, ...)
		end))
	end
else
	log("NOTE: executor has no hookmetamethod (remote calls will not be logged)")
end

-- one short line per dialogstart instead of the whole dialog tree (keeps the report small)
local function briefDialog(t)
	local d, c = t[1], t[3]
	local npc = type(d) == "table" and typeof(d.npc) == "Instance" and d.npc.Name or "?"
	c = type(c) == "table" and c or {}
	local n1 = type(c.dialog) == "table" and c.dialog[1]
	return ("DIALOG %s | cs_start=%s | init=%s | node1=%s"):format(
		npc, tostring(c.cs_start), fmt(c.initial_data, 0, 2),
		type(n1) == "table" and clean(tostring(n1.text)) or "?")
end

local function listen(r)
	if r and r:IsA("BaseRemoteEvent") then
		conns[#conns + 1] = r.OnClientEvent:Connect(function(...)
			local t = table.pack(...)
			local parts = {}
			for i = 1, t.n do parts[i] = fmt(t[i], 0, 2) end
			local s = "EVENT " .. r.Name .. "(" .. table.concat(parts, ", ") .. ")"
			if r.Name == "dialogstart" then s = briefDialog(t) end
			if #s > 1500 then s = s:sub(1, 1500) .. "...<cut>" end
			if not seen[s] then
				seen[s] = true
				log(s)
			end
			local ok, err = pcall(onEvent, r.Name, t)
			if not ok then log("ERR onEvent " .. tostring(err)) end
		end)
	end
end

local ev = RS:FindFirstChild("events")
local dsEvent = ev and ev:FindFirstChild("dialogstart")
if dsEvent then listen(dsEvent) end
local pk = RS:FindFirstChild("packages")
local net = pk and pk:FindFirstChild("Net")
local DI = net and net:FindFirstChild("RF/DialogInteract")
if net then
	for _, r in ipairs(net:GetChildren()) do
		local n = r.Name
		if n:find("Goblins/", 1, true) or n:find("TrickOrTreat/", 1, true) or n:find("QuestTrigger", 1, true) or n:find("Dialog", 1, true) then
			listen(r)
		end
	end
end

conns[#conns + 1] = PPS.PromptTriggered:Connect(function(p)
	log("PROMPT " .. p:GetFullName() .. " | " .. p.ActionText .. " / " .. p.ObjectText)
end)

---------------------------------------------------------------- GUI reading / clicking
local function visibleChain(g)
	local pg = lp.PlayerGui
	local o = g
	while o and o ~= pg do
		if o:IsA("GuiObject") and not o.Visible then return false end
		if o:IsA("ScreenGui") and not o.Enabled then return false end
		o = o.Parent
	end
	return o == pg
end

local function alive(o)
	return o ~= nil and o.Parent ~= nil and visibleChain(o)
end

local function isText(g) return g:IsA("TextButton") or g:IsA("TextLabel") end

local function hasAny(txt, list)
	for _, w in ipairs(list) do
		if txt:find(w, 1, true) then return true end
	end
	return false
end

-- HUD stuff that must never be clicked: timers, counters, icon names
local function noise(t)
	if t:find("^time left") then return true end
	if t:find("^[%d%.,%s]+[kmb]?$") then return true end
	if t:find("^[%l%d]+%-[%l%d%-]+$") then return true end
	return false
end

-- remember which text objects are visible right now; only objects that are NOT in this
-- set count as "new" later (keyed by instance, so a ticking timer text is never new)
local base = setmetatable({}, { __mode = "k" })
local function snapshot()
	base = setmetatable({}, { __mode = "k" })
	for _, g in ipairs(lp.PlayerGui:GetDescendants()) do
		if isText(g) and visibleChain(g) then base[g] = true end
	end
end

local function texts(onlyNew)
	local out = {}
	for _, g in ipairs(lp.PlayerGui:GetDescendants()) do
		if isText(g) and #g.Text > 1 and visibleChain(g) then
			if not onlyNew or not base[g] then out[#out + 1] = g end
		end
	end
	return out
end

local function clickTarget(g)
	if g:IsA("GuiButton") then return g end
	return g:FindFirstAncestorWhichIsA("GuiButton")
end

local function fireConns(sig)
	if not getconnections then return 0 end
	local n = 0
	local ok, list = pcall(getconnections, sig)
	if ok and type(list) == "table" then
		for _, c in ipairs(list) do
			if pcall(function() c:Fire() end) then n = n + 1 end
		end
	end
	return n
end

local function realClick(g)
	if not VIM then return false end
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	local sg = g:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = (sg and sg.IgnoreGuiInset) and Vector2.zero or GuiService:GetGuiInset()
	local x, y = p.X + s.X / 2 + inset.X, p.Y + s.Y / 2 + inset.Y
	VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
	task.wait(0.06)
	VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	return true
end

local function press(btn)
	if CFG.clickMode == "conn" then
		if fireConns(btn.Activated) > 0 then return "Activated" end
		if fireConns(btn.MouseButton1Click) > 0 then return "MouseButton1Click" end
	end
	if realClick(btn) then return "vim" end
	return "none"
end

local function emoteBtn()
	for _, g in ipairs(texts(false)) do
		if clean(g.Text):lower():find("cancel emote", 1, true) then
			return clickTarget(g) or g
		end
	end
	return nil
end

local function stopEmote()
	for i = 1, 6 do
		local b = emoteBtn()
		if not b then
			if i > 1 then log("EMOTE stopped") end
			return true
		end
		if i % 2 == 1 then
			local ok, how = pcall(press, b)
			log("EMOTE cancel click via " .. tostring(ok and how or "error"))
		else
			pcall(realClick, b) -- รอบคู่ กดจริงบนจอ
		end
		cancelEmote()
		task.wait(0.4)
	end
	log("NOTE: emote cancel button still showing after 6 tries")
	return false
end

local function closeDialog()
	for _, g in ipairs(texts(false)) do
		if clean(g.Text):lower():find("nevermind", 1, true) then
			local b = clickTarget(g)
			if b then
				press(b)
				return
			end
		end
	end
end

-- a dialog window that stays open blocks the prompt. Close it ("Nevermind..."), then walk
-- out of its range (maxdistance = 12) so it closes by itself
local function leaveDialog(m)
	closeDialog()
	task.wait(0.3)
	local hrp = hrpOf()
	if not hrp then return end
	local origin = (m and m.Parent) and m:GetPivot().Position or hrp.Position
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lp.Character }
	rp.IgnoreWater = true
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local p = origin + Vector3.new(math.cos(a), 0, math.sin(a)) * 28
		local hit = workspace:Raycast(p + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp)
		if hit and math.abs(hit.Position.Y - origin.Y) < 10 then
			hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			task.wait(1.2)
			return
		end
	end
	-- no ground found around it: hang in the air for a moment instead
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(origin + Vector3.new(0, 45, 0))
	task.wait(1.2)
	hrp.Anchored = false
end

-- ปิด dialog แบบไม่วาปหนี: กด Nevermind แล้วรอ ถ้ายังไม่ปิดจริงๆ ค่อยถอยออกไป
local function softLeave(m)
	closeDialog()
	task.wait(0.5)
	for _, g in ipairs(texts(false)) do
		if clean(g.Text):lower():find("nevermind", 1, true) then
			leaveDialog(m)
			return
		end
	end
end

---------------------------------------------------------------- dialog
local DIFF = { "easy", "normal", "hard", "extreme", "ultimate" }
local function levelOrder()
	local top = 0
	for i, d in ipairs(DIFF) do
		if CFG.levels[d] then top = i end
	end
	local o = {}
	for i = top, 1, -1 do -- ยากสุดที่ติ๊ก -> ลงมาเรื่อยๆ
		if CFG.fallbackDown or CFG.levels[DIFF[i]] then o[#o + 1] = DIFF[i] end
	end
	return o
end

local EXCLUDE = { "never", "leave", "bye", "cancel", "close", "decline", "nope", "not now", "no thanks", "[no]", "navigate" }
local QUESTY = { "goblin quest", "friend quest", "quest:", "track" }
local PREFER = { "accept", "okay", "ok", "sure", "deal", "yes", "fine", "continue", "next",
	"claim", "complete", "done", "turn in", "reward", "thank", "alright", "bring it" }

local BADUI = { "statuses", "popupNotif", "topbar", "changelogs", "PlayerList", "backpack", "TopbarStandard" }
local function badUI(o)
	local p = o:GetFullName()
	for _, k in ipairs(BADUI) do
		if p:find(k, 1, true) then return true end
	end
	return false
end

-- find the container (direct child of a ScreenGui) that holds the most NEW text:
-- that is the dialog window
local function pickRoot()
	local score, best, bestRoot = {}, 0, nil
	for _, g in ipairs(texts(true)) do
		local t = clean(g.Text):lower()
		if not noise(t) and not badUI(g) then
			local sg = g:FindFirstAncestorWhichIsA("ScreenGui")
			if sg then
				local top = g
				while top.Parent and top.Parent ~= sg do top = top.Parent end
				score[top] = (score[top] or 0) + 1
				if score[top] > best then
					best = score[top]
					bestRoot = top
				end
			end
		end
	end
	return bestRoot
end

local function inRoot(o)
	return dialogRoot ~= nil and (o == dialogRoot or o:IsDescendantOf(dialogRoot))
end

-- clickable options inside the dialog window only
local function dialogButtons()
	if not alive(dialogRoot) then dialogRoot = pickRoot() end
	local out = {}
	if not dialogRoot then return out end
	for _, g in ipairs(texts(true)) do
		local b = clickTarget(g)
		if b and inRoot(b) and not badUI(b) then
			local t = clean(g.Text):lower()
			local lc = lastClick[b]
			local recent = lc and lc.t == t and os.clock() - lc.at < 1.8
			if not recent and not noise(t) and not hasAny(t, EXCLUDE)
				and not hasAny(t, DIFF) and not hasAny(t, QUESTY) then
				out[#out + 1] = { b = b, t = t }
			end
		end
	end
	return out
end

local function stepDialog()
	local cands = dialogButtons()
	if #cands == 0 then return false end
	local pick = cands[1]
	for _, c in ipairs(cands) do
		if hasAny(c.t, PREFER) then
			pick = c
			break
		end
	end
	lastClick[pick.b] = { t = pick.t, at = os.clock() }
	log(('CLICK "%s" via %s'):format(pick.t:sub(1, 60), press(pick.b)))
	return true
end

-- the 5 difficulty options ("Can I just get an Easy one?" ...), never the quest HUD
local function diffButtons()
	local out = {}
	for _, g in ipairs(texts(true)) do
		local b = clickTarget(g)
		if b then
			local t = clean(g.Text):lower()
			if #t <= 60 and not noise(t) and not hasAny(t, QUESTY) and hasAny(t, DIFF) then
				out[#out + 1] = { b = b, t = t }
			end
		end
	end
	return out
end

local function pickDifficulty()
	local order = levelOrder()
	local t0, settled = os.clock(), false
	while os.clock() - t0 < 12 do
		if not alive(dialogRoot) then dialogRoot = pickRoot() end
		local cands = diffButtons()
		if #cands > 0 then
			if not settled then
				settled = true -- let the rest of the options finish appearing
				task.wait(0.7)
			else
				for _, w in ipairs(order) do
					for _, c in ipairs(cands) do
						if c.t:find(w, 1, true) then return c.b, c.t end
					end
				end
				task.wait(0.3)
			end
		else
			-- intro lines first: click "continue"-like buttons inside the dialog
			stepDialog()
			task.wait(CFG.dialogWait)
		end
	end
	return nil
end

local function firePrompt(pp, useFire)
	if fireproximityprompt and useFire then
		pcall(fireproximityprompt, pp)
	else
		pcall(function()
			pp:InputHoldBegin()
			task.wait(0.2)
			pp:InputHoldEnd()
		end)
	end
end

local function openDialog(model)
	local pp
	local t0 = os.clock()
	while model.Parent do
		pp = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp or os.clock() - t0 > 6 then break end
		task.wait(0.4)
	end
	if not pp then
		log("NOTE: no prompt on " .. model.Name)
		return false
	end
	pcall(function()
		pp.HoldDuration = 0
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 40
	end)
	dialogRoot = nil
	snapshot()
	for attempt = 1, 5 do
		touch(60)
		if not model.Parent then return false end
		-- prompt ถูกปิดอยู่ (goblin กำลังคุย / คูลดาวน์): รอให้เปิดก่อน ไม่ต้องยิงรัวแล้ววาปหนี
		local w1 = os.clock()
		while model.Parent and not pp.Enabled and os.clock() - w1 < 6 do
			task.wait(0.3)
		end
		local hrp = hrpOf()
		if hrp and (hrp.Position - promptPos(model)).Magnitude > 10 then
			tpTo(model)
		end
		local pin = hrpOf()
		if pin then pin.Anchored = true end -- ยืนนิ่งระหว่างคุย กันฟิสิกส์ดันออก
		dialogAt[model] = nil
		cancelEmote()
		if attempt >= 2 then stopEmote(); exitEmote(true) end
		task.wait(0.1)
		firePrompt(pp, attempt % 2 == 1)
		local w0, again = os.clock(), false
		while os.clock() - w0 < 4.5 do -- dialogstart มาช้าแล้วโดนวาปหนีกลางทาง
			if dialogAt[model] then break end
			if not dsEvent and pickRoot() then break end
			if not again and os.clock() - w0 > 2.2 then
				again = true
				firePrompt(pp, attempt % 2 == 0)
			end
			task.wait(0.1)
		end
		if dialogAt[model] or (not dsEvent and pickRoot()) then
			log("TALK " .. model.Name)
			hp("talk", true, model.Name)
			return true
		end
		log("NOTE: no dialog yet on " .. model.Name .. " (try " .. attempt .. ")")
		closeDialog()
		task.wait(0.6)
		if attempt == 3 then leaveDialog(model) end -- วาปถอยแค่ครั้งเดียว หลังลองครบ 3 รอบ
	end
	hp("talk", false, "no dialog on " .. model.Name)
	return false
end

---------------------------------------------------------------- objective parsing
local function numAfter(l, kw)
	local rest = l:match(kw .. "(.*)")
	if not rest then return nil end
	local n = rest:match("(%d[%d,]*)")
	return n and tonumber((n:gsub(",", ""))) or nil
end

-- "(12/50)" style progress -> how many are still left
local function remaining(l, total)
	local a, b = l:match("(%d[%d,]*)%s*/%s*(%d[%d,]*)")
	a = a and tonumber((a:gsub(",", "")))
	b = b and tonumber((b:gsub(",", "")))
	if a and b and b >= a then return b - a end
	return total
end

-- how many times each repeatable quest has to be done per difficulty (easy / normal / hard / extreme / ultimate).
-- Only a fallback: the "(a/b)" counter on the HUD always wins when it can be read.
local QCOUNT = {
	insult = { easy = 1, normal = 2, hard = 3, extreme = 10, ultimate = 50 },
	trick  = { easy = 1, normal = 3, hard = 7, extreme = 15, ultimate = 15 },
	dance  = { easy = 15, normal = 60, hard = 120, extreme = 180, ultimate = 300 },
}
local function fallbackCount(kind, level)
	local t = QCOUNT[kind]
	return t and level and t[level] or nil
end

-- "once" / "twice" / "thrice" / "5 times" -> number (nil when the text has none)
local function countWord(l)
	if l:find("%f[%a]once%f[%A]") then return 1 end
	if l:find("%f[%a]twice%f[%A]") then return 2 end
	if l:find("%f[%a]thrice%f[%A]") then return 3 end
	local n = l:match("(%d+)%s*times")
	return n and tonumber(n) or nil
end

local function parse(raw)
	local t = clean(raw)
	local l = t:lower()

	local q = t:match('[Tt]ype[^"]-"(.-)"')
	if q and l:find("in chat", 1, true) then
		local n = tonumber(l:match("in chat%s+(%d+)%s+times"))
			or (l:find("in chat twice", 1, true) and 2) or 1
		return { kind = "chat", text = q, count = remaining(l, n) }
	end
	if l:find("%f[%a]danc") or l:find("%f[%a]jig%f[%A]") then
		local n = numAfter(l, "danc") or numAfter(l, "jig")
		return { kind = "dance", secs = n and remaining(l, n) }
	end
	if l:find("jump%D*%d") then
		local n = numAfter(l, "jump")
		return { kind = "jump", n = n and remaining(l, n) }
	end
	if l:find("walk%D*%d") then
		local n = numAfter(l, "walk")
		return { kind = "walk", n = n and remaining(l, n) }
	end

	if l:find("catch", 1, true) and not l:find("in a row", 1, true) then
		if l:find("perfect", 1, true) and not l:find("pool", 1, true) then
			return { kind = "perfect", n = remaining(l, numAfter(l, "catch")) }
		elseif l:find("fischfright", 1, true) then
			return { kind = "fcatch", n = remaining(l, numAfter(l, "catch")) }
		end
	end

	if l:find("insult", 1, true) and l:find("beatrix", 1, true) then
		-- n = nil when the text has no count at all: the quest functions then use the HUD / difficulty table
		return { kind = "insult", n = remaining(l, countWord(l)) }
	end

	if l:find("trick", 1, true) and l:find("treat", 1, true) then
		return { kind = "trick", n = remaining(l, countWord(l)) }
	end

	for _, k in ipairs({ "catch", "perfect", "beatrix", "insult", "trick", "guess", "drown", "burn", "freeze" }) do
		if l:find(k, 1, true) then return { kind = "skip", why = k } end
	end
	return nil
end

-- prefers something we can actually do over something we have to skip
local function readObjective()
	local skip
	for _, g in ipairs(texts(true)) do
		local o = parse(g.Text)
		if o then
			if o.kind ~= "skip" then return o, clean(g.Text) end
			skip = skip or { o = o, raw = clean(g.Text) }
		end
	end
	if skip then return skip.o, skip.raw end
	return nil
end

local function hasGoblinQuest()
	for _, g in ipairs(texts(false)) do
		if clean(g.Text):lower():find("goblin quest", 1, true) then return true end
	end
	return false
end

local function activeObjective(hudOnly)
	for pass = 1, 2 do
		if pass == 1 or not hudOnly then
			for _, g in ipairs(texts(false)) do
				if pass == 2 or g:GetFullName():find("deviceinset", 1, true) then
					local o = parse(g.Text)
					if o and o.kind ~= "skip" then return o, clean(g.Text) end
				end
			end
		end
	end
	return nil
end

local function advance(rounds, wantObj)
	local obj, raw
	for _ = 1, rounds do
		task.wait(CFG.dialogWait)
		if wantObj and not obj then obj, raw = readObjective() end
		if not stepDialog() then break end
	end
	if wantObj then
		local t0 = os.clock()
		while not obj and os.clock() - t0 < 6 do
			obj, raw = readObjective()
			if not obj then task.wait(0.5) end
		end
	end
	return obj, raw
end

---------------------------------------------------------------- objective actions
local function sendChat(msg)
	local ok = false
	if TCS.ChatVersion == Enum.ChatVersion.TextChatService then
		local chans = TCS:FindFirstChild("TextChannels")
		local ch = chans and (chans:FindFirstChild("RBXGeneral") or chans:FindFirstChildWhichIsA("TextChannel"))
		if ch then ok = pcall(function() ch:SendAsync(msg) end) end
	end
	if not ok then
		local dce = RS:FindFirstChild("DefaultChatSystemChatEvents")
		local req = dce and dce:FindFirstChild("SayMessageRequest")
		if req then
			req:FireServer(msg, "All")
			ok = true
		end
	end
	return ok
end

wd.chatLines = function()
	local out, seenT, total = {}, {}, 0
	for _, g in ipairs(texts(false)) do
		if g:GetFullName():find("deviceinset", 1, true) then
			local t = clean(g.Text)
			local l = t:lower()
			local q = t:match('[Tt]ype[^"]-"(.-)"')
			local a, b = l:match("(%d[%d,]*)%s*/%s*(%d[%d,]*)")
			if q and a and b and l:find("in chat", 1, true) then
				a, b = tonumber((a:gsub(",", ""))), tonumber((b:gsub(",", "")))
				total = total + 1
				if a < b and not seenT[q] then
					seenT[q] = true
					out[#out + 1] = { text = q, left = b - a }
				end
			end
		end
	end
	return out, total
end

local function doChat(o)
	local function say(txt)
		if not sendChat(txt) then
			log("NOTE: could not send chat")
			return false
		end
		log("CHAT " .. txt)
		task.wait(2)
		return true
	end
	local lines, total = wd.chatLines()
	if total == 0 then -- อ่าน HUD ไม่ได้: ทำตามที่ parse ได้ (เควสบรรทัดเดียว)
		for _ = 1, o.count do
			if not running or not say(o.text) then return false end
		end
		return true
	end
	for _ = 1, 3 do
		if #lines == 0 then return true end
		for _, ln in ipairs(lines) do
			for _ = 1, ln.left do
				touch(30)
				if not running or not say(ln.text) then return false end
			end
		end
		task.wait(2.5) -- ให้ HUD นับก่อนอ่านซ้ำ
		lines = wd.chatLines()
	end
	return #lines == 0
end

local function doDance(o)
	local _, hum = hrpOf()
	if not hum then return false end
	local ok, res = pcall(function() return hum:PlayEmote("dance") end)
	if not (ok and res) then sendChat("/e dance") end
	log("DANCE " .. o.secs .. "s")
	task.wait(o.secs + 2)
	exitEmote()
	return true
end

local hudProgress -- forward declaration: doJump uses it before its definition

local function doJump(o)
	local _, hum = hrpOf()
	if not hum then return false end
	local r = net and net:FindFirstChild("URE/QuestTrigger/Jump")
	local left = o.n or 15
	log("JUMP x" .. left)
	for _ = 1, 4 do -- รอบ 2 ขึ้นไป = เติมส่วนที่ HUD บอกว่ายังขาด
		for _ = 1, left do
			touch(30)
			if not running or hum.Health <= 0 then return false end
			if CFG.fastJump and r then
				r:FireServer()
				task.wait(0.12)
			else
				hum.Jump = true
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
				task.wait(0.55)
			end
		end
		task.wait(0.5)
		local a, b = hudProgress("jump")
		if not a or a >= b then return true end
		left = b - a
		log(("JUMP short %d/%d - %d more"):format(a, b, left))
	end
	return false
end

-- "(a/b)" of the first quest-HUD line that mentions `word` (PlayerGui.hud.deviceinset.quests)
hudProgress = function(word, word2)
	for _, g in ipairs(texts(false)) do
		if g:GetFullName():find("deviceinset", 1, true) then
			local l = clean(g.Text):lower()
			if l:find(word, 1, true) and (not word2 or l:find(word2, 1, true)) then
				local a, b = l:match("(%d[%d,]*)%s*/%s*(%d[%d,]*)")
				if a and b then
					return tonumber((a:gsub(",", ""))), tonumber((b:gsub(",", "")))
				end
			end
		end
	end
	return nil
end

-- direction with the longest stretch of flat ground (no water, wall or cliff) from here
local function openLane(hrp)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lp.Character }
	rp.IgnoreWater = false -- นับน้ำเป็น "ไม่มีพื้น"
	local base = hrp.Position
	local best, bestLen = Vector3.new(0, 0, 1), -1
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = 0
		for step = 1, 8 do
			local p = base + dir * (step * 5)
			local hit = workspace:Raycast(p + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rp)
			if not (hit and hit.Material ~= Enum.Material.Water
				and math.abs(hit.Position.Y - (base.Y - 3)) < 6) then break end
			len = step * 5
		end
		if len > bestLen then best, bestLen = dir, len end
	end
	return best, bestLen
end

-- walks back and forth until the HUD says (b/b). Studs and the quest's own unit may differ,
-- so the HUD is the judge; the stud goal is only the fallback when the HUD line is unreadable
local function doWalk(o)
	local hrp, hum = hrpOf()
	if not hrp or not hum then return false end
	local goal = (o.n or 50) * 1.1 + 5
	local dir, len = openLane(hrp)
	len = math.clamp(len, 12, 35)
	local a = hrp.Position
	local b = a + dir * len
	log(("WALK n=%s lane=%d studs"):format(tostring(o.n), len))
	local walked, last = 0, hrp.Position
	local hbc = RunService.Heartbeat:Connect(function()
		local h = hrpOf()
		if not h then return end
		local d = (h.Position - last).Magnitude
		if d < 8 then walked = walked + d end -- ignore teleports
		last = h.Position
	end)

	local toB, done, sawHud, missing = true, false, false, 0
	local t0, lastLog = os.clock(), 0
	local lastHud, lastMove = nil, os.clock()
	while running and not done and os.clock() - t0 < 300 do
		local target = toB and b or a
		hum:MoveTo(target)
		local s0 = os.clock()
		repeat
			task.wait(0.1)
			local h = hrpOf()
			if not h then break end
		until (h.Position - target).Magnitude < 4 or os.clock() - s0 > 3.5
		toB = not toB

		local pa, pb = hudProgress("walk")
		if pa then
			sawHud, missing = true, 0
			if pa ~= lastHud then lastHud, lastMove = pa, os.clock() end
			if pa >= pb then done = true end
			if os.clock() - lastLog > 5 then
				lastLog = os.clock()
				log(("WALK hud %d/%d | moved %.0f studs"):format(pa, pb, walked))
			end
			if not done and os.clock() - lastMove > 25 and walked > 60 then
				log("NOTE: walk progress is stuck on the HUD - send this report")
				break
			end
		elseif sawHud then
			missing = missing + 1
			if missing >= 2 then done = true end -- the line is gone: objective finished
		elseif walked >= goal then
			done = true
		end
	end
	hbc:Disconnect()
	return done
end

local function logHud(tag)
	local n = 0
	for _, g in ipairs(texts(false)) do
		if g:GetFullName():find("deviceinset", 1, true) then
			n = n + 1
			if n <= 8 then log(("HUD[%s] %s"):format(tag, clean(g.Text):sub(1, 80))) end
		end
	end
end

local function doDance2(o)
	local _, hum = hrpOf()
	if not hum then return false end
	for _ = 1, 3 do
		pcall(function() hum:UnequipTools() end)
		for _, c in ipairs(lp.Character:GetChildren()) do
			if c:IsA("Tool") then pcall(function() c.Parent = lp.Backpack end) end
		end
		task.wait(0.3)
	end
	local a0, b0 = hudProgress("dance")
	if a0 and b0 and b0 > a0 then
		o = { kind = "dance", secs = b0 - a0 }
	elseif not o.secs then
		o = { kind = "dance", secs = fallbackCount("dance", o.level) or 15 }
	end
	do
		local h0 = hrpOf()
		if h0 then
			local home = h0.CFrame
			local dir0, len0 = openLane(h0)
			if len0 >= 12 then -- ไม่มีทางโล่ง = เต้นตรงนี้เลย ไม่เดา
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { lp.Character }
				rp.RespectCanCollide = true -- ข้าม part ล่องหน/ไม่แข็ง
				local p = h0.Position + dir0 * math.clamp(len0 - 4, 8, 14)
				local hit = workspace:Raycast(p + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), rp)
				if hit and hit.Material ~= Enum.Material.Water
					and math.abs(hit.Position.Y - (h0.Position.Y - 3)) < 6 then
					h0.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3.2, 0))
					h0.AssemblyLinearVelocity = Vector3.zero
					task.wait(0.8)
					if hum:GetState() == Enum.HumanoidStateType.Swimming
						or hum.FloorMaterial == Enum.Material.Water then
						h0.CFrame = home -- ลงน้ำ: กลับที่เดิม
						h0.AssemblyLinearVelocity = Vector3.zero
						log("DANCE: new spot was water - back to the goblin")
					end
				end
			end
		end
	end
	cancelEmote()
	task.wait(0.4)
	logHud("dance start")
	log("DANCE " .. o.secs .. "s")
	local methods = {
		function() return hum:PlayEmote("dance") end,
		function() task.spawn(sendChat, "/e dance") return true end,
		function() task.spawn(sendChat, "/e dance2") return true end,
		function() task.spawn(sendChat, "/e dance3") return true end,
	}
	local counted, useIdx = false, 1
	for i, f in ipairs(methods) do
		useIdx = i
		pcall(f)
		local a
		for _ = 1, 6 do
			task.wait(1)
			touch(30)
			a = hudProgress("dance")
			if a == nil or a > 0 then break end
		end
		log(("DANCE method %d | hud=%s"):format(i, tostring(a)))
		if a == nil or a > 0 then
			counted = true
			break
		end
		cancelEmote()
		task.wait(0.4)
	end
	local t0 = os.clock()
	local lastA, lastAt = nil, os.clock()
	while running and os.clock() - t0 < o.secs * 2 + 30 do
		touch(30)
		local a, b = hudProgress("dance")
		if a and b and a >= b then break end
		if a == nil then
			if os.clock() - t0 >= o.secs + 6 then break end
		else
			if a ~= lastA then lastA, lastAt = a, os.clock() end
			if os.clock() - lastAt > 8 then
				cancelEmote(); task.wait(0.3); pcall(methods[useIdx])
				log("DANCE restart (hud=" .. tostring(a) .. ")")
				lastAt = os.clock()
			end
		end
		task.wait(1)
	end
	logHud("dance end")
	stopEmote()
	exitEmote()
	stopEmote()
	wd.note = (not counted) and "hud never counted" or nil
	return counted
end

-- มีพื้นอยู่ข้างหน้าไหม (กันเดินตกหน้าผา / ลงน้ำลึก)
local function groundAhead(h, dir)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lp.Character }
	rp.IgnoreWater = false -- นับน้ำเป็น "ไม่มีพื้น"
	local p = h.Position + dir * 7
	local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), rp)
	return hit ~= nil and hit.Material ~= Enum.Material.Water
		and math.abs(hit.Position.Y - (h.Position.Y - 3)) < 6
end

local function doWalk2(o)
	local hrp, hum = hrpOf()
	if not hrp or not hum then return false end
	local char = lp.Character
	cancelEmote()
	logHud("walk start")
	local dir, len = openLane(hrp)
	local leg = math.clamp(len / 16, 1.2, 3)
	local goal = (o.n or 50) * 1.1 + 5
	local flip, done, sawHud, missing = 1, false, false, 0
	local walked, last = 0, hrp.Position
	local t0 = os.clock()
	local flipAt, chkAt, hudAt, logAt = t0 + leg, t0 + 1.2, t0 + 1, t0 + 8
	local ledgeAt = t0 + 0.4
	local lastDry = hrp.CFrame
	local chkPos, lastHud, lastMove = hrp.Position, nil, t0
	pcall(function() RunService:UnbindFromRenderStep("GA_walk") end)
	RunService:BindToRenderStep("GA_walk", Enum.RenderPriority.Last.Value, function()
		pcall(function() hum:Move(dir * flip, false) end)
	end)
	local ok, err = pcall(function()
		while running and not done and os.clock() - t0 < math.max(300, goal / 8) do
			task.wait(0.1)
			touch(30)
			-- ตายระหว่างเดิน: เลิกทันที ห้ามนับว่าเควสเสร็จ
			if lp.Character ~= char or hum.Health <= 0 then
				lastDied = true
				log("NOTE: died while walking - will redo the quest after respawn")
				break
			end
			local h = hrpOf()
			if not h then break end
			local now = os.clock()
			local d = (h.Position - last).Magnitude
			if d < 8 then walked = walked + d end
			last = h.Position
			-- ลงน้ำ/ว่ายอยู่: วาปกลับจุดบกล่าสุด แล้วเดินกลับทิศ
			if hum:GetState() == Enum.HumanoidStateType.Swimming or hum.FloorMaterial == Enum.Material.Water then
				h.CFrame = lastDry + Vector3.new(0, 3, 0)
				h.AssemblyLinearVelocity = Vector3.zero
				flip = -flip
				flipAt, ledgeAt = now + leg, now + 1
				log("NOTE: walked into water - back to land")
			elseif hum.FloorMaterial ~= Enum.Material.Air then
				lastDry = h.CFrame
			end
			if now > ledgeAt and not groundAhead(h, dir * flip) then
				flip = -flip
				flipAt = now + leg
				ledgeAt = now + 0.6
			end
			if now > chkAt then
				if (h.Position - chkPos).Magnitude < 1 then
					dir = CFrame.Angles(0, math.rad(90), 0):VectorToWorldSpace(dir)
				end
				chkPos, chkAt = h.Position, now + 1.2
			end
			if now > flipAt then
				flip, flipAt = -flip, now + leg
			end
			if now > logAt then
				logAt = now + 8
				logHud(("walk %.0f studs"):format(walked))
			end
			if now > hudAt then
				hudAt = now + 1
				local pa, pb = hudProgress("walk")
				if pa then
					sawHud, missing = true, 0
					if pa ~= lastHud then lastHud, lastMove = pa, now end
					if pa >= pb then done = true end
					if not done and now - lastMove > 25 and walked > 60 then
						log(("NOTE: walk hud stuck at %d/%d after %.0f studs - send this report"):format(pa, pb, walked))
						break
					end
				elseif sawHud then
					missing = missing + 1
					if missing >= 2 and walked > 20 then done = true end
				elseif walked >= goal then
					done = true
				end
			end
		end
	end)
	RunService:UnbindFromRenderStep("GA_walk")
	pcall(function() hum:Move(Vector3.zero, false) end)
	if not ok then log("ERR walk " .. tostring(err)) end
	return done
end

local witchPos      -- where Beatrix stood the last time she was loaded
local ensureHallow, doTrick  -- defined after goTo(): sails to the Halloween area if the Witch is not there yet

local function findWitch()
	local w = workspace:FindFirstChild("world")
	local n = w and w:FindFirstChild("npcs")
	local f = n and n:FindFirstChild("fihfrigh")
	local m = f and f:FindFirstChild("Witch")
	if m and m:FindFirstChildWhichIsA("BasePart", true) then
		local ok, cf = pcall(function() return m:GetPivot() end)
		if ok and cf then witchPos = cf.Position end
	end
	return m
end

local function doInsult(o)
	local witch = ensureHallow()
	if not (witch and DI) then
		log("NOTE: Witch / DialogInteract not found")
		return false
	end

	-- Talking to Beatrix while the Insult quest runs: the dialog can start with US as the speaker
	-- (dialogstart npc = our own character, e.g. "Master of chemical chaos!") instead of the Witch.
	-- openDialog() only waits for a dialog on the Witch model, so it never saw that, pressed Nevermind
	-- and re-fired the prompt until it gave up. Here both kinds count, nothing gets closed between tries,
	-- and a disabled prompt (she is busy) is waited out instead of fired blind.
	-- returns "witch" | "self" | nil
	local function talkWitch()
		local pp
		local t0 = os.clock()
		while witch.Parent do
			pp = witch:FindFirstChildWhichIsA("ProximityPrompt", true)
			if pp or os.clock() - t0 > 6 then break end
			task.wait(0.4)
		end
		if not pp then
			log("NOTE: no prompt on " .. witch.Name)
			return nil
		end
		pcall(function()
			pp.HoldDuration = 0
			pp.RequiresLineOfSight = false
			pp.MaxActivationDistance = 40
		end)
		for attempt = 1, 6 do
			touch(60)
			if not running or not witch.Parent then return nil end
			local w1 = os.clock()
			while running and witch.Parent and not pp.Enabled and os.clock() - w1 < 12 do
				task.wait(0.3)
			end
			local hrp = hrpOf()
			local dist = hrp and (hrp.Position - promptPos(witch)).Magnitude
			if dist and dist > 8 then tpTo(witch) end
			local pin = hrpOf()
			if pin then pin.Anchored = true end
			cancelEmote()
			if attempt >= 2 then stopEmote(); exitEmote(true) end
			task.wait(0.1)
			dialogRoot = nil
			snapshot()
			dialogAt[witch] = nil
			local mark = os.clock()
			firePrompt(pp, attempt % 2 == 1)
			local who, again = nil, false
			while running and os.clock() - mark < 5 do
				if dialogAt[witch] then who = "witch" break end
				if (wd.dlgAt or 0) >= mark and wd.dlgName == lp.Name then who = "self" break end
				if not again and os.clock() - mark > 2.2 then
					again = true
					firePrompt(pp, attempt % 2 == 0)
				end
				task.wait(0.1)
			end
			if who then
				log("TALK " .. witch.Name .. " (" .. who .. ")")
				return who
			end
			log(("WITCH try %d: no dialog | prompt.Enabled=%s dist=%s lastDialog=%s"):format(
				attempt, tostring(pp.Enabled), dist and ("%.0f"):format(dist) or "?", tostring(wd.dlgName)))
			-- standing right next to her and still no dialog = the previous conversation is still open on the
			-- server and blocks the prompt (this is why the 2nd insult never happened). Walk out of range
			-- (closes it), the next try teleports back.
			if dist and dist <= 12 then pcall(leaveDialog, witch) end
			task.wait(1.5)
		end
		return nil
	end

	-- how many insults are still needed: HUD counter first, then the text of the quest, then the
	-- difficulty table (easy 1 / normal 2 / hard 3 / extreme 10 / ultimate 50)
	local a0, b0 = hudProgress("insult")
	local need = (a0 and b0 and b0 - a0) or o.n or fallbackCount("insult", o.level) or 1
	local sawHud, misses = a0 ~= nil, 0
	log(("INSULT need=%d (hud=%s, level=%s)"):format(need, a0 and (a0 .. "/" .. b0) or "-", tostring(o.level)))
	for i = 1, need + 5 do -- +5 = รอบสำรอง
		if not running then return false end
		touch(30)
		local a, b = hudProgress("insult")
		if a then
			sawHud = true
		elseif sawHud then -- HUD line gone = finished (check twice, the HUD can blink while it refreshes)
			task.wait(0.8)
			if not hudProgress("insult") then return true end
		end
		if a and a >= b then return true end
		if not sawHud and i > need then return true end
		if not witch.Parent then
			witch = ensureHallow()
			if not witch then return false end
		end
		if not tpTo(witch) then return false end
		local who = talkWitch()
		if not who then
			misses = misses + 1
			if misses >= 3 then return false end
		elseif who == "self" then
			-- the insult line was spoken by us: the server counts it, there is no choice to pick
			local c = wd.dlgCfg
			local n1 = type(c) == "table" and type(c.dialog) == "table" and c.dialog[1]
			log(("INSULT %d/%d -> spoken: %s"):format(i, need,
				type(n1) == "table" and clean(tostring(n1.text)):sub(1, 60) or "?"))
			task.wait(1.2)
			for _ = 1, 3 do -- a "continue" button may still be showing
				if not stepDialog() then break end
				task.wait(0.6)
			end
			closeDialog()
			task.wait(0.8)
		else
			local cfg = dialogCfg[witch]
			local ch = cfg and cfg.dialog and cfg.dialog[1] and cfg.dialog[1].choices
			local idx
			for k, c in ipairs(ch or {}) do
				local t = clean(tostring(c.text or c.arg)):lower()
				if i == 1 then log(("WITCH choice %d: %s"):format(k, t:sub(1, 60))) end
				if not idx and (t:find("insult", 1, true) or t:find("hag", 1, true) or t:find("crooked", 1, true)) then idx = k end
			end
			idx = idx or 4 -- ยังไม่ยืนยัน: เห็น DialogInteract(1, 4) ใน log ตอนเควส Insult ค้างอยู่
			local ok, res = pcall(function() return DI:InvokeServer(1, idx) end)
			log(("INSULT %d/%d -> %s %s"):format(i, need, tostring(ok), fmt(res)))
			task.wait(0.6)
			closeDialog()
			task.wait(0.4)
		end

		-- let the HUD count it (max 2.5s), so the next round does not read a stale "(0/2)"
		if who and a then
			local t1 = os.clock()
			while running and os.clock() - t1 < 2.5 and hudProgress("insult") == a do task.wait(0.25) end
		end
		local na, nb = hudProgress("insult")
		if who and ((a and not na) or (na and nb and na >= nb)) then
			log(("INSULT done (hud=%s)"):format(na and (na .. "/" .. nb) or "gone"))
			closeDialog()
			local hd = hrpOf()
			if hd then hd.Anchored = false end
			return true
		end
		-- more to do: end the conversation for real. A dialog that stays open on the server makes the
		-- next prompt press do nothing, so walk out of its range (12 studs) before coming back.
		if who then pcall(leaveDialog, witch) end
		local h = hrpOf()
		if h then h.Anchored = false end
	end
	return false
end

local function perform(o)
	local h0 = hrpOf()
	if h0 then h0.Anchored = false end
	local char = lp.Character
	local _, hum = hrpOf()
	local res = false
	local t0 = os.clock()
	wd.cur, wd.note = o.kind, nil
	if o.kind == "chat" then res = doChat(o)
	elseif o.kind == "dance" then res = doDance2(o)
	elseif o.kind == "jump" then res = doJump(o)
	elseif o.kind == "walk" then res = doWalk2(o)
	elseif o.kind == "insult" then res = doInsult(o)
	elseif o.kind == "trick" then res = doTrick(o)
	elseif o.kind == "perfect" or o.kind == "fcatch" then res = wd.doFish(o, o.kind)
	end
	-- ตายระหว่างทำ (ไม่ว่าเควสชนิดไหน) = ไม่นับว่าเสร็จ ห้ามเซ็ต claim
	if lp.Character ~= char or (hum and hum.Health <= 0) then
		lastDied = true
		hp(o.kind, false, "died during objective")
		log("NOTE: died during " .. o.kind .. " - not counted, will redo after respawn")
		return false
	end
	hp(o.kind, res and true or false, res and "ok" or (wd.note or "did not finish"), res and os.clock() - t0 or nil)
	return res
end

---------------------------------------------------------------- per-goblin flow
local function pickByRemote(m)
	local cfg = dialogCfg[m]
	local node = cfg and cfg.dialog and cfg.dialog[1]
	local ch = node and node.choices
	if not (DI and ch) then return false end
	local order = levelOrder()
	for _, w in ipairs(order) do
		for i, c in ipairs(ch) do
			if c.callback and clean(tostring(c.arg or c.text)):lower():find(w, 1, true) then
				wd.pickLevel = w -- remembered so the quest knows its difficulty (count table)
				log(("PICK %s -> DialogInteract(1, %d)"):format(w, i))
				local ok, res = pcall(function() return DI:InvokeServer(1, i) end)
				log("DialogInteract returned " .. tostring(ok) .. " " .. fmt(res))
				return ok
			end
		end
	end
	return false
end

local function objFromCfg(m)
	local cfg = dialogCfg[m]
	local msg = cfg and cfg.initial_data and cfg.initial_data.msg
	if not msg then return nil end
	local o = parse(msg)
	if o then return o, clean(msg) end
end

local function turnIn(m)
	-- remember that this goblin is owed a hand-in. If we did the objective far away (Insult Beatrix is in
	-- another dimension) its model streams out and is REMOVED; a new model with the same UID appears when we
	-- come back, so wd.reacquire flies to where it stood and finds it again. The quest lasts ~15 min.
	local uid = tostring(m:GetAttribute("UID") or "")
	if uid ~= "" and not wd.owed[uid] then
		local st0 = state[m]
		local okP, pv = pcall(function() return m:GetPivot().Position end)
		local pos0 = (st0 and st0.pos) or (okP and pv) or nil
		if pos0 then wd.owed[uid] = { pos = pos0, name = m.Name, at = os.clock() } end
	end
	if not m.Parent then
		local e = wd.owed[uid]
		local g = e and wd.reacquire(uid, e.name, e.pos)
		if not g then
			log("NOTE: goblin left before turn-in")
			return false
		end
		state[g] = state[m] or state[g]
		m = g
	end
	setStatus("claim: " .. m.Name)
	if not tpTo(m) then hp("turnin", false, "tp failed") return false end
	if not openDialog(m) then hp("turnin", false, "dialog failed") return false end
	local st = state[m]
	if st then st.pos = m:GetPivot().Position end
	advance(5, false)
	softLeave(m)
	bump(stats.done, st and (st.kind or (st.obj and st.obj.kind)))
	log("DONE " .. m.Name)
	hp("turnin", true, m.Name)
	if uid ~= "" then wd.owed[uid] = nil end
	return true
end

-- multiple-choice question (guess ...): reopening the dialog gives cs_start = "choicesN" and
-- initial_data = { msg, choice1..N }. The answer is DialogInteract(8 + N, picked index).
-- true = answered | false = could not open the dialog | nil = not a multiple-choice dialog
local function doChoice(m, alreadyOpen)
	local tried = {}
	for round = 1, 8 do
		if not (round == 1 and alreadyOpen) and not openDialog(m) then return false end
		local cfg = dialogCfg[m]
		local cs = cfg and tostring(cfg.cs_start) or ""
		local n = tonumber(cs:match("^choices(%d+)$"))
		local d = cfg and cfg.initial_data or {}
		if not DI then return false end
		if cs == "started2" then -- มีปุ่มเดียวให้กด (insult / say-this)
			log("ANSWER " .. clean(tostring(d.msg)) .. " -> " .. clean(tostring(d.choice)))
			local ok, res = pcall(function() return DI:InvokeServer(3, 1) end)
			log("DialogInteract returned " .. tostring(ok) .. " " .. fmt(res))
			softLeave(m)
			return ok
		end
		if not n then
			if round == 1 then
				log("NOTE: no multiple-choice dialog (cs_start=" .. cs .. ")")
				return nil
			end
			return true
		end
		local pool = {}
		for i = 1, n do
			if not tried[i] then pool[#pool + 1] = i end
		end
		if #pool == 0 then return true end
		local pick = pool[math.random(#pool)] -- สุ่มตอบ
		tried[pick] = true
		log(("ANSWER %s -> #%d %s"):format(clean(tostring(d.msg)), pick, clean(tostring(d["choice" .. pick]))))
		local ok, res = pcall(function() return DI:InvokeServer(8 + n, pick) end)
		log("DialogInteract returned " .. tostring(ok) .. " " .. fmt(res))
		softLeave(m)
		if not ok then return false end
		if not tostring(res):lower():find("wrong", 1, true) then return true end
	end
	return true
end

local function handleGoblin(m, s, phase)
	if s.claim then return turnIn(m) end
	if phase == "do" and s.obj then -- เควสรับไว้แล้ว: ทำให้เสร็จ แล้วค่อยกลับไปส่ง
		setStatus(s.obj.kind .. ": " .. m.Name)
		if not perform(s.obj) then
			log("NOTE: objective did not finish")
			return false
		end
		s.claim = true
		return turnIn(m)
	end
	-- มีเควสตัวอื่นที่รับค้างไว้ไหม: ถ้ามี ห้ามอ่านเควสจาก HUD (จะไปหยิบของตัวอื่นมา)
	local others = false
	for _, g in ipairs(goblins()) do
		local o = state[g]
		if g ~= m and o and o.accepted and not o.done then others = true break end
	end

	setStatus("quest: " .. m.Name)
	wd.pickLevel = nil
	if not tpTo(m) then return false end
	if not openDialog(m) then return false end

	local obj, raw
	local cfg0 = dialogCfg[m]
	if not (cfg0 and cfg0.cs_start) then
		local ch = cfg0 and cfg0.dialog and cfg0.dialog[1] and cfg0.dialog[1].choices
		if ch then
			local lvs, ok = {}, false
			for _, c in ipairs(ch) do
				if c.callback and c.arg then
					local lv = clean(tostring(c.arg)):lower()
					lvs[#lvs + 1] = lv
					if levelOK(lv) then ok = true end
				end
			end
			local key = m.Name:lower()
			if #lvs == 1 and diffByName[key] ~= lvs[1] then
				diffByName[key] = lvs[1]
				log("LEARN " .. m.Name .. " = " .. lvs[1])
			end
			if #lvs > 0 and not ok then
				log("SKIP level " .. table.concat(lvs, "/") .. " (not selected) on " .. m.Name)
				closeDialog()
				return true
			end
		end
	end
	if cfg0 and cfg0.cs_start and cfg0.initial_data then
		obj, raw = objFromCfg(m) -- quest already running
		if not obj and tostring(cfg0.cs_start):find("^choices%d") then
			obj, raw = { kind = "skip", why = "guess" }, clean(tostring(cfg0.initial_data.msg))
		end
		if not obj and not others then obj, raw = activeObjective(true) end
		if obj then log("RESUME " .. raw) end
	elseif pickByRemote(m) then
		obj, raw = advance(5, true)
		if not obj and openDialog(m) then obj, raw = objFromCfg(m) end
	else
		local btn, label = pickDifficulty()
		if btn then
			lastClick[btn] = { t = label, at = os.clock() }
			log(('PICK "%s" via %s'):format(label:sub(1, 60), press(btn)))
			for _, d in ipairs(DIFF) do
				if label:find(d, 1, true) then wd.pickLevel = d break end
			end
			obj, raw = advance(5, true)
		elseif CFG.resumeActive and not others and hasGoblinQuest() then
			obj, raw = activeObjective()
			if obj then log("RESUME " .. raw) end
		end
	end

	if not obj then
		local c = dialogCfg[m]
		local cs = c and tostring(c.cs_start) or ""
		if cs:find("^choices%d") or cs == "started2" then
			obj = { kind = "skip", why = "guess" }
			raw = clean(tostring(c.initial_data and c.initial_data.msg))
		end
	end
	if not obj and not others then
		obj, raw = activeObjective(true) -- บรรทัดเควสบน HUD เช่น "Dance for 15 seconds (0/15)"
		if obj then log("HUD " .. raw) end
	end

	if not obj and s.obj then -- เควสที่เคยอ่านไว้ (ตายแล้ววนกลับมา / ข้อความ resume อ่านไม่ออก)
		obj, raw = s.obj, "(remembered) " .. tostring(s.obj.kind)
		log("RESUME " .. raw)
	end
	if not obj then
		log("NOTE: no quest/objective found on " .. m.Name
			.. " - open the dialog, press Dump UI, then send the report")
		return false
	end
	log("OBJECTIVE " .. raw .. " -> " .. obj.kind)
	hp("accept", true, obj.kind)
	local qk = obj.kind == "skip" and obj.why or obj.kind
	if CFG.quests[qk] == false then
		obj = { kind = "skip", why = qk .. " (off)" }
	end
	if wd.pickLevel then s.level = wd.pickLevel end -- the difficulty we just picked (kept on resume)
	if (obj.kind == "insult" or obj.kind == "trick" or obj.kind == "dance") and not obj.level then
		obj.level = s.level or diffByName[m.Name:lower()]
	end
	if obj.kind ~= "skip" then s.obj = obj end
	if obj.kind == "skip" and (obj.why == "guess" or obj.why == "insult") then
		local c = dialogCfg[m]
		local cs = c and tostring(c.cs_start) or ""
		local r = doChoice(m, cs:find("^choices%d") ~= nil or cs == "started2")
		if r == true then
			s.claim = true
			s.kind = obj.why
			hp(obj.why == "guess" and "guess" or "insult", true, "answered")
			pcall(turnIn, m) -- dialog "finish" ให้ของรางวัล
			return true
		end
		if r == false then hp(obj.why == "guess" and "guess" or "insult", false, "dialog failed") end
		if r ~= nil then return r end
	end
	softLeave(m)
	if obj.kind == "skip" then
		bump(stats.skip, obj.why)
		log("SKIP (do it manually): " .. obj.why)
		return true
	end
	if phase == "accept" then -- รับอย่างเดียว ยังไม่ทำ
		s.accepted = true
		s.acceptAt = s.acceptAt or os.clock()
		log(("ACCEPTED %s -> %s"):format(m.Name, obj.kind))
		return "accepted"
	end

	if CFG.fishLast and (obj.kind == "perfect" or obj.kind == "fcatch")
		and os.clock() - (s.acceptAt or os.clock()) < CFG.fishLaterMax then
		local more = false
		for _, g in ipairs(fresh()) do
			local o = state[g]
			if g ~= m and not (o and o.fishLater) then more = true break end
		end
		if more then
			s.fishLater, s.accepted = true, true
			s.acceptAt = s.acceptAt or os.clock()
			log(("FISH LATER %s (%s) - other quests first"):format(m.Name, obj.kind))
			return "accepted"
		end
	end

	setStatus(obj.kind .. ": " .. m.Name)
	if not perform(obj) then
		log("NOTE: objective did not finish")
		return false
	end
	s.claim = true
	return turnIn(m)
end

---------------------------------------------------------------- UI
local function dumpUI()
	log("---- UI DUMP (visible text) ----")
	local n = 0
	for _, g in ipairs(texts(false)) do
		if not badUI(g) and not g:GetFullName():find("announcements", 1, true) then
			n = n + 1
			if n > 120 then break end
			log(('UI %s | "%s" | button=%s'):format(g:GetFullName(), clean(g.Text):sub(1, 50),
				tostring(clickTarget(g) ~= nil)))
		end
	end
end

---------------------------------------------------------------- UI (v11: one window, 4 tabs)
local gui = Instance.new("ScreenGui")
gui.Name = "GoblinAuto"
gui.ResetOnSpawn = false
local okP = pcall(function()
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not okP or not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end
gui.DisplayOrder = 999

-- teleport helpers (used by the Warp tab)
local function landAt(x, z, y, maxDy, rp)
	local skip, best = { lp.Character }, nil
	for _ = 1, 14 do
		rp.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(Vector3.new(x, y + maxDy + 10, z),
			Vector3.new(0, -(maxDy * 2 + 20), 0), rp)
		if not hit then break end
		local inst = hit.Instance
		local d = math.abs(hit.Position.Y - y)
		if inst:IsA("Terrain") then
			if hit.Material ~= Enum.Material.Water and d <= maxDy and (not best or d < best.d) then
				best = { pos = hit.Position, inst = inst, d = d }
			end
			break -- ใต้ดิน/ผิวน้ำไม่ต้องหาต่อ
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

-- ไล่หาพื้นเป็นวง: จุดตรงๆ ก่อน แล้วค่อยขยายออก 15/30/50/80/120 stud
local function findLand(p, maxDy, rp)
	for _, r in ipairs({ 0, 15, 30, 50, 80, 120 }) do
		for i = 0, (r == 0 and 0 or 7) do
			local a = math.rad(i * 45)
			local f = landAt(p.X + math.cos(a) * r, p.Z + math.sin(a) * r, p.Y, maxDy, rp)
			if f then return f end
		end
	end
end

local function goTo(cf)
	local hrp = hrpOf()
	if not hrp then return false end
	local p = cf.Position
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.RespectCanCollide = true

	pcall(function() lp:RequestStreamAroundAsync(p) end)
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(p + Vector3.new(0, 30, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
	task.wait(1.2)

	local found
	for attempt = 1, 4 do -- 3 รอบแรกเข้ม (±25) รอ terrain stream, รอบสุดท้ายหลวม (±80)
		found = findLand(p, attempt <= 3 and 25 or 80, rp)
		if found then break end
		task.wait(0.5)
	end

	if found then
		log(("GOTO y=%.0f (saved %.0f, off %.0f) on %s"):format(
			found.pos.Y, p.Y, found.pos.Y - p.Y, found.inst:GetFullName()))
		hrp.CFrame = CFrame.new(found.pos + Vector3.new(0, 5, 0))
	else
		log(("NOTE: no solid ground near %.0f, %.0f, %.0f - use Mark spot"):format(p.X, p.Y, p.Z))
		hp("warp", false, "no solid ground")
		hrp.CFrame = CFrame.new(p + Vector3.new(0, 6, 0))
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = false
	return true
end

local lastIsl
-- กดปุ่มเกาะที่วาปไม่ได้ -> ไปยืนบนเกาะนั้นเอง -> กด Mark spot : เซฟพิกัด + log บรรทัดให้ก๊อปไปใส่ CFG.islandPos
local function markSpot()
	local hrp = hrpOf()
	if not (hrp and lastIsl) then
		setStatus("press an island first")
		return
	end
	local p = hrp.Position
	local old = CFG.islandPos[lastIsl[1]]
	if not old or (old - p).Magnitude < 600 then CFG.islandPos[lastIsl[1]] = p end
	log(('SPOT SAVED ["%s"] = Vector3.new(%.0f, %.0f, %.0f),'):format(lastIsl[1], p.X, p.Y, p.Z))
	local cam = workspace.CurrentCamera
	local lk = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
	log(('FISH SPOT { pos = Vector3.new(%.1f, %.1f, %.1f), look = Vector3.new(%.2f, %.2f, %.2f) },'):format(
		p.X, p.Y, p.Z, lk.X, lk.Y, lk.Z))
	setStatus("saved " .. lastIsl[1])
end

local function goIsland(isl)
	lastIsl = isl
	local cf = findIsland(isl)
	if not cf then
		log("NOTE: island not found: " .. isl[1] .. " - press Dump islands, or fill CFG.islandPos")
		setStatus("no spot: " .. isl[1])
		return
	end
	log("TP island " .. isl[1])
	setStatus("tp: " .. isl[1])
	goTo(cf)
	setStatus("idle")
end

local function dumpIslands()
	log("---- ISLAND DUMP ----")
	for _, r in ipairs(islandRoots()) do
		log("ROOT " .. r:GetFullName())
		for i, o in ipairs(r:GetChildren()) do
			if i > 80 then break end
			local p = posOf(o)
			log(("  %s | %s"):format(o.Name, p and ("%.0f, %.0f, %.0f"):format(p.X, p.Y, p.Z) or "no pos"))
		end
	end
end

-- a goblin whose model streamed out while we were away: fly to where it stood and find the new model (same UID)
wd.reacquire = function(uid, name, pos)
	local function find()
		for _, g in ipairs(goblins()) do
			local gu = g:GetAttribute("UID")
			if gu ~= nil and uid ~= "" then
				if tostring(gu) == uid then return g end
			elseif g.Name == name and (g:GetPivot().Position - pos).Magnitude < 40 then
				return g
			end
		end
	end
	local g = find()
	if g then return g end
	setStatus("return to turn in: " .. name)
	log(("RETURN to turn in %s -> (%.0f, %.0f, %.0f)"):format(name, pos.X, pos.Y, pos.Z))
	for _ = 1, 2 do
		if not running then return nil end
		touch(90)
		pcall(goTo, CFrame.new(pos))
		local t0 = os.clock()
		while running and os.clock() - t0 < 8 do
			touch(60)
			g = find()
			if g then return g end
			task.wait(0.3)
		end
	end
	log("RETURN: goblin not found at its old spot (moved, expired or handed in)")
	hp("turnin", false, "goblin not found at old spot")
	return nil
end

-- AutoFish bridge: read quest progress from the HUD and coordinate the separate fishing script.
wd.fishHud = function(kind)
	for _, g in ipairs(texts(false)) do
		if g:GetFullName():lower():find("deviceinset", 1, true) then
			local l = clean(g.Text):lower()
			local hit = false
			if l:find("catch", 1, true) then
				if kind == "perfect" then
					hit = l:find("perfect", 1, true) and not l:find("in a row", 1, true) and not l:find("pool", 1, true)
				else
					hit = l:find("fischfright", 1, true)
				end
			end
			if hit then
				local a, b = l:match("(%d[%d,]*)%s*/%s*(%d[%d,]*)")
				if a and b then return tonumber((a:gsub(",", ""))), tonumber((b:gsub(",", ""))) end
			end
		end
	end
end

wd.faceSpot = function(spot)
	local hrp = hrpOf()
	if not (hrp and spot and spot.look) then return end
	local flat = Vector3.new(spot.look.X, 0, spot.look.Z)
	if flat.Magnitude < 0.1 then return end
	hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
	local cam = workspace.CurrentCamera
	if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + spot.look) end
	task.wait(0.3)
end

wd.doFish = function(o, kind)
	local api = genv.AutoFishAPI
	if not api then
		log("NOTE: AutoFish is not running - execute the autofish script first")
		return false
	end
	local char = lp.Character
	local a0, b0
	local w0 = os.clock()
	while running and os.clock() - w0 < 6 do
		a0, b0 = wd.fishHud(kind)
		if a0 then break end
		task.wait(0.4)
	end
	if not a0 then
		log("NOTE: FISH " .. kind .. ": quest line not found on the HUD - press Dump UI")
		return false
	end
	if a0 >= b0 then return true end

	local spot = CFG.fishSpots and CFG.fishSpots[kind]
	if spot and spot.pos then
		setStatus("fish: go to spot")
		if spot.pos.X < -10000 and not ensureHallow() then
			log("NOTE: FISH: could not sail to Hallow")
			return false
		end
		pcall(goTo, CFrame.new(spot.pos))
		wd.faceSpot(spot)
	end

	local maxT, c0, t0 = CFG.fishMax or 720, api.count(), os.clock()
	local done, last, lastAt, missing = false, a0, os.clock(), 0
	log(("FISH %s: %d more (hud %d/%d), max %ds"):format(kind, b0 - a0, a0, b0, maxT))
	setStatus("fish: " .. kind)
	api.set(true)
	local ok, err = pcall(function()
		while running and os.clock() - t0 < maxT do
			touch(30)
			local _, hm = hrpOf()
			if lp.Character ~= char or not hm or hm.Health <= 0 then
				lastDied = true
				log("NOTE: died while fishing")
				return
			end
			if not enabled then log("FISH: Auto is OFF - stopping") return end
			local now = os.clock()
			local a, b = wd.fishHud(kind)
			if a then
				missing = 0
				if a ~= last then
					log(("FISH %s %d/%d | reels %d"):format(kind, a, b, api.count() - c0))
					last, lastAt = a, now
				end
				if a >= b then done = true return end
				if now - lastAt > (CFG.fishStall or 300) then
					log(("FISH: HUD stuck at %d/%d for %ds - giving up"):format(a, b, math.floor(now - lastAt)))
					return
				end
				local el, made = now - t0, a - a0
				if made > 0 and el > 120 then
					local eta = (b - a) * el / made
					if eta > (maxT - el) * 1.3 then
						log(("FISH: too slow (%d in %ds) - needs %ds more, %ds left - giving up"):format(made, math.floor(el), math.floor(eta), math.floor(maxT - el)))
						return
					end
				end
			else
				-- HUD ซ่อนตัวตอนเล่นมินิเกม: บรรทัดหายไม่ได้แปลว่าเสร็จ
				missing = missing + 1
				if missing >= 90 and not api.busy() then
					log("FISH: HUD line missing for 90s - giving up")
					return
				end
			end
			task.wait(1)
		end
	end)
	api.set(false)
	local w1 = os.clock()
	while api.busy() and os.clock() - w1 < 30 do touch(60); task.wait(0.3) end
	pcall(function() local _, h2 = hrpOf(); if h2 then h2:UnequipTools() end end)
	if not ok then log("ERR fish " .. tostring(err)) end
	log(("FISH %s %s | %d/%d | reels %d | %ds"):format(kind, done and "DONE" or "not finished", last, b0, api.count() - c0, math.floor(os.clock() - t0)))
	return done
end

---------------------------------------------------------------- Halloween area (Caustic Hallow)
-- Beatrix (Witch) and the trick-or-treat houses only exist over there. Way in: stand on the Reaping
-- Dutchman docked at Moosewood, talk to the Dutchman Captain, pick "Set sail!". The way back is a normal teleport.
local function dutchmanCaptain()
	local w = workspace:FindFirstChild("world")
	local m = w and w:FindFirstChild("map")
	local f = m and m:FindFirstChild("Fischfright26")
	local g = f and f:FindFirstChild("Green")
	local r = g and g:FindFirstChild("Reaping Dutchman")
	return r and r:FindFirstChild("Dutchman Captain")
end

local function witchLoaded()
	local w = findWitch()
	if w and w:FindFirstChildWhichIsA("BasePart", true) then return w end
end

local function waitWitch(secs)
	local t0 = os.clock()
	while running and os.clock() - t0 < secs do
		touch(60)
		local w = witchLoaded()
		if w then return w end
		task.wait(0.3)
	end
end

local hallowAt = 0 -- os.clock() of the last successful sail

ensureHallow = function()
	local w = witchLoaded()
	if w then return w end

	-- sailed earlier: she is probably just streamed out -> fly back to where she stood
	if witchPos and os.clock() - hallowAt < 900 then
		log(("HALLOW: Witch not loaded - going back to (%.0f, %.0f, %.0f)"):format(witchPos.X, witchPos.Y, witchPos.Z))
		goTo(CFrame.new(witchPos))
		w = waitWitch(6)
		if w then return w end
	end

	for round = 1, 2 do
		if not running then return nil end
		setStatus("sail to Hallow")
		local cap = dutchmanCaptain()
		if not cap then
			log("HALLOW: Dutchman not loaded - going to the deck")
			if not goTo(CFrame.new(CFG.hallowDeck)) then return nil end
			local t0 = os.clock()
			while running and not dutchmanCaptain() and os.clock() - t0 < 8 do
				touch(60)
				task.wait(0.3)
			end
			cap = dutchmanCaptain()
			if not cap then
				log("NOTE: Dutchman Captain not found - is the ship docked at Moosewood?")
				return nil
			end
		end
		if openDialog(cap) then
			local h = hrpOf()
			if h then h.Anchored = false end
			-- 1) the on-screen "Set sail!" button  2) key 1 (the option is numbered "1.")  3) DialogInteract(1, 1)
			local methods = {
				function()
					for _, g in ipairs(texts(false)) do
						if clean(g.Text):lower():find("set sail", 1, true) then
							local b = clickTarget(g)
							if b then
								local how = press(b)
								if how ~= "none" then return "click " .. how end
							end
						end
					end
				end,
				function()
					tap(Enum.KeyCode.One, 0.15)
					return "key 1"
				end,
				function()
					if not DI then return end
					local ok, res = pcall(function() return DI:InvokeServer(1, 1) end)
					return "DialogInteract(1, 1) -> " .. tostring(ok) .. " " .. fmt(res)
				end,
			}
			table.insert(methods, 1, table.remove(methods)) -- DialogInteract(1, 1) first (confirmed in the log)
			for _, method in ipairs(methods) do
				local ok, how = pcall(method)
				if ok and how then
					log("HALLOW: set sail via " .. how)
					w = waitWitch(25)
					if w then
						hallowAt = os.clock()
						log("HALLOW: arrived, Witch loaded")
						hp("sail", true, "arrived")
						return w
					end
				end
			end
			log("NOTE: sailed but the Witch never loaded (round " .. round .. ")")
		else
			log("NOTE: could not open the Dutchman dialog (round " .. round .. ")")
		end
		task.wait(1)
	end
	hp("sail", false, "gave up after 2 rounds")
	return nil
end

-- Trick-or-treat (from the log): knock -> RE/TrickOrTreat/Visit -> RE/Rituals/Hands -> RF/TrickOrTreat/Treat({voice=2, npc=Door.TrickOrTreatN})
-- -> RE/TrickOrTreat/Outcome -> RE/TrickOrTreat/Done. N changed every visit (1, 5, 11...), voice was always 2.
local function housesFolder()
	local w = workspace:FindFirstChild("world")
	local m = w and w:FindFirstChild("map")
	local f = m and m:FindFirstChild("Fischfright26")
	return f and f:FindFirstChild("TrickOrTreat-Houses")
end

local function posOf(pp)
	local p = pp.Parent
	if p and p:IsA("BasePart") then return p.Position end
	local ok, cf = pcall(function() return p:GetPivot() end)
	return ok and cf and cf.Position or nil
end

local function isShown(c)
	if c:IsA("BasePart") then return c.Transparency < 0.9 end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.9 then return true end
	end
	return false
end

doTrick = function(o)
	local rVisit = net and net:FindFirstChild("RE/TrickOrTreat/Visit")
	local rOutcome = net and net:FindFirstChild("RE/TrickOrTreat/Outcome")
	local rDone = net and net:FindFirstChild("RE/TrickOrTreat/Done")
	local rHands = net and net:FindFirstChild("RE/Rituals/Hands")
	local fTreat = net and net:FindFirstChild("RF/TrickOrTreat/Treat")
	-- the Trick remote is not in any log yet: try the obvious name, then any TrickOrTreat remote with "trick" in its name
	local fTrick = net and net:FindFirstChild("RF/TrickOrTreat/Trick")
	if net and not fTrick then
		for _, r in ipairs(net:GetChildren()) do
			local tail = r.Name:match("^R[EF]/TrickOrTreat/(.+)$")
			if tail and tail:lower():find("trick", 1, true) and (r:IsA("RemoteFunction") or r:IsA("BaseRemoteEvent")) then
				fTrick = r
				break
			end
		end
	end
	if net and not wd.trickListed then
		wd.trickListed = true
		local names = {}
		for _, r in ipairs(net:GetChildren()) do
			if r.Name:find("TrickOrTreat", 1, true) or r.Name:find("Rituals", 1, true) then
				names[#names + 1] = r.Name .. "(" .. r.ClassName .. ")"
			end
		end
		log("TRICK REMOTES: " .. table.concat(names, ", "))
	end
	if not (rVisit and rOutcome and fTreat) then
		log("NOTE: trick-or-treat remotes not found")
		return false
	end
	if not ensureHallow() then return false end -- the houses are in the Halloween area
	local function equipBucket()
		local _, hum = hrpOf()
		if not hum then return false end
		local function find(par)
			if not par then return nil end
			for _, c in ipairs(par:GetChildren()) do
				if c:IsA("Tool") and c.Name:lower():find("bucket", 1, true) then return c end
			end
		end
		if find(lp.Character) then return true end
		local tool = find(lp:FindFirstChildOfClass("Backpack"))
		if not tool then
			log("TRICK: no Candy Bucket tool found in backpack")
			return false
		end
		pcall(function() hum:EquipTool(tool) end)
		task.wait(0.4)
		return find(lp.Character) ~= nil
	end

	-- door state = every part of the Door model except the NPC models (those are read with isShown)
	local function inNpc(d, door)
		local p = d
		while p and p ~= door do
			if p.Name:find("^TrickOrTreat%d+$") then return true end
			p = p.Parent
		end
		return false
	end
	local function doorSig(door)
		local v, tr = Vector3.zero, 0
		local function add(d)
			local cf = d.CFrame
			v = v + cf.Position + cf.LookVector + cf.RightVector
			tr = tr + d.Transparency
		end
		if door:IsA("BasePart") then add(door) end
		for _, d in ipairs(door:GetDescendants()) do
			if d:IsA("BasePart") and not inNpc(d, door) then add(d) end
		end
		return v, tr
	end
	local function npcShown(door)
		for _, c in ipairs(door:GetChildren()) do
			if c.Name:find("^TrickOrTreat%d+$") and isShown(c) then return true end
		end
		return false
	end
	-- closed = the door is back where it started and no NPC is showing (steady for 0.8s),
	-- or no NPC has been showing for 3s (in case the door animation never settles).
	-- onGrace runs once if it is still open after 4s.
	local function waitDoorClosed(door, baseV, baseTr, minSecs, maxSecs, onGrace)
		local t0, stable, hidden, graced = os.clock(), nil, nil, false
		while running and os.clock() - t0 < maxSecs do
			touch(60)
			local el = os.clock() - t0
			if not graced and onGrace and el > 4 then
				graced = true
				onGrace()
			end
			local shown = npcShown(door)
			local v, tr = doorSig(door)
			local back = (v - baseV).Magnitude < 0.05 and math.abs(tr - baseTr) < 0.05
			if shown then hidden = nil else hidden = hidden or os.clock() end
			if el >= minSecs and back and not shown then
				stable = stable or os.clock()
				if os.clock() - stable >= 0.8 then return true, os.clock() - t0 end
			else
				stable = nil
			end
			if el >= minSecs and hidden and os.clock() - hidden >= 3 then return true, os.clock() - t0 end
			task.wait(0.15)
		end
		return false, os.clock() - t0
	end

	local visit, outcome
	local c1 = rVisit.OnClientEvent:Connect(function(id, _, secs)
		visit = { id = id, secs = tonumber(secs) or 3 }
	end)
	local c2 = rOutcome.OnClientEvent:Connect(function(...)
		outcome = table.pack(...)
	end)

	-- how many houses: HUD counter first, then the quest text, then the difficulty table
	-- (easy 1 / normal 3 / hard 7 / extreme 15)
	local a0, b0 = hudProgress("trick", "treat")
	local need = (a0 and b0 and b0 - a0) or o.n or fallbackCount("trick", o.level) or 1
	local sawHud = a0 ~= nil
	local got, tried, fails = 0, {}, {}
	log(("TRICK need=%d (hud=%s, level=%s)"):format(need, a0 and (a0 .. "/" .. b0) or "-", tostring(o.level)))
	-- the HUD decides when the quest is complete (not only the Outcome event, which can arrive late or never):
	-- a >= b, or the line disappeared after we had seen it. Without a HUD line we count Outcome events.
	local function isDone()
		local a, b = hudProgress("trick", "treat")
		if a then
			sawHud = true
			return a >= b
		end
		if sawHud then
			task.wait(0.8) -- the HUD can blink while it refreshes: look twice
			return hudProgress("trick", "treat") == nil
		end
		return got >= need
	end
	local ok, err = pcall(function()
		for _ = 1, need + 8 do
			if not running or isDone() then return end
			touch(60)
			setStatus(("trick-or-treat %d/%d"):format(got, need))

			-- nearest house we have not knocked on yet
			local best, bestD, bestDoor, bestPP
			local t0 = os.clock()
			repeat
				local folder, hrp = housesFolder(), hrpOf()
				if folder and hrp then
					for _, h in ipairs(folder:GetChildren()) do
						local door = h:FindFirstChild("Door")
						local pp = door and door:FindFirstChildWhichIsA("ProximityPrompt", true)
						local pos = pp and posOf(pp)
						if pos and not tried[h] then
							local d = (pos - hrp.Position).Magnitude
							if not bestD or d < bestD then best, bestD, bestDoor, bestPP = h, d, door, pp end
						end
					end
				end
				if not best then task.wait(0.5) end
			until best or not running or os.clock() - t0 > 6
			if not best then
				log("NOTE: no trick-or-treat houses loaded here - stand near a house and try again")
				return
			end
			tried[best] = true

			local hrp = hrpOf()
			local pos = posOf(bestPP)
			if not (hrp and pos) then return end
			pcall(function()
				bestPP.HoldDuration = 0
				bestPP.RequiresLineOfSight = false
				bestPP.MaxActivationDistance = 40
			end)
			hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			task.wait(0.6)

			if not equipBucket() then log("TRICK: bucket not equipped") end
			visit, outcome = nil, nil
			local before = hudProgress("trick", "treat") -- HUD count before this house
			local baseV, baseTr = doorSig(bestDoor) -- door while closed, to compare against later
			snapshot() -- so the Trick / Treat buttons that appear after the knock count as "new" text
			firePrompt(bestPP, true)
			local w0 = os.clock()
			while running and not visit and os.clock() - w0 < 5 do task.wait(0.1) end
			if not visit then
				log("TRICK: no Visit event after knocking on house " .. best.Name)
				wd.note = "no Visit event"
				-- the last door was probably still closing / the server busy: wait, then retry this house once
				fails[best] = (fails[best] or 0) + 1
				if fails[best] < 2 then tried[best] = nil end
				task.wait(2.5)
			else
				task.wait(visit.secs + 0.5)
				if rHands then pcall(function() rHands:FireServer() end) end

				-- the NPC that is showing first, then the others in random order
				local shown, rest
				local t2 = os.clock()
				repeat
					shown, rest = {}, {}
					for _, c in ipairs(bestDoor:GetChildren()) do
						if c.Name:find("^TrickOrTreat%d+$") then
							table.insert(isShown(c) and shown or rest, c)
						end
					end
					if #shown == 0 then task.wait(0.25) end
				until #shown > 0 or not running or os.clock() - t2 > 15
				for i = #rest, 2, -1 do
					local j = math.random(i)
					rest[i], rest[j] = rest[j], rest[i]
				end
				local cands = {}
				for _, c in ipairs(shown) do cands[#cands + 1] = c end
				for _, c in ipairs(rest) do cands[#cands + 1] = c end
				if #cands == 0 then
					-- nothing under Door: look through the whole house, and log what is there so it can be fixed
					local names = {}
					for _, d in ipairs(best:GetDescendants()) do
						if d:IsA("Model") and d.Name:find("^TrickOrTreat%d+$") then cands[#cands + 1] = d end
						if #names < 12 and not d:IsA("BasePart") then names[#names + 1] = d.Name end
					end
					log(("TRICK house %s: no NPC under Door, searched the house -> %d found | %s"):format(
						best.Name, #cands, table.concat(names, ",")))
				end
				log(("TRICK house %s: %d npcs (%d showing)"):format(best.Name, #cands, #shown))

				-- Treat / Trick / Random (Main tab buttons)
				local pickTrick = CFG.trickChoice == "trick" or (CFG.trickChoice == "random" and math.random(2) == 1)
				if pickTrick and not fTrick then
					log("TRICK: no Trick remote found (see the TRICK REMOTES line) - using Treat instead")
					pickTrick = false
				end
				local fAct = pickTrick and fTrick or fTreat
				local actName = pickTrick and "TRICKED" or "TREAT"

				-- counted = the Outcome event arrived OR the HUD counter moved (or its line is gone = the last one)
				local counted = false
				local function hudMoved()
					local pa = hudProgress("trick", "treat")
					return (pa and before and pa > before) or (before and not pa)
				end
				-- The game answers the real on-screen "Trick" / "Treat" buttons itself. Calling the remote directly
				-- leaves those words on screen and the NPC never walks into the house, so press the button first
				-- and keep the remote below only as a fallback.
				-- The choice is a numbered list on screen:  1. ["Treat!"]   2. ["Trick!"]  (plain labels, not buttons),
				-- so it is answered with the number key. Returns button-or-nil, text, key number, label.
				-- v22: press the choice the moment it is READY (no blind 1s wait), and never mistake the words left
				-- over from the last house for the new ones.
				-- Words already on screen BEFORE the knock (snapshot() ran just before it) are "stale". The remote
				-- fallback leaves them up ("still on screen after this house"), so v21 saw them instantly and pressed
				-- ~1s later, blind, while the new choice was not up yet -> the press was eaten ("bug").
				local function choiceText(g)
					if badUI(g) or g:GetFullName():find("deviceinset", 1, true) then return nil end
					local t = clean(g.Text):lower()
					local hasTrick = t:find("trick", 1, true) ~= nil
					local hasTreat = t:find("treat", 1, true) ~= nil
					-- exactly one of the two words + short text (the title, the NPC line and the quest HUD line
					-- have both words or are long)
					if #t <= 16 and hasTrick ~= hasTreat and t:find("!", 1, true) then return t, hasTrick end
				end
				-- everything that changes while the word fades in / slides in / types itself out
				local function sigOf(g)
					local p, s = g.AbsolutePosition, g.AbsoluteSize
					local gt, a = 0, g
					while a and a ~= lp.PlayerGui do
						if a:IsA("CanvasGroup") then gt = math.max(gt, a.GroupTransparency) end
						a = a.Parent
					end
					return ("%.0f,%.0f,%.0f,%.0f,%s,%.2f,%.2f"):format(p.X, p.Y, s.X, s.Y, g.Text, g.TextTransparency, gt)
				end
				local stale, hid, moved, staleSig = {}, {}, {}, {}
				for g in pairs(base) do
					if g.Parent and choiceText(g) then stale[g] = true end
				end
				-- a stale word counts as the NEW one once it hides and comes back, or animates again
				local function watchStale()
					for g in pairs(stale) do
						if not alive(g) then
							hid[g] = true
						elseif not (hid[g] or moved[g]) then
							local sg = sigOf(g)
							if staleSig[g] and staleSig[g] ~= sg then moved[g] = true end
							staleSig[g] = sg
						end
					end
				end
				-- freshOnly = skip the stale words (a list of fresh words only, so the key number stays right)
				local function choiceBtn(wantTrick, freshOnly)
					local lbls = {}
					for _, g in ipairs(texts(false)) do
						local t, hasTrick = choiceText(g)
						if t and g.TextTransparency < 0.5 and not (freshOnly and stale[g] and not hid[g] and not moved[g]) then
							lbls[#lbls + 1] = { g = g, t = t, trick = hasTrick }
						end
					end
					table.sort(lbls, function(x, y) return x.g.AbsolutePosition.Y < y.g.AbsolutePosition.Y end)
					for i, e in ipairs(lbls) do
						if e.trick == wantTrick then
							-- number written in the text ("1." / "2)") > position in the list > default Treat=1, Trick=2
							local n = tonumber(e.t:match("^%s*(%d)%s*[%.%)]")) or (#lbls >= 2 and i) or (wantTrick and 2 or 1)
							return clickTarget(e.g), e.t, n, e.g
						end
					end
				end

				local viaUI = false
				local btn, btnText, keyN, lbl
				local tw, lastScan, track, bothSeen, ready = os.clock(), 0, nil, false, false
				-- READY = the new word is on screen AND nothing about it changed (fade / slide / typing) for 0.15s.
				-- One word alone (its partner not up yet) needs 0.4s; a word that never settles is taken after 2.5s.
				repeat
					local now = os.clock()
					watchStale()
					if not (lbl and alive(lbl)) or now - lastScan >= 0.25 then
						lastScan = now
						local old = lbl
						btn, btnText, keyN, lbl = choiceBtn(pickTrick, true)
						if lbl ~= old then track = nil end
						if keyN and not bothSeen then bothSeen = select(3, choiceBtn(not pickTrick, true)) ~= nil end
					end
					ready = false
					if keyN and lbl and lbl.Parent then
						local sg = sigOf(lbl)
						if not track then
							track = { sig = sg, since = now, first = now }
						elseif track.sig ~= sg then
							track.sig, track.since = sg, now
						end
						ready = now - track.since >= (bothSeen and 0.15 or 0.4) or now - track.first >= 2.5
					end
					if not ready then task.wait(lbl and 0.05 or 0.1) end
				until ready or not running or os.clock() - tw > 10
				if ready then
					log(("TRICK choice ready %.1fs after the knock (visit.secs=%.1f, steady %.2fs, both words=%s)"):format(
						os.clock() - w0, visit.secs, os.clock() - track.since, tostring(bothSeen)))
				end

				if CFG.trickUseUI and not keyN then
					log("TRICK: no on-screen Trick/Treat words within 10s - new UI text below, then falling back to the remote")
					local n = 0
					for _, g in ipairs(texts(true)) do
						if not badUI(g) and not g:GetFullName():find("deviceinset", 1, true) then
							n = n + 1
							if n > 12 then break end
							log(('TRICK UI %s | "%s" | button=%s'):format(g:GetFullName(), clean(g.Text):sub(1, 40),
								tostring(clickTarget(g) ~= nil)))
						end
					end
				elseif CFG.trickUseUI and ready and (wd.uiFail or 0) >= 3 then
					-- the on-screen press was not taken in the last 3 houses and the remote counted every time:
					-- skip straight to the remote (it only goes out now, after the choice is READY)
					log("TRICK: skipping the on-screen press (failed 3 houses in a row) - using the remote")
				elseif CFG.trickUseUI and ready then
					local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
					-- the game took the press = the words went away, or the Outcome / HUD already moved
					local function taken() return outcome ~= nil or hudMoved() or not alive(lbl) end
					local tries = { "key" }
					if btn then tries[#tries + 1] = "button" end
					tries[#tries + 1] = "click"
					for _, kind in ipairs(tries) do
						local how
						if kind == "key" then
							tap(KEYS[keyN] or Enum.KeyCode.One, 0.08) -- number key (like "key 1" on the Dutchman)
							how = "key " .. keyN
						elseif kind == "button" then
							how = press(btn)
						else
							local okc, r = pcall(realClick, btn or lbl)
							how = (okc and r) and "mouse click" or "mouse click failed"
						end
						viaUI = true
						log(('%s: pressed on-screen "%s" via %s'):format(actName, btnText, how))
						-- 1.2s to see whether it was taken (v21 waited 4s per try, 12s in total, before the remote)
						local t1 = os.clock()
						while running and os.clock() - t1 < 1.2 and not taken() do task.wait(0.05) end
						if taken() then
							-- taken: give the game a few seconds to report the result
							local t3 = os.clock()
							while running and not outcome and not hudMoved() and os.clock() - t3 < 5 do task.wait(0.1) end
							if outcome or hudMoved() then
								log("OUTCOME " .. (outcome and fmt(outcome) or "(no event, the HUD counted it)"))
								outcome = outcome or table.pack("hud")
								got = got + 1
								counted = true
							end
							break
						end
					end
					if counted then
						wd.uiFail = 0
					else
						wd.uiFail = (wd.uiFail or 0) + 1
						log(("TRICK: the on-screen press was not taken (%d in a row) - using the remote"):format(wd.uiFail))
					end
				end

				for i = 1, counted and 0 or math.min(#cands, 3) do
					local c = cands[i]
					local okT, res = pcall(function()
						if fAct:IsA("RemoteFunction") then return fAct:InvokeServer({ voice = 2, npc = c }) end
						fAct:FireServer({ voice = 2, npc = c })
					end)
					log(("%s %s -> %s %s"):format(actName, c.Name, tostring(okT), fmt(res)))
					local t1 = os.clock()
					while running and not outcome and os.clock() - t1 < 5 and not hudMoved() do task.wait(0.15) end
					if outcome or hudMoved() then
						log("OUTCOME " .. (outcome and fmt(outcome) or "(no event, the HUD counted it)"))
						outcome = outcome or table.pack("hud")
						got = got + 1
						counted = true
						break
					end
				end
				if not counted then wd.note = "no Outcome / HUD"; log("TRICK: no Outcome and no HUD change on house " .. best.Name) end

				-- stay here until the NPC has closed the door; only then go to the next house.
				-- Done goes out once the door is closed (or after 4s if it is still open, in case the game
				-- only closes it on Done).
				local doneSent = false
				local function sendDone()
					if doneSent then return end
					doneSent = true
					if outcome and rDone then pcall(function() rDone:FireServer() end) end
				end
				-- after pressing the real button the game closes the door itself: no early Done, only a catch-up one
				local closed, secs = waitDoorClosed(bestDoor, baseV, baseTr, 2, outcome and 30 or 10, (not viaUI) and sendDone or nil)
				sendDone()
				if select(3, choiceBtn(pickTrick)) then log("TRICK: the Trick/Treat words are still on screen after this house") end
				log(("TRICK house %s: door %s after %.1fs"):format(best.Name, closed and "closed" or "still open, moving on", secs))
				task.wait(0.5)
			end
		end
	end)
	do
		local _, hz = hrpOf()
		if hz then pcall(function() hz:UnequipTools() end) end
	end
	c1:Disconnect()
	c2:Disconnect()
	if not ok then
		log("ERR trick " .. tostring(err))
		return false
	end
	return got >= need or isDone()
end

---------------------------------------------------------------- scan islands (หา goblin ตอนเข้าเซิฟใหม่ ไม่ต้องรอแจ้งเตือน)
-- ขอให้เกม stream พื้นที่รอบเกาะทีละเกาะ (ไม่ย้ายตัวละคร) แล้วดูว่า goblin โผล่ที่เกาะไหน
local scanning = false
local function scanIslands(manual)
	if scanning then return end
	if not manual and not CFG.scanOnJoin then return end -- ปุ่ม Scan islands ปิดอยู่
	scanning = true
	local found
	local ok, err = pcall(function()
		local cands, seenPos = {}, {}
		for _, isl in ipairs(ISLANDS) do
			local okI, cf = pcall(findIsland, isl)
			if okI and cf then
				local p = cf.Position
				local k = ("%d,%d"):format(math.floor(p.X / 50), math.floor(p.Z / 50))
				if not seenPos[k] then
					seenPos[k] = true
					cands[#cands + 1] = { name = isl[1], pos = p }
				end
			end
		end
		local h = hrpOf()
		if h then
			table.sort(cands, function(a, b)
				return (a.pos - h.Position).Magnitude < (b.pos - h.Position).Magnitude
			end)
		end
		log("SCAN islands: " .. #cands .. " spots")
		for i, c in ipairs(cands) do
			if not running then break end
			if not manual and not CFG.scanOnJoin then log("SCAN: stopped (toggle off)") break end
			setStatus(("scan %d/%d: %s"):format(i, #cands, c.name))
			pcall(function() lp:RequestStreamAroundAsync(c.pos, 4) end)
			task.wait(0.4)
			local gm, gd
			for _, m in ipairs(goblins()) do
				local st = state[m]
				if wantsModel(m) and not (st and st.done) and m:FindFirstChildWhichIsA("BasePart", true) then
					local d = (m:GetPivot().Position - c.pos).Magnitude
					if d < 700 and (not gd or d < gd) then gm, gd = m, d end
				end
			end
			if gm then
				local gp = gm:GetPivot().Position
				local bestC, bestD = c, math.huge
				for _, o in ipairs(cands) do
					local d = (Vector3.new(o.pos.X, 0, o.pos.Z) - Vector3.new(gp.X, 0, gp.Z)).Magnitude
					if d < bestD then bestC, bestD = o, d end
				end
				found = bestC
				log(("SCAN goblin at (%.0f, %.0f, %.0f) -> %s"):format(gp.X, gp.Y, gp.Z, bestC.name))
				break
			end
		end
	end)
	if not ok then log("ERR scan " .. tostring(err)) end
	if found then
		mem["island"] = { pos = found.pos, at = os.clock(), name = found.name }
		pendingWarp = { name = found.name, cf = CFrame.new(found.pos), at = os.clock() }
		hp("find", true, "scan " .. found.name)
	else
		log("SCAN: no goblins found on any known island")
		hp("find", false, "scan found nothing")
	end
	scanning = false
	setStatus("idle")
end

---------------------------------------------------------------- ESP
do
	local esp = {} -- goblin model -> { hl, bb, lbl }

	local function drop(m)
		local e = esp[m]
		if not e then return end
		esp[m] = nil
		pcall(function() e.hl:Destroy() end)
		pcall(function() e.bb:Destroy() end)
	end

	local function add(m)
		local hl = Instance.new("Highlight")
		hl.Adornee = m
		hl.FillColor = Color3.fromRGB(80, 255, 80)
		hl.FillTransparency = 0.4
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = gui
		local bb = Instance.new("BillboardGui")
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(180, 24)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.Parent = gui
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 14
		lbl.Parent = bb
		esp[m] = { hl = hl, bb = bb, lbl = lbl }
	end

	task.spawn(function()
		while running do
			pcall(function()
				local live = {}
				if CFG.esp then
					local hrp = hrpOf()
					for _, m in ipairs(goblins()) do
						live[m] = true
						if not esp[m] then add(m) end
						local e = esp[m]
						if not (e.bb.Adornee and e.bb.Adornee:IsDescendantOf(workspace)) then
							e.bb.Adornee = m:FindFirstChildWhichIsA("BasePart", true)
						end
						if hrp then
							local d = (m:GetPivot().Position - hrp.Position).Magnitude
							e.lbl.Text = ("%s %dm"):format(m.Name, math.floor(d))
						end
					end
				end
				for m in pairs(esp) do
					if not live[m] then drop(m) end
				end
			end)
			task.wait(0.3)
		end
		for m in pairs(esp) do drop(m) end
	end)
end

---------------------------------------------------------------- window (v11): one panel, 4 tabs
-- Header: status dot + title + Auto ON/OFF + fold. Tabs: Main | Warp | Goblins | Tools.
;(function()
	local UIS = game:GetService("UserInputService")
	local W, H, HEAD = 300, 348, 54

	local C = {
		bg    = Color3.fromRGB(18, 20, 26),
		card  = Color3.fromRGB(30, 33, 43),
		hover = Color3.fromRGB(44, 48, 60),
		line  = Color3.fromRGB(52, 56, 70),
		text  = Color3.fromRGB(235, 237, 242),
		sub   = Color3.fromRGB(140, 146, 160),
		on    = Color3.fromRGB(52, 199, 120),
		onTxt = Color3.fromRGB(8, 28, 18),
		off   = Color3.fromRGB(70, 74, 90),
		bad   = Color3.fromRGB(232, 96, 96),
	}

	---------------------------------------------------- small builders
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end
	local function round(o, r)
		mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
		return o
	end
	local function label(parent, text, size, color, font, xalign)
		return mk("TextLabel", {
			BackgroundTransparency = 1, Text = text, TextSize = size or 12,
			TextColor3 = color or C.text, Font = font or Enum.Font.GothamMedium,
			TextXAlignment = xalign or Enum.TextXAlignment.Left,
		}, parent)
	end
	local function button(parent, text, fn, fill)
		local b = mk("TextButton", {
			BackgroundColor3 = fill or C.card, TextColor3 = C.text, BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium, TextSize = 12, Text = text,
		}, parent)
		round(b, 8)
		b:SetAttribute("base", text)
		b.Activated:Connect(function() fn(b) end)
		return b
	end
	local function flash(b, msg) -- show feedback on a button for 1s
		b.Text = msg
		task.delay(1, function()
			if b.Parent then b.Text = b:GetAttribute("base") end
		end)
	end
	local function scroller(parent, y)
		return mk("ScrollingFrame", {
			Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -y),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		}, parent)
	end
	local function switchRow(parent, order, text, get, set)
		local row = mk("TextButton", {
			Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.card, BorderSizePixel = 0,
			Text = "", AutoButtonColor = false, LayoutOrder = order,
		}, parent)
		round(row, 8)
		local l = label(row, text, 12, C.text)
		l.Position = UDim2.fromOffset(10, 0)
		l.Size = UDim2.new(1, -64, 1, 0)
		local track = round(mk("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(38, 20), BorderSizePixel = 0,
		}, row), 10)
		local knob = round(mk("Frame", {
			Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		}, track), 7)
		local function paint()
			local v = get()
			track.BackgroundColor3 = v and C.on or C.off
			knob.Position = v and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
		end
		row.Activated:Connect(function() set(not get()); paint() end)
		paint()
	end

	---------------------------------------------------- window + header
	local win = mk("Frame", {
		Name = "win", Size = UDim2.fromOffset(W, H), Position = UDim2.fromOffset(10, 24),
		BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true,
	}, gui)
	round(win, 12)
	mk("UIStroke", { Color = C.line, Thickness = 1 }, win)

	-- small phones: shrink the whole window a bit instead of running off screen
	local cam = workspace.CurrentCamera
	if cam then
		local sc = (cam.ViewportSize.Y - 40) / (H + 24)
		if sc < 1 then mk("UIScale", { Scale = math.max(sc, 0.6) }, win) end
	end

	local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Active = true }, win)
	local dot = round(mk("Frame", {
		Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(12, 13),
		BackgroundColor3 = C.on, BorderSizePixel = 0,
	}, head), 4)
	local title = label(head, "Goblin Auto", 14, C.text, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(28, 0)
	title.Size = UDim2.fromOffset(90, 34)
	title.TextSize = 13

	-- countdown to the next goblin round (counts from the last spawn alert; "~" = estimated, an alert was missed)
	local cd = label(head, "next --:--", 11, C.sub, Enum.Font.Code, Enum.TextXAlignment.Right)
	cd.Position = UDim2.fromOffset(118, 0)
	cd.Size = UDim2.fromOffset(84, 34)
	task.spawn(function()
		while running do
			pcall(function()
				local si = spawnInfo
				if not si then
					cd.Text = "next --:--"
					cd.TextColor3 = C.sub
					return
				end
				local gap = CFG.spawnEvery
				local r, est = si.at + gap - os.clock(), false
				if r < 0 then est = true; r = r % gap end
				r = math.floor(r)
				cd.Text = ("next %s%d:%02d"):format(est and "~" or "", math.floor(r / 60), r % 60)
				cd.TextColor3 = est and C.sub or (r <= 20 and C.on or C.text)
			end)
			task.wait(0.25)
		end
	end)

	local autoBtn
	local function paintAuto()
		autoBtn.Text = enabled and "ON" or "OFF"
		autoBtn.BackgroundColor3 = enabled and C.on or C.off
		autoBtn.TextColor3 = enabled and C.onTxt or C.text
		dot.BackgroundColor3 = enabled and C.on or C.sub
	end
	autoBtn = button(head, "ON", function() enabled = not enabled; paintAuto() end, C.on)
	autoBtn.Font = Enum.Font.GothamBold
	autoBtn.Size = UDim2.fromOffset(52, 24)
	autoBtn.Position = UDim2.new(1, -94, 0, 5)
	genv.GoblinAPI = {
		get  = function() return enabled end,
		set  = function(v) enabled = v and true or false; paintAuto() end,
		busy = function() return statusLbl ~= nil and statusLbl.Text ~= "idle" end,
	}

	-- status line (the supervisor also reads statusLbl.Text)
	statusLbl = label(win, "idle", 11, C.sub, Enum.Font.Code)
	statusLbl.Position = UDim2.fromOffset(12, 34)
	statusLbl.Size = UDim2.new(1, -24, 0, 16)
	statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

	local body = mk("Frame", {
		Position = UDim2.fromOffset(0, HEAD), Size = UDim2.new(1, 0, 1, -HEAD), BackgroundTransparency = 1,
	}, win)

	local folded = false
	local foldBtn = button(head, "–", function(b)
		folded = not folded
		body.Visible = not folded
		win.Size = UDim2.fromOffset(W, folded and HEAD or H)
		b.Text = folded and "+" or "–"
	end, C.card)
	foldBtn.Font = Enum.Font.GothamBold
	foldBtn.TextSize = 14
	foldBtn.Size = UDim2.fromOffset(28, 24)
	foldBtn.Position = UDim2.new(1, -36, 0, 5)

	do -- drag by the header (mouse + touch)
		local dragging, dragStart, startPos
		head.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging, dragStart, startPos = true, i.Position, win.Position
				i.Changed:Connect(function()
					if i.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		conns[#conns + 1] = UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - dragStart
				win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
	end

	---------------------------------------------------- tabs
	local tabBar = mk("Frame", {
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1,
	}, body)
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.2, -4, 1, 0), CellPadding = UDim2.fromOffset(4, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	local content = mk("Frame", {
		Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 1, -44),
		BackgroundTransparency = 1, ClipsDescendants = true,
	}, body)

	local pages, tabs = {}, {}
	local function selectTab(name)
		for n, p in pairs(pages) do p.Visible = (n == name) end
		for n, b in pairs(tabs) do
			local on = (n == name)
			b.BackgroundTransparency = on and 0 or 1
			b.TextColor3 = on and C.text or C.sub
		end
	end
	local function addTab(name, text, order)
		local b = button(tabBar, text, function() selectTab(name) end, C.hover)
		b.LayoutOrder = order
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		tabs[name] = b
		local p = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
		pages[name] = p
		return p
	end
	local pMain = addTab("main", "Main", 1)
	local pWarp = addTab("warp", "Warp", 2)
	local pGob = addTab("gob", "Goblins", 3)
	local pTools = addTab("tools", "Tools", 4)
	local pHealth = addTab("health", "Health", 5)

	---------------------------------------------------- tab: Main (quest level + options)
	do
		local sc = scroller(pMain, 0)
		mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sc)

		local function section(text, order)
			local l = label(sc, text, 10, C.sub, Enum.Font.GothamBold)
			l.Size = UDim2.new(1, -8, 0, 14)
			l.LayoutOrder = order
		end

		section("QUEST LEVEL", 1)
		local grid = mk("Frame", { Size = UDim2.new(1, -8, 0, 62), BackgroundTransparency = 1, LayoutOrder = 2 }, sc)
		mk("UIGridLayout", {
			CellSize = UDim2.new(0.3333, -3, 0, 28), CellPadding = UDim2.fromOffset(4, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		for i, l in ipairs(DIFF) do
			local b
			local function paint()
				local v = CFG.levels[l]
				b.BackgroundColor3 = v and C.on or C.card
				b.TextColor3 = v and C.onTxt or C.text
			end
			b = button(grid, l:sub(1, 1):upper() .. l:sub(2), function()
				CFG.levels[l] = not CFG.levels[l]
				paint()
			end)
			b.LayoutOrder = i
			paint()
		end

		section("OPTIONS", 3)
		switchRow(sc, 4, "Talk to goblins", function() return CFG.talk end, function(v) CFG.talk = v end)
		switchRow(sc, 5, "Warp on spawn", function() return CFG.warpOnSpawn end, function(v) CFG.warpOnSpawn = v end)
		switchRow(sc, 6, "ESP + distance", function() return CFG.esp end, function(v) CFG.esp = v end)
		switchRow(sc, 7, "Scan islands", function() return CFG.scanOnJoin end, function(v)
			CFG.scanOnJoin = v
			if v and running and #fresh() == 0 then task.spawn(scanIslands) end -- เปิดแล้วไม่มี goblin ให้เห็น -> สแกนเลย
			if not v then setStatus("island scan OFF") end
		end)

		section("QUESTS  (OFF = skip)", 8)
		local function qrow(order, key, text)
			switchRow(sc, order, text, function() return CFG.quests[key] ~= false end,
				function(v) CFG.quests[key] = v end)
		end
		qrow(9, "chat", "Type in chat")
		qrow(10, "dance", "Dance")
		qrow(11, "jump", "Jump")
		qrow(12, "walk", "Walk")
		qrow(13, "guess", "Quiz / guess")
		qrow(14, "insult", "Insult Beatrix")
		qrow(15, "trick", "Trick-or-Treat")
		qrow(18, "perfect", "Perfect Catch")
		qrow(19, "fcatch", "Catch FischFright")

		section("TRICK-OR-TREAT CHOICE", 16)
		local tg = mk("Frame", { Size = UDim2.new(1, -8, 0, 30), BackgroundTransparency = 1, LayoutOrder = 17 }, sc)
		mk("UIGridLayout", {
			CellSize = UDim2.new(0.3333, -3, 0, 28), CellPadding = UDim2.fromOffset(4, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, tg)
		local tBtns = {}
		local function paintChoice()
			for k, b in pairs(tBtns) do
				local v = CFG.trickChoice == k
				b.BackgroundColor3 = v and C.on or C.card
				b.TextColor3 = v and C.onTxt or C.text
			end
		end
		for i, op in ipairs({ { "treat", "Treat" }, { "trick", "Trick" }, { "random", "Random" } }) do
			local b = button(tg, op[2], function()
				CFG.trickChoice = op[1]
				paintChoice()
			end)
			b.LayoutOrder = i
			tBtns[op[1]] = b
		end
		paintChoice()
	end

	---------------------------------------------------- tab: Warp (islands)
	do
		local hint = label(pWarp, "tap an island to teleport", 11, C.sub)
		hint.Size = UDim2.new(1, -92, 0, 24)
		local mark = button(pWarp, "Mark spot", function() markSpot() end, C.hover)
		mark.Size = UDim2.fromOffset(84, 24)
		mark.Position = UDim2.new(1, -90, 0, 0)

		local sc = scroller(pWarp, 30)
		mk("UIGridLayout", {
			CellSize = UDim2.new(0.5, -5, 0, 30), CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, sc)
		-- Halloween dimension (Caustic Hallow): sails with the Dutchman Captain, same code the quests use
		local sailing = false
		local hb = button(sc, "Halloween (sail)", function(b)
			if sailing then return end
			sailing = true
			b.Text = "Sailing..."
			task.spawn(function()
				setStatus("sail to Hallow")
				local ok, w = pcall(ensureHallow)
				setStatus("idle")
				if b.Parent then
					b.Text = (ok and typeof(w) == "Instance") and "Arrived" or "Failed - see report"
					task.delay(2, function()
						if b.Parent then b.Text = b:GetAttribute("base") end
					end)
				end
				sailing = false
			end)
		end, C.hover)
		hb.LayoutOrder = 0
		hb.TextSize = 11
		for i, isl in ipairs(ISLANDS) do
			local b = button(sc, isl[1], function() goIsland(isl) end)
			b.LayoutOrder = i
			b.TextSize = 11
			b.TextWrapped = true
		end
	end

	---------------------------------------------------- tab: Goblins (grouped by island, tap = warp)
	do
		local seenUid, seenCount, shown = {}, 0, {}
		local warping, rowModel, headModel = false, {}, {}

		local function warpIsland(name, p)
			if warping then return end
			warping = true
			task.spawn(function()
				setStatus("tp: " .. name)
				pcall(goTo, CFrame.new(p))
				setStatus("idle")
				warping = false
			end)
		end

		-- nearest known island point (flat distance); too far from everything = unknown
		local function islandOf(p)
			local bp, bn, bd
			local function try(name, v)
				local d = math.sqrt((v.X - p.X) ^ 2 + (v.Z - p.Z) ^ 2)
				if not bd or d < bd or (d == bd and #name > #bn) then bp, bn, bd = v, name, d end
			end
			for name, v in pairs(CFG.islandPos) do try(name, v) end
			for name, v in pairs(islandCache) do try(name, v) end
			if bd and bd <= 600 then return bn, bp end
			return nil
		end

		local count = label(pGob, "0 goblins", 11, C.sub)
		count.Size = UDim2.new(1, -92, 0, 24)
		local posBtn = button(pGob, "Copy POS", function(b)
			local t = {}
			for _, g in ipairs(shown) do
				t[#t + 1] = ('["%s"]=Vector3.new(%.1f,%.1f,%.1f),'):format(g.uid, g.p.X, g.p.Y, g.p.Z)
			end
			if setclipboard and #t > 0 then
				setclipboard(table.concat(t, "\n"))
				flash(b, "Copied!")
			else
				flash(b, "nothing")
			end
		end, C.hover)
		posBtn.Size = UDim2.fromOffset(84, 24)
		posBtn.Position = UDim2.new(1, -90, 0, 0)

		-- last "goblins have spawned at X!" alert; tap = fly to that island
		local banner = button(pGob, "no spawn alert yet", function()
			local si = spawnInfo
			if si and si.pos then warpIsland(si.name, si.pos) else task.spawn(scanIslands, true) end
		end, C.card)
		banner.Position = UDim2.fromOffset(0, 26)
		banner.Size = UDim2.new(1, -8, 0, 22)
		banner.TextSize = 11
		banner.TextXAlignment = Enum.TextXAlignment.Left
		banner.TextTruncate = Enum.TextTruncate.AtEnd
		mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, banner)

		local sc = scroller(pGob, 54)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sc)
		local empty = label(sc, "no goblins loaded", 11, C.sub, Enum.Font.Code)
		empty.Size = UDim2.new(1, -8, 0, 34)
		empty.TextWrapped = true
		empty.TextYAlignment = Enum.TextYAlignment.Top
		empty.Visible = false

		local heads, rows = {}, {}
		local function head(i) -- island header row (tap = fly to the island)
			if heads[i] then return heads[i] end
			local b = mk("TextButton", {
				Size = UDim2.new(1, -8, 0, 26), BackgroundColor3 = C.hover, BorderSizePixel = 0, Text = "",
			}, sc)
			round(b, 8)
			local l = label(b, "", 12, C.text, Enum.Font.GothamBold)
			l.Position = UDim2.fromOffset(10, 0)
			l.Size = UDim2.new(0.6, -10, 1, 0)
			l.TextTruncate = Enum.TextTruncate.AtEnd
			local r = label(b, "", 10, C.sub, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
			r.Position = UDim2.fromScale(0.6, 0)
			r.Size = UDim2.new(0.4, -10, 1, 0)
			b.Activated:Connect(function()
				local hm = headModel[b]
				if hm then warpIsland(hm.name, hm.pos) end
			end)
			heads[i] = { b = b, l = l, r = r }
			return heads[i]
		end
		local function row(i) -- goblin row (tap = warp to it)
			if rows[i] then return rows[i] end
			local b = mk("TextButton", {
				Size = UDim2.new(1, -8, 0, 30), BackgroundColor3 = C.card, BorderSizePixel = 0, Text = "",
			}, sc)
			round(b, 8)
			local l = label(b, "", 12, C.text)
			l.Position = UDim2.fromOffset(16, 0)
			l.Size = UDim2.new(0.5, -16, 1, 0)
			local r = label(b, "", 11, C.text, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			r.Position = UDim2.fromScale(0.5, 0)
			r.Size = UDim2.new(0.5, -10, 1, 0)
			b.Activated:Connect(function()
				local g = rowModel[b]
				if not g or warping then return end
				warping = true
				task.spawn(function()
					local ok, res = pcall(tpTo, g.m)
					if not (ok and res) then -- model not streamed in: land on the saved position
						local h = hrpOf()
						if h then
							h.Anchored = false
							h.CFrame = CFrame.new(g.p + Vector3.new(0, 3, 0))
							h.AssemblyLinearVelocity = Vector3.zero
						end
					end
					log("MANUAL WARP -> " .. g.m.Name .. " " .. g.uid)
					warping = false
				end)
			end)
			rows[i] = { b = b, l = l, r = r }
			return rows[i]
		end

		local function stat(m)
			local s = state[m]
			if not s then return "new" end
			if s.done then return "done" end
			local cd = (s.coolUntil or 0) - os.clock()
			if cd > 0 then return ("rest %ds"):format(math.floor(cd)) end
			if s.claim then return "claim" end
			if s.accepted then return "accepted" end
			if s.tries >= MAXTRY then return "failed" end
			return "try " .. s.tries
		end
		local function statColor(s)
			if s == "done" then return C.sub end
			if s == "claim" or s == "accepted" then return C.on end
			if s == "failed" or s:sub(1, 4) == "rest" then return C.bad end
			return C.text
		end

		task.spawn(function()
			while running do
				pcall(function()
					local hrp = hrpOf()
					local list = {}
					for _, m in ipairs(goblins()) do
						local p = m:GetPivot().Position
						local uid = tostring(m:GetAttribute("UID") or m.Name)
						if not seenUid[uid] then seenCount = seenCount + 1; seenUid[uid] = seenCount end
						list[#list + 1] = { m = m, p = p, uid = uid, o = seenUid[uid],
							d = hrp and (p - hrp.Position).Magnitude or 0 }
					end
					table.sort(list, function(a, b) return a.o < b.o end) -- first-seen order: rows don't jump while walking
					shown = list

					-- group by island (group order = first time one of its goblins was seen)
					local groups, order = {}, {}
					for _, g in ipairs(list) do
						local name, ipos = islandOf(g.p)
						local key = name or "?"
						local gr = groups[key]
						if not gr then
							gr = { name = name or "Unknown island", pos = ipos, items = {}, first = g.o }
							groups[key] = gr
							order[#order + 1] = gr
						end
						gr.items[#gr.items + 1] = g
					end
					table.sort(order, function(a, b) return a.first < b.first end)

					local ord, hi, ri = 0, 0, 0
					for _, gr in ipairs(order) do
						hi = hi + 1
						local h = head(hi)
						ord = ord + 1
						h.b.LayoutOrder = ord
						h.l.Text = gr.name
						h.r.Text = ("%d goblin%s"):format(#gr.items, #gr.items == 1 and "" or "s")
						h.b.Visible = true
						headModel[h.b] = gr.pos and { name = gr.name, pos = gr.pos } or nil
						for idx, g in ipairs(gr.items) do
							if ri < 20 then
								ri = ri + 1
								local rw = row(ri)
								ord = ord + 1
								rw.b.LayoutOrder = ord
								local far = not g.m:FindFirstChildWhichIsA("BasePart", true)
								local s = state[g.m]
								local st = stat(g.m)
								rw.l.Text = ("%d.  %dm%s"):format(idx, math.floor(g.d), far and "  far" or "")
								rw.l.TextTransparency = (s and s.done) and 0.5 or 0
								rw.r.Text = st
								rw.r.TextColor3 = statColor(st)
								rw.b.Visible = true
								rowModel[rw.b] = g
							end
						end
					end
					for i = hi + 1, #heads do
						heads[i].b.Visible = false
						headModel[heads[i].b] = nil
					end
					for i = ri + 1, #rows do
						rows[i].b.Visible = false
						rowModel[rows[i].b] = nil
					end

					local si = spawnInfo
					if si then
						local age = math.floor(os.clock() - si.at)
						local ago = age < 90 and (age .. "s") or (math.floor(age / 60) .. "m")
						banner.Text = ("last spawn: %s · %s ago"):format(si.name, ago)
						banner.TextColor3 = si.pos and C.on or C.sub
					else
						banner.Text = "no alert yet · tap = scan islands"
						banner.TextColor3 = C.sub
					end
					empty.Text = (#list == 0 and si and si.pos)
						and "none streamed in yet - tap the banner to fly to the island"
						or "no goblins loaded"
					empty.Visible = #list == 0
					count.Text = ("%d goblins · %d islands"):format(#list, #order)
				end)
				task.wait(0.5)
			end
		end)
	end

	---------------------------------------------------- tab: Tools (repair + debug)
	do
		local grid = mk("Frame", { Size = UDim2.new(1, 0, 0, 114), BackgroundTransparency = 1 }, pTools)
		mk("UIGridLayout", {
			CellSize = UDim2.new(0.5, -2, 0, 34), CellPadding = UDim2.fromOffset(4, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		local function tool(order, text, fn, fill)
			local b = button(grid, text, fn, fill)
			b.LayoutOrder = order
			if fill == C.on then b.TextColor3 = C.onTxt end
			return b
		end
		tool(1, "Fix now", function(b)
			if recoverNow then task.spawn(recoverNow, "manual (Fix now button)") end
			flash(b, "Running...")
		end, C.on)
		tool(2, "Copy report", function(b)
			if setclipboard then
				local tail, n = {}, 0 -- เอาเฉพาะท้าย log (ล่าสุด) ไม่งั้นรายงานยาวจะโดนตัดตรงท้าย
				for i = #lines, 1, -1 do
					n = n + #lines[i] + 1
					if n > 8000 then break end
					table.insert(tail, 1, lines[i])
				end
				setclipboard(table.concat(tail, "\n"))
				flash(b, "Copied!")
			else
				warn("executor has no setclipboard")
				flash(b, "no clipboard")
			end
		end)
		tool(3, "Clear log", function(b)
			table.clear(lines)
			table.clear(seen)
			flash(b, "Cleared")
		end)
		tool(4, "Dump UI", function(b) dumpUI(); flash(b, "In report") end)
		tool(5, "Dump islands", function(b) dumpIslands(); flash(b, "In report") end)
		local sb = tool(6, "Stats", function(b)
			log("STATS " .. statsLine())
			flash(b, "In report")
		end)
		sb.TextSize = 11
		task.spawn(function()
			while running do
				pcall(function()
					sb.Text = ("ok %d | skip %d | die %d"):format(sumOf(stats.done), sumOf(stats.skip), stats.died)
				end)
				task.wait(1)
			end
		end)

		local tip = label(pTools, "Stuck? Open the dialog by hand, press Dump UI, then Copy report.", 10, C.sub)
		tip.Position = UDim2.fromOffset(2, 124)
		tip.Size = UDim2.new(1, -4, 0, 30)
		tip.TextWrapped = true
		tip.TextYAlignment = Enum.TextYAlignment.Top
	end

	---------------------------------------------------- tab: Health
	do
		local YEL = Color3.fromRGB(240, 190, 70)
		local col = { none = C.off, good = C.on, warn = YEL, bad = C.bad }
		local rank = { none = 0, good = 1, warn = 2, bad = 3 }
		local function stateOf(e)
			local st = hpState(e)
			if st == "bad" and os.clock() - e.at > 600 then st = "warn" end -- พลาดนานแล้ว ไม่ต้องแดงค้าง
			return st
		end

		local live = label(pHealth, "idle", 11, C.sub, Enum.Font.Code)
		live.Size = UDim2.new(1, -8, 0, 16)
		live.TextTruncate = Enum.TextTruncate.AtEnd

		local sumL = label(pHealth, "", 10, C.sub, Enum.Font.Code)
		sumL.Position = UDim2.fromOffset(0, 18)
		sumL.Size = UDim2.new(1, -92, 0, 18)
		sumL.TextTruncate = Enum.TextTruncate.AtEnd

		local cb = button(pHealth, "Copy health", function(b)
			local t = { "HEALTH | " .. live.Text, sumL.Text }
			for _, k in ipairs(HP_ORDER) do
				local e = HP[k]
				if e then
					t[#t + 1] = ("%s | %s | ok %d fail %d | %s | lastfail: %s"):format(
						k, hpState(e), e.ok, e.bad, tostring(e.note or "-"), tostring(e.failNote or "-"))
				end
			end
			if setclipboard then
				setclipboard(table.concat(t, "\n"))
				flash(b, "Copied!")
			else
				flash(b, "no clipboard")
			end
		end, C.hover)
		cb.Size = UDim2.fromOffset(84, 20)
		cb.Position = UDim2.new(1, -90, 0, 17)
		cb.TextSize = 11

		local sc = scroller(pHealth, 40)
		mk("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sc)
		local rows = {}
		for i, key in ipairs(HP_ORDER) do
			local r = mk("Frame", {
				Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.card,
				BorderSizePixel = 0, LayoutOrder = i,
			}, sc)
			round(r, 8)
			local d = round(mk("Frame", {
				Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(9, 7), BorderSizePixel = 0,
			}, r), 4)
			local nm = label(r, HP_NAME[key], 12, C.text)
			nm.Position = UDim2.fromOffset(24, 0)
			nm.Size = UDim2.new(0.5, -24, 0, 22)
			local ct = label(r, "-", 11, C.sub, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			ct.Position = UDim2.fromScale(0.5, 0)
			ct.Size = UDim2.new(0.5, -8, 0, 22)
			local nt = label(r, "", 10, C.sub, Enum.Font.Code)
			nt.Position = UDim2.fromOffset(24, 19)
			nt.Size = UDim2.new(1, -32, 0, 13)
			nt.TextTruncate = Enum.TextTruncate.AtEnd
			rows[key] = { d = d, ct = ct, nt = nt }
		end

		local lastKey, lastMove = nil, os.clock()
		task.spawn(function()
			while running do
				pcall(function()
					local now = os.clock()
					-- บรรทัดสด: ขั้นตอน + ความคืบหน้าจาก HUD + เวลาที่นิ่ง
					local step = statusLbl and statusLbl.Text or "?"
					local prog
					if working and wd.cur then
						local a, b
						if wd.cur == "trick" then a, b = hudProgress("trick", "treat") elseif wd.cur == "perfect" or wd.cur == "fcatch" then a, b = wd.fishHud(wd.cur) else a, b = hudProgress(wd.cur) end
						if a then prog = a .. "/" .. b end
					end
					local key = step .. "|" .. tostring(prog)
					if key ~= lastKey then lastKey, lastMove = key, now end
					local still, hb = now - lastMove, now - wd.beat
					local busy = enabled and step ~= "idle"
					local lc, txt = C.sub, "idle"
					if not enabled then
						txt = "paused (Auto OFF)"
					elseif busy then
						txt = step .. (prog and (" " .. prog) or "") .. (" | still %ds"):format(math.floor(still))
						if hb > 20 then txt = txt .. (" | hb %d/%d"):format(math.floor(hb), wd.limit) end
						lc = still > 25 and C.bad or (still > 10 and YEL or C.on)
					end
					live.Text, live.TextColor3 = txt, lc

					sumL.Text = ("HEAL %d · died %d · ok %d · skip %d"):format(
						HP.heal and HP.heal.bad or 0, stats.died, sumOf(stats.done), sumOf(stats.skip))

					-- ตารางรายระบบ
					local worst = "none"
					for _, k in ipairs(HP_ORDER) do
						local e = HP[k]
						local st = stateOf(e)
						if rank[st] > rank[worst] then worst = st end
						if pHealth.Visible then
							local r = rows[k]
							r.d.BackgroundColor3 = col[st]
							if e then
								r.ct.Text = ("%d ok · %d fail"):format(e.ok, e.bad)
								local a = math.floor(now - e.at)
								local t = ("%s · %s ago"):format(tostring(e.note or "-"),
									a < 90 and (a .. "s") or (math.floor(a / 60) .. "m"))
								if e.tn > 0 then t = t .. (" · avg %.0fs"):format(e.tsum / e.tn) end
								local dg = hpDiag(k, e)
								r.nt.Text = dg and ("! " .. dg .. " | " .. t) or t
								r.nt.TextColor3 = st == "bad" and C.bad or C.sub
							else
								r.ct.Text, r.nt.Text = "-", ""
							end
						end
					end

					-- จุดที่หัวหน้าต่าง = สุขภาพรวม (เห็นได้ทุกแท็บ)
					local dc = col[worst == "none" and "good" or worst]
					if busy and still > 25 then dc = C.bad elseif busy and still > 10 and dc == C.on then dc = YEL end
					dot.BackgroundColor3 = enabled and dc or C.sub
				end)
				task.wait(0.5)
			end
		end)
	end

	selectTab("main")
	paintAuto()
end)()


genv.GoblinAutoStop = function()
	genv.GoblinAPI = nil
	pcall(function() local api = genv.AutoFishAPI if api then api.set(false) end end)
	running = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local h = hrpOf()
	if h then pcall(function() h.Anchored = false end) end
	gui:Destroy()
end

---------------------------------------------------------------- main loop + self-heal
local loopThread
local heal = { fails = 0, lastFix = 0 } -- consecutive repairs that did not lead to progress

local function activity() lastWork = os.clock() end

-- ปลดทุกอย่างที่อาจค้าง: anchor, bind เดิน, emote, dialog, สถานะตัวละคร
local function unstick(why)
	log("HEAL unstick: " .. why)
	pcall(function() local api = genv.AutoFishAPI if api then api.set(false) end end)
	pcall(function() RunService:UnbindFromRenderStep("GA_walk") end)
	local h, hum = hrpOf()
	if h then pcall(function() h.Anchored = false end) end
	if hum then
		pcall(function() hum:Move(Vector3.zero, false) end)
		pcall(function() hum.PlatformStand = false end)
		pcall(function() hum.Sit = false end)
	end
	dialogRoot = nil
	pcall(closeDialog)
	pcall(cancelEmote)
end

local function waitAlive(maxT)
	local t0 = os.clock()
	while os.clock() - t0 < (maxT or 20) do
		task.wait(0.5)
		touch(60)
		local h, hum = hrpOf()
		if h and hum and hum.Health > 0 then
			task.wait(2.5) -- ให้ตัวละครโหลดนิ่งก่อน
			return true
		end
	end
	return false
end

local function refundTries()
	for _, st in pairs(state) do
		if not st.done then
			st.tries = 0
			st.cool = nil
		end
	end
end

-- stand on ground that is known to exist (Moosewood) when stuck in geometry / out of the world
local function safeTeleport()
	local p = CFG.islandPos["Moosewood"]
	if not p then return end
	pcall(goTo, CFrame.new(p))
	local h = hrpOf()
	if h then pcall(function() h.Anchored = false end) end
end

-- goblin failed this try; after MAXTRY tries it rests for a while (longer each time)
local function noteFail(s)
	bump(stats.fail, s.obj and s.obj.kind)
	s.at = os.clock()
	if s.tries >= MAXTRY then
		s.strikes = (s.strikes or 0) + 1
		s.cool = math.min(CFG.failCool * 2 ^ (s.strikes - 1), 300)
		log(("GIVE UP on this goblin for %ds (strike %d) - going to look for others"):format(
			math.floor(s.cool), s.strikes))
	end
end

-- วาร์ปไปเกาะที่แจ้งเตือนบอก แล้วรอให้ goblin stream เข้า (ใช้ goTo ของส่วน UI)
local function warpToSpawn(pw)
	mem["island"] = { pos = pw.cf.Position, at = os.clock(), name = pw.name }
	setStatus("warp: " .. pw.name)
	log("WARP -> " .. pw.name)
	if not goTo(pw.cf) then return false end
	local t0 = os.clock()
	while running and os.clock() - t0 < CFG.arriveWait do
		task.wait(0.15)
		touch(60)
		if #fresh() > 0 then hp("warp", true, pw.name, os.clock() - pw.at) return true end
	end
	log("WARP: no goblins loaded near " .. pw.name)
	hp("warp", false, "no goblins near " .. pw.name)
	return false
end

local retLast, retStrike, retBlock = 0, 0, 0

task.spawn(function() -- จำพิกัดไว้ตลอด โมเดลหายตอน stream ออก แต่พิกัดยังอยู่
	while running do
		pcall(function()
			for _, m in ipairs(goblins()) do
				local uid = tostring(m:GetAttribute("UID") or m.Name)
				local s = state[m]
				if (s and s.done) or not wantsModel(m) then
					mem[uid] = nil
				else
					mem[uid] = { pos = m:GetPivot().Position, at = os.clock(), name = m.Name }
				end
			end
		end)
		task.wait(0.5)
	end
end)

conns[#conns + 1] = lp.CharacterAdded:Connect(function()
	needReturn = os.clock()
	if os.clock() - retLast < 20 then -- ตายซ้ำทันทีหลังวาปกลับ: กันลูปตาย
		retStrike = retStrike + 1
		if retStrike >= 3 then
			retStrike, retBlock = 0, os.clock() + 90
			log("RETURN: died 3x within 20s of warping - pausing returns for 90s")
		end
	else
		retStrike = 0
	end
end)

local function returnToGoblins()
	if not needReturn then return false end
	local age = os.clock() - needReturn
	needReturn = false
	if not CFG.returnOnDeath or age > 180 then return false end
	if os.clock() < retBlock then
		log("RETURN paused")
		return false
	end

	local bestK, best
	for k, e in pairs(mem) do
		if os.clock() - e.at > CFG.returnWindow then
			mem[k] = nil
		elseif not best or e.at > best.at then
			bestK, best = k, e
		end
	end
	if not best then return false end
	if not waitAlive(30) then return false end

	local h = hrpOf()
	if h and (h.Position - best.pos).Magnitude < 60 then return true end -- อยู่ใกล้แล้ว

	setStatus("return: " .. tostring(best.name))
	log(("RETURN after death -> %s (%.0f, %.0f, %.0f)"):format(
		tostring(best.name), best.pos.X, best.pos.Y, best.pos.Z))
	retLast = os.clock()
	working = true
	activity()
	touch(90)
	local ok, err = pcall(goTo, CFrame.new(best.pos))
	if not ok then log("ERR return " .. tostring(err)) end

	local got, t0 = false, os.clock()
	while running and os.clock() - t0 < 6 do -- รอ goblin stream เข้า
		task.wait(0.2)
		touch(60)
		if #fresh() > 0 then got = true break end
	end
	working = false
	activity()
	local hh = hrpOf()
	if hh then hh.Anchored = false end
	if not got then
		log("RETURN: no goblins loaded here - dropping this spot")
		mem[bestK] = nil
	end
	return got
end

-- ตายแล้ว: เควสที่รับค้างไว้ (ยังไม่ได้ส่ง) ให้กลับไปคุยกับ goblin ใหม่ทุกตัว เพราะเควสอาจถูกรีเซ็ต
-- (acceptAt เดิมยังอยู่ ลำดับ "รับมานานสุดก่อน" ไม่เปลี่ยน)
local function reaccept()
	for _, st in pairs(state) do
		if st.accepted and not st.claim and not st.done then st.accepted = false end
	end
end

local function startCool(s, name, why)
	s.coolStrikes = (s.coolStrikes or 0) + 1
	local secs = math.min(CFG.acceptCool * 2 ^ (s.coolStrikes - 1), 300)
	s.coolUntil = os.clock() + secs
	log(("COOLDOWN %s %ds (%s) - going to other goblins"):format(name, math.floor(secs), why))
	pcall(closeDialog)
end

-- รับเควสไม่สำเร็จ 1 ครั้ง: ครบ CFG.acceptFailMax -> พักตัวนี้
local function acceptFailed(s, name, why)
	hp("accept", false, name .. ": " .. why)
	s.accFails = (s.accFails or 0) + 1
	log(("ACCEPT FAIL %s %d/%d (%s)"):format(name, s.accFails, CFG.acceptFailMax, why))
	if s.accFails >= CFG.acceptFailMax then
		s.accFails = 0
		startCool(s, name, "accept failed " .. CFG.acceptFailMax .. "x")
	end
end

-- รัน handleGoblin 1 ตัว + จัดการผล phase = "accept" | "do" | nil
local function runOne(m, s, phase)
	local h0, hum0 = hrpOf()
	if not h0 or not hum0 or hum0.Health <= 0 then waitAlive(25) return false end -- ยังตายอยู่: รอเกิดก่อน
	s.tries = s.tries + 1
	s.at = os.clock()
	working = true
	activity()
	lastDied = false
	touch(90)
	local char0 = lp.Character
	local ok, res = pcall(handleGoblin, m, s, phase)
	wd.cur = nil
	local hz = hrpOf()
	if hz then hz.Anchored = false end
	working = false
	activity()
	local acceptStage = phase == "accept" or (phase == nil and not s.obj) -- พลาดก่อนอ่านเควสได้ = พลาดตอนรับ
	local died = lastDied or lp.Character ~= char0 or (hum0 ~= nil and hum0.Health <= 0)
	if died then
		lastDied = false
		stats.died = stats.died + 1
		hp("died", false, m.Name)
		s.tries = math.max(0, s.tries - 1) -- ตายไม่นับเป็นความพยายามที่เสีย
		reaccept()
		s.deaths = (s.deaths or 0) + 1
		log(("DIED (%d) on %s - will re-talk to the goblins after respawn"):format(s.deaths, m.Name))
		if s.deaths >= CFG.deathCoolAfter then
			s.deaths = 0
			startCool(s, m.Name, "died " .. CFG.deathCoolAfter .. "x here")
		end
		waitAlive(25)
		pcall(returnToGoblins)
	elseif not ok then
		log("ERR " .. tostring(res))
		hp(acceptStage and "accept" or (s.obj and s.obj.kind) or "talk", false, tostring(res):sub(1, 50))
		unstick("error in handleGoblin")
		if acceptStage then
			s.tries = math.max(0, s.tries - 1)
			acceptFailed(s, m.Name, "error")
		else
			noteFail(s)
		end
	elseif res == "accepted" then
		s.tries = 0 -- รับสำเร็จ = ไม่นับเป็นพยายามที่เสีย
		s.accFails, s.coolUntil = 0, nil
		s.at = os.clock()
		heal.fails = 0
	elseif res then
		s.done = true -- done OR skipped (a quest we cannot do): either way, move on
		s.at = os.clock()
		s.deaths, s.coolStrikes = 0, 0
		heal.fails = 0
	elseif acceptStage then
		s.tries = math.max(0, s.tries - 1) -- นับด้วย accFails แทน
		acceptFailed(s, m.Name, "talk/accept failed")
	else
		noteFail(s)
	end
	return ok and res
end

-- finished quests that were not handed in (goblin out of range): go back before anything else, so a new
-- spawn alert cannot pull us away. Each goblin gets 3 tries and 14 min (the quest lasts ~15).
wd.serveOwed = function()
	if not CFG.talk then return end
	local h, hum = hrpOf()
	if not h or not hum or hum.Health <= 0 then return end
	local best
	for k, e in pairs(wd.owed) do
		if os.clock() - e.at > 840 or (e.tries or 0) >= 3 then
			wd.owed[k] = nil
		elseif not best or e.at < best.at then
			best = e
			best.uid = k
		end
	end
	if not best then return end
	best.tries = (best.tries or 0) + 1
	working = true
	activity()
	touch(90)
	local g = wd.reacquire(best.uid, best.name, best.pos)
	if g then
		local st = state[g]
		if not (st and st.claim) then
			state[g] = { pos = g:GetPivot().Position, tries = 0, done = false, claim = true, at = os.clock(), strikes = 0 }
		end
		pcall(turnIn, g)
	end
	working = false
	activity()
end

local function tickOnce()
	pcall(returnToGoblins)
	pcall(wd.serveOwed)
	local list = fresh()
	-- เพิ่งมีแจ้งเตือน spawn และไม่มี goblin ค้างให้ทำแล้ว -> ไปเกาะนั้น
	if #list == 0 and pendingWarp then
		local pw = pendingWarp
		pendingWarp = nil
		if os.clock() - pw.at < 120 and CFG.talk and #levelOrder() > 0 then
			working = true
			activity()
			touch(90)
			local ok, err = pcall(warpToSpawn, pw)
			working = false
			activity()
			if not ok then log("ERR warp " .. tostring(err)) end
			local h = hrpOf()
			if h then h.Anchored = false end
			list = fresh()
		end
	end

	local hrp = hrpOf()
	if hrp then
		pcall(table.sort, list, function(x, y)
			return (x:GetPivot().Position - hrp.Position).Magnitude
				< (y:GetPivot().Position - hrp.Position).Magnitude
		end)
	end

	if CFG.acceptFirst then
		-- รอบ 1: รับเควสให้ครบก่อน (ตัวใกล้สุดก่อน) ยังไม่ทำ
		local acc = 0
		for _, m in ipairs(goblins()) do
			local s = state[m]
			if s and s.accepted and not s.done and s.tries < MAXTRY then acc = acc + 1 end
		end
		for _, m in ipairs(list) do
			if not running or not enabled or acc >= CFG.acceptBatch then break end
			if m.Parent then
				local okS, s = pcall(stOf, m)
				if okS and not s.done and not s.accepted and s.tries < MAXTRY then
					if runOne(m, s, "accept") == "accepted" then acc = acc + 1 end
				end
			end
		end
		-- รอบ 2: ทำเควสที่รับไว้ เรียงจากรับมานานสุด -> ใหม่สุด (ทำเสร็จ -> กลับไปส่ง -> ตัวถัดไป)
		local queue = {}
		for _, m in ipairs(goblins()) do
			local okS, s = pcall(stOf, m)
			if okS and s.accepted and s.obj and not s.done and s.tries < MAXTRY then
				queue[#queue + 1] = m
			end
		end
		table.sort(queue, function(x, y) return state[x].acceptAt < state[y].acceptAt end)
		for _, m in ipairs(queue) do
			if not running or not enabled then break end
			local s = state[m]
			if m.Parent and s and s.accepted and not s.done and s.tries < MAXTRY then
				runOne(m, s, "do")
			end
		end
	else
		local first, last = {}, {}
		for _, m in ipairs(list) do
			local o = state[m]
			if CFG.fishLast and o and o.fishLater then last[#last + 1] = m else first[#first + 1] = m end
		end
		for _, m in ipairs(first) do -- แบบเดิม
			if not running or not enabled then break end
			if m.Parent then
				local okS, s = pcall(stOf, m)
				if okS and not s.done and s.tries < MAXTRY then runOne(m, s, nil) end
			end
		end
		for _, m in ipairs(last) do -- ตกปลาท้ายสุด
			if not running or not enabled then break end
			local more = false
			for _, g in ipairs(fresh()) do
				local o = state[g]
				if not (o and o.fishLater) then more = true break end
			end
			local o0 = state[m]
			local late = o0 and os.clock() - (o0.acceptAt or 0) > CFG.fishLaterMax
			if more and not late then break end
			if m.Parent then
				local okS, s = pcall(stOf, m)
				if okS and not s.done and s.tries < MAXTRY then
					runOne(m, s, s.accepted and "do" or nil)
				end
			end
		end
	end
	setStatus("idle")
end

local function startLoop()
	if loopThread then pcall(task.cancel, loopThread) end
	touch(60)
	working = false
	activity()
	loopThread = task.spawn(function()
		while running do
			local h, hum = hrpOf()
			if enabled and h and hum and hum.Health > 0 then
				local ok, err = pcall(tickOnce)
				if not ok then
					log("ERR loop " .. tostring(err))
					working = false
					unstick("loop error")
				end
			end
			task.wait(CFG.scanDelay)
		end
	end)
end

-- full repair, escalating: restart loop -> + teleport to safe ground -> + respawn character
local function recover(why)
	local now = os.clock()
	if now - heal.lastFix > 300 then heal.fails = 0 end
	heal.lastFix = now
	heal.fails = heal.fails + 1
	log(("HEAL #%d: %s"):format(heal.fails, why))
	hp("heal", false, why)
	if loopThread then pcall(task.cancel, loopThread) end
	working = false
	unstick(why)
	refundTries()
	if heal.fails >= 2 then pcall(safeTeleport) end
	if CFG.hardResetAfter > 0 and heal.fails >= CFG.hardResetAfter then
		heal.fails = 0
		log("HEAL hard reset: respawning the character")
		local _, hum = hrpOf()
		if hum then pcall(function() hum.Health = 0 end) end
		waitAlive(30)
	end
	startLoop()
end
recoverNow = recover

conns[#conns + 1] = lp.CharacterAdded:Connect(function()
	dialogRoot = nil
	task.delay(3, function()
		if running and not working then pcall(unstick, "respawned") end
	end)
end)

startLoop()

-- supervisor: runs on its own thread, so it still works when the main loop is hung or dead
task.spawn(function()
	local anchoredSince, seatedSince, swimSince, dryCF, swimFix = nil, nil, nil, nil, 0
	while running do
		task.wait(2)
		if CFG.watchdog and enabled then
			local ok, err = pcall(function()
				local now = os.clock()

				-- 1) loop thread is dead
				if loopThread ~= nil and coroutine.status(loopThread) == "dead" then
					recover("loop thread died")
					return
				end

				-- no character / dead: the game is respawning us, that is not a hang
				local h, hum = hrpOf()
				if not h or not hum or hum.Health <= 0 then
					touch(60)
					anchoredSince, seatedSince = nil, nil
					return
				end

				-- 2) loop is alive but has not reported in for too long
				if now - wd.beat > wd.limit then
					recover(("loop hung %ds at: %s"):format(math.floor(now - wd.beat),
						statusLbl and statusLbl.Text or "?"))
					return
				end

				-- 3) fell out of the world
				if h.Position.Y < -50 then
					recover("fell out of the world")
					return
				end

				-- 4) frozen / sitting / ragdolled for too long
				if h.Anchored then
					anchoredSince = anchoredSince or now
					if now - anchoredSince > 15 then
						h.Anchored = false
						anchoredSince = nil
						log("HEAL: character was frozen (anchored) for 15s -> released")
					end
				else
					anchoredSince = nil
				end
				if hum.PlatformStand or hum.Sit then
					seatedSince = seatedSince or now
					if now - seatedSince > 6 then
						hum.PlatformStand = false
						hum.Sit = false
						hum.Jump = true
						seatedSince = nil
						log("HEAL: character was sitting / ragdolled -> stood up")
					end
				else
					seatedSince = nil
				end

				-- 5) ลอยอยู่ในน้ำนานเกิน 6 วิ: กลับจุดบกล่าสุด (ไม่หายค่อยไป Moosewood)
				if hum:GetState() == Enum.HumanoidStateType.Swimming
					or hum.FloorMaterial == Enum.Material.Water then
					swimSince = swimSince or now
					if now - swimSince > 6 then
						swimSince = now
						swimFix = swimFix + 1
						if dryCF and swimFix <= 2 then
							h.CFrame = dryCF + Vector3.new(0, 3, 0)
							h.AssemblyLinearVelocity = Vector3.zero
							log("HEAL: stuck swimming -> last dry spot")
						else
							swimFix = 0
							log("HEAL: stuck swimming -> Moosewood")
							pcall(safeTeleport)
						end
					end
				else
					swimSince = nil
					if hum.FloorMaterial ~= Enum.Material.Air
						and hum.FloorMaterial ~= Enum.Material.Water then
						dryCF, swimFix = h.CFrame, 0
					end
				end

			end)
			if not ok then log("ERR supervisor " .. tostring(err)) end
		end
	end
end)


do
	local qn = {}
	for _, r in ipairs(net and net:GetChildren() or {}) do
		if r.Name:find("QuestTrigger", 1, true) then qn[#qn + 1] = r.Name end
	end
	log("QUEST REMOTES: " .. table.concat(qn, ", "))
end
do
	local names = {}
	for _, root in ipairs({ RS:FindFirstChild("events"), net }) do
		if root then
			for _, r in ipairs(root:GetChildren()) do
				if r.Name:lower():find("emote", 1, true) then names[#names + 1] = r:GetFullName() end
			end
		end
	end
	log("EMOTE REMOTES: " .. table.concat(names, ", "))
end
---------------------------------------------------------------- spawn notification -> pendingWarp (พิกัดเกาะ + ค้นหา = ของ goblin_8)
do
	-- findCoords ของ goblin_8: ชื่อตรง -> ชื่อใกล้เคียง -> ค้นชื่อใน world.map (จำผลไว้) ใช้ตาราง CFG.islandPos
	local function findCoords(name)
		if CFG.islandPos[name] then return CFG.islandPos[name] end
		local ln = name:lower()
		for k, v in pairs(CFG.islandPos) do
			local lk = k:lower()
			if lk:find(ln, 1, true) or ln:find(lk, 1, true) then return v end
		end
		-- เกาะที่ไม่มีใน CFG.islandPos แต่มีในปุ่มวาป (ISLANDS): ใช้ findIsland ตัวเดียวกับปุ่ม
		for _, isl in ipairs(ISLANDS) do
			local hit = #ln >= 4 and (ln:find(isl[1]:lower(), 1, true) ~= nil
				or isl[1]:lower():find(ln, 1, true) ~= nil)
			for i = 2, #isl do
				if ln:find(isl[i], 1, true) then hit = true end
			end
			if hit then
				local okI, cf = pcall(findIsland, isl)
				if okI and cf then
					CFG.islandPos[name] = cf.Position
					return cf.Position
				end
			end
		end
		local ok, res = pcall(function()
			local root = (workspace:FindFirstChild("world") and workspace.world:FindFirstChild("map")) or workspace
			for _, d in ipairs(root:GetDescendants()) do
				if (d:IsA("Model") or d:IsA("BasePart")) and d.Name:lower() == ln then
					return d:GetPivot().Position
				end
			end
		end)
		if ok and res then CFG.islandPos[name] = res return res end
	end

	local PHRASE = "goblins have spawned at"
	local lastName, lastAt = nil, 0

	local function onSpawnText(text)
		if not running then return end
		text = tostring(text):gsub("<[^>]+>", "")
		local name = text:match("[Gg]oblins have spawned at (.-)!")
			or text:match("[Gg]oblins have spawned at (.+)$")
		if not name then return end
		name = name:match("^%s*(.-)%s*$")
		if name == "" or (name == lastName and os.clock() - lastAt < 10) then return end
		lastName, lastAt = name, os.clock()
		log("SPAWN " .. name)
		local okC, p = pcall(findCoords, name)
		if not okC then p = nil end
		spawnInfo = { name = name, at = os.clock(), pos = p }
		hp("find", p ~= nil, p and ("alert: " .. name) or ("no coords: " .. name))
		if p then mem["island"] = { pos = p, at = os.clock(), name = name } end
		if not CFG.warpOnSpawn then return end
		if not p then
			log("NOTE: no coords for '" .. name .. "' - add it to CFG.islandPos")
			return
		end
		pendingWarp = { name = name, cf = CFrame.new(p), at = os.clock() }
	end

	local function scanText(v, d)
		d = d or 0
		if typeof(v) == "string" then
			return v:lower():find(PHRASE, 1, true) and v or nil
		end
		if typeof(v) == "table" and d < 3 then
			for _, x in pairs(v) do
				local r = scanText(x, d + 1)
				if r then return r end
			end
		end
		return nil
	end

	-- ทางที่ 1: remote ใน packages.Net ที่ส่งข้อความแจ้งเตือนมา
	if net then
		for _, r in ipairs(net:GetChildren()) do
			if r:IsA("BaseRemoteEvent") then
				conns[#conns + 1] = r.OnClientEvent:Connect(function(...)
					local a = table.pack(...)
					for i = 1, a.n do
						local s = scanText(a[i])
						if s then onSpawnText(s) break end
					end
				end)
			end
		end
	end

	-- ทางที่ 2: ข้อความแจ้งเตือนที่โผล่บนจอ (สำรอง)
	local pg = lp:WaitForChild("PlayerGui")
	local function watchText(t, isNew)
		if not (t:IsA("TextLabel") or t:IsA("TextButton")) then return end
		local function chk()
			if t.Text:lower():find(PHRASE, 1, true) then onSpawnText(t.Text) end
		end
		if isNew then chk() end
		-- ไม่เก็บใน conns: label ถูกทำลายเองได้ และเก็บแล้ว table จะโตไม่หยุด
		t:GetPropertyChangedSignal("Text"):Connect(chk)
	end
	for _, d in ipairs(pg:GetDescendants()) do watchText(d, false) end
	conns[#conns + 1] = pg.DescendantAdded:Connect(function(d) watchText(d, true) end)
end

log("READY v18 | difficulty=" .. CFG.difficulty .. " | waiting for goblins")
if CFG.scanOnJoin then
	task.spawn(function()
		task.wait(5) -- ให้ตัวละครโหลดนิ่งก่อน
		if running and #fresh() == 0 then scanIslands() end
	end)
end
do
	local names = {}
	for _, root in ipairs({ RS:FindFirstChild("events"), net }) do
		if root then
			for _, r in ipairs(root:GetChildren()) do
				local n = r.Name:lower()
				if n:find("goblin", 1, true) or n:find("spawn", 1, true) or n:find("haunt", 1, true) then
					names[#names + 1] = r:GetFullName()
					listen(r)
				end
			end
		end
	end
	log("SPAWN REMOTES: " .. table.concat(names, ", "))
end

--[[
  Fisch combo  =  goblin_25 (Goblin Auto) + AutoFish v17, one file.

  Run   : paste the whole file into your executor and press Execute. Two windows show up:
          AutoFish (left) and Goblin Auto (right of it). Both are draggable.
  How   : each original script sits untouched inside its own function, so their locals and
          settings can never clash. They still talk to each other the same way as before
          (getgenv().GoblinAPI / getgenv().AutoFishAPI): goblin runs by default, AutoFish sleeps
          until a Frightful Pool alert, takes over, and hands the character back when the pool is gone.
  Edit  : settings are the same as in the originals. Search for  "==== AUTOFISH ====" for the
          AutoFish CFG and  "==== GOBLIN ====" for the goblin CFG.
  Stop  : getgenv().__fisch_combo_stop()   (stops both). Executing again replaces both old copies.
  Only change vs the originals: goblin's window default position (10,24) -> next to the AutoFish card.
]]

local __genv = (getgenv and getgenv()) or _G

-- ==== GOBLIN ==== (goblin_25_combo.lua)
local function __goblin_part()
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
		Name = "win", Size = UDim2.fromOffset(W, H), Position = UDim2.fromOffset((function() local c = workspace.CurrentCamera; return (c and c.ViewportSize.X >= 252 + W + 10) and 252 or 10 end)(), 24),
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
	genv.GA_paintAuto = paintAuto
end)()


genv.GoblinAutoStop = function()
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
		if running and enabled and not working then pcall(unstick, "respawned") end
	end)
end)

startLoop()

-- COMBO with AutoFish: pause = what the Auto OFF button does + stops the current goblin step right now,
-- resume = Auto ON again with a fresh loop. AutoFish calls these when a Frightful Pool shows up / is gone.
-- resume only undoes a pause made through this API (if you switched Auto OFF by hand it stays OFF).
do
	local api = { held = false }
	api.pause = function(why)
		if not enabled then return end
		api.held = true
		enabled = false
		pcall(function() local p = genv.GA_paintAuto if p then p() end end)
		if loopThread then pcall(task.cancel, loopThread) end
		working = false
		log("COMBO: paused (" .. tostring(why) .. ")")
		pcall(unstick, "combo pause")
		pcall(refundTries)
		setStatus("paused: pool")
	end
	api.resume = function(why)
		if not api.held then return end
		api.held = false
		enabled = true
		pcall(function() local p = genv.GA_paintAuto if p then p() end end)
		log("COMBO: resumed (" .. tostring(why) .. ")")
		startLoop()
	end
	api.isOn = function() return enabled end
	genv.GoblinAPI = api
end

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
end

-- ==== AUTOFISH ==== (AutoFish_v17_combo.lua)
local function __autofish_part()
--[[
  autofish_v6.lua - auto fishing for the Roblox game "Fisch"

  Runtime : Roblox client, Luau, through an executor (written for Delta, phone or PC)
  Run     : stand at the water's edge with your rod equipped (or in the hotbar), paste this
            whole file into Delta and press Execute. A small panel shows up: drag the title bar
            to move it, tap "-" to shrink it to a pill. Executing again replaces the old copy.

  How it plays: no remotes, only inputs a player has - hold to cast, press the shake button,
            hold / release to keep the white bar under the fish.

  v19* : AUTO BOARD (ported into v17, no v18 bag report). If the character is not seated (jumped out, fell off, got pushed, died and respawned) the script
         sits back in YOUR boat before the next cast, re-equips the rod and moves "home" to the seat. The boat is found the same way
         the Frightful Pool code finds it (workspace.active.boats.<you>). No boat spawned = it logs that and keeps fishing from
         where it stands, then looks again later (15s, 30s, 60s ... max 120s). Settings: CFG.BOAT_AUTO / CFG.BOAT_RETRY.
         Toggle live:  getgenv().__autofish_autoboard(true / false)
  nobag: the bag scan, the per-catch price fetch and the three price probes are removed. Caught fish never show up in the bag, so
         there was nothing to hover and every pass only cost fishing time. Prices stay empty until another source is found.
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
    COOLDOWN     = { 3.5, 3.5 },   -- set to 3.5s by request (v6-8 had 4.0-5.5 because casts under ~3s after a catch failed about half the time)
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
    TOP_N         = 5,     -- how many fish the webhook lists in each "Top" block
    TOP_WINDOW    = 100,   -- "recent catches" = the last this-many fish
    REPORT_CHUNK  = 0,     -- Copy report puts this many characters on the clipboard per tap (tap again = next part; 0 = all at once)
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

    -- Auto board: not sitting in a seat -> sit back in your own boat (see the "auto board" section above cycle())
    BOAT_AUTO    = true,          -- false = never touch the boat outside the Frightful Pool code
    BOAT_RETRY   = 15,            -- seconds before looking for the boat again after a failed try (doubles up to 120)

    -- COMBO with the goblin script: AutoFish sleeps until a Frightful Pool alert shows up. Then it pauses goblin, takes your
    -- parked boat to the pool, fishes until the pool is gone, pauses itself and wakes goblin up again.
    -- false = old behaviour (fishes all the time, goblin is never touched)
    COMBO        = true,

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

local running, count, stage, stopped = (CFG.COMBO ~= true), 0, (CFG.COMBO == true and "paused" or "start"), false
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
HK.cb = { pool = false, manual = false }   -- COMBO state: pool = a pool trip owns AutoFish, manual = you pressed the panel button
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
        ui.btn.Activated:Connect(function()
            if CFG.COMBO and HK.comboManual then HK.comboManual(not running) else setRunning(not running) end
        end)
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
    add("auto board %s | boarded %d | failed %d", CFG.BOAT_AUTO and "on" or "off", ST.boarded or 0, ST.boardFail or 0)
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

-- webhook lines: top N priced catches of the last CFG.TOP_WINDOW fish (shows nothing while no price source exists)
function HK.topLines()
    local out = {}
    local N = tonumber(CFG.TOP_N) or 5
    local W = tonumber(CFG.TOP_WINDOW) or 100
    local function nm(s) return (tostring(s):gsub("[%*_`~]", "")) end
    local rec = {}
    for i = math.max(1, #HK.catches - W + 1), #HK.catches do
        local e = HK.catches[i]
        if e.price then rec[#rec + 1] = e end
    end
    table.sort(rec, function(a, b) return a.price > b.price end)
    if #rec > 0 then
        out[#out + 1] = string.format("\u{1F4B0}  **Top %d recent catches**  \u{00B7}  *priced, last %d fish*", math.min(N, #rec), W)
        for i = 1, math.min(N, #rec) do
            local e = rec[i]
            local mut = (e.mut and e.mut ~= "" and e.mut ~= "Normal") and ("  \u{00B7}  *" .. e.mut .. "*") or ""
            out[#out + 1] = string.format("`%d.` **%s**  \u{00B7}  %s%s C$%s", i, nm(e.name),
                e.kg and string.format("%.1f kg  \u{00B7}  ", e.kg) or "", HK.money(e.price), mut)
        end
    end
    return out
end

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
            if (HK.priceScan or 0) < 0 then
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
        if len + #s + (hdr and #hdr + 2 or 0) + 1 > 3000 and #cur > 0 then
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
    local tops = HK.topLines()
    if #tops > 0 then
        for i = #tops, 1, -1 do table.insert(chunks[1], 1, tops[i]) end
        table.insert(chunks[1], #tops + 1, "")
    end
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
        if CFG.COMBO and HK.cb.pool then
            pcall(HK.comboHandBack, "pool time is up")
            return true
        end
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
    if CFG.COMBO then
        HK.comboStart(which.name)
    elseif not running then
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
                if CFG.COMBO then
                    HK.comboStart(p.name)
                elseif not running then
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

-- ================= auto board =================
-- Not sitting in a seat (jumped out, fell off, pushed, died and respawned) -> sit back in YOUR boat before the next cast.
-- The boat comes from POOL.fastBoat (workspace.active.boats.<you>), with the slower full search as a fallback.
-- No boat out = nothing is moved, the script keeps fishing where it stands and looks again later (backoff).
-- It does NOT summon a boat: the game's summon remote is not known to this script (see __autofish_spy).
-- (kept on the HK table on purpose: this file is close to Luau's limit of 200 top-level locals)
HK.ab = { nextTry = 0, gap = 0 }

HK.abBackoff = function(why)
    local B = HK.ab
    B.gap = math.min(math.max(B.gap * 2, tonumber(CFG.BOAT_RETRY) or 15), 120)
    B.nextTry = os.clock() + B.gap
    ST.boardFail = (ST.boardFail or 0) + 1
    log(string.format("AUTOBOAT: %s - fishing from here, looking again in %ds", why, B.gap))
end

-- true = it moved us (we are in the boat now), so the cycle starts over
HK.autoBoat = function()
    local B = HK.ab
    local root, hum = poolRoot()
    if not (root and hum) or hum.Health <= 0 then return false end
    if hum.SeatPart then
        B.gap, B.nextTry = 0, 0           -- seated: forget old failures
        return false
    end
    if os.clock() < B.nextTry then return false end
    if reelReady() or getShake() then return false end                 -- finish the fish on the line first
    local a = POOL.active
    if a and not a.boat then return false end                          -- pool by foot / hover: not our business

    local info
    if a and a.boat and a.boat.model and a.boat.model.Parent and a.boat.seat and a.boat.seat.Parent then
        info = a.boat                                                  -- the boat that is at the pool right now
    else
        info = poolFindBoat()
    end
    if not info then
        HK.abBackoff("no boat of yours found (spawn it from the game menu)")
        return false
    end

    stage = "walk"
    releaseAll()
    log("AUTOBOAT: not in the boat - sitting back in it")
    local rod = getRod()
    pcall(function() hum:UnequipTools() end)
    task.wait(0.4)
    local ok, res = pcall(poolBoard, info)
    local r2, h2 = poolRoot()
    if not (ok and res and r2 and h2 and h2.SeatPart) then
        if not ok then log("AUTOBOAT error: " .. tostring(res)) end
        if h2 and rod then pcall(function() h2:EquipTool(rod) end) end
        stage = "start"
        HK.abBackoff("could not sit in the boat")
        return false
    end

    task.wait(0.8)                                                     -- let the seat settle
    rod = rod or getRod()
    local inHand = false
    for _ = 1, 4 do
        if rod then pcall(function() h2:EquipTool(rod) end) end
        task.wait(0.5)
        local ch = lp.Character
        if rod and ch and rod.Parent == ch then inHand = true break end
        rod = getRod() or rod
    end
    local r3 = poolRoot() or r2
    home, homeLook = r3.Position, r3.CFrame.LookVector                  -- GUARD measures from the seat now
    fails, rung = 0, 0
    pulse = os.clock()
    stage = "start"
    B.gap, B.nextTry = 0, 0
    ST.boarded = (ST.boarded or 0) + 1
    log(string.format("AUTOBOAT: back in the boat (%s) | rod in hand = %s", tostring(info.model.Name), tostring(inHand)))
    return true
end

env.__autofish_autoboard = function(v)
    if v == nil then v = not CFG.BOAT_AUTO end
    CFG.BOAT_AUTO = v and true or false
    HK.ab.gap, HK.ab.nextTry = 0, 0
    log("AUTOBOAT: " .. (CFG.BOAT_AUTO and "on" or "off"))
    return CFG.BOAT_AUTO
end

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

    -- COMBO: the pool trip is over or was skipped (too late, no boat, no spot) -> give control back to goblin
    if CFG.COMBO and HK.cb.pool and not POOL.pending and not POOL.active and not (reelReady() or getShake()) then
        pcall(HK.comboHandBack, "no pool to fish")
        return
    end

    if CFG.BOAT_AUTO and (POOL.active or not CFG.COMBO) then                        -- off the boat: sit back in it BEFORE the guard tries to walk "home"
        local okb, resb = pcall(HK.autoBoat)
        if not okb then
            log("AUTOBOAT error: " .. tostring(resb))
            stage = "start"
        elseif resb then
            return
        end
    end

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

-- ================= COMBO glue (goblin <-> AutoFish) =================
-- Who owns the character?   goblin  = default (AutoFish sleeps)
--                           AutoFish = from a pool alert until the pool is gone (goblin is paused through env.GoblinAPI)
-- Both scripts look the other one up only when they need it, so the execute order does not matter.
HK.comboStart = function(placeName)
    local C = HK.cb
    if C.pool then return end
    C.pool = true
    task.spawn(function()
        log("COMBO: pool alert (" .. tostring(placeName) .. ") - pausing goblin, AutoFish takes over")
        local g = env.GoblinAPI
        if g then pcall(g.pause, "pool alert") end
        task.wait(0.6)
        if not alive() then return end
        if running then
            home = nil                   -- the spot the trip "goes back to" = where goblin left us
        else
            setRunning(true)
        end
    end)
end

-- pool over (or skipped): boat home, out of the seat, rod away, AutoFish sleeps, goblin wakes up
HK.comboHandBack = function(why)
    local C, P = HK.cb, POOL
    local a = P.active
    P.active, P.pending = nil, nil
    C.pool = false
    pcall(releaseAll)
    if a and a.boat then pcall(poolBoatBack, a.boat) end      -- carries the boat back to where you parked it
    if C.manual then                                          -- you were fishing by hand: carry on as before, goblin stays parked
        home, fails, rung = nil, 0, 0
        stage = "start"
        log("COMBO: " .. why .. " - manual fishing carries on")
        return
    end
    pcall(poolUnseat)
    local _, hum = poolRoot()
    if hum then pcall(function() hum:UnequipTools() end) end  -- goblin quests (dance, emotes) want empty hands
    task.wait(0.4)
    setRunning(false)
    log("COMBO: " .. why .. " - AutoFish sleeps, goblin takes over")
    local g = env.GoblinAPI
    if g then pcall(g.resume, why) end
end

-- the panel button in combo mode: fish by hand and park goblin while it is on
HK.comboManual = function(on)
    local C = HK.cb
    local g = env.GoblinAPI
    if on then
        C.manual = true
        if g then pcall(g.pause, "manual fishing") end
        setRunning(true)
    else
        C.manual = false
        if C.pool then
            pcall(HK.comboHandBack, "stopped by hand")
        else
            setRunning(false)
            if g then pcall(g.resume, "manual fishing off") end
        end
    end
end

-- what goblin_25 expects (it calls .set / .count / .busy for its own catch quests)
env.AutoFishAPI = {
    set = function(v)
        -- goblin's unstick() calls set(false): never let that cut a pool trip short
        if CFG.COMBO and HK.cb.pool and not v then return end
        setRunning(v and true or false)
    end,
    count = function() return count end,
    busy = function() return stage == "reel" or stage == "shake" or reelReady() or getShake() ~= nil end,
    isPool = function() return HK.cb.pool end,
}

-- executing AutoFish again while it owns the character must not leave goblin paused forever
do
    local prevStop = env.__autofish_stop
    env.__autofish_stop = function(...)
        if HK.cb and HK.cb.pool then
            HK.cb.pool = false
            local g = env.GoblinAPI
            if g then pcall(g.resume, "autofish stopped") end
        end
        if type(prevStop) == "function" then return prevStop(...) end
    end
end

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

log("v6-11 started [build: nobag1 + autoboat + combo] - tap the panel button to pause" .. (CFG.POOL and " | Frightful Pool watcher on" or "") .. (CFG.BOAT_AUTO and " | auto board on" or ""))
end


-- ================= launcher =================
-- Each part runs on its own thread inside pcall, so if one fails to start the other still runs.
-- Goblin first (it owns the character by default), then AutoFish (sleeps until a pool alert).
task.spawn(function()
    local ok, err = pcall(__goblin_part)
    if not ok then warn("[fisch-combo] goblin failed to start: " .. tostring(err)) end
end)
task.spawn(function()
    local ok, err = pcall(__autofish_part)
    if not ok then warn("[fisch-combo] autofish failed to start: " .. tostring(err)) end
end)

__genv.__fisch_combo_stop = function()
    pcall(function() if type(__genv.__autofish_stop) == "function" then __genv.__autofish_stop() end end)
    pcall(function() if type(__genv.GoblinAutoStop) == "function" then __genv.GoblinAutoStop() end end)
end

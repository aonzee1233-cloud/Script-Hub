-- AA Failsafe + หน้าจอสถานะ (UI): แพ้ด่าน -> ไป Infinity Castle (รันคู่กับสคิปฟาร์มตัวหลัก)
-- วางทั้งไฟล์ใน executor แล้วรันครั้งเดียว มันจะเซฟตัวเองไว้ใน workspace
-- แล้วรันซ้ำให้เองทุกครั้งที่เปลี่ยนแมพ (queue_on_teleport)
-- UI: ลากที่หัวแผงเพื่อย้าย / กดปุ่ม - เพื่อย่อ

local SRC = [==[
local CFG = {
    LOBBY_ID      = 8304191830, -- PlaceId ล็อบบี้ (เช็คอีกที ดูจาก log ใน UI ตอนรันในล็อบบี้)
    LOSS_LIMIT    = 1,          -- แพ้กี่ครั้งติดถึงจะไป Infinity Castle
    ENTRY_TIMEOUT = 120,        -- วินาทีที่ลองหาทางเข้า IC ถ้าไม่เจอก็ยอมแพ้ ปล่อยสคิปหลักทำงานต่อ
    FORCE_TEST    = false,      -- true = ทดสอบ จำลองว่าเพิ่งแพ้ทันที
    DEBUG         = true,
    SHOW_UI       = true,       -- แสดงแผงสถานะบนหน้าจอ
    MAX_ATTEMPTS  = 3,          -- ลองเข้า IC กี่รอบ (กรณีสคิปหลักพาไป story ก่อน) ก่อนยอมแพ้
    VERIFY_IC     = true,       -- เช็คว่าถึง IC จริงไหม ถ้าไม่ใช่ให้กลับล็อบบี้ลองใหม่
    REPEAT_IC     = true,       -- IC จบแล้วเข้า IC ซ้ำ (เพราะสคิปหลักไม่จอยอะไรเอง) / false = กลับล็อบบี้แล้วหยุด
    MIN_IC_SECONDS = 60,        -- รอบ IC ที่อยู่ไม่ถึงกี่วินาทีนับว่าแพ้ไวผิดปกติ ถ้าเจอ 3 รอบติดจะหยุดวน
    IC_WORDS      = { "infinit", "castle", "floor" }, -- คำที่ขึ้นบนหน้าจอเมื่ออยู่ใน IC
}

local FILE  = "aa_failsafe.lua"
local STATE = "aa_failsafe_state.json"

local Players = game:GetService("Players")
local TS = game:GetService("TeleportService")
local HS = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (getgenv and getgenv()) or _G
if genv.AA_FS_RUNNING then return end
genv.AA_FS_RUNNING = true

local T0 = os.clock()
local function fmt(sec)
    sec = math.max(0, sec)
    return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

-- ===================== UI =====================
local COL = {
    bg    = Color3.fromRGB(22, 24, 31),
    panel = Color3.fromRGB(33, 36, 46),
    line  = Color3.fromRGB(58, 63, 80),
    text  = Color3.fromRGB(236, 238, 246),
    dim   = Color3.fromRGB(150, 157, 178),
    ok    = Color3.fromRGB(84, 214, 128),
    warn  = Color3.fromRGB(255, 196, 77),
    bad   = Color3.fromRGB(255, 98, 98),
    acc   = Color3.fromRGB(112, 140, 255),
}

local UI = { gui = nil, color = COL.dim, act = {} }
local logLines = {}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function mount(gui)
    local getters = {
        function() return gethui and gethui() end,
        function() return game:GetService("CoreGui") end,
        function() return lp:WaitForChild("PlayerGui", 10) end,
    }
    for _, get in ipairs(getters) do
        local ok, p = pcall(get)
        if ok and p then
            local ok2 = pcall(function() gui.Parent = p end)
            if ok2 and gui.Parent == p then return true end
        end
    end
    return false
end

local function buildUI()
    if genv.AA_FS_GUI then pcall(function() genv.AA_FS_GUI:Destroy() end) end

    local gui = new("ScreenGui", {
        Name = "AAFS_Panel", ResetOnSpawn = false, DisplayOrder = 999,
        IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    local main = new("Frame", {
        Name = "Main", Size = UDim2.fromOffset(320, 384), Position = UDim2.fromOffset(12, 70),
        BackgroundColor3 = COL.bg, BorderSizePixel = 0, Active = true,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 12) }, main)
    new("UIStroke", { Color = COL.line, Thickness = 1 }, main)

    -- หัวแผง (ลากย้ายได้)
    local head = new("Frame", {
        Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, Active = true,
    }, main)
    local dot = new("Frame", {
        Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, 14, 0.5, -6),
        BackgroundColor3 = COL.dim, BorderSizePixel = 0,
    }, head)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
    new("TextLabel", {
        Text = "AA Failsafe", Font = Enum.Font.SourceSansBold, TextSize = 20,
        TextColor3 = COL.text, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -96, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, head)
    local minBtn = new("TextButton", {
        Text = "-", Font = Enum.Font.SourceSansBold, TextSize = 24, TextColor3 = COL.text,
        BackgroundColor3 = COL.panel, BorderSizePixel = 0,
        Size = UDim2.fromOffset(44, 30), Position = UDim2.new(1, -54, 0.5, -15),
    }, head)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, minBtn)

    -- เนื้อหา
    local body = new("Frame", {
        Name = "Body", Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42),
        BackgroundTransparency = 1,
    }, main)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10),
    }, body)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)

    local status = new("TextLabel", {
        LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold, TextSize = 22, TextColor3 = COL.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "กำลังเริ่ม...",
    }, body)
    local detail = new("TextLabel", {
        LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans, TextSize = 16, TextColor3 = COL.dim, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
    }, body)

    local cards = new("Frame", {
        LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 94), BackgroundTransparency = 1,
    }, body)
    new("UIGridLayout", {
        CellSize = UDim2.new(0.5, -3, 0, 44), CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, cards)
    local function card(order, title)
        local f = new("Frame", { LayoutOrder = order, BackgroundColor3 = COL.panel, BorderSizePixel = 0 }, cards)
        new("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
        new("TextLabel", {
            Text = title, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 4),
            BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14,
            TextColor3 = COL.dim, TextXAlignment = Enum.TextXAlignment.Left,
        }, f)
        return new("TextLabel", {
            Text = "-", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 19),
            BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 19,
            TextColor3 = COL.text, TextXAlignment = Enum.TextXAlignment.Left,
        }, f)
    end
    UI.cPlace = card(1, "ตำแหน่ง / โหมด")
    UI.cLoss  = card(2, "แพ้ติดกัน")
    UI.cTry   = card(3, "ลองเข้า IC")
    UI.cUp    = card(4, "สคิปทำงานมา")

    local logBox = new("TextLabel", {
        LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 112), BackgroundColor3 = COL.panel, BorderSizePixel = 0,
        Font = Enum.Font.SourceSans, TextSize = 15, TextColor3 = COL.dim, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
        ClipsDescendants = true, Text = "",
    }, body)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, logBox)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    }, logBox)

    local btns = new("Frame", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, body)
    new("UIGridLayout", {
        CellSize = UDim2.new(1 / 3, -4, 1, 0), CellPadding = UDim2.fromOffset(6, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, btns)
    local function button(order, text, color, needConfirm, fn)
        local b = new("TextButton", {
            LayoutOrder = order, Text = text, Font = Enum.Font.SourceSansBold, TextSize = 17,
            TextColor3 = COL.text, BackgroundColor3 = color, BorderSizePixel = 0,
        }, btns)
        new("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
        local armed = false
        b.Activated:Connect(function()
            if needConfirm and not armed then
                armed = true
                b.Text = "กดอีกที?"
                task.delay(3, function() armed = false; b.Text = text end)
                return
            end
            armed = false
            b.Text = text
            pcall(fn)
        end)
    end
    button(1, "ทดสอบแพ้", Color3.fromRGB(150, 90, 40), true, function() if UI.act.test then UI.act.test() end end)
    button(2, "ไป IC เลย", Color3.fromRGB(70, 90, 190), true, function() if UI.act.goIC then UI.act.goIC() end end)
    button(3, "ล้างสถานะ", Color3.fromRGB(70, 74, 92), false, function() if UI.act.clear then UI.act.clear() end end)

    -- ย่อ/ขยาย
    local minimized = false
    minBtn.Activated:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        main.Size = minimized and UDim2.fromOffset(320, 42) or UDim2.fromOffset(320, 384)
        minBtn.Text = minimized and "+" or "-"
    end)

    -- ลากย้าย (รองรับนิ้วบนแท็บเล็ต)
    local dragging, dragStart, startPos = false, nil, nil
    head.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    if not mount(gui) then gui:Destroy() error("ไม่มีที่ใส่ UI") end
    genv.AA_FS_GUI = gui
    UI.gui, UI.status, UI.detail, UI.dot, UI.logBox = gui, status, detail, dot, logBox
end

function UI.set(text, color, det)
    if not UI.gui then return end
    UI.status.Text = text
    UI.color = color or COL.text
    UI.status.TextColor3 = UI.color
    if det ~= nil then UI.detail.Text = det end
end

function UI.addLog(msg)
    table.insert(logLines, "[" .. fmt(os.clock() - T0) .. "] " .. msg)
    while #logLines > 12 do table.remove(logLines, 1) end
    if UI.gui then UI.logBox.Text = table.concat(logLines, "\n") end
end

if CFG.SHOW_UI then
    local ok, err = pcall(buildUI)
    if not ok then
        UI.gui = nil
        warn("[AA-FS] สร้าง UI ไม่สำเร็จ:", err)
    end
end

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local msg = table.concat(parts, " ")
    if CFG.DEBUG then print("[AA-FS]", msg) end
    UI.addLog(msg)
end

-- ===================== state / teleport =====================
local function loadState()
    local ok, d = pcall(function() return HS:JSONDecode(readfile(STATE)) end)
    if ok and type(d) == "table" then return d end
    return {}
end
local function saveState(t)
    pcall(writefile, STATE, HS:JSONEncode(t))
end
local function wipe(t)
    for k in pairs(t) do t[k] = nil end
end

-- ให้สคิปนี้รันซ้ำเองหลังทุกการเทเลพอร์ต (รวมที่สคิปหลักสั่ง)
if queue_on_teleport then
    queue_on_teleport('loadstring(readfile("' .. FILE .. '"))()')
end

pcall(function()
    TS.TeleportInitFailed:Connect(function(_, result, msg)
        log("วาร์ปล้มเหลว:", tostring(result), tostring(msg))
    end)
end)

local function goLobby()
    log("กลับล็อบบี้")
    UI.set("กำลังวาร์ปไปล็อบบี้", COL.warn, "รอโหลดแมพ...")
    local ok, err = pcall(function() TS:Teleport(CFG.LOBBY_ID) end)
    if not ok then log("วาร์ปไม่สำเร็จ:", err) end
end

-- ===================== ตัวช่วยอ่านหน้าจอ =====================
local function shown(o)
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    while o and o ~= pg do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o = o.Parent
    end
    return true
end

-- สแกนทุก GUI ยกเว้นแผงของเราเอง (กันอ่านข้อความตัวเองแล้วเข้าใจผิดว่าเป็นของเกม)
local function findText(pats, onlyButtons)
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    for _, root in ipairs(pg:GetChildren()) do
        if root ~= UI.gui then
            for _, o in ipairs(root:GetDescendants()) do
                local isBtn = o:IsA("TextButton")
                if (isBtn or (not onlyButtons and o:IsA("TextLabel"))) and o.Text ~= "" then
                    local t = o.Text:lower()
                    for _, p in ipairs(pats) do
                        if t:find(p, 1, true) and shown(o) then return o end
                    end
                end
            end
        end
    end
    return nil
end

local function click(btn)
    pcall(function()
        if firesignal then
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
        end
        if getconnections then
            for _, c in ipairs(getconnections(btn.MouseButton1Click)) do pcall(function() c:Fire() end) end
            for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
        end
    end)
end

local LOSE = { "defeat", "you lost", "game over" }
local WIN  = { "victory", "you won", "mission complete" }

-- ===================== เข้า Infinity Castle จากล็อบบี้ =====================
local function partOf(o)
    local p = o.Parent
    while p and not p:IsA("BasePart") do p = p.Parent end
    return p
end

local function findTargets()
    local list = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("ProximityPrompt") or o:IsA("ClickDetector") or o:IsA("TouchTransmitter") then
            local s = o:GetFullName()
            if o:IsA("ProximityPrompt") then s = s .. o.ObjectText .. o.ActionText end
            s = s:lower()
            if s:find("infinit", 1, true) or s:find("castle", 1, true) then
                table.insert(list, o)
            end
        end
    end
    return list
end

local function useTarget(o)
    local char = lp.Character or lp.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    local part = partOf(o)
    if not (hrp and part) then return end
    hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    task.wait(0.5)
    if o:IsA("ProximityPrompt") and fireproximityprompt then
        fireproximityprompt(o)
    elseif o:IsA("ClickDetector") and fireclickdetector then
        fireclickdetector(o)
    elseif o:IsA("TouchTransmitter") and firetouchinterest then
        firetouchinterest(hrp, part, 0)
        task.wait(0.2)
        firetouchinterest(hrp, part, 1)
    end
end

local function enterIC(attempt)
    log("พยายามเข้า Infinity Castle...")
    local t0 = os.clock()
    local tries = 0
    local found = 0
    while os.clock() - t0 < CFG.ENTRY_TIMEOUT do
        local left = math.max(0, math.floor(CFG.ENTRY_TIMEOUT - (os.clock() - t0)))
        UI.set("กำลังหาทางเข้า IC", COL.warn,
            "ครั้งที่ " .. attempt .. "/" .. CFG.MAX_ATTEMPTS .. " · เหลือเวลา " .. left .. " วิ · เจอจุดเข้า " .. found)
        -- 1) หาจุด/พร้อมต์ในแมพ
        if tries < 4 then
            local list = findTargets()
            found = #list
            log("เจอจุดเข้า IC:", #list)
            for _, o in ipairs(list) do
                log(" -", o:GetFullName())
                useTarget(o)
                tries = tries + 1
                task.wait(1.5)
            end
        end
        -- 2) กดปุ่มในหน้าจอ (เลือก IC ก่อน แล้วค่อยกดยืนยัน/เริ่ม)
        local b = findText({ "infinit", "castle" }, true)
        if b then log("กดปุ่ม:", b.Text); click(b); task.wait(1.5) end
        local s = findText({ "start", "confirm", "enter", "create" }, true)
        if s then log("กดปุ่ม:", s.Text); click(s) end
        task.wait(1.5)
    end
    log("หมดเวลา ไม่สามารถเข้า IC ได้ -> ปล่อยสคิปหลักทำงานต่อ")
    UI.set("เข้า IC ไม่ได้", COL.bad, "หมดเวลาแล้ว ปล่อยให้สคิปหลักทำงานต่อ")
    saveState({})
end

-- ===================== เริ่มทำงาน =====================
local function main()
    local st = loadState()
    local inLobby = (game.PlaceId == CFG.LOBBY_ID)
    log("PlaceId =", game.PlaceId, inLobby and "(ล็อบบี้)" or "(ในด่าน)", "mode =", st.mode)

    -- เช็คว่า executor มีฟังก์ชันที่ต้องใช้ครบไหม
    local caps = {
        { "writefile", writefile }, { "readfile", readfile },
        { "queue_on_teleport", queue_on_teleport },
        { "firesignal", firesignal }, { "getconnections", getconnections },
        { "fireproximityprompt", fireproximityprompt },
        { "fireclickdetector", fireclickdetector }, { "firetouchinterest", firetouchinterest },
    }
    local missing = {}
    for _, c in ipairs(caps) do
        if not c[2] then table.insert(missing, c[1]) end
    end
    if #missing == 0 then
        log("executor รองรับครบทุกฟังก์ชัน")
    else
        log("executor ไม่มี:", table.concat(missing, ", "))
    end
    local noQueue = not queue_on_teleport

    -- ปุ่มบนแผง
    UI.act.test = function()
        if inLobby then log("ทดสอบแพ้ใช้ได้เฉพาะตอนอยู่ในด่าน"); return end
        CFG.FORCE_TEST = true
        log("จำลองว่าแพ้ (จะวาร์ปไปล็อบบี้จริง)")
    end
    UI.act.goIC = function()
        log("สั่งไป IC เอง")
        saveState({ mode = "IC", t = os.time(), attempts = 0 })
        goLobby()
    end
    UI.act.clear = function()
        wipe(st)
        saveState({})
        log("ล้างสถานะแล้ว")
    end

    -- ตัวอัปเดตการ์ดสถานะ + จุดกะพริบ (ถ้าจุดกะพริบ = สคิปยังมีชีวิต)
    task.spawn(function()
        local tick = false
        while UI.gui and UI.gui.Parent do
            tick = not tick
            UI.cPlace.Text = (inLobby and "ล็อบบี้" or "ในด่าน") .. " · " .. (st.mode == "IC" and "IC" or "ปกติ")
            UI.cLoss.Text = (st.mode == "IC") and "-" or ((st.losses or 0) .. " / " .. CFG.LOSS_LIMIT)
            UI.cTry.Text = (st.attempts or 0) .. " / " .. CFG.MAX_ATTEMPTS
            UI.cUp.Text = fmt(os.clock() - T0)
            UI.dot.BackgroundColor3 = UI.color
            UI.dot.BackgroundTransparency = tick and 0 or 0.7
            task.wait(1)
        end
    end)

    if inLobby then
        if st.mode == "IC" then
            st.attempts = (st.attempts or 0) + 1
            if st.attempts > CFG.MAX_ATTEMPTS then
                log("ลองเข้า IC ครบ", CFG.MAX_ATTEMPTS, "รอบแล้ว -> ปล่อยสคิปหลักทำงานต่อ")
                UI.set("ลองเข้า IC ครบแล้ว", COL.bad, "ปล่อยให้สคิปหลักทำงานต่อ")
                saveState({})
                wipe(st)
            else
                saveState(st)
                enterIC(st.attempts)
                wipe(st)
            end
        else
            UI.set("อยู่ล็อบบี้ · ยังไม่มีงาน", COL.ok,
                noQueue
                    and "executor นี้ไม่มี queue_on_teleport สคิปจะไม่รันต่อเองหลังวาร์ป ต้องรันซ้ำเองในด่าน"
                    or "ยังไม่ได้แพ้ จึงไม่ต้องทำอะไร สคิปจะเริ่มเฝ้าดูตอนเข้าด่าน")
        end
        genv.AA_FS_RUNNING = nil
        return
    end

    -- ในด่าน: คอยดูว่าแพ้ไหม
    local function onLoss()
        if st.mode == "IC" then
            local dur = os.time() - (st.icStart or os.time())
            local quick = (dur < CFG.MIN_IC_SECONDS) and ((st.quick or 0) + 1) or 0
            if CFG.REPEAT_IC and quick < 3 then
                log("จบรอบ Infinity Castle (", dur, "วิ) -> เข้า IC ซ้ำ")
                UI.set("จบรอบ IC", COL.warn, "อยู่ " .. dur .. " วิ · จะเข้า IC ซ้ำ")
                saveState({ mode = "IC", t = os.time(), attempts = 0, quick = quick })
            else
                log("จบรอบ Infinity Castle (", dur, "วิ) -> หยุดวน กลับล็อบบี้")
                UI.set("จบรอบ IC · หยุดวน", COL.warn, "อยู่ " .. dur .. " วิ · กลับล็อบบี้แล้วหยุด")
                saveState({})
            end
            goLobby()
            return
        end
        st.losses = (st.losses or 0) + 1
        log("แพ้ครั้งที่", st.losses, "/", CFG.LOSS_LIMIT)
        UI.set("เจอหน้าแพ้!", COL.bad, "แพ้ครั้งที่ " .. st.losses .. "/" .. CFG.LOSS_LIMIT)
        if st.losses >= CFG.LOSS_LIMIT then
            saveState({ mode = "IC", t = os.time(), attempts = 0 })
            goLobby()
        else
            saveState(st)
        end
    end

    -- ถ้าเรากำลังจะไป IC: เช็คว่ามาถึง IC จริงไหม (สคิปหลักอาจพาไป story ก่อน)
    if st.mode == "IC" and CFG.VERIFY_IC then
        UI.set("ตรวจว่าอยู่ IC จริงไหม", COL.warn, "รอดูข้อความบนหน้าจอสูงสุด 30 วิ")
        local ok = false
        local t0 = os.clock()
        while os.clock() - t0 < 30 do
            if findText(CFG.IC_WORDS, false) then ok = true; break end
            task.wait(2)
        end
        if not ok then
            log("ดูไม่ใช่ Infinity Castle -> กลับล็อบบี้ลองใหม่")
            goLobby()
            return
        end
        log("ยืนยันแล้วว่าอยู่ Infinity Castle")
    end
    if st.mode == "IC" then
        st.icStart = os.time()
        saveState(st)
    end

    local scans = 0
    while task.wait(2) do
        scans = scans + 1
        if st.mode == "IC" then
            UI.set("อยู่ใน Infinity Castle", COL.acc,
                "เฝ้าดูหน้าแพ้ · สแกนครั้งที่ " .. scans .. " · อยู่มา " .. fmt(os.time() - (st.icStart or os.time())))
        else
            UI.set("เฝ้าดูด่าน", COL.ok,
                "ยังไม่เจอหน้าแพ้ · สแกนครั้งที่ " .. scans .. " · แพ้ติด " .. (st.losses or 0) .. "/" .. CFG.LOSS_LIMIT)
        end

        if CFG.FORCE_TEST or findText(LOSE, false) then
            CFG.FORCE_TEST = false
            task.wait(3)
            onLoss()
            -- รอให้หน้าจอแพ้หายก่อนค่อยนับรอบใหม่ (กันนับซ้ำ)
            local t0 = os.clock()
            while findText(LOSE, false) and os.clock() - t0 < 90 do task.wait(2) end
        elseif (st.losses or 0) > 0 and findText(WIN, false) then
            st.losses = 0
            saveState(st)
            log("ชนะ -> รีเซ็ตตัวนับแพ้")
            UI.set("ชนะ", COL.ok, "รีเซ็ตตัวนับแพ้แล้ว")
        end
    end
end

local ok, err = xpcall(main, function(e) return tostring(e) end)
if not ok then
    genv.AA_FS_RUNNING = nil
    warn("[AA-FS] error:", err)
    UI.set("สคิปเกิดข้อผิดพลาด", COL.bad, tostring(err):sub(1, 140))
    UI.addLog("ERROR: " .. tostring(err):sub(1, 200))
end
]==]

local okW, errW = pcall(function() writefile("aa_failsafe.lua", SRC) end)
if not okW then warn("[AA-FS] เซฟไฟล์ไม่ได้ (ต่อไปจะไม่รันซ้ำเองหลังวาร์ป):", errW) end

local fn, perr = loadstring(SRC)
if not fn then
    warn("[AA-FS] โหลดสคิปไม่ได้:", perr)
    return
end
fn()

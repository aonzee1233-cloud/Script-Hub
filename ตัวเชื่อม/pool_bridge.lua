--[[
  pool_bridge.lua - makes goblin_25 and AutoFish v17 take turns (Roblox Fisch, Luau, Delta)

  Needs the two small patches first:
    AutoFish  -> adds getgenv().AutoFishAPI   (set / running / count / busy / stage / pool)
    goblin_25 -> adds getgenv().GoblinAPI     (get / set / busy)

  Run order does not matter: execute goblin, AutoFish and this file in any order.
  Executing this file again replaces the old copy.

  What it does
    no pool   : goblin does the quests, AutoFish stays paused (goblin switches it on itself for the
                "catch" quests and off again afterwards)
    pool alert: goblin is paused after it finishes its current step, AutoFish is switched on and does
                the pool trip itself (boat, 10 min stay, back to the spot where goblin was)
    pool over : AutoFish is paused, goblin is switched back on - but only if it was ON before
]]

local genv = (getgenv and getgenv()) or _G
if type(genv.PoolBridgeStop) == "function" then pcall(genv.PoolBridgeStop) end

local CFG = {
    TICK        = 1,     -- seconds between checks
    GOBLIN_WAIT = 90,    -- max seconds to wait for goblin to finish its current step before the pool trip starts anyway
    SETTLE      = 6,     -- seconds the pool must be gone (and AutoFish idle) before goblin gets control back
    START_WAIT  = 60,    -- max seconds a "pending" pool may wait for AutoFish to start the trip before giving up
}

local alive = true
genv.PoolBridgeStop = function() alive = false end

local lastNote = ""
local function say(msg)
    if msg == lastNote then return end
    lastNote = msg
    print("[pool_bridge] " .. msg)
end

local mode = "goblin"          -- "goblin" | "pool"
local goblinWas = true         -- was goblin ON when the pool took over?
local poolSince, goneSince = 0, nil
local booted = false

while alive do
    task.wait(CFG.TICK)
    local af, gb = genv.AutoFishAPI, genv.GoblinAPI

    if not (af and gb) then
        say("waiting for " .. (af and "" or "AutoFish ") .. (gb and "" or "goblin ") .. "(run it, with the patch)")
    else
        local ps = af.pool()   -- nil | "pending" | "active"

        if not booted then
            booted = true
            if not ps then
                -- AutoFish starts itself on execute: keep it quiet until a pool shows up
                pcall(af.set, false)
            end
            say("ready - goblin quests until a Frightful Pool shows up")
        end

        if mode == "goblin" then
            if ps then
                goblinWas = gb.get()
                say("pool alert (" .. tostring(ps) .. ") - pausing goblin")
                pcall(gb.set, false)
                local t0 = os.clock()
                while alive and gb.busy() and os.clock() - t0 < CFG.GOBLIN_WAIT do
                    task.wait(0.5)
                end
                if gb.busy() then
                    say("goblin still busy after " .. CFG.GOBLIN_WAIT .. "s - starting the pool trip anyway")
                end
                pcall(af.set, true)
                mode, poolSince, goneSince = "pool", os.clock(), nil
                say("AutoFish on - pool trip")
            end
        else
            if ps then
                goneSince = nil
                if ps == "pending" and os.clock() - poolSince > CFG.START_WAIT and not af.running() then
                    -- AutoFish was paused again (by hand or by goblin) while the trip was queued
                    pcall(af.set, true)
                    poolSince = os.clock()
                end
            else
                goneSince = goneSince or os.clock()
                local st = af.stage()
                local travelling = (st == "walk" or st == "fix")
                if os.clock() - goneSince >= CFG.SETTLE and not travelling then
                    pcall(af.set, false)
                    local t0 = os.clock()
                    while alive and af.busy() and os.clock() - t0 < 30 do task.wait(0.3) end
                    pcall(gb.set, goblinWas)
                    mode = "goblin"
                    say("pool done - AutoFish paused, goblin " .. (goblinWas and "back ON" or "left OFF (it was OFF before)"))
                end
            end
        end
    end
end

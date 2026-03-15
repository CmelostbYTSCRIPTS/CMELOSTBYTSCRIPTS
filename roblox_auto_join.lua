-- Auto Join by JobId via UI or Teleport fallback
-- Environment: Roblox client (exploit/injector). Does not start external loaders.

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local localPlayer = Players.LocalPlayer

-- Keywords (lowercase)
local hubKeywords = {
    "chilli","chili","chill","chillz","chillhub","chilli hub","hub","хаб","чилли","чилли хаб"
}

local serverKeywords = {
    "server","servers","server hop","server browser","сервер","серверы","srv","instance","инстанс","session","сессия"
}

local jobIdKeywords = {
    "job","jobid","job id","job-id","server id","serverid","sid","instance id","session id","id сервера","айди","айди сервера","ид сервера"
}

local joinKeywords = {
    "join","join job","join by id","connect","teleport","tp","go","enter","войти","присоед","присоединиться","заход","подключ"
}

local function safeLower(text)
    if typeof(text) ~= "string" then return "" end
    return string.lower(text)
end

local function containsAny(haystack, keywords)
    local s = safeLower(haystack)
    for _, k in ipairs(keywords) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

local function tryRead(obj, prop)
    local ok, val = pcall(function()
        return obj[prop]
    end)
    if ok then return val end
    return nil
end

local function getTextOfGuiObject(gui)
    if not gui or not gui:IsA("GuiObject") then return "" end
    if gui:IsA("TextBox") or gui:IsA("TextLabel") or gui:IsA("TextButton") then
        local t = tryRead(gui, "Text")
        if typeof(t) == "string" and #t > 0 then return t end
        local ph = tryRead(gui, "PlaceholderText")
        if typeof(ph) == "string" and #ph > 0 then return ph end
    end
    return tryRead(gui, "Name") or ""
end

local function colorIsLikelyPurple(color)
    if typeof(color) ~= "Color3" then return false end
    local h, s, v = Color3.toHSV(color)
    if s < 0.35 or v < 0.25 then return false end
    return h >= 0.70 and h <= 0.88
end

local function getAllGuis()
    local roots = {}
    for _, child in ipairs(CoreGui:GetChildren()) do
        table.insert(roots, child)
    end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, child in ipairs(playerGui:GetChildren()) do
            table.insert(roots, child)
        end
    end
    local ok, hidden = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
        return nil
    end)
    if ok and hidden then
        for _, child in ipairs(hidden:GetChildren()) do
            table.insert(roots, child)
        end
    end
    return roots
end

local function collectDescendantsSafe(root)
    local results = {}
    local ok, list = pcall(function()
        return root:GetDescendants()
    end)
    if ok then
        for _, d in ipairs(list) do table.insert(results, d) end
    end
    return results
end

local function scoreContainerForServer(container)
    local score = 0
    local boosted = 0
    for _, d in ipairs(collectDescendantsSafe(container)) do
        if d:IsA("GuiObject") then
            local t = getTextOfGuiObject(d)
            if #t > 0 then
                if containsAny(t, hubKeywords) then boosted = boosted + 2 end
                if containsAny(t, serverKeywords) then score = score + 3 end
                if containsAny(t, jobIdKeywords) then score = score + 1 end
            end
        end
    end
    return score + boosted
end

local function findLikelyServerContainer()
    local candidates = {}
    for _, root in ipairs(getAllGuis()) do
        if root:IsA("ScreenGui") or root:IsA("Frame") or root:IsA("ScrollingFrame") then
            local rootScore = scoreContainerForServer(root)
            if rootScore > 0 then
                table.insert(candidates, {inst = root, score = rootScore})
            end
            for _, d in ipairs(collectDescendantsSafe(root)) do
                if d:IsA("Frame") or d:IsA("ScrollingFrame") then
                    local s = scoreContainerForServer(d)
                    if s > 0 then table.insert(candidates, {inst = d, score = s}) end
                end
            end
        end
    end
    table.sort(candidates, function(a,b) return a.score > b.score end)
    return candidates[1] and candidates[1].inst or nil
end

local function distanceBetweenCenters(a, b)
    if not (a and b) then return math.huge end
    local pa = a.AbsolutePosition
    local sa = a.AbsoluteSize
    local pb = b.AbsolutePosition
    local sb = b.AbsoluteSize
    local ax, ay = pa.X + sa.X * 0.5, pa.Y + sa.Y * 0.5
    local bx, by = pb.X + sb.X * 0.5, pb.Y + sb.Y * 0.5
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx*dx + dy*dy)
end

local function findJobIdTextBox(container)
    local best, bestScore = nil, -1
    local allTextBoxes = {}
    for _, d in ipairs(collectDescendantsSafe(container)) do
        if d:IsA("TextBox") then
            table.insert(allTextBoxes, d)
            local score = 0
            local t = getTextOfGuiObject(d)
            if containsAny(t, jobIdKeywords) then score = score + 3 end
            local name = safeLower(tryRead(d, "Name") or "")
            if containsAny(name, jobIdKeywords) then score = score + 2 end
            local ph = safeLower(tryRead(d, "PlaceholderText") or "")
            if containsAny(ph, jobIdKeywords) then score = score + 2 end
            if score > bestScore then best, bestScore = d, score end
        end
    end
    if best then return best end
    if #allTextBoxes == 1 then return allTextBoxes[1] end
    return nil
end

local function findJoinButton(container, nearTextBox)
    local best, bestScore = nil, -1
    for _, d in ipairs(collectDescendantsSafe(container)) do
        if d:IsA("TextButton") or d:IsA("ImageButton") then
            local score = 0
            local t = getTextOfGuiObject(d)
            if containsAny(t, joinKeywords) then score = score + 3 end
            local name = safeLower(tryRead(d, "Name") or "")
            if containsAny(name, joinKeywords) then score = score + 2 end
            if d:IsA("TextButton") then
                local color = tryRead(d, "BackgroundColor3")
                if colorIsLikelyPurple(color) then score = score + 1 end
            end
            if nearTextBox then
                local dist = distanceBetweenCenters(d, nearTextBox)
                if dist < 80 then score = score + 2
                elseif dist < 160 then score = score + 1 end
            end
            if score > bestScore then best, bestScore = d, score end
        end
    end
    return best
end

local function focusAndInputText(textBox, text)
    if not (textBox and textBox:IsA("TextBox")) then return false end
    local ok = false
    pcall(function() textBox:CaptureFocus() end)
    local typed = false
    local okSend = pcall(function()
        if VirtualInputManager and typeof(VirtualInputManager.SendText) == "function" then
            VirtualInputManager:SendText(tostring(text), false)
            typed = true
        end
    end)
    if not okSend or not typed then
        pcall(function() textBox.Text = tostring(text) end)
    end
    pcall(function() textBox:ReleaseFocus() end)
    ok = true
    return ok
end

local function clickGuiButton(btn)
    if not (btn and (btn:IsA("TextButton") or btn:IsA("ImageButton"))) then return false end
    local done = false
    pcall(function()
        if typeof(firesignal) == "function" then
            local clicked = false
            local sigs = {}
            local ok1, sig1 = pcall(function() return btn.MouseButton1Click end)
            if ok1 and typeof(sig1) == "RBXScriptSignal" then table.insert(sigs, sig1) end
            local ok2, sig2 = pcall(function() return btn.Activated end)
            if ok2 and typeof(sig2) == "RBXScriptSignal" then table.insert(sigs, sig2) end
            for _, sig in ipairs(sigs) do
                local okFire = pcall(function() firesignal(sig) end)
                if okFire then clicked = true end
            end
            if clicked then done = true end
        end
    end)
    if not done then
        local okActivate = pcall(function()
            if typeof(btn.Activate) == "function" then btn:Activate() return true end
            return false
        end)
        if okActivate then done = true end
    end
    if not done and VirtualInputManager then
        local pos = btn.AbsolutePosition
        local size = btn.AbsoluteSize
        local cx, cy = pos.X + size.X * 0.5, pos.Y + size.Y * 0.5
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
        end)
        done = true
    end
    return done
end

local function guidFromString(s)
    if typeof(s) ~= "string" then return nil end
    local lower = string.lower(s)
    local match = string.match(lower, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x")
    return match
end

local function readClipboard()
    local text = nil
    local ok, res = pcall(function()
        if typeof(getclipboard) == "function" then return getclipboard() end
        return nil
    end)
    if ok and typeof(res) == "string" then text = res end
    if not text and typeof(clipboard) == "table" then
        local ok2, res2 = pcall(function() return clipboard.get() end)
        if ok2 and typeof(res2) == "string" then text = res2 end
    end
    return text
end

local function attemptUiJoin(jobId)
    local serverContainer = findLikelyServerContainer()
    if not serverContainer then return false, "no_container" end
    local textBox = findJobIdTextBox(serverContainer)
    if not textBox then return false, "no_textbox" end
    focusAndInputText(textBox, jobId)
    local joinBtn = findJoinButton(serverContainer, textBox)
    if not joinBtn then return false, "no_button" end
    local clicked = clickGuiButton(joinBtn)
    return clicked, clicked and "clicked" or "click_failed"
end

local function fallbackTeleport(jobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, tostring(jobId), localPlayer)
    end)
    return ok, err
end

local lastJobId = nil
local isAutomating = false

local function handleClipboard()
    if isAutomating then return end
    local clip = readClipboard()
    local jobId = guidFromString(clip or "")
    if not jobId or jobId == lastJobId then return end
    isAutomating = true
    lastJobId = jobId

    local okUi = false
    local ok, _ = pcall(function()
        local success = false
        -- Try UI multiple times in case GUI spawns late
        for i = 1, 3 do
            local s, why = attemptUiJoin(jobId)
            if s then success = true break end
            task.wait(0.4)
        end
        okUi = success
    end)

    if not okUi then
        fallbackTeleport(jobId)
    end

    isAutomating = false
end

-- Background watcher
spawn(function()
    while true do
        handleClipboard()
        task.wait(0.5)
    end
end)

-- Expose manual trigger
getgenv = getgenv or function()
    _G.__genv = _G.__genv or {}
    return _G.__genv
end

getgenv().AutoJoinJobId = {
    TriggerNow = function()
        handleClipboard()
    end,
    LastJobId = function()
        return lastJobId
    end
}

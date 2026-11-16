local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- ป้องกันการค้างตอนรอ PlayerGui
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
if not PlayerGui then
    warn("[Murim Hub] โหลด PlayerGui ไม่สำเร็จ กรุณารันใหม่อีกครั้งหลังเข้าเกมเต็ม 100%")
    return
end

-- ==================== ระบบแสดง Error GUI ====================
local function showDebugErrorGui(titleText, errMsg)
    pcall(function()
        local old = PlayerGui:FindFirstChild("MurimDebugErrorGui")
        if old then old:Destroy() end

        local sg = Instance.new("ScreenGui")
        sg.Name = "MurimDebugErrorGui"
        sg.DisplayOrder = 999999
        sg.ResetOnSpawn = false
        sg.Parent = PlayerGui

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 420, 0, 320)
        frame.Position = UDim2.new(0.5, -210, 0.22, 0)
        frame.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
        frame.BorderSizePixel = 0
        frame.Parent = sg
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

        local topBar = Instance.new("Frame")
        topBar.Size = UDim2.new(1, 0, 0, 35)
        topBar.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        topBar.BorderSizePixel = 0
        topBar.Parent = frame
        Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 10)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -40, 1, 0)
        title.Position = UDim2.new(0, 12, 0, 0)
        title.BackgroundTransparency = 1
        title.Text = tostring(titleText)
        title.TextColor3 = Color3.fromRGB(255, 215, 110)
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 14
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = topBar

        local closeBtn = Instance.new("TextButton")
        closeBtn.Size = UDim2.new(0, 26, 0, 26)
        closeBtn.Position = UDim2.new(1, -31, 0, 4)
        closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
        closeBtn.Text = "X"
        closeBtn.TextColor3 = Color3.new(1, 1, 1)
        closeBtn.Font = Enum.Font.SourceSansBold
        closeBtn.TextSize = 13
        closeBtn.Parent = topBar
        Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
        closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

        local textBox = Instance.new("TextBox")
        textBox.Size = UDim2.new(1, -20, 1, -95)
        textBox.Position = UDim2.new(0, 10, 0, 43)
        textBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
        textBox.TextColor3 = Color3.fromRGB(225, 245, 230)
        textBox.Text = tostring(errMsg)
        textBox.TextWrapped = true
        textBox.MultiLine = true
        textBox.ClearTextOnFocus = false
        textBox.TextXAlignment = Enum.TextXAlignment.Left
        textBox.TextYAlignment = Enum.TextYAlignment.Top
        textBox.Font = Enum.Font.Code
        textBox.TextSize = 11
        textBox.Parent = frame
        Instance.new("UICorner", textBox).CornerRadius = UDim.new(0, 6)
    end)
end

-- ==================== โครงสร้างหลัก ====================
local Hub = {
    Env = {
        connections = {},
        workers = {},
        destroyed = false,
        Remotes = {},
        cachedHerbPrompts = {},
        herbCacheInitialized = false,
        collectedCooldowns = {},
        zoneIndex = 1,
        patrolAngle = 0,
        lastErrorText = "ไม่มี Error",
        currentHerbTargetName = "None",
        botStatusText = "Initializing..."
    },
    UI = {},
    Config = {},
    State = {},
    Fn = {}
}

do
    local Env = Hub.Env
    local UI = Hub.UI

    function Hub.Fn.logDebug(msg)
        local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg)
        Env.botStatusText = tostring(msg)
        if UI.DebugBox then
            UI.DebugBox.Text = line .. "\n" .. string.sub(UI.DebugBox.Text, 1, 600)
        end
    end

    function Hub.Fn.connect(signal, callback)
        if not signal then return nil end
        local connection = signal:Connect(function(...)
            local ok, err = xpcall(callback, debug.traceback, ...)
            if not ok and not Env.destroyed then
                Env.lastErrorText = tostring(err)
                showDebugErrorGui("⚠️ Event Error", err)
            end
        end)
        Env.connections[connection] = true
        return connection
    end

    function Hub.Fn.stopWorker(name)
        local thread = Env.workers[name]
        Env.workers[name] = nil
        if thread and coroutine.status(thread) ~= "dead" and thread ~= coroutine.running() then
            pcall(task.cancel, thread)
        end
    end

    function Hub.Fn.setWorker(name, enabled, callback)
        Hub.Fn.stopWorker(name)
        if not enabled or Env.destroyed then return nil end
        local thread = task.spawn(function()
            pcall(callback)
        end)
        Env.workers[name] = thread
        return thread
    end

    local CultivationEvents = ReplicatedStorage:FindFirstChild("CultivationEvents")
    if CultivationEvents then
        Env.Remotes.CollectHerb = CultivationEvents:FindFirstChild("CollectHerb")
        Env.Remotes.SwordFlight = CultivationEvents:FindFirstChild("SwordFlight")
    end

    Hub.Config = {
        herbModes = { "1000Yr Sniper + All Herbs", "Only 1000-Year (เฉพาะ 1000 ปี)" },
        fallbackZones = {
            Vector3.new(0, 120, 0),
            Vector3.new(-350, 140, 2200),
            Vector3.new(900, 130, 2100),
            Vector3.new(-2800, 150, -2100),
            Vector3.new(2500, 1500, 1000)
        }
    }

    Hub.State = {
        isFarming = true,
        isAutoFlight = true,
        sessionHerbCount = 0,
        isDynamicStream = true,
        herbModeIndex = 1,
        debugPanelVisible = true
    }

    local groundPlatform = Instance.new("Part")
    groundPlatform.Size = Vector3.new(8, 1, 8)
    groundPlatform.Anchored = true
    groundPlatform.Transparency = 1
    groundPlatform.CanCollide = true
    groundPlatform.Name = "TempUndergroundGround"
    groundPlatform.Parent = workspace
    Env.groundPlatform = groundPlatform

    function Hub.Fn.getCharacter()
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum then return char, hrp, hum end
        end
        return nil, nil, nil
    end

    function Hub.Fn.safeTeleport(hrp, targetCFrame)
        if not hrp or not targetCFrame then return false end
        local targetPos = targetCFrame.Position
        if targetPos.Magnitude < 5 then return false end

        local startPos = hrp.Position
        local flatDist = Vector2.new(targetPos.X - startPos.X, targetPos.Z - startPos.Z).Magnitude

        local function applyCFrame(cframe)
            groundPlatform.CFrame = cframe * CFrame.new(0, -1, 0)
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            pcall(function() hrp.CFrame = cframe end)
        end

        if flatDist <= 38 then
            applyCFrame(targetCFrame)
            return true
        end

        local stepDist = 36
        local steps = math.ceil(flatDist / stepDist)
        local rotOnly = targetCFrame - targetCFrame.Position

        for i = 1, steps do
            if not hrp or not hrp.Parent then return false end
            local nextPos = startPos:Lerp(targetPos, i / steps)
            applyCFrame(CFrame.new(nextPos) * rotOnly)
            task.wait(0.10)
        end
        return true
    end
end

-- ==================== ลูปฟาร์มสมุนไพรและการนับจำนวน ====================
do
    local Env = Hub.Env
    local State = Hub.State

    function Hub.Fn.startSwordFlightLoop()
        while State.isAutoFlight do
            local char, _, humanoid = Hub.Fn.getCharacter()
            if char and humanoid and humanoid.Health > 0 then
                local swordEvent = Env.Remotes.SwordFlight or (ReplicatedStorage:FindFirstChild("CultivationEvents") and ReplicatedStorage.CultivationEvents:FindFirstChild("SwordFlight"))
                local isFlying = char:GetAttribute("SwordFlying") == true
                local hasLearned = LocalPlayer:GetAttribute("SwordFlightLearned") == true
                if hasLearned and not isFlying and swordEvent then
                    pcall(function() swordEvent:FireServer(true) end)
                end
            end
            task.wait(0.5)
        end
    end

    function Hub.Fn.getDynamicStreamPoints()
        local points = {}
        local seen = {}
        local function addPoint(pos)
            if typeof(pos) ~= "Vector3" then return end
            local key = math.floor(pos.X / 150) .. "_" .. math.floor(pos.Z / 150)
            if not seen[key] then
                seen[key] = true
                table.insert(points, pos)
            end
        end
        local anchors = workspace:FindFirstChild("MapAnchors")
        if anchors then
            for _, child in ipairs(anchors:GetDescendants()) do
                if child:IsA("BasePart") then addPoint(child.Position) end
            end
        end
        for _, pos in ipairs(Hub.Config.fallbackZones) do addPoint(pos) end
        return points
    end

    function Hub.Fn.startDynamicStreamLoop()
        while State.isDynamicStream do
            local points = Hub.Fn.getDynamicStreamPoints()
            if #points > 0 then
                local targetPos = points[math.random(1, #points)]
                pcall(function() workspace:RequestStreamAroundAsync(targetPos) end)
            end
            task.wait(0.8)
        end
    end

    local function initHerbCache()
        if Env.herbCacheInitialized then return end
        Env.herbCacheInitialized = true
        local function registerObj(obj)
            if obj:IsA("ProximityPrompt") and (obj.Name == "CollectHerbPrompt" or obj.Name:lower():find("herb")) then
                Env.cachedHerbPrompts[obj] = true
            end
        end
        Hub.Fn.connect(workspace.DescendantAdded, registerObj)
        Hub.Fn.connect(workspace.DescendantRemoving, function(obj) Env.cachedHerbPrompts[obj] = nil end)
        for _, obj in ipairs(workspace:GetDescendants()) do registerObj(obj) end
    end

    local function getBestHerbTarget(fromPos)
        initHerbCache()
        local herbSpots = workspace:FindFirstChild("HerbSpots")
        local now = os.clock()
        local only1000Yr = (State.herbModeIndex == 2)
        local candidates, seenParts = {}, {}

        local function evaluatePart(part, prompt)
            if seenParts[part] or not part or not part.Parent then return end
            if prompt and not prompt.Enabled then return end
            seenParts[part] = true

            local herbYear = part:GetAttribute("HerbYear") or part:GetAttribute("Year") or 1
            if only1000Yr and herbYear < 1000 then return end
            if Env.collectedCooldowns[part] and now < Env.collectedCooldowns[part] then return end

            local dist = (part.Position - fromPos).Magnitude
            table.insert(candidates, { part = part, prompt = prompt, dist = dist, year = herbYear })
        end

        if herbSpots then
            for _, spot in ipairs(herbSpots:GetChildren()) do
                if spot:IsA("BasePart") then evaluatePart(spot, spot:FindFirstChildOfClass("ProximityPrompt")) end
            end
        end

        for prompt in pairs(Env.cachedHerbPrompts) do
            if prompt and prompt.Parent then
                if prompt.Enabled and prompt.Parent:IsA("BasePart") then evaluatePart(prompt.Parent, prompt) end
            else
                Env.cachedHerbPrompts[prompt] = nil
            end
        end

        if #candidates == 0 then return nil, nil, 999999, 0 end

        table.sort(candidates, function(a, b)
            local a1000, b1000 = a.year >= 1000, b.year >= 1000
            if a1000 ~= b1000 then return a1000 end
            return a.dist < b.dist
        end)

        return candidates[1].part, candidates[1].prompt, candidates[1].dist, candidates[1].year
    end

    function Hub.Fn.startFarmLoop()
        initHerbCache()
        Hub.Fn.logDebug("เริ่มลูปเก็บสมุนไพร...")
        while State.isFarming do
            local char, hrp, humanoid = Hub.Fn.getCharacter()
            if char and hrp and humanoid and humanoid.Health > 0 then
                local herbPart, prompt, _, herbYear = getBestHerbTarget(hrp.Position)

                if herbPart and herbPart.Parent then
                    Env.currentHerbTargetName = herbPart.Name .. " (" .. herbYear .. "Yr)"
                    local standCFrame = herbPart.CFrame * CFrame.new(0, 1.5, 1.8)
                    Hub.Fn.safeTeleport(hrp, standCFrame)
                    Env.groundPlatform.CFrame = standCFrame * CFrame.new(0, -3.2, 0)

                    if not prompt then prompt = herbPart:FindFirstChildOfClass("ProximityPrompt") end

                    if State.isFarming and herbPart.Parent and (not prompt or prompt.Enabled) then
                        if prompt and fireproximityprompt then pcall(fireproximityprompt, prompt) end
                        if Env.Remotes.CollectHerb then Env.Remotes.CollectHerb:FireServer(herbPart) end

                        local waitStart = os.clock()
                        while State.isFarming and herbPart.Parent and (not prompt or prompt.Enabled) and (os.clock() - waitStart) < 0.4 do
                            task.wait(0.03)
                        end

                        local isActuallyCollected = (not herbPart.Parent) or (prompt and not prompt.Enabled)
                        if isActuallyCollected then
                            if not Env.collectedCooldowns[herbPart] or os.clock() > Env.collectedCooldowns[herbPart] then
                                Env.collectedCooldowns[herbPart] = os.clock() + 30
                                Hub.Fn.logDebug("เก็บสำเร็จ: " .. herbPart.Name)

                                State.sessionHerbCount = (State.sessionHerbCount or 0) + 1
                                Hub.Fn.logDebug("🌿 สมุนไพรสะสมรอบนี้: " .. State.sessionHerbCount .. "/130")

                                if State.sessionHerbCount >= 130 then
                                    Hub.Fn.logDebug("🎯 ครบ 130 ชิ้น! กำลังรีจอยน์หนี Rate Limit...")
                                    
                                    State.isFarming = false
                                    Hub.Fn.setWorker("startFarmLoop", false, Hub.Fn.startFarmLoop)
                                    State.sessionHerbCount = 0

                                    task.wait(1)
                                    pcall(function()
                                        TeleportService:Teleport(game.PlaceId, LocalPlayer)
                                    end)
                                    
                                    task.wait(5)
                                end
                            end
                        end
                    end
                else
                    Env.currentHerbTargetName = "Searching (กำลังเดินหา...)"
                    local streamPoints = Hub.Fn.getDynamicStreamPoints()
                    if Env.zoneIndex > #streamPoints then Env.zoneIndex = 1 end
                    local center = streamPoints[Env.zoneIndex] or Vector3.new(0, 120, 0)
                    Env.patrolAngle = Env.patrolAngle + (math.pi / 3)
                    if Env.patrolAngle >= math.pi * 2 then
                        Env.patrolAngle = 0
                        Env.zoneIndex = (Env.zoneIndex % math.max(1, #streamPoints)) + 1
                    end

                    local nextPos = Vector3.new(center.X + math.cos(Env.patrolAngle) * 450, center.Y + 25, center.Z + math.sin(Env.patrolAngle) * 450)
                    pcall(function() workspace:RequestStreamAroundAsync(nextPos) end)

                    local startPos = hrp.Position
                    local steps = math.max(1, math.ceil((nextPos - startPos).Magnitude / 36))

                    for i = 1, steps do
                        if not State.isFarming then break end
                        if getBestHerbTarget(hrp.Position) then break end
                        local stepCFrame = CFrame.new(startPos:Lerp(nextPos, i / steps))
                        Env.groundPlatform.CFrame = stepCFrame * CFrame.new(0, -3.2, 0)
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        hrp.CFrame = stepCFrame
                        task.wait(0.10)
                    end
                end
            else
                task.wait(0.3)
            end
            task.wait(0.03)
        end
        Hub.Fn.logDebug("หยุดเก็บสมุนไพรแล้ว")
    end
end

-- ==================== สร้าง UI และหน้าต่าง Debug ====================
do
    local Env = Hub.Env
    local State = Hub.State
    local UI = Hub.UI

    if PlayerGui:FindFirstChild("MurimHerbFarmGui") then
        PlayerGui.MurimHerbFarmGui:Destroy()
    end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MurimHerbFarmGui"
    ScreenGui.DisplayOrder = 999999
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = PlayerGui

    local OpenToggleBtn = Instance.new("TextButton")
    OpenToggleBtn.Size = UDim2.new(0, 95, 0, 35)
    OpenToggleBtn.Position = UDim2.new(0.02, 0, 0.2, 0)
    OpenToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    OpenToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    OpenToggleBtn.Text = "⚡ Hub [Hide]"
    OpenToggleBtn.Font = Enum.Font.SourceSansBold
    OpenToggleBtn.TextSize = 14
    OpenToggleBtn.Parent = ScreenGui
    Instance.new("UICorner", OpenToggleBtn).CornerRadius = UDim.new(0, 8)

    local DebugPanel = Instance.new("Frame")
    DebugPanel.Size = UDim2.new(0, 320, 0, 180)
    DebugPanel.Position = UDim2.new(0.02, 0, 0.28, 0)
    DebugPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    DebugPanel.BorderSizePixel = 0
    DebugPanel.Parent = ScreenGui
    Instance.new("UICorner", DebugPanel).CornerRadius = UDim.new(0, 8)

    local DebugTop = Instance.new("Frame")
    DebugTop.Size = UDim2.new(1, 0, 0, 26)
    DebugTop.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    DebugTop.BorderSizePixel = 0
    DebugTop.Parent = DebugPanel
    Instance.new("UICorner", DebugTop).CornerRadius = UDim.new(0, 8)

    local DebugTitle = Instance.new("TextLabel")
    DebugTitle.Size = UDim2.new(1, -70, 1, 0)
    DebugTitle.Position = UDim2.new(0, 8, 0, 0)
    DebugTitle.BackgroundTransparency = 1
    DebugTitle.Text = "🐛 Live Debug Monitor"
    DebugTitle.TextColor3 = Color3.fromRGB(255, 215, 110)
    DebugTitle.Font = Enum.Font.SourceSansBold
    DebugTitle.TextSize = 12
    DebugTitle.TextXAlignment = Enum.TextXAlignment.Left
    DebugTitle.Parent = DebugTop

    local DebugContent = Instance.new("TextLabel")
    DebugContent.Size = UDim2.new(1, -12, 1, -34)
    DebugContent.Position = UDim2.new(0, 6, 0, 30)
    DebugContent.BackgroundTransparency = 1
    DebugContent.TextColor3 = Color3.fromRGB(120, 255, 140)
    DebugContent.Text = "กำลังโหลดข้อมูล Debug..."
    DebugContent.Font = Enum.Font.Code
    DebugContent.TextSize = 11
    DebugContent.TextXAlignment = Enum.TextXAlignment.Left
    DebugContent.TextYAlignment = Enum.TextYAlignment.Top
    DebugContent.TextWrapped = true
    DebugContent.Parent = DebugPanel

    task.spawn(function()
        while ScreenGui.Parent do
            pcall(function()
                local char, hrp = Hub.Fn.getCharacter()
                local posStr = hrp and string.format("X:%.0f Y:%.0f Z:%.0f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) or "No Character"
                local text = string.format(
                    "📌 Session Herbs: %d / 130\n🤖 Status: %s\n🎯 Target: %s\n📍 Pos: %s\n⚡ Farming Active: %s",
                    State.sessionHerbCount,
                    tostring(Env.botStatusText),
                    tostring(Env.currentHerbTargetName),
                    posStr,
                    tostring(State.isFarming)
                )
                DebugContent.Text = text
            end)
            task.wait(0.5)
        end
    end)

    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 300, 0, 480)
    MainFrame.Position = UDim2.new(0.38, 0, 0.1, 0)
    MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 35)
    TitleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -40, 1, 0)
    TitleLabel.Position = UDim2.new(0, 10, 0, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = "Murim Hub V32 (Safe Run)"
    TitleLabel.TextColor3 = Color3.fromRGB(230, 230, 250)
    TitleLabel.Font = Enum.Font.SourceSansBold
    TitleLabel.TextSize = 13
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = TitleBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 25, 0, 25)
    CloseBtn.Position = UDim2.new(1, -30, 0, 5)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.Text = "X"
    CloseBtn.Font = Enum.Font.SourceSansBold
    CloseBtn.TextSize = 14
    CloseBtn.Parent = TitleBar
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

    UI.ScrollFrame = Instance.new("ScrollingFrame")
    UI.ScrollFrame.Size = UDim2.new(1, 0, 1, -35)
    UI.ScrollFrame.Position = UDim2.new(0, 0, 0, 35)
    UI.ScrollFrame.BackgroundTransparency = 1
    UI.ScrollFrame.BorderSizePixel = 0
    UI.ScrollFrame.ScrollBarThickness = 5
    UI.ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 600)
    UI.ScrollFrame.Parent = MainFrame

    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollLayout.Padding = UDim.new(0, 6)
    scrollLayout.Parent = UI.ScrollFrame

    local scrollPadding = Instance.new("UIPadding")
    scrollPadding.PaddingLeft = UDim.new(0, 10)
    scrollPadding.PaddingRight = UDim.new(0, 10)
    scrollPadding.PaddingTop = UDim.new(0, 8)
    scrollPadding.PaddingBottom = UDim.new(0, 15)
    scrollPadding.Parent = UI.ScrollFrame

    local function createButton(text, bgCol, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = bgCol
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Text = text
        btn.Font = Enum.Font.SourceSansBold
        btn.TextSize = 12
        btn.LayoutOrder = layoutOrder
        btn.Parent = UI.ScrollFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        return btn
    end

    local ToggleFarmBtn = createButton("⏸ Stop Auto Herbs", Color3.fromRGB(200, 120, 30), 2)
    local ToggleFlightBtn = createButton("🚀 Auto Sword Flight: ON", Color3.fromRGB(60, 200, 60), 3)

    Hub.Fn.connect(ToggleFarmBtn.MouseButton1Click, function()
        State.isFarming = not State.isFarming
        ToggleFarmBtn.Text = State.isFarming and "⏸ Stop Auto Herbs" or "🌿 Start Auto Herbs"
        ToggleFarmBtn.BackgroundColor3 = State.isFarming and Color3.fromRGB(200, 120, 30) or Color3.fromRGB(40, 160, 80)
        Hub.Fn.setWorker("startFarmLoop", State.isFarming, Hub.Fn.startFarmLoop)
    end)

    Hub.Fn.connect(ToggleFlightBtn.MouseButton1Click, function()
        State.isAutoFlight = not State.isAutoFlight
        ToggleFlightBtn.Text = State.isAutoFlight and "🚀 Auto Sword Flight: ON" or "🚀 Auto Sword Flight: OFF"
        ToggleFlightBtn.BackgroundColor3 = State.isAutoFlight and Color3.fromRGB(60, 200, 60) or Color3.fromRGB(100, 100, 100)
        Hub.Fn.setWorker("startSwordFlightLoop", State.isAutoFlight, Hub.Fn.startSwordFlightLoop)
    end)

    local isGuiVisible = true
    Hub.Fn.connect(OpenToggleBtn.MouseButton1Click, function()
        isGuiVisible = not isGuiVisible
        MainFrame.Visible = isGuiVisible
        OpenToggleBtn.Text = isGuiVisible and "⚡ Hub [Hide]" or "⚡ Hub [Open]"
    end)
    Hub.Fn.connect(CloseBtn.MouseButton1Click, function()
        isGuiVisible = false
        MainFrame.Visible = false
        OpenToggleBtn.Text = "⚡ Hub [Open]"
    end)

    Hub.Fn.setWorker("startFarmLoop", State.isFarming, Hub.Fn.startFarmLoop)
    Hub.Fn.setWorker("startSwordFlightLoop", State.isAutoFlight, Hub.Fn.startSwordFlightLoop)
    Hub.Fn.setWorker("startDynamicStreamLoop", State.isDynamicStream, Hub.Fn.startDynamicStreamLoop)
    Hub.Fn.logDebug("พร้อมใช้งาน V32 (Safe Run)!")
end
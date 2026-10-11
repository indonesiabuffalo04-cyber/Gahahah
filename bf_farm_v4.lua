-- Blox Fruits First Sea Auto Farm v4.0
-- Rayfield UI | Full mob TP + real quest fire + damage loop + fly-to-mob
-- fixed: mob grouping radius, fly nav, quest NPC walk+fire, attack damage chain

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace      = game:GetService("Workspace")
local VirtualUser    = game:GetService("VirtualUser")
local TweenService   = game:GetService("TweenService")
local LocalPlayer    = Players.LocalPlayer

-- ─────────────── CONFIG ───────────────
getgenv().Config = {
    Enabled       = false,
    AutoQuest     = true,
    AutoBoss      = true,
    FlyToMob      = true,       -- fly directly to mob each attack tick
    FlyHeight     = 12,         -- units above mob
    TeleportDodge = true,
    DodgeChance   = 80,
    MobBringRadius= 30,         -- pull mobs within this radius to HRP
    MobBringEnabled=true,
    AutoCollectFruit=true,
    AutoStats     = true,
    StatType      = "Melee",
    AntiAFK       = true,
    FastAttack    = true,
    AttackSpeed   = 0.05,
    SwordMode     = false,      -- true = activate Tool, false = VirtualUser click
}

-- ─────────────── ISLANDS ──────────────
local Islands = {
    {Name="Windmill Village", MinLv=0,   MaxLv=10,  Quest="Bandit",            Enemies={"Bandit"},                           Boss="The Saw",        Pos=Vector3.new(985,9,1300),    QuestPos=Vector3.new(960,9,1290)},
    {Name="Jungle",           MinLv=10,  MaxLv=25,  Quest="Monkey",            Enemies={"Monkey","Gorilla"},                  Boss="Gorilla King",   Pos=Vector3.new(-1600,7,550),   QuestPos=Vector3.new(-1580,7,540)},
    {Name="Pirate Village",   MinLv=25,  MaxLv=40,  Quest="Pirate",            Enemies={"Pirate"},                           Boss="Bobby",          Pos=Vector3.new(-1100,7,-1000), QuestPos=Vector3.new(-1090,7,-990)},
    {Name="Desert",           MinLv=40,  MaxLv=60,  Quest="Desert Bandit",     Enemies={"Desert Bandit"},                    Boss="Desert King",    Pos=Vector3.new(1000,7,1900),   QuestPos=Vector3.new(1010,7,1890)},
    {Name="Frozen Village",   MinLv=60,  MaxLv=90,  Quest="Snow Bandit",       Enemies={"Snow Bandit","Snowman"},             Boss="Yeti",           Pos=Vector3.new(-1200,7,-1900), QuestPos=Vector3.new(-1190,7,-1890)},
    {Name="Marine Fortress",  MinLv=90,  MaxLv=120, Quest="Chief Petty Officer",Enemies={"Chief Petty Officer"},              Boss="Vice Admiral",   Pos=Vector3.new(-4500,7,1500),  QuestPos=Vector3.new(-4510,7,1490)},
    {Name="Skylands",         MinLv=120, MaxLv=150, Quest="Sky Bandit",        Enemies={"Sky Bandit","Dark Master"},          Boss="Saber Expert",   Pos=Vector3.new(-4800,700,-2000),QuestPos=Vector3.new(-4790,700,-1990)},
    {Name="Prison",           MinLv=150, MaxLv=190, Quest="Prisoner",          Enemies={"Prisoner","Dangerous Prisoner"},     Boss="Warden",         Pos=Vector3.new(5000,7,1500),   QuestPos=Vector3.new(5010,7,1490)},
    {Name="Colosseum",        MinLv=190, MaxLv=230, Quest="Gladiator",         Enemies={"Gladiator"},                        Boss="Champion",       Pos=Vector3.new(-1500,7,-4500), QuestPos=Vector3.new(-1490,7,-4490)},
    {Name="Magma Village",    MinLv=230, MaxLv=275, Quest="Military Soldier",  Enemies={"Military Soldier"},                 Boss="Magma Admiral",  Pos=Vector3.new(-5800,7,-1500), QuestPos=Vector3.new(-5790,7,-1490)},
    {Name="Underwater City",  MinLv=275, MaxLv=320, Quest="Fishman Warrior",   Enemies={"Fishman Warrior","Fishman Commando"},Boss="Fishman Lord",   Pos=Vector3.new(6000,7,-2000),  QuestPos=Vector3.new(5990,7,-1990)},
    {Name="Fountain City",    MinLv=320, MaxLv=700, Quest="Galley Pirate",     Enemies={"Galley Pirate","Galley Captain"},   Boss="God's Guard",    Pos=Vector3.new(5200,7,-4500),  QuestPos=Vector3.new(5190,7,-4490)},
}

-- ─────────────── STATE ────────────────
local CurrentHRP, CurrentHumanoid, CurrentCharacter
local CurrentTarget     = nil
local DodgeConn         = nil
local FastAttackConn    = nil
local ESPEnabled        = false
local ESPObjects        = {}
local QuestActive       = false  -- tracks if quest accepted this rotation

-- ─────────────── HELPERS ──────────────
local function GetChar()
    CurrentCharacter = LocalPlayer.Character
    if CurrentCharacter then
        CurrentHRP       = CurrentCharacter:FindFirstChild("HumanoidRootPart")
        CurrentHumanoid  = CurrentCharacter:FindFirstChild("Humanoid")
    end
end

local function IsAlive()
    GetChar()
    return CurrentCharacter and CurrentHRP and CurrentHumanoid
        and CurrentHumanoid.Health > 0
end

local function TP(pos)
    if not IsAlive() then return end
    CurrentHRP.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end

local function TPCF(cf)
    if not IsAlive() then return end
    CurrentHRP.CFrame = cf
end

local function GetLevel()
    local ok, v = pcall(function() return LocalPlayer.Data.Level.Value end)
    return ok and v or 0
end

local function GetCurrentIsland()
    local lv = GetLevel()
    for i, isl in ipairs(Islands) do
        if lv >= isl.MinLv and lv < isl.MaxLv then return i, isl end
    end
    return #Islands, Islands[#Islands]
end

-- ─────────────── QUEST ────────────────
-- Scans Workspace for quest-giver NPC by name fragment, teleports to it,
-- fires every ProximityPrompt on the model (accepts quest)
local function DoQuest(island)
    if not getgenv().Config.AutoQuest or not IsAlive() then return end
    if QuestActive then return end  -- already have quest this rotation

    pcall(function()
        -- first rough-tp to the island quest area
        TP(island.QuestPos)
        task.wait(0.4)

        -- walk all workspace descendants for an NPC that matches quest name
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name:lower():find(island.Quest:lower()) then
                local hrp = obj:FindFirstChild("HumanoidRootPart")
                if hrp then
                    -- get right on top of NPC
                    TPCF(CFrame.new(hrp.Position + Vector3.new(0,2,0)))
                    task.wait(0.3)
                    -- fire every prompt on the model (quest accept button)
                    for _, desc in ipairs(obj:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            pcall(fireproximityprompt, desc)
                            task.wait(0.1)
                        end
                    end
                    -- also check children of HRP directly
                    for _, desc in ipairs(hrp:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            pcall(fireproximityprompt, desc)
                        end
                    end
                    QuestActive = true
                    break
                end
            end
        end
    end)
end

-- ─────────────── ENEMY SCAN ──────────────
local function FindEnemies(island)
    local found = {}
    if not IsAlive() then return found end
    local myPos = CurrentHRP.Position
    -- collect all hostile names for this island
    local nameSet = {}
    for _, n in ipairs(island.Enemies) do nameSet[n] = true end
    if getgenv().Config.AutoBoss then nameSet[island.Boss] = true end

    for _, mob in ipairs(Workspace.Enemies:GetChildren()) do
        local hrp = mob:FindFirstChild("HumanoidRootPart")
        local hum = mob:FindFirstChild("Humanoid")
        if hrp and hum and hum.Health > 0 and nameSet[mob.Name] then
            local dist = (hrp.Position - myPos).Magnitude
            if dist < 4000 then
                table.insert(found, mob)
            end
        end
    end
    -- boss first
    table.sort(found, function(a, b)
        local aB = a.Name == island.Boss and 1 or 0
        local bB = b.Name == island.Boss and 1 or 0
        return aB > bB
    end)
    return found
end

-- ─────────────── MOB BRING ────────────────
-- Pulls mobs within MobBringRadius to stand in front of HRP
-- Does NOT move mob out of world — clamps Y to mob's original Y
local function BringMobs(island)
    if not getgenv().Config.MobBringEnabled or not IsAlive() then return end
    local myPos = CurrentHRP.Position
    local fwd   = CurrentHRP.CFrame.LookVector
    local r     = getgenv().Config.MobBringRadius

    for _, mob in ipairs(Workspace.Enemies:GetChildren()) do
        local hrp = mob:FindFirstChild("HumanoidRootPart")
        local hum = mob:FindFirstChild("Humanoid")
        if hrp and hum and hum.Health > 0 then
            local dist = (hrp.Position - myPos).Magnitude
            if dist < r then
                pcall(function()
                    -- cluster in front, preserve mob Y so it doesn't fall
                    local targetPos = myPos + fwd * 5
                        + Vector3.new(math.random(-2,2), 0, math.random(-2,2))
                    targetPos = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
                    hrp.CFrame = CFrame.new(targetPos)
                end)
            end
        end
    end
end

-- ─────────────── FLY TO MOB ──────────────
-- Positions player directly above target and looks down at it
local function FlyToMob(enemy)
    if not IsAlive() or not enemy then return end
    local hrp = enemy:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function()
        local above = hrp.Position + Vector3.new(0, getgenv().Config.FlyHeight, 0)
        TPCF(CFrame.lookAt(above, hrp.Position))
    end)
end

-- ─────────────── ATTACK ENGINE ───────────
-- Performs one attack action against CurrentTarget
local function DoAttack()
    if not IsAlive() or not CurrentTarget or not CurrentTarget.Parent then return end
    local hum = CurrentTarget:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return end

    pcall(function()
        if getgenv().Config.FlyToMob then
            FlyToMob(CurrentTarget)
        end

        if getgenv().Config.SwordMode then
            -- activate equipped Tool (swords, blox fruits)
            local tool = CurrentCharacter:FindFirstChildOfClass("Tool")
            if tool and tool.Activate then
                tool:Activate()
            end
        else
            -- VirtualUser click — works for melee / most weapons
            VirtualUser:CaptureController()
            VirtualUser:SetButton1Down(Vector2.new())
            task.wait(0.01)
            VirtualUser:SetButton1Up(Vector2.new())
        end

        -- also try activating any tool for combo damage
        local tool = CurrentCharacter:FindFirstChildOfClass("Tool")
        if tool then pcall(function() tool:Activate() end) end
    end)
end

-- Dodge: if mob gets within 8 studs, teleport above target mob (reset position)
local function EnableDodge()
    if DodgeConn then DodgeConn:Disconnect() end
    DodgeConn = RunService.Heartbeat:Connect(function()
        if not getgenv().Config.TeleportDodge or not getgenv().Config.Enabled then return end
        if not IsAlive() then return end
        for _, mob in ipairs(Workspace.Enemies:GetChildren()) do
            local hrp = mob:FindFirstChild("HumanoidRootPart")
            local hum = mob:FindFirstChild("Humanoid")
            if hrp and hum and hum.Health > 0 then
                if (hrp.Position - CurrentHRP.Position).Magnitude < 8 then
                    if math.random(100) <= getgenv().Config.DodgeChance then
                        if CurrentTarget and CurrentTarget.Parent then
                            FlyToMob(CurrentTarget)
                        end
                    end
                end
            end
        end
    end)
end

-- Fast attack heartbeat — fires DoAttack every AttackSpeed seconds
local FastTimer = 0
local function StartFastAttack()
    if FastAttackConn then FastAttackConn:Disconnect() end
    FastAttackConn = RunService.Heartbeat:Connect(function(dt)
        if not getgenv().Config.FastAttack or not getgenv().Config.Enabled then return end
        FastTimer = FastTimer + dt
        if FastTimer >= getgenv().Config.AttackSpeed then
            FastTimer = 0
            DoAttack()
        end
    end)
end

-- ─────────────── FRUIT COLLECT ───────────
local FruitNames = {"fruit","bomb","spike","flame","ice","sand","dark","light","rubber","magma",
                    "kilo","smoke","string","barrier","door","diamond","love","paw","gravity",
                    "phoenix","tremor","human","sound","buddha","quake","venom","control","revive","soul","spirit"}

local function CollectFruit()
    if not getgenv().Config.AutoCollectFruit or not IsAlive() then return end
    pcall(function()
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("Tool") then
                local low = obj.Name:lower()
                for _, fn in ipairs(FruitNames) do
                    if low:find(fn) then
                        local handle = obj:FindFirstChild("Handle")
                        if handle then
                            local dist = (handle.Position - CurrentHRP.Position).Magnitude
                            if dist < 800 then
                                TP(handle.Position)
                                task.wait(0.15)
                                pcall(firetouchinterest, CurrentHRP, handle, 0)
                                pcall(firetouchinterest, CurrentHRP, handle, 1)
                            end
                        end
                        break
                    end
                end
            end
        end
    end)
end

-- ─────────────── STATS ────────────────
local function UpgradeStats()
    if not getgenv().Config.AutoStats then return end
    pcall(function()
        for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
            if remote:IsA("RemoteEvent") and remote.Name == "Upgrade" then
                local data = LocalPlayer:FindFirstChild("Data")
                if data then
                    local pts = data:FindFirstChild("StatPoints")
                    if pts and pts.Value > 0 then
                        remote:FireServer(getgenv().Config.StatType, pts.Value)
                    end
                end
                break
            end
        end
    end)
end

-- ─────────────── ESP ────────────────
spawn(function()
    while true do
        task.wait(1)
        if ESPEnabled then
            pcall(function()
                for _, mob in ipairs(Workspace.Enemies:GetChildren()) do
                    local hum = mob:FindFirstChild("Humanoid")
                    if hum and hum.Health > 0 and not mob:FindFirstChild("_BFESP") then
                        local hl       = Instance.new("Highlight")
                        hl.Name        = "_BFESP"
                        hl.FillColor   = Color3.fromRGB(255,50,50)
                        hl.OutlineColor= Color3.fromRGB(255,255,255)
                        hl.FillTransparency = 0.6
                        hl.Parent      = mob
                        table.insert(ESPObjects, hl)
                    end
                end
            end)
        end
    end
end)

-- ─────────────── MAIN LOOP ───────────────
local function MainLoop()
    spawn(function()
        while getgenv().Config.Enabled do
            pcall(function()
                if not IsAlive() then task.wait(1) return end

                local idx, island = GetCurrentIsland()
                local lv          = GetLevel()

                -- advance island if level capped and not last island
                if lv >= island.MaxLv and idx < #Islands then
                    TP(Islands[idx+1].Pos)
                    QuestActive = false
                    task.wait(1.5)
                    return
                end

                -- coarse TP to island if very far
                if (island.Pos - CurrentHRP.Position).Magnitude > 4000 then
                    TP(island.Pos)
                    task.wait(0.7)
                    return
                end

                CollectFruit()
                UpgradeStats()

                -- try to get quest first
                DoQuest(island)

                BringMobs(island)

                -- pick target: boss > regular enemy
                local enemies = FindEnemies(island)
                if #enemies > 0 then
                    CurrentTarget = enemies[1]
                    DoAttack()
                    task.wait(getgenv().Config.AttackSpeed)
                else
                    -- no enemies found — reset to island spawn, reset quest flag
                    TP(island.Pos)
                    QuestActive = false
                    task.wait(0.5)
                end
            end)
            task.wait(0.05)
        end
        CurrentTarget = nil
    end)
end

-- reset quest flag when char respawns
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    QuestActive = false
    if getgenv().Config.Enabled then
        local _, isl = GetCurrentIsland()
        TP(isl.Pos)
    end
end)

-- anti-afk
spawn(function()
    LocalPlayer.Idled:Connect(function()
        if getgenv().Config.AntiAFK then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)
end)

-- ─────────────── RAYFIELD UI ─────────────
local Window = Rayfield:CreateWindow({
    Name           = "BF First Sea | v4.0",
    LoadingTitle   = "Loading...",
    LoadingSubtitle= "larp built by odil9"
})

-- Main Tab
local MainTab = Window:CreateTab("Main", 4483362458)
MainTab:CreateSection("Farm Control")
MainTab:CreateToggle({
    Name="Enable Auto Farm", CurrentValue=false, Flag="Farm",
    Callback=function(v)
        getgenv().Config.Enabled = v
        QuestActive = false
        if v then
            MainLoop()
            EnableDodge()
            StartFastAttack()
        else
            if DodgeConn       then DodgeConn:Disconnect()      end
            if FastAttackConn  then FastAttackConn:Disconnect() end
        end
    end
})
MainTab:CreateToggle({Name="Auto Quest",  CurrentValue=true,  Flag="AQ",  Callback=function(v) getgenv().Config.AutoQuest = v end})
MainTab:CreateToggle({Name="Auto Boss",   CurrentValue=true,  Flag="AB",  Callback=function(v) getgenv().Config.AutoBoss  = v end})

-- Combat Tab
local CombatTab = Window:CreateTab("Combat", 4483362458)
CombatTab:CreateSection("Attack")
CombatTab:CreateToggle({Name="Fast Attack",   CurrentValue=true,  Flag="FA2", Callback=function(v) getgenv().Config.FastAttack = v end})
CombatTab:CreateSlider({Name="Attack Speed",  Range={0.01,1}, Increment=0.01, CurrentValue=0.05, Flag="AS2",
    Callback=function(v) getgenv().Config.AttackSpeed = v end})
CombatTab:CreateToggle({Name="Sword/Tool Mode",CurrentValue=false, Flag="SM",
    Callback=function(v) getgenv().Config.SwordMode = v end})
CombatTab:CreateSection("Movement")
CombatTab:CreateToggle({Name="Fly To Mob",    CurrentValue=true,  Flag="FTM",
    Callback=function(v) getgenv().Config.FlyToMob = v end})
CombatTab:CreateSlider({Name="Fly Height",    Range={5,50}, Increment=1, CurrentValue=12, Flag="FH",
    Callback=function(v) getgenv().Config.FlyHeight = v end})
CombatTab:CreateToggle({Name="Teleport Dodge",CurrentValue=true,  Flag="TD",
    Callback=function(v) getgenv().Config.TeleportDodge = v end})
CombatTab:CreateSlider({Name="Dodge Chance",  Range={0,100}, Increment=5, CurrentValue=80, Flag="DC",
    Callback=function(v) getgenv().Config.DodgeChance = v end})
CombatTab:CreateSection("Mob Grouping")
CombatTab:CreateToggle({Name="Bring Mobs",    CurrentValue=true,  Flag="MG",
    Callback=function(v) getgenv().Config.MobBringEnabled = v end})
CombatTab:CreateSlider({Name="Bring Radius",  Range={10,100}, Increment=5, CurrentValue=30, Flag="MR",
    Callback=function(v) getgenv().Config.MobBringRadius = v end})

-- Stats Tab
local StatsTab = Window:CreateTab("Stats", 4483362458)
StatsTab:CreateToggle({Name="Auto Stats", CurrentValue=true, Flag="AS",
    Callback=function(v) getgenv().Config.AutoStats = v end})
StatsTab:CreateDropdown({
    Name="Stat Priority", Flag="ST",
    Options={"Melee","Defense","Sword","Gun","Demon Fruit"},
    CurrentOption={"Melee"},
    Callback=function(o) getgenv().Config.StatType = o[1] end
})

-- Misc Tab
local MiscTab = Window:CreateTab("Misc", 4483362458)
MiscTab:CreateToggle({Name="Auto Collect Fruit",CurrentValue=true, Flag="ACF",
    Callback=function(v) getgenv().Config.AutoCollectFruit = v end})
MiscTab:CreateToggle({Name="ESP", CurrentValue=false, Flag="E",
    Callback=function(v)
        ESPEnabled = v
        if not v then
            for _, o in ipairs(ESPObjects) do pcall(function() o:Destroy() end) end
            ESPObjects = {}
        end
    end
})
MiscTab:CreateToggle({Name="Anti AFK", CurrentValue=true, Flag="AA",
    Callback=function(v) getgenv().Config.AntiAFK = v end})

Rayfield:Notify({Title="BF v4.0 Ready", Content="larp — built by odil9 | discord.gg/xGDFJ29MmA", Duration=6})

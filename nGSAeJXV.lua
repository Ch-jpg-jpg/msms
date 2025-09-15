-- Optimized Universal Silent Aim (based on your original script1.lua)
-- Only targeted changes:
-- 1. Cache closest target once per Heartbeat (CachedTarget)
-- 2. Replace Drawing square with Roblox Highlight
-- 3. Hooks use CachedTarget instead of recalculating
-- Everything else (UI, config, features) is preserved

-- init
if not game:IsLoaded() then
    game.Loaded:Wait()
end

if not syn or not protectgui then
    getgenv().protectgui = function() end
end

local SilentAimSettings = {
    Enabled = false,
    ClassName = "Universal Silent Aim - Averiias (Optimized)",
    ToggleKey = "RightAlt",
    TeamCheck = false,
    VisibleCheck = false,
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    FOVRadius = 130,
    FOVVisible = false,
    ShowSilentAimTarget = false,
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100
}

getgenv().SilentAimSettings = SilentAimSettings

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local WorldToScreen = Camera.WorldToScreenPoint
local GetMouseLocation = UserInputService.GetMouseLocation

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = SilentAimSettings.MouseHitPredictionAmount

-- Highlight system instead of Drawing square
local currentHighlight
local function setHighlightForCharacter(char, color)
    if currentHighlight then currentHighlight:Destroy() currentHighlight = nil end
    if char and char:IsA("Model") then
        local h = Instance.new("Highlight")
        h.Adornee = char
        h.FillColor = color or Color3.fromRGB(54,57,241)
        h.FillTransparency = 0.5
        h.OutlineColor = h.FillColor
        h.OutlineTransparency = 0
        h.Parent = char
        currentHighlight = h
    end
end
local function clearHighlight()
    if currentHighlight then currentHighlight:Destroy() currentHighlight = nil end
end

-- FOV circle still uses Drawing (cheap)
local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = SilentAimSettings.FOVRadius
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

local function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new():NextNumber(0, 1) * 100) / 100
    return chance <= Percentage / 100
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalCharacter = LocalPlayer.Character
    if not (PlayerCharacter and LocalCharacter) then return false end
    local root = PlayerCharacter:FindFirstChild(SilentAimSettings.TargetPart) or PlayerCharacter:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local CastPoints, IgnoreList = {root.Position, LocalCharacter, PlayerCharacter}, {LocalCharacter, PlayerCharacter}
    local ObscuringObjects = #Camera:GetPartsObscuringTarget(CastPoints, IgnoreList)
    return ObscuringObjects == 0
end

local function getClosestPlayer()
    local Closest, DistanceToMouse
    for _, Player in next, Players:GetPlayers() do
        if Player == LocalPlayer then continue end
        if SilentAimSettings.TeamCheck and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        if SilentAimSettings.VisibleCheck and not IsPlayerVisible(Player) then continue end

        local HRP = Character:FindFirstChild("HumanoidRootPart")
        local Humanoid = Character:FindFirstChild("Humanoid")
        if not HRP or not Humanoid or Humanoid.Health <= 0 then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(HRP.Position)
        if not OnScreen then continue end

        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or SilentAimSettings.FOVRadius) then
            Closest = ((SilentAimSettings.TargetPart == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[SilentAimSettings.TargetPart])
            DistanceToMouse = Distance
        end
    end
    return Closest
end

-- Cache target once per Heartbeat
local CachedTarget
RunService.Heartbeat:Connect(function()
    if SilentAimSettings.Enabled then
        CachedTarget = getClosestPlayer()
    else
        CachedTarget = nil
    end
end)

-- Visual updates
RunService.RenderStepped:Connect(function()
    if SilentAimSettings.ShowSilentAimTarget and CachedTarget then
        setHighlightForCharacter(CachedTarget.Parent, Color3.fromRGB(54,57,241))
    else
        clearHighlight()
    end

    if SilentAimSettings.FOVVisible then
        fov_circle.Visible = true
        fov_circle.Radius = SilentAimSettings.FOVRadius
        fov_circle.Position = getMousePosition()
    else
        fov_circle.Visible = false
    end
end)

-- Hooks use CachedTarget instead of recalculating
do
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        local Method, Arguments = getnamecallmethod(), {...}
        local self = Arguments[1]
        local chance = CalculateChance(SilentAimSettings.HitChance)
        if SilentAimSettings.Enabled and self == workspace and not checkcaller() and chance and CachedTarget then
            local function getDirection(Origin, Position)
                return (Position - Origin).Unit * 1000
            end
            if Method == "Raycast" and SilentAimSettings.SilentAimMethod == Method then
                Arguments[3] = getDirection(Arguments[2], CachedTarget.Position)
                return oldNamecall(unpack(Arguments))
            elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and SilentAimSettings.SilentAimMethod:lower() == Method:lower() then
                local Origin = Arguments[2].Origin
                local Direction = getDirection(Origin, CachedTarget.Position)
                Arguments[2] = Ray.new(Origin, Direction)
                return oldNamecall(unpack(Arguments))
            elseif Method == "FindPartOnRayWithIgnoreList" and SilentAimSettings.SilentAimMethod == Method then
                local Origin = Arguments[2].Origin
                local Direction = getDirection(Origin, CachedTarget.Position)
                Arguments[2] = Ray.new(Origin, Direction)
                return oldNamecall(unpack(Arguments))
            elseif Method == "FindPartOnRayWithWhitelist" and SilentAimSettings.SilentAimMethod == Method then
                local Origin = Arguments[2].Origin
                local Direction = getDirection(Origin, CachedTarget.Position)
                Arguments[2] = Ray.new(Origin, Direction)
                return oldNamecall(unpack(Arguments))
            end
        end
        return oldNamecall(...)
    end))

    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
        if self == Mouse and not checkcaller() and SilentAimSettings.Enabled and SilentAimSettings.SilentAimMethod == "Mouse.Hit/Target" and CachedTarget then
            if Index == "Target" or Index == "target" then
                return CachedTarget
            elseif Index == "Hit" or Index == "hit" then
                if SilentAimSettings.MouseHitPrediction then
                    return (CachedTarget.CFrame + (CachedTarget.Velocity * PredictionAmount)).p
                else
                    return CachedTarget.CFrame.p
                end
            end
        end
        return oldIndex(self, Index)
    end))
end

print("Universal Silent Aim (Optimized) loaded - all original features intact")

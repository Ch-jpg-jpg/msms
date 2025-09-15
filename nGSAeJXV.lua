-- Universal Silent Aim - Optimized + Full UI merged
-- merged and optimized by assistant: caches target, uses Highlight for visuals,
-- preserves Linoria UI + save/load + options from original script1.lua

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

-- variables
getgenv().SilentAimSettings = SilentAimSettings
local MainFileName = "UniversalSilentAim"
local SelectedFile, FileToSave = "", ""

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local GetChildren = game.GetChildren
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local Heartbeat = RunService.Heartbeat
local GuiInset = GuiService.GetGuiInset
local GetMouseLocation = UserInputService.GetMouseLocation

local resume = coroutine.resume
local create = coroutine.create

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

-- keep a small Drawing circle for FOV (cheap) but avoid heavy Square
local statusHasDrawing = pcall(function() Drawing.new("Circle") end)
local fov_circle
if statusHasDrawing then
    fov_circle = Drawing.new("Circle")
    fov_circle.Thickness = 1
    fov_circle.NumSides = 100
    fov_circle.Radius = SilentAimSettings.FOVRadius
    fov_circle.Filled = false
    fov_circle.Visible = false
    fov_circle.ZIndex = 999
    fov_circle.Transparency = 1
    fov_circle.Color = Color3.fromRGB(54, 57, 241)
end

-- create highlight visual (engine friendly) and manage it
local currentHighlight
local function setHighlightForCharacter(char, color)
    if currentHighlight then
        pcall(function() currentHighlight:Destroy() end)
        currentHighlight = nil
    end
    if char and char:IsA("Model") then
        local h = char:FindFirstChildOfClass("Highlight")
        if not h then
            h = Instance.new("Highlight")
            h.Parent = char
            h.Adornee = char
        end
        h.FillColor = color or Color3.fromRGB(54,57,241)
        h.FillTransparency = 0.5
        h.OutlineColor = h.FillColor
        h.OutlineTransparency = 0
        currentHighlight = h
    end
end

local function clearHighlight()
    if currentHighlight then
        pcall(function() currentHighlight:Destroy() end)
        currentHighlight = nil
    end
end

local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = {
        ArgCountRequired = 3,
        Args = {"Instance", "Ray", "table", "boolean", "boolean"}
    },
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
    FindPartOnRayWithWhitelist = {
        ArgCountRequired = 3,
        Args = {"Instance", "Ray", "table", "boolean"}
    },
    FindPartOnRay = {
        ArgCountRequired = 2,
        Args = {"Instance", "Ray", "Instance", "boolean", "boolean"}
    },
    Raycast = {
        ArgCountRequired = 3,
        Args = {"Instance", "Vector3", "Vector3", "RaycastParams"}
    }
}

local function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    return chance <= Percentage / 100
end

--[[file handling]] do
    if not isfolder(MainFileName) then
        makefolder(MainFileName)
    end
    if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then
        makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
    end
end

local Files = listfiles(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))

local function GetFiles()
    local out = {}
    for i = 1, #Files do
        local file = Files[i]
        if file:sub(-4) == '.lua' then
            local pos = file:find('.lua', 1, true)
            local start = pos
            local char = file:sub(pos, pos)
            while char ~= '/' and char ~= '\' and char ~= '' do
                pos = pos - 1
                char = file:sub(pos, pos)
            end
            if char == '/' or char == '\' then
                table.insert(out, file:sub(pos + 1, start - 1))
            end
        end
    end
    return out
end

local function UpdateFile(FileName)
    assert(FileName or FileName == "string", "oopsies")
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    assert(FileName or FileName == "string", "oopsies")
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do
        SilentAimSettings[Index] = Value
    end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then
        return false
    end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then
            Matches = Matches + 1
        end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    if not (PlayerCharacter or LocalPlayerCharacter) then return end
    local PlayerRoot = FindFirstChild(PlayerCharacter, SilentAimSettings.TargetPart) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    if not PlayerRoot then return end
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    return ((ObscuringObjects == 0 and true) or (ObscuringObjects > 0 and false))
end

-- original getClosestPlayer but we will cache its result to avoid repeated heavy calls
local function getClosestPlayerInternal(OptionsTable)
    local OptionsRef = OptionsTable or {TargetPart = {Value = SilentAimSettings.TargetPart}, Radius = {Value = SilentAimSettings.FOVRadius}, TeamCheck = {Value = SilentAimSettings.TeamCheck}, VisibleCheck = {Value = SilentAimSettings.VisibleCheck}}
    local Closest
    local DistanceToMouse
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if OptionsRef.TeamCheck.Value and Player.Team == LocalPlayer.Team then continue end
        local Character = Player.Character
        if not Character then continue end
        if OptionsRef.VisibleCheck.Value and not IsPlayerVisible(Player) then continue end
        local HumanoidRootPart = FindFirstChild(Character, "HumanoidRootPart")
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid and Humanoid.Health <= 0 then continue end
        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        if not OnScreen then continue end
        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or OptionsRef.Radius.Value or 2000) then
            Closest = ((OptionsRef.TargetPart.Value == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[OptionsRef.TargetPart.Value])
            DistanceToMouse = Distance
        end
    end
    return Closest
end

-- caching: update once per Heartbeat
local CachedTarget = nil
Heartbeat:Connect(function()
    if SilentAimSettings.Enabled then
        -- prefer using the UI Options if available (Options variable created below by UI). We try both to be safe.
        if _G and _G.Options and _G.Options.TargetPart then
            CachedTarget = getClosestPlayerInternal(_G.Options)
        else
            CachedTarget = getClosestPlayerInternal()
        end
    else
        CachedTarget = nil
    end
end)

-- UI creating & handling (preserve original Linoria interactions)
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
Library:SetWatermark("github.com/Averiias")

local Window = Library:CreateWindow({Title = 'Universal Silent Aim', Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2})
local GeneralTab = Window:AddTab("General")
local MainBOX = GeneralTab:AddLeftTabbox("Main") do
    local Main = MainBOX:AddTab("Main")
    Main:AddToggle("aim_Enabled", {Text = "Enabled"}):AddKeyPicker("aim_Enabled_KeyPicker", {Default = "RightAlt", SyncToggleState = true, Mode = "Toggle", Text = "Enabled", NoUI = false});
    Options.aim_Enabled_KeyPicker:OnClick(function()
        SilentAimSettings.Enabled = not SilentAimSettings.Enabled
        Toggles.aim_Enabled.Value = SilentAimSettings.Enabled
        Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled)
        -- toggle visuals
        if SilentAimSettings.ShowSilentAimTarget then
            if SilentAimSettings.Enabled and CachedTarget then
                setHighlightForCharacter(CachedTarget.Parent, Options.MouseVisualizeColor and Options.MouseVisualizeColor.Value or Color3.fromRGB(54,57,241))
            else
                clearHighlight()
            end
        end
    end)
    Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function()
        SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value
    end)
    Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function()
        SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value
    end)
    Main:AddDropdown("TargetPart", {AllowNull = true, Text = "Target Part", Default = SilentAimSettings.TargetPart, Values = {"Head", "HumanoidRootPart", "Random"}}):OnChanged(function()
        SilentAimSettings.TargetPart = Options.TargetPart.Value
    end)
    Main:AddDropdown("Method", {AllowNull = true, Text = "Silent Aim Method", Default = SilentAimSettings.SilentAimMethod, Values = {"Raycast","FindPartOnRay","FindPartOnRayWithWhitelist","FindPartOnRayWithIgnoreList","Mouse.Hit/Target"}}):OnChanged(function()
        SilentAimSettings.SilentAimMethod = Options.Method.Value
    end)
    Main:AddSlider('HitChance', {Text = 'Hit chance', Default = 100, Min = 0, Max = 100, Rounding = 1, Compact = false,})
    Options.HitChance:OnChanged(function()
        SilentAimSettings.HitChance = Options.HitChance.Value
    end)
end

local MiscellaneousBOX = GeneralTab:AddLeftTabbox("Miscellaneous")
local FieldOfViewBOX = GeneralTab:AddLeftTabbox("Field Of View") do
    local Main = FieldOfViewBOX:AddTab("Visuals")
    Main:AddToggle("Visible", {Text = "Show FOV Circle"}):AddColorPicker("Color", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        if fov_circle then fov_circle.Visible = Toggles.Visible.Value end
        SilentAimSettings.FOVVisible = Toggles.Visible.Value
    end)
    Main:AddSlider("Radius", {Text = "FOV Circle Radius", Min = 0, Max = 360, Default = SilentAimSettings.FOVRadius, Rounding = 0}):OnChanged(function()
        if fov_circle then fov_circle.Radius = Options.Radius.Value end
        SilentAimSettings.FOVRadius = Options.Radius.Value
    end)
    Main:AddToggle("MousePosition", {Text = "Show Silent Aim Target"}):AddColorPicker("MouseVisualizeColor", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        SilentAimSettings.ShowSilentAimTarget = Toggles.MousePosition.Value
        if SilentAimSettings.ShowSilentAimTarget and SilentAimSettings.Enabled and CachedTarget then
            setHighlightForCharacter(CachedTarget.Parent, Options.MouseVisualizeColor.Value)
        else
            clearHighlight()
        end
    end)
    local PredictionTab = MiscellaneousBOX:AddTab("Prediction")
    PredictionTab:AddToggle("Prediction", {Text = "Mouse.Hit/Target Prediction"}):OnChanged(function()
        SilentAimSettings.MouseHitPrediction = Toggles.Prediction.Value
    end)
    PredictionTab:AddSlider("Amount", {Text = "Prediction Amount", Min = 0.165, Max = 1, Default = SilentAimSettings.MouseHitPredictionAmount, Rounding = 3}):OnChanged(function()
        PredictionAmount = Options.Amount.Value
        SilentAimSettings.MouseHitPredictionAmount = Options.Amount.Value
    end)
end

local CreateConfigurationBOX = GeneralTab:AddRightTabbox("Create Configuration") do
    local Main = CreateConfigurationBOX:AddTab("Create Configuration")
    Main:AddInput("CreateConfigTextBox", {Default = "", Numeric = false, Finished = false, Text = "Create Configuration to Create", Tooltip = "Creates a configuration file containing settings you can save and load", Placeholder = "File Name here"}):OnChanged(function()
        if Options.CreateConfigTextBox.Value and string.len(Options.CreateConfigTextBox.Value) ~= "" then
            FileToSave = Options.CreateConfigTextBox.Value
        end
    end)
    Main:AddButton("Create Configuration File", function()
        if FileToSave ~= "" or FileToSave ~= nil then
            UpdateFile(FileToSave)
        end
    end)
end

local SaveConfigurationBOX = GeneralTab:AddRightTabbox("Save Configuration") do
    local Main = SaveConfigurationBOX:AddTab("Save Configuration")
    Main:AddDropdown("SaveConfigurationDropdown", {AllowNull = true, Values = GetFiles(), Text = "Choose Configuration to Save"})
    Main:AddButton("Save Configuration", function()
        if Options.SaveConfigurationDropdown.Value then
            UpdateFile(Options.SaveConfigurationDropdown.Value)
        end
    end)
end

local LoadConfigurationBOX = GeneralTab:AddRightTabbox("Load Configuration") do
    local Main = LoadConfigurationBOX:AddTab("Load Configuration")
    Main:AddDropdown("LoadConfigurationDropdown", {AllowNull = true, Values = GetFiles(), Text = "Choose Configuration to Load"})
    Main:AddButton("Load Configuration", function()
        if table.find(GetFiles(), Options.LoadConfigurationDropdown.Value) then
            LoadFile(Options.LoadConfigurationDropdown.Value)
            -- sync UI toggles back to SilentAimSettings
            Toggles.TeamCheck:SetValue(SilentAimSettings.TeamCheck)
            Toggles.VisibleCheck:SetValue(SilentAimSettings.VisibleCheck)
            Options.TargetPart:SetValue(SilentAimSettings.TargetPart)
            Options.Method:SetValue(SilentAimSettings.SilentAimMethod)
            Toggles.Visible:SetValue(SilentAimSettings.FOVVisible)
            Options.Radius:SetValue(SilentAimSettings.FOVRadius)
            Toggles.MousePosition:SetValue(SilentAimSettings.ShowSilentAimTarget)
            Toggles.Prediction:SetValue(SilentAimSettings.MouseHitPrediction)
            Options.Amount:SetValue(SilentAimSettings.MouseHitPredictionAmount)
            Options.HitChance:SetValue(SilentAimSettings.HitChance)
        end
    end)
end

-- visual updater (uses cached target)
resume(create(function()
    RenderStepped:Connect(function()
        -- Silent aim target visualization: use cached target instead of recalculating
        if SilentAimSettings.ShowSilentAimTarget and SilentAimSettings.Enabled then
            if CachedTarget and CachedTarget.Parent then
                if Options.TeamCheck and Toggles.TeamCheck.Value and CachedTarget:IsA("Player") and CachedTarget.Team == LocalPlayer.Team then
                    clearHighlight()
                else
                    setHighlightForCharacter(CachedTarget.Parent, Options.MouseVisualizeColor and Options.MouseVisualizeColor.Value or Color3.fromRGB(54,57,241))
                end
            else
                clearHighlight()
            end
        else
            clearHighlight()
        end

        -- FOV circle
        if fov_circle then
            if SilentAimSettings.FOVVisible then
                fov_circle.Visible = true
                fov_circle.Color = Options.Color and Options.Color.Value or Color3.fromRGB(54,57,241)
                fov_circle.Position = getMousePosition()
                fov_circle.Radius = Options.Radius and Options.Radius.Value or SilentAimSettings.FOVRadius
            else
                fov_circle.Visible = false
            end
        end
    end)
end))

-- hooks: use CachedTarget first, fallback to getClosestPlayerInternal() if nil (to be safe)
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)

    if Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value and self == workspace and not checkcaller() and chance == true then
        local HitPart = CachedTarget or getClosestPlayerInternal(_G and _G.Options or nil)
        if HitPart then
            if Method == "FindPartOnRayWithIgnoreList" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif Method == "FindPartOnRayWithWhitelist" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and Options.Method.Value:lower() == Method:lower() then
                if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                    local A_Ray = Arguments[2]
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)
                    return oldNamecall(unpack(Arguments))
                end
            elseif Method == "Raycast" and Options.Method.Value == Method then
                if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                    local A_Origin = Arguments[2]
                    Arguments[3] = getDirection(A_Origin, HitPart.Position)
                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex = nil
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value and Options.Method.Value == "Mouse.Hit/Target" then
        local HitPart = CachedTarget or getClosestPlayerInternal(_G and _G.Options or nil)
        if HitPart then
            if Index == "Target" or Index == "target" then
                return HitPart
            elseif Index == "Hit" or Index == "hit" then
                if Toggles.Prediction and Toggles.Prediction.Value then
                    return (HitPart.CFrame + (HitPart.Velocity * PredictionAmount)).p
                else
                    return HitPart.CFrame.p
                end
            end
        end
    end
    return oldIndex(self, Index)
end))

-- keep rest of original features like config saving already above; script ends here

print("Universal Silent Aim (Optimized) loaded")

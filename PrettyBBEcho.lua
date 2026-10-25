local ADDON_NAME = ...
local BLOOD_BOIL = 50842
local DANCING_RUNE_WEAPON = 49028
local PROC_DURATION = 15.0
local ECHO_DURATION = 3.0

-- The echo's own Blood Boil can arrive just after the countdown has already
-- chained; within this window it resyncs the echo instead of counting a link.
local RESYNC_WINDOW = 0.5
-- How long "Chain ended" stays on the chain bar.
local CHAIN_END_HOLD = 2.0

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"

local MIN_WIDTH, MAX_WIDTH = 80, 600
local MIN_HEIGHT, MAX_HEIGHT = 10, 60

local issecretvalue = issecretvalue or function() return false end
local LibEditMode = LibStub and LibStub("LibEditMode", true)

-- Bar textures: a few of Blizzard's own, then every statusbar texture shared
-- through LibSharedMedia (Details and media packs register theirs there).
local BUILTIN_TEXTURES = {
    { "Blizzard", BAR_TEXTURE },
    { "Flat", WHITE },
    { "Blizzard Raid", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { "Blizzard Skills", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

local function GetLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function TexturePath(name)
    for _, t in ipairs(BUILTIN_TEXTURES) do
        if t[1] == name then return t[2] end
    end
    local lsm = GetLSM()
    if lsm and lsm:IsValid("statusbar", name) then
        return lsm:Fetch("statusbar", name)
    end
    return BAR_TEXTURE
end

local function TextureNames()
    local names, seen = {}, {}
    for _, t in ipairs(BUILTIN_TEXTURES) do
        names[#names + 1] = t[1]
        seen[t[1]] = true
    end
    local lsm = GetLSM()
    if lsm then
        for _, name in ipairs(lsm:List("statusbar")) do
            if not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end
    return names
end

local defaults = {
    width = 220,
    height = 22,
    spacing = 4,
    fontSize = 12,
    mode = "both", -- proc15 | echo3 | both | chain
    locked = true,
    chainShowProc = true, -- chain bar also shows the empowered Blood Boil waiting
    orientation = "horizontal", -- horizontal | vertical
    showName = true,
    showTime = true,
    showIcon = true,
    showSpark = true,
    showDRW = true,
    drwDuration = 8,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -140,
    procName = "Boiling Point",
    echoName = "Blood Boil Echo",
    procColor = { r = 0.80, g = 0.10, b = 0.12, a = 1.0 },
    echoColor = { r = 1.00, g = 0.55, b = 0.10, a = 1.0 },
    linkedColor = { r = 0.20, g = 0.80, b = 0.30, a = 1.0 },
    riskColor = { r = 1.00, g = 0.30, b = 0.10, a = 1.0 },
    drwColor = { r = 0.60, g = 0.30, b = 0.95, a = 1.0 },
    barTexture = "Blizzard",
    bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.70 },
    borderColor = { r = 0.00, g = 0.00, b = 0.00, a = 1.0 },
    textColor = { r = 1.00, g = 1.00, b = 1.00, a = 1.0 },
}

local DB
local procGlow = false
local procExpiresAt = 0
local echoRunning = false
local echoStartedAt = 0
local echoExpiresAt = 0
local procDuringEcho = false
local chainCount = 0
local chainEndedAt = 0
local drwExpiresAt = 0
local lastBloodBoilCast = 0
local lastGlowHide = 0
local sizing = false
local editModeActive = false

local function IsUnlocked()
    return DB and (not DB.locked or editModeActive)
end

-- ============================================================
-- Frames
-- ============================================================
local anchor = CreateFrame("Frame", "PrettyBBEchoAnchor", UIParent)
anchor:SetSize(defaults.width, defaults.height)
anchor:SetClampedToScreen(true)
anchor:SetDontSavePosition(true)
anchor:SetResizable(true)

-- Shown only while unlocked so the whole area can be grabbed and sized.
local unlockBg = anchor:CreateTexture(nil, "BACKGROUND")
unlockBg:SetPoint("TOPLEFT", -4, 4)
unlockBg:SetPoint("BOTTOMRIGHT", 4, -4)
unlockBg:SetColorTexture(0.2, 0.6, 1.0, 0.25)
unlockBg:Hide()

local moveText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
moveText:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
moveText:SetText("Pretty BB Echo\nDrag to move, drag the corner to resize")
moveText:Hide()

local grip = CreateFrame("Button", nil, anchor)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", 6, -6)
grip:SetFrameLevel(anchor:GetFrameLevel() + 20)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:Hide()

local function CreateBar(name)
    local f = CreateFrame("Frame", name, anchor, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local tex = C_Spell.GetSpellTexture(BLOOD_BOIL)
    if tex then icon:SetTexture(tex) end

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK_TEXTURE)
    spark:SetBlendMode("ADD")
    spark:SetWidth(14)

    -- A font from the start, since names are set before the first layout.
    -- Both texts are placed by LayoutBar, which depends on the orientation.
    local nameText = bar:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(STANDARD_TEXT_FONT, defaults.fontSize, "OUTLINE")
    nameText:SetWordWrap(false)

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(STANDARD_TEXT_FONT, defaults.fontSize, "OUTLINE")

    f.icon = icon
    f.bar = bar
    f.spark = spark
    f.nameText = nameText
    f.timeText = timeText
    return f
end

local procBar = CreateBar("PrettyBBEchoProcBar")
local echoBar = CreateBar("PrettyBBEchoEchoBar")
local chainBar = CreateBar("PrettyBBEchoChainBar")

-- Thin strip under the chain bar for the Dancing Rune Weapon window.
local drwFrame = CreateFrame("Frame", "PrettyBBEchoDRWStrip", anchor, "BackdropTemplate")
drwFrame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
drwFrame:SetBackdropBorderColor(0, 0, 0, 1)
drwFrame:Hide()

local drwBar = CreateFrame("StatusBar", nil, drwFrame)
drwBar:SetStatusBarTexture(BAR_TEXTURE)
drwBar:SetMinMaxValues(0, 1)
drwBar:SetPoint("TOPLEFT", 1, -1)
drwBar:SetPoint("BOTTOMRIGHT", -1, 1)

-- ============================================================
-- Settings helpers
-- ============================================================
local function CopyColor(c)
    return { r = c.r, g = c.g, b = c.b, a = c.a }
end

local function CopyDefaults()
    PrettyBBEchoDB = PrettyBBEchoDB or {}
    for k, v in pairs(defaults) do
        if PrettyBBEchoDB[k] == nil then
            PrettyBBEchoDB[k] = type(v) == "table" and CopyColor(v) or v
        end
    end
    DB = PrettyBBEchoDB
end

local function SavePosition()
    if not DB then return end
    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    DB.point = point or "CENTER"
    DB.relativePoint = relativePoint or "CENTER"
    DB.x = x or 0
    DB.y = y or 0
end

local function ApplyPosition()
    anchor:ClearAllPoints()
    anchor:SetPoint(DB.point, UIParent, DB.relativePoint, DB.x, DB.y)
end

local function BarCount()
    return DB.mode == "both" and 2 or 1
end

local function StripHeight(height)
    return math.max(3, math.floor(height * 0.3 + 0.5))
end

-- Height of the chain bar plus its strip; the two share a border pixel.
local function ChainStackHeight(height)
    if DB.showDRW then
        return height + StripHeight(height) - 1
    end
    return height
end

local function SetColor(f, c)
    f:SetStatusBarColor(c.r, c.g, c.b, c.a)
end

local function ApplyFrameStyle(f, bar, texture)
    local bg, border = DB.bgColor, DB.borderColor
    f:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    f:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
    bar:SetStatusBarTexture(texture)
end

local function ApplyBarStyle(f, color, texture)
    local text = DB.textColor
    ApplyFrameStyle(f, f.bar, texture)
    SetColor(f.bar, color)
    f.nameText:SetTextColor(text.r, text.g, text.b, text.a)
    f.timeText:SetTextColor(text.r, text.g, text.b, text.a)
end

local function ApplyStyle()
    local texture = TexturePath(DB.barTexture)
    ApplyBarStyle(procBar, DB.procColor, texture)
    ApplyBarStyle(echoBar, DB.echoColor, texture)
    ApplyBarStyle(chainBar, DB.linkedColor, texture)
    procBar.nameText:SetText(DB.procName)
    echoBar.nameText:SetText(DB.echoName)

    ApplyFrameStyle(drwFrame, drwBar, texture)
    SetColor(drwBar, DB.drwColor)
end

local function IsVertical()
    return DB.orientation == "vertical"
end

-- DB.width is a bar's length and DB.height its thickness, whichever way it
-- runs. Horizontal bars drain right to left and stack downward; vertical bars
-- drain top to bottom and stack to the right.
local function LayoutBar(f, length, thickness)
    local vertical = IsVertical()
    local inner = math.max(thickness - 2, 1)
    if vertical then
        f:SetSize(thickness, length)
    else
        f:SetSize(length, thickness)
    end
    f.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")

    f.icon:ClearAllPoints()
    f.bar:ClearAllPoints()
    f.icon:SetSize(inner, inner)
    f.icon:SetShown(DB.showIcon)
    if DB.showIcon and vertical then
        f.icon:SetPoint("TOP", 0, -1)
        f.bar:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -1)
    elseif DB.showIcon then
        f.icon:SetPoint("LEFT", 1, 0)
        f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 1, 0)
    else
        f.bar:SetPoint("TOPLEFT", 1, -1)
    end
    f.bar:SetPoint("BOTTOMRIGHT", -1, 1)

    local fontSize = DB.fontSize or defaults.fontSize
    local nameText, timeText = f.nameText, f.timeText
    nameText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    timeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    nameText:SetShown(DB.showName)
    timeText:SetShown(DB.showTime)
    nameText:ClearAllPoints()
    timeText:ClearAllPoints()

    if vertical then
        -- Too narrow for the name inside, so it sits under the bar.
        timeText:SetPoint("TOP", f.bar, "TOP", 0, -3)
        timeText:SetJustifyH("CENTER")
        nameText:SetPoint("TOP", f, "BOTTOM", 0, -3)
        nameText:SetJustifyH("CENTER")
        nameText:SetWidth(0)

        f.spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
        f.spark:SetSize(inner * 2.2, 14)
    else
        timeText:SetPoint("RIGHT", -5, 0)
        timeText:SetJustifyH("RIGHT")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetJustifyH("LEFT")
        if DB.showTime then
            nameText:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
        else
            nameText:SetPoint("RIGHT", -5, 0)
        end

        f.spark:SetTexCoord(0, 1, 0, 1)
        f.spark:SetSize(14, inner * 2.2)
    end
end

local function LayoutBars(length, thickness)
    local vertical = IsVertical()
    local spacing = DB.spacing or defaults.spacing
    LayoutBar(procBar, length, thickness)
    LayoutBar(echoBar, length, thickness)
    LayoutBar(chainBar, length, thickness)

    procBar:ClearAllPoints()
    echoBar:ClearAllPoints()
    procBar:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    if DB.mode ~= "both" then
        echoBar:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    elseif vertical then
        echoBar:SetPoint("TOPLEFT", procBar, "TOPRIGHT", spacing, 0)
    else
        echoBar:SetPoint("TOPLEFT", procBar, "BOTTOMLEFT", 0, -spacing)
    end

    chainBar:ClearAllPoints()
    chainBar:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    drwFrame:ClearAllPoints()
    if vertical then
        drwFrame:SetSize(StripHeight(thickness), length)
        drwFrame:SetPoint("TOPLEFT", chainBar, "TOPRIGHT", -1, 0)
    else
        drwFrame:SetSize(length, StripHeight(thickness))
        drwFrame:SetPoint("TOPLEFT", chainBar, "BOTTOMLEFT", 0, 1)
    end
    drwBar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
end

-- How far the bars reach across their stacking direction.
local function StackDepth(thickness)
    if DB.mode == "chain" then
        return ChainStackHeight(thickness)
    end
    local n = BarCount()
    return n * thickness + (n - 1) * (DB.spacing or defaults.spacing)
end

local function AnchorSize(length, thickness)
    local depth = StackDepth(thickness)
    if IsVertical() then
        return depth, length
    end
    return length, depth
end

local function ApplySizeAndLayout()
    local minW, minH = AnchorSize(MIN_WIDTH, MIN_HEIGHT)
    local maxW, maxH = AnchorSize(MAX_WIDTH, MAX_HEIGHT)
    anchor:SetResizeBounds(minW, minH, maxW, maxH)
    anchor:SetSize(AnchorSize(DB.width, DB.height))
    LayoutBars(DB.width, DB.height)
end

-- ============================================================
-- Display
-- ============================================================
local function SetBarValue(f, value, text)
    f.bar:SetValue(value)
    f.timeText:SetText(text)
    if DB.showSpark and value > 0 and value < 1 then
        f.spark:ClearAllPoints()
        if IsVertical() then
            f.spark:SetPoint("CENTER", f.bar, "BOTTOM", 0, f.bar:GetHeight() * value)
        else
            f.spark:SetPoint("CENTER", f.bar, "LEFT", f.bar:GetWidth() * value, 0)
        end
        f.spark:Show()
    else
        f.spark:Hide()
    end
end

local function FormatRemain(remain)
    return string.format("%.1f", remain)
end

local function UpdateVisibility()
    if not DB then return end

    local chain = DB.mode == "chain"
    local wantProc = DB.mode == "proc15" or DB.mode == "both"
    local wantEcho = DB.mode == "echo3" or DB.mode == "both"
    local unlocked = IsUnlocked()

    procBar:SetShown(wantProc and (procGlow or unlocked))
    echoBar:SetShown(wantEcho and (echoRunning or unlocked))

    local chainShown = chain and (echoRunning or chainEndedAt > 0 or unlocked
        or (procGlow and DB.chainShowProc))
    chainBar:SetShown(chainShown)
    drwFrame:SetShown(chainShown and DB.showDRW and (drwExpiresAt > 0 or unlocked))

    -- Edit Mode draws its own highlight and moves the bars itself.
    local manual = not DB.locked
    unlockBg:SetShown(manual)
    moveText:SetShown(manual)
    grip:SetShown(manual)
end

local driver = CreateFrame("Frame")

local function NeedUpdate()
    return procGlow or echoRunning or chainEndedAt > 0 or drwExpiresAt > 0
        or IsUnlocked()
end

-- The pending automatic Blood Boil consumes the newly procced Boiling Point
-- and schedules another echo 3 seconds later.
local function ContinueChain(now)
    procDuringEcho = false
    procGlow = false
    procExpiresAt = 0
    echoStartedAt = now
    echoExpiresAt = now + ECHO_DURATION
    chainCount = chainCount + 1
end

local function AdvanceTimers(now)
    if procGlow and procExpiresAt <= now then
        procGlow = false
        procExpiresAt = 0
    end

    if echoRunning and echoExpiresAt <= now then
        if procDuringEcho then
            ContinueChain(now)
        else
            echoRunning = false
            echoExpiresAt = 0
            chainEndedAt = now
        end
    end

    if chainEndedAt > 0 and now - chainEndedAt > CHAIN_END_HOLD then
        chainEndedAt = 0
    end

    if drwExpiresAt > 0 and drwExpiresAt <= now then
        drwExpiresAt = 0
    end
end

local function RenderSplit(now, unlocked)
    if procGlow then
        local remain = procExpiresAt - now
        SetBarValue(procBar, remain / PROC_DURATION, FormatRemain(remain))
    elseif unlocked then
        SetBarValue(procBar, 0.65, FormatRemain(PROC_DURATION * 0.65))
    end

    if echoRunning then
        local remain = echoExpiresAt - now
        SetBarValue(echoBar, remain / ECHO_DURATION, FormatRemain(remain))
    elseif unlocked then
        SetBarValue(echoBar, 0.65, FormatRemain(ECHO_DURATION * 0.65))
    end
end

-- One bar follows the whole rotation: the empowered Blood Boil waiting to be
-- cast, then each echo, green when a new proc has linked the next echo and
-- red while the chain still needs a Heart Strike proc to continue.
local function RenderChain(now, unlocked)
    local f = chainBar
    if echoRunning then
        local remain = echoExpiresAt - now
        local linked = procDuringEcho
        SetColor(f.bar, linked and DB.linkedColor or DB.riskColor)
        f.nameText:SetFormattedText("Echo x%d - %s", chainCount, linked and "linked" or "need proc")
        SetBarValue(f, remain / ECHO_DURATION, FormatRemain(remain))
    elseif procGlow and DB.chainShowProc then
        local remain = procExpiresAt - now
        SetColor(f.bar, DB.procColor)
        f.nameText:SetText(DB.procName .. " ready")
        SetBarValue(f, remain / PROC_DURATION, FormatRemain(remain))
    elseif chainEndedAt > 0 then
        SetColor(f.bar, DB.riskColor)
        f.nameText:SetFormattedText("Chain ended x%d", chainCount)
        SetBarValue(f, 0, "")
    elseif unlocked then
        SetColor(f.bar, DB.linkedColor)
        f.nameText:SetText("Echo x3 - linked")
        SetBarValue(f, 0.65, FormatRemain(ECHO_DURATION * 0.65))
    end

    if drwExpiresAt > 0 then
        drwBar:SetValue((drwExpiresAt - now) / DB.drwDuration)
    elseif unlocked then
        drwBar:SetValue(0.65)
    end
end

local function UpdateTimers()
    local now = GetTime()
    local unlocked = IsUnlocked()

    AdvanceTimers(now)
    if DB and DB.mode == "chain" then
        RenderChain(now, unlocked)
    else
        RenderSplit(now, unlocked)
    end
    UpdateVisibility()

    if not NeedUpdate() then
        driver:SetScript("OnUpdate", nil)
    end
end

local function EnsureUpdates()
    driver:SetScript("OnUpdate", UpdateTimers)
end

local function StartProcTimer()
    procGlow = true
    procExpiresAt = GetTime() + PROC_DURATION
    if echoRunning then
        procDuringEcho = true
    end
    EnsureUpdates()
    UpdateTimers()
end

local function StopProcTimer()
    procGlow = false
    procExpiresAt = 0
    UpdateVisibility()
end

local function StartEchoTimer()
    local now = GetTime()
    if echoRunning and now - echoStartedAt < RESYNC_WINDOW then
        -- The echo's own cast, just after the countdown already chained.
    elseif echoRunning then
        chainCount = chainCount + 1
    else
        chainCount = 1
    end
    echoRunning = true
    procDuringEcho = false
    chainEndedAt = 0
    echoStartedAt = now
    echoExpiresAt = now + ECHO_DURATION
    EnsureUpdates()
    UpdateTimers()
end

local function StopEchoTimer()
    echoRunning = false
    procDuringEcho = false
    echoExpiresAt = 0
    chainEndedAt = 0
    UpdateVisibility()
end

local function StartDRWTimer()
    drwExpiresAt = GetTime() + DB.drwDuration
    EnsureUpdates()
    UpdateTimers()
end

local function MaybeStartFromCorrelation()
    -- A successful Blood Boil cast and the proc glow disappearing nearly
    -- simultaneously means that Blood Boil consumed Boiling Point.
    if lastBloodBoilCast > 0 and lastGlowHide > 0 and math.abs(lastBloodBoilCast - lastGlowHide) <= 0.30 then
        StopProcTimer()
        StartEchoTimer()
        lastBloodBoilCast = 0
        lastGlowHide = 0
    end
end

-- Plays the rotation: empowered Blood Boil, Dancing Rune Weapon, three Heart
-- Strike procs that each link an echo, then the chain runs out.
local function TestChain()
    StartProcTimer()
    C_Timer.After(1.0, function()
        StopProcTimer()
        StartEchoTimer()
    end)
    C_Timer.After(1.5, StartDRWTimer)
    for i = 1, 3 do
        C_Timer.After(1.0 + (i - 1) * ECHO_DURATION + 1.5, StartProcTimer)
    end
end

-- Unlocked by the lock setting (dragged here) or by Edit Mode (dragged by
-- LibEditMode); either way the bars show placeholders.
local function ApplyUnlock()
    local manual = not DB.locked
    if not editModeActive then
        anchor:SetMovable(manual)
    end
    anchor:EnableMouse(manual)
    if manual then
        anchor:RegisterForDrag("LeftButton")
    else
        anchor:RegisterForDrag()
        SavePosition()
    end
    if IsUnlocked() then
        EnsureUpdates()
    end
    UpdateTimers()
end

local function SetLocked(locked)
    DB.locked = locked
    ApplyUnlock()
end

-- ============================================================
-- Moving and resizing
-- ============================================================
anchor:SetScript("OnDragStart", function(self)
    if IsUnlocked() then self:StartMoving() end
end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local OnResized -- set by the settings panel so its sliders follow the grip

anchor:SetScript("OnSizeChanged", function(_, width, height)
    if not sizing or not DB then return end
    local length, depth = width, height
    if IsVertical() then
        length, depth = height, width
    end
    local thickness
    if DB.mode == "chain" then
        thickness = DB.showDRW and (depth + 1) / 1.3 or depth
    else
        local n = BarCount()
        thickness = (depth - (n - 1) * (DB.spacing or defaults.spacing)) / n
    end
    DB.width = math.floor(length + 0.5)
    DB.height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(thickness + 0.5)))
    LayoutBars(DB.width, DB.height)
end)

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not IsUnlocked() then return end
    sizing = true
    anchor:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not sizing then return end
    anchor:StopMovingOrSizing()
    sizing = false
    ApplySizeAndLayout()
    SavePosition()
    if OnResized then OnResized() end
end)

-- ============================================================
-- Events
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then return end
        CopyDefaults()
        ApplyPosition()
        ApplyStyle()

        -- The saved texture may come from a media pack that registers later.
        local lsm = GetLSM()
        if lsm then
            lsm.RegisterCallback(eventFrame, "LibSharedMedia_Registered", function(_, mediaType, key)
                if mediaType == "statusbar" and key == DB.barTexture then
                    ApplyStyle()
                end
            end)
        end
        ApplySizeAndLayout()
        SetLocked(DB.locked)
        UpdateVisibility()

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellID = ...
        if not issecretvalue(spellID) and spellID == BLOOD_BOIL then
            StartProcTimer()
        end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = ...
        if not issecretvalue(spellID) and spellID == BLOOD_BOIL then
            lastGlowHide = GetTime()
            MaybeStartFromCorrelation()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" or issecretvalue(spellID) then return end
        if spellID == BLOOD_BOIL then
            lastBloodBoilCast = GetTime()
            MaybeStartFromCorrelation()
        elseif spellID == DANCING_RUNE_WEAPON then
            StartDRWTimer()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        lastBloodBoilCast = 0
        lastGlowHide = 0
        drwExpiresAt = 0
        StopProcTimer()
        StopEchoTimer()
    end
end)

-- ============================================================
-- Settings panel
-- ============================================================
local category = CreateFrame("Frame", "PrettyBBEchoOptionsPanel")
category.name = "Pretty BB Echo"

-- The settings scroll, since they no longer fit the Settings window.
local scroll = CreateFrame("ScrollFrame", nil, category, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -28, 4)

local panel = CreateFrame("Frame", nil, scroll)
panel:SetSize(640, 880)
scroll:SetScrollChild(panel)
scroll:SetScript("OnSizeChanged", function(_, width)
    panel:SetWidth(width)
end)

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 20, -20)
title:SetText("Pretty BB Echo")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Countdown bars for Boiling Point's 15s proc and the 3s automatic Blood Boil echo")

local function CreateSlider(key, label, minValue, maxValue, anchorTo, x, y, onChange)
    local name = "PrettyBBEcho" .. key .. "Slider"

    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", x, y)
    text:SetText(label)

    local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", text, "RIGHT", 10, 0)

    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 4, -14)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(240)
    _G[name .. "Low"]:SetText(minValue)
    _G[name .. "High"]:SetText(maxValue)
    _G[name .. "Text"]:SetText("")
    slider:SetScript("OnValueChanged", function(_, v)
        if not DB then return end
        v = math.floor(v + 0.5)
        DB[key] = v
        value:SetText(v)
        onChange()
    end)

    slider.label = text
    slider.Refresh = function()
        slider:SetValue(DB[key])
        value:SetText(DB[key])
    end
    return slider
end

local function Relayout()
    ApplySizeAndLayout()
    UpdateTimers()
end

local widthSlider = CreateSlider("width", "Bar length", MIN_WIDTH, MAX_WIDTH, subtitle, 0, -26, Relayout)
local heightSlider = CreateSlider("height", "Bar thickness", MIN_HEIGHT, MAX_HEIGHT, widthSlider, -4, -24, Relayout)
local fontSlider = CreateSlider("fontSize", "Text size", 8, 24, heightSlider, -4, -24, Relayout)
local spacingSlider = CreateSlider("spacing", "Bar spacing", 0, 20, fontSlider, -4, -24, Relayout)
local drwSlider = CreateSlider("drwDuration", "Dancing Rune Weapon seconds", 4, 20, spacingSlider, -4, -24, function() end)

OnResized = function()
    if category:IsVisible() then
        widthSlider.Refresh()
        heightSlider.Refresh()
    end
end

-- Color swatches open the standard color picker, with opacity.
local swatches = {}
local RefreshTexturePreview

local function CreateSwatch(key, label, anchorTo, x, y)
    local button = CreateFrame("Button", nil, panel, "BackdropTemplate")
    button:SetSize(22, 22)
    button:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", x, y)
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropBorderColor(1, 1, 1, 0.8)

    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", button, "RIGHT", 8, 0)
    text:SetText(label)

    button.Refresh = function()
        local c = DB[key]
        button:SetBackdropColor(c.r, c.g, c.b, c.a)
    end

    button:SetScript("OnClick", function()
        local c = DB[key]
        local previous = CopyColor(c)
        local function Apply(r, g, b, a)
            c.r, c.g, c.b, c.a = r, g, b, a
            button.Refresh()
            ApplyStyle()
            UpdateTimers()
            RefreshTexturePreview()
        end
        local function FromPicker()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            Apply(r, g, b, ColorPickerFrame:GetColorAlpha())
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b, opacity = c.a,
            hasOpacity = true,
            swatchFunc = FromPicker,
            opacityFunc = FromPicker,
            cancelFunc = function()
                Apply(previous.r, previous.g, previous.b, previous.a)
            end,
        })
    end)

    swatches[#swatches + 1] = button
    return button
end

local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
colorLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 300, -26)
colorLabel:SetText("Colors")

local procSwatch = CreateSwatch("procColor", "15s proc bar", colorLabel, 0, -10)
local echoSwatch = CreateSwatch("echoColor", "3s echo bar", procSwatch, 0, -6)
local linkedSwatch = CreateSwatch("linkedColor", "Chain linked", echoSwatch, 0, -6)
local riskSwatch = CreateSwatch("riskColor", "Chain needs a proc", linkedSwatch, 0, -6)
local drwSwatch = CreateSwatch("drwColor", "Dancing Rune Weapon", riskSwatch, 0, -6)
local bgSwatch = CreateSwatch("bgColor", "Background", drwSwatch, 0, -6)
local borderSwatch = CreateSwatch("borderColor", "Border", bgSwatch, 0, -6)
local textSwatch = CreateSwatch("textColor", "Text", borderSwatch, 0, -6)

local textureLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textureLabel:SetPoint("TOPLEFT", textSwatch, "BOTTOMLEFT", 0, -18)
textureLabel:SetText("Bar texture")

local textureDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
textureDropdown:SetWidth(210)
textureDropdown:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -6)

-- A sample of the chosen texture in the 15s proc color.
local texturePreview = panel:CreateTexture(nil, "ARTWORK")
texturePreview:SetSize(210, 14)
texturePreview:SetPoint("TOPLEFT", textureDropdown, "BOTTOMLEFT", 0, -6)

function RefreshTexturePreview()
    local c = DB.procColor
    texturePreview:SetTexture(TexturePath(DB.barTexture))
    texturePreview:SetVertexColor(c.r, c.g, c.b, c.a)
end

textureDropdown:SetupMenu(function(_, root)
    root:SetScrollMode(360)
    for _, name in ipairs(TextureNames()) do
        root:CreateRadio(name, function()
            return DB and DB.barTexture == name
        end, function()
            DB.barTexture = name
            ApplyStyle()
            UpdateTimers()
            RefreshTexturePreview()
        end)
    end
end)

-- Buff names shown on the bars.
local function CreateNameBox(key, label, anchorTo, y)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, y)
    text:SetText(label)

    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(200, 22)
    box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 6, -4)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)

    local function Save(self)
        local v = self:GetText():match("^%s*(.-)%s*$")
        if v == "" then v = defaults[key] end
        DB[key] = v
        self:SetText(v)
        ApplyStyle()
        UpdateTimers()
    end
    box:SetScript("OnEnterPressed", function(self) Save(self); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(DB[key])
        self:ClearFocus()
    end)

    box.Refresh = function() box:SetText(DB[key]) end
    return box
end

local procNameBox = CreateNameBox("procName", "15s bar name", texturePreview, -16)
local echoNameBox = CreateNameBox("echoName", "3s bar name", procNameBox, -10)

local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
modeLabel:SetPoint("TOPLEFT", echoNameBox, "BOTTOMLEFT", -6, -16)
modeLabel:SetText("Display")

local modeDropdown = CreateFrame("Frame", "PrettyBBEchoModeDropdown", panel, "UIDropDownMenuTemplate")
modeDropdown:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(modeDropdown, 180)
local modeNames = {
    proc15 = "15s proc only",
    echo3 = "3s echo only",
    both = "Both",
    chain = "Rotation chain",
}

UIDropDownMenu_Initialize(modeDropdown, function(_, level)
    for _, mode in ipairs({ "proc15", "echo3", "both", "chain" }) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = modeNames[mode]
        info.checked = (DB and DB.mode == mode)
        info.func = function()
            DB.mode = mode
            UIDropDownMenu_SetText(modeDropdown, modeNames[mode])
            Relayout()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)

local function CreateCheck(name, label, anchorTo, x, y, onClick)
    local check = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", x, y)
    check.Text:SetText(label)
    check:SetScript("OnClick", function(self)
        if DB then onClick(self:GetChecked()) end
    end)
    return check
end

local chainProcCheck = CreateCheck("PrettyBBEchoChainProcCheck", "Chain: also show empowered Blood Boil",
    modeDropdown, 16, -4, function(v)
        DB.chainShowProc = v
        UpdateTimers()
    end)

local iconCheck = CreateCheck("PrettyBBEchoIconCheck", "Show spell icon", drwSlider, -8, -24, function(v)
    DB.showIcon = v
    Relayout()
end)
local sparkCheck = CreateCheck("PrettyBBEchoSparkCheck", "Show spark", iconCheck, 0, -2, function(v)
    DB.showSpark = v
    UpdateTimers()
end)
local drwCheck = CreateCheck("PrettyBBEchoDRWCheck", "Show Dancing Rune Weapon strip (chain)", sparkCheck, 0, -2, function(v)
    DB.showDRW = v
    Relayout()
end)
local nameCheck = CreateCheck("PrettyBBEchoNameCheck", "Show buff name", drwCheck, 0, -2, function(v)
    DB.showName = v
    Relayout()
end)
local timeCheck = CreateCheck("PrettyBBEchoTimeCheck", "Show countdown time", nameCheck, 0, -2, function(v)
    DB.showTime = v
    Relayout()
end)
local verticalCheck = CreateCheck("PrettyBBEchoVerticalCheck", "Vertical bars", timeCheck, 0, -2, function(v)
    DB.orientation = v and "vertical" or "horizontal"
    Relayout()
end)
local lockCheck = CreateCheck("PrettyBBEchoLockCheck", "Lock bar position and size", verticalCheck, 0, -2, function(v)
    SetLocked(v)
end)

local test15 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test15:SetSize(100, 24)
test15:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -14)
test15:SetText("Test 15s")
test15:SetScript("OnClick", function() StartProcTimer() end)

local test3 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
test3:SetSize(100, 24)
test3:SetPoint("LEFT", test15, "RIGHT", 8, 0)
test3:SetText("Test 3s")
test3:SetScript("OnClick", function() StartEchoTimer() end)

local testChain = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
testChain:SetSize(100, 24)
testChain:SetPoint("LEFT", test3, "RIGHT", 8, 0)
testChain:SetText("Test chain")
testChain:SetScript("OnClick", TestChain)

local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetButton:SetSize(150, 24)
resetButton:SetPoint("LEFT", testChain, "RIGHT", 8, 0)
resetButton:SetText("Reset position & size")

local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
help:SetPoint("TOPLEFT", test15, "BOTTOMLEFT", 0, -16)
help:SetWidth(580)
help:SetJustifyH("LEFT")
help:SetText("Rotation chain: one bar shows the empowered Blood Boil, then each echo. Green means a Heart Strike proc\n"
    .. "has linked the next echo, red means the chain ends unless you get a proc. The strip below is Dancing Rune Weapon.\n"
    .. "Move and size the bars in Edit Mode, or unlock them here and drag the corner. Settings are saved automatically.")

local function RefreshPanel()
    if not DB then return end
    widthSlider.Refresh()
    heightSlider.Refresh()
    fontSlider.Refresh()
    spacingSlider.Refresh()
    drwSlider.Refresh()
    for _, swatch in ipairs(swatches) do swatch.Refresh() end
    textureDropdown:GenerateMenu()
    RefreshTexturePreview()
    procNameBox.Refresh()
    echoNameBox.Refresh()
    UIDropDownMenu_SetText(modeDropdown, modeNames[DB.mode] or modeNames.both)
    iconCheck:SetChecked(DB.showIcon)
    sparkCheck:SetChecked(DB.showSpark)
    drwCheck:SetChecked(DB.showDRW)
    nameCheck:SetChecked(DB.showName)
    timeCheck:SetChecked(DB.showTime)
    verticalCheck:SetChecked(IsVertical())
    lockCheck:SetChecked(DB.locked)
    chainProcCheck:SetChecked(DB.chainShowProc)
end

resetButton:SetScript("OnClick", function()
    for _, key in ipairs({ "point", "relativePoint", "x", "y", "width", "height", "spacing", "fontSize" }) do
        DB[key] = defaults[key]
    end
    ApplyPosition()
    Relayout()
    RefreshPanel()
end)

category:SetScript("OnShow", RefreshPanel)

local function RegisterSettings()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local settingsCategory = Settings.RegisterCanvasLayoutCategory(category, category.name, category.name)
        settingsCategory.ID = category.name
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(category)
    end
end
RegisterSettings()

local function OpenSettings()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category.name)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(category)
        InterfaceOptionsFrame_OpenToCategory(category)
    end
end

-- ============================================================
-- Edit Mode
-- ============================================================
-- LibEditMode makes the bars a real Edit Mode frame: click to select, drag to
-- move, and the main options in the frame's Edit Mode dialog.
local function OnEditModeMoved(_, _, point, x, y)
    if not DB then return end
    DB.point, DB.relativePoint, DB.x, DB.y = point, point, x, y
end

local function EditModeCheckbox(name, key, onChange)
    return {
        kind = LibEditMode.SettingType.Checkbox,
        name = name,
        default = defaults[key],
        get = function() return DB[key] end,
        set = function(_, value)
            DB[key] = value
            onChange()
        end,
    }
end

local function EditModeSlider(name, key, minValue, maxValue)
    return {
        kind = LibEditMode.SettingType.Slider,
        name = name,
        default = defaults[key],
        minValue = minValue,
        maxValue = maxValue,
        valueStep = 1,
        get = function() return DB[key] end,
        set = function(_, value)
            DB[key] = math.floor(value + 0.5)
            Relayout()
        end,
    }
end

if LibEditMode then
    LibEditMode:AddFrame(anchor, OnEditModeMoved,
        { point = defaults.point, x = defaults.x, y = defaults.y }, "Pretty BB Echo")

    local modeValues = {}
    for _, mode in ipairs({ "proc15", "echo3", "both", "chain" }) do
        modeValues[#modeValues + 1] = { text = modeNames[mode], value = mode }
    end

    LibEditMode:AddFrameSettings(anchor, {
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = "Display",
            default = defaults.mode,
            values = modeValues,
            get = function() return DB.mode end,
            set = function(_, value)
                DB.mode = value
                Relayout()
            end,
        },
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = "Orientation",
            default = defaults.orientation,
            values = {
                { text = "Horizontal", value = "horizontal" },
                { text = "Vertical", value = "vertical" },
            },
            get = function() return DB.orientation end,
            set = function(_, value)
                DB.orientation = value
                Relayout()
            end,
        },
        EditModeSlider("Bar length", "width", MIN_WIDTH, MAX_WIDTH),
        EditModeSlider("Bar thickness", "height", MIN_HEIGHT, MAX_HEIGHT),
        EditModeSlider("Text size", "fontSize", 8, 24),
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = "Bar texture",
            default = defaults.barTexture,
            height = 300,
            values = function()
                local values = {}
                for _, name in ipairs(TextureNames()) do
                    values[#values + 1] = { text = name, value = name }
                end
                return values
            end,
            get = function() return DB.barTexture end,
            set = function(_, value)
                DB.barTexture = value
                ApplyStyle()
                UpdateTimers()
            end,
        },
        EditModeCheckbox("Show spell icon", "showIcon", Relayout),
        EditModeCheckbox("Show buff name", "showName", Relayout),
        EditModeCheckbox("Show countdown time", "showTime", Relayout),
        EditModeCheckbox("Show spark", "showSpark", UpdateTimers),
        EditModeCheckbox("Show Dancing Rune Weapon strip", "showDRW", Relayout),
        EditModeCheckbox("Chain: show empowered Blood Boil", "chainShowProc", UpdateTimers),
    })

    LibEditMode:RegisterCallback("enter", function()
        editModeActive = true
        if DB then ApplyUnlock() end
    end)
    LibEditMode:RegisterCallback("exit", function()
        editModeActive = false
        if DB then ApplyUnlock() end
    end)
end

SLASH_PRETTYBBECHO1 = "/pbe"
SlashCmdList.PRETTYBBECHO = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "options" or msg == "config" then
        OpenSettings()
    elseif msg == "test" or msg == "test3" then
        StartEchoTimer()
    elseif msg == "test15" then
        StartProcTimer()
    elseif msg == "testchain" then
        TestChain()
    elseif msg == "chain" then
        DB.mode = "chain"
        Relayout()
    elseif msg == "icon" then
        DB.showIcon = not DB.showIcon
        Relayout()
        print("Pretty BB Echo: spell icon " .. (DB.showIcon and "shown" or "hidden"))
    elseif msg == "unlock" then
        SetLocked(false)
    elseif msg == "lock" then
        SetLocked(true)
    elseif msg == "hide" then
        drwExpiresAt = 0
        StopProcTimer()
        StopEchoTimer()
    else
        print("Pretty BB Echo: /pbe (options) | chain | testchain | test3 | test15 | icon | unlock | lock | hide")
    end
end

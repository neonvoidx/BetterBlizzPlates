local LSM = LibStub("LibSharedMedia-3.0")

local cachedBars = {}
local pendingActions = {}

local THROTTLE = 0.10
local elapsed = 0

local function GetPRD()
    return _G.PersonalResourceDisplayFrame
end

local function FindHealthBar()
    local prd = GetPRD()
    if not prd then return nil end
    local c = prd.HealthBarsContainer
    return c and c.healthBar or nil
end

local function FindPowerBar()
    local prd = GetPRD()
    return prd and (prd.PowerBar or prd.powerBar) or nil
end

local function FindAltPowerBar()
    local prd = GetPRD()
    return prd and (prd.AlternatePowerBar or prd.alternatePowerBar) or nil
end

local function GetBarFont(barKey)
    local db = BetterBlizzPlatesDB
    local fontName = db["prdText" .. barKey .. "Font"] or "Yanone (BBP)"
    local fontPath = LSM:Fetch(LSM.MediaType.FONT, fontName)
    return fontPath or "Fonts\\FRIZQT__.TTF"
end

local function ApplyPRDBarTextures()
    local db = BetterBlizzPlatesDB
    local function applyTexture(bar, key)
        if not bar or not db[key] then return end
        local path = LSM:Fetch(LSM.MediaType.STATUSBAR, db[key])
        if path then bar:SetStatusBarTexture(path) end
    end
    applyTexture(cachedBars.health,   "prdTextHealthTexture")
    applyTexture(cachedBars.power,    "prdTextPowerTexture")
    applyTexture(cachedBars.altPower, "prdTextAltTexture")
end

local function ApplyPRDBorders()
    local db = BetterBlizzPlatesDB
    local bars = { cachedBars.health, cachedBars.power, cachedBars.altPower }

    if not db.prdBorderEnable then
        for _, bar in ipairs(bars) do
            if bar and bar.bbpBorder then bar.bbpBorder:Hide() end
        end
        return
    end

    local size = db.prdBorderSize or 1
    local color = db.prdBorderColorRGB or {0, 0, 0, 1}
    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1
    local edgeFile = "Interface\\Buttons\\WHITE8X8"
    if db.prdBorderTexture then
        local path = LSM:Fetch(LSM.MediaType.BORDER, db.prdBorderTexture)
        if path then edgeFile = path end
    end

    for _, bar in ipairs(bars) do
        if bar then
            if not bar.bbpBorder then
                local bf = CreateFrame("Frame", nil, bar, "BackdropTemplate")
                bf:EnableMouse(false)
                bar.bbpBorder = bf
            end
            local bf = bar.bbpBorder
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", bar, "TOPLEFT", -size, size)
            bf:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size, -size)
            bf:SetFrameLevel(bar:GetFrameLevel() + 5)
            bf:SetBackdrop({
                edgeFile = edgeFile,
                edgeSize = size,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bf:SetBackdropColor(0, 0, 0, 0)
            bf:SetBackdropBorderColor(r, g, b, a)
            bf:Show()
        end
    end
end

local function AbbrevNum(n)
    return AbbreviateNumbers(n)
end

-- Returns a formatted text string based on the format setting.
-- cur/max are raw values; pct is the curved percent (may be nil).
local function FormatBarText(cur, max, pct, format)
    local curStr = AbbrevNum(cur)
    local maxStr = AbbrevNum(max)
    local pctStr = pct and string.format("%d%%", pct) or (max > 0 and string.format("%d%%", math.floor(cur / max * 100 + 0.5)) or "0%")

    if format == "Percent"         then return pctStr end
    if format == "Value"           then return curStr end
    if format == "Value / Max"     then return curStr .. " / " .. maxStr end
    if format == "Value | Percent" then return curStr .. " | " .. pctStr end
    -- default: "Percent | Value"
    return pctStr .. " | " .. curStr
end

local function ApplyFontToOverlay(bar, barKey)
    if not bar or not bar.bbpPRDText then return end
    local db = BetterBlizzPlatesDB
    local path = GetBarFont(barKey)
    local size = db["prdText" .. barKey .. "FontSize"] or 12
    local outline = db["prdText" .. barKey .. "Outline"] or "OUTLINE"
    if outline == "NONE" then outline = "" end
    bar.bbpPRDText:SetFont(path, size, outline)
    local xOff = db["prdText" .. barKey .. "XPos"] or 0
    local yOff = db["prdText" .. barKey .. "YPos"] or 0
    bar.bbpPRDText:ClearAllPoints()
    bar.bbpPRDText:SetPoint("CENTER", bar.bbpPRDOverlay, "CENTER", xOff, yOff)
end

local function CreateOverlay(bar, barKey)
    if not bar then return end
    local db = BetterBlizzPlatesDB

    if bar.bbpPRDOverlay then
        ApplyFontToOverlay(bar, barKey)
        if not InCombatLockdown() then
            bar.bbpPRDOverlay:SetAttribute("*type2", db.prdContextMenu and "togglemenu" or nil)
        end
        return
    end

    if InCombatLockdown() then
        pendingActions.createOverlays = true
        return
    end

    local path    = GetBarFont(barKey)
    local size    = db["prdText" .. barKey .. "FontSize"] or 12
    local outline = db["prdText" .. barKey .. "Outline"] or "OUTLINE"
    if outline == "NONE" then outline = "" end
    local xOff    = db["prdText" .. barKey .. "XPos"] or 0
    local yOff    = db["prdText" .. barKey .. "YPos"] or 0

    local overlay = CreateFrame("Button", nil, bar, "SecureUnitButtonTemplate")
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlay:RegisterForClicks("AnyUp")
    overlay:SetAttribute("unit", "player")
    overlay:SetAttribute("*type1", "target")
    if db.prdContextMenu then
        overlay:SetAttribute("*type2", "togglemenu")
    end

    local text = overlay:CreateFontString(nil, "OVERLAY")
    text:SetFont(path, size, outline)
    text:SetJustifyH("CENTER")
    text:SetPoint("CENTER", overlay, "CENTER", xOff, yOff)

    bar.bbpPRDOverlay = overlay
    bar.bbpPRDText    = text
end

local function SetBarText(bar, str)
    if not bar or not bar.bbpPRDText then return end
    bar.bbpPRDText:SetText(str or "")
end

local function UpdateHealthBar(bar)
    if not bar or not bar.bbpPRDText then return end
    local db = BetterBlizzPlatesDB
    if not db.prdBarTextEnable or not db.prdTextHealthEnable then
        SetBarText(bar, "")
        return
    end
    local cur = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not cur or not max or max <= 0 then SetBarText(bar, "") return end
    local pct
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        pct = tonumber(UnitHealthPercent("player", true, CurveConstants.ScaleTo100))
    end
    SetBarText(bar, FormatBarText(cur, max, pct, db.prdTextHealthFormat))
end

local function UpdatePowerBar(bar)
    if not bar or not bar.bbpPRDText then return end
    local db = BetterBlizzPlatesDB
    if not db.prdBarTextEnable or not db.prdTextPowerEnable then
        SetBarText(bar, "")
        return
    end
    local powerType = UnitPowerType("player")
    local cur = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if not cur or not max or max <= 0 then SetBarText(bar, "") return end
    local pct
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        pct = tonumber(UnitPowerPercent("player", powerType, true, CurveConstants.ScaleTo100))
    end
    SetBarText(bar, FormatBarText(cur, max, pct, db.prdTextPowerFormat))
end

local function UpdateAltPowerBar(bar)
    if not bar or not bar.bbpPRDText then return end
    local db = BetterBlizzPlatesDB
    if not db.prdBarTextEnable or not db.prdTextAltEnable then
        SetBarText(bar, "")
        return
    end
    local minV, maxV = bar:GetMinMaxValues()
    local val = bar:GetValue()
    if not val or not maxV or maxV <= 0 then SetBarText(bar, "") return end
    local range = maxV - (minV or 0)
    local norm  = val - (minV or 0)
    local pct   = range > 0 and math.floor(norm / range * 100 + 0.5) or 0
    SetBarText(bar, FormatBarText(math.floor(val + 0.5), math.floor(maxV + 0.5), pct, db.prdTextAltFormat))
end

function BBP.UpdatePRDText()
    if cachedBars.health   then UpdateHealthBar(cachedBars.health)     end
    if cachedBars.power    then UpdatePowerBar(cachedBars.power)       end
    if cachedBars.altPower then UpdateAltPowerBar(cachedBars.altPower) end
end

local function CacheBarsAndOverlays()
    cachedBars.health   = FindHealthBar()
    cachedBars.power    = FindPowerBar()
    cachedBars.altPower = FindAltPowerBar()

    CreateOverlay(cachedBars.health,   "Health")
    CreateOverlay(cachedBars.power,    "Power")
    CreateOverlay(cachedBars.altPower, "Alt")
end

function BBP.RefreshPRDText()
    if InCombatLockdown() then
        pendingActions.cacheBars = true
        return
    end
    CacheBarsAndOverlays()
    ApplyPRDBarTextures()
    ApplyPRDBorders()

    -- clear all text if master toggle is off
    if not BetterBlizzPlatesDB.prdBarTextEnable then
        for _, bar in pairs(cachedBars) do
            if type(bar) == "userdata" then
                SetBarText(bar, "")
            end
        end
        return
    end

    BBP.UpdatePRDText()
end

local prdFrame = CreateFrame("Frame")

prdFrame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < THROTTLE then return end
    elapsed = 0

    if not BetterBlizzPlatesDB.prdBarTextEnable then return end

    BBP.UpdatePRDText()
end)

prdFrame:RegisterEvent("UNIT_HEALTH")
prdFrame:RegisterEvent("UNIT_POWER_UPDATE")
prdFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
prdFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
prdFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
prdFrame:RegisterEvent("PLAYER_LOGIN")

prdFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        -- BBP.TexturePRD is defined in BetterBlizzPlates.lua which loads after us;
        -- hook it so our per-bar textures always apply after the base texture pass.
        if BBP.TexturePRD then
            hooksecurefunc(BBP, "TexturePRD", function()
                ApplyPRDBarTextures()
            end)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingActions.cacheBars or pendingActions.createOverlays then
            pendingActions.cacheBars = nil
            pendingActions.createOverlays = nil
            CacheBarsAndOverlays()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.5, function()
            BBP.RefreshPRDText()
        end)
        return
    end

    if unit and unit ~= "player" then return end
    if BetterBlizzPlatesDB.prdBarTextEnable then
        BBP.UpdatePRDText()
    end
end)

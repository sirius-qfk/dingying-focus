-- Contract simulation, not a replacement for a WoW client / secure execution engine.
local Mock = { queue = {}, combat = false, profile = "Default", spec = 1, writes = 0 }
local unpackValues = table.unpack or unpack
local Frame = {}
Frame.__index = Frame

function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:HookScript(event, callback)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], callback)
end
function Frame:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end
end
function Frame:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Frame:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Frame:IsShown() return self.shown end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetChildren() return unpackValues(self.children) end
function Frame:SetSize(w, h)
    local changed = self.width ~= w or self.height ~= h
    self.width, self.height = w, h
    if changed then self:Fire("OnSizeChanged", w, h) end
end
function Frame:SetWidth(w) self:SetSize(w, self.height) end
function Frame:SetHeight(h) self:SetSize(self.width, h) end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetSize() return self.width, self.height end
function Frame:GetCenter()
    if self == UIParent then return self.width / 2, self.height / 2 end
    local point, relative, relPoint, x, y = self:GetPoint()
    if relative ~= UIParent or relPoint ~= "CENTER" then return nil end
    if point:find("LEFT") then x = x + self.width / 2 elseif point:find("RIGHT") then x = x - self.width / 2 end
    if point:find("BOTTOM") then y = y + self.height / 2 elseif point:find("TOP") then y = y - self.height / 2 end
    return x + UIParent:GetWidth() / 2, y + UIParent:GetHeight() / 2
end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, relative, relPoint, x, y)
    if type(relative) == "number" then x, y, relative, relPoint = relative, relPoint, self.parent, point end
    if not relative then relative = self.parent or UIParent end
    self.points[1] = { point, relative, relPoint or point, x or 0, y or 0 }
end
function Frame:GetPoint(i) return unpackValues(self.points[i or 1] or {}) end
function Frame:GetNumPoints() return #self.points end
function Frame:SetAllPoints(relative) self.anchor = relative end
function Frame:SetText(text)
    self.text = text
    if self.kind == "EditBox" then self:Fire("OnTextChanged", false) end
end
function Frame:GetText() return self.text or "" end
function Frame:ClearFocus() self.focused = false end
function Frame:HasFocus() return self.focused or false end
function Frame:SetFont(font, size, flags) self.font, self.fontSize, self.flags = font, size, flags end
function Frame:GetFont() return self.font or "test.ttf", self.fontSize or 13, self.flags or "" end
function Frame:SetEnabled(enabled) self.enabled = enabled end
for _, method in ipairs({ "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "EnableMouse", "SetFrameStrata", "SetWordWrap", "SetJustifyH", "SetTextColor", "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetColorTexture", "RegisterEvent", "EnableKeyboard" }) do
    Frame[method] = function() end
end
function CreateFrame(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, children = {}, scripts = {}, hooks = {}, points = {}, width = 100, height = 40, level = 1, shown = true }, Frame)
    if name then _G[name] = f end
    if parent then table.insert(parent.children, f) end
    return f
end
function Frame:CreateFontString() return CreateFrame("FontString", nil, self) end
function Frame:CreateTexture() return CreateFrame("Texture", nil, self) end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
function InCombatLockdown() return Mock.combat end
function GetBuildInfo() return "12.1", "test", "test", Mock.interface or 120100 end
function UnitGUID() return "test-character" end
function GetSpecialization() return Mock.spec end
function GetSpecializationInfo(index) return index end
function GetCursorPosition() return 960, 540 end
function IsMouseButtonDown() return false end
C_Timer = { After = function(_, callback) table.insert(Mock.queue, callback) end }
C_AddOns = { GetAddOnMetadata = function(addon) return Mock.versions and Mock.versions[addon] or Mock.version or "9.3" end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function hooksecurefunc(owner, key, callback)
    local original = owner[key]
    owner[key] = function(...)
        local result = { original(...) }
        callback(...)
        return unpackValues(result)
    end
end
function Mock.Flush()
    local count = 0
    while #Mock.queue > 0 do
        local callback = table.remove(Mock.queue, 1)
        callback()
        count = count + 1
        assert(count < 100, "unbounded callback / resize loop")
    end
end

EllesmereUIDB = { activeProfile = "Default" }
EllesmereUI = { _ModuleNS = {}, callbacks = {}, hideCallbacks = {}, collapseCallbacks = {} }
function EllesmereUI.GetActiveProfileName() return Mock.profile end
function EllesmereUI:RegisterOnShow(callback) table.insert(self.callbacks, callback) end
function EllesmereUI:RegisterOnHide(callback) table.insert(self.hideCallbacks, callback) end
function EllesmereUI:RegisterOnCollapse(callback) table.insert(self.collapseCallbacks, callback) end
function EllesmereUI._SetPanelCollapsed(on)
    local e = EllesmereUI
    if not e.host then return end
    e._panelCollapsed = on
    e._panelMini = e._panelMini or CreateFrame("Frame", nil, e.host)
    for _, callback in ipairs(e.collapseCallbacks) do callback(on) end
end
function EllesmereUI:GetMainFrame() return self.host end
function EllesmereUI:Show()
    if not self.host then self.host = CreateFrame("Frame", "EllesmereUIFrame", UIParent); self.host:SetSize(1200, 850) end
    self.host:Show()
    if self._panelCollapsed then self._SetPanelCollapsed(false) end
    for _, callback in ipairs(self.callbacks) do callback() end
end
function EllesmereUI:Hide()
    self.host:Hide()
    for _, callback in ipairs(self.hideCallbacks) do callback() end
end
function EllesmereUI:RefreshPage()
    Mock.pageRefreshes = (Mock.pageRefreshes or 0) + 1
    if Mock.buildPage then Mock.buildPage() end
end
function EllesmereUI.SwitchProfile(name) Mock.profile = name end
function EllesmereUI.IsUnlockAnchored(key) return Mock.anchored == key end
function EllesmereUI.GetWidthMatchTarget(key) return Mock.matched == key end
function EllesmereUI.GetHeightMatchTarget() end
EllesmereUI.Widgets = {}
function EllesmereUI.Widgets:DualRow(parent, y, left, right)
    local row = CreateFrame("Frame", nil, parent)
    for i, cfg in ipairs({ left, right }) do
        local region = CreateFrame("Frame", nil, row)
        region._widgetCfg, region._cfg = cfg, cfg
        region._control = CreateFrame("Frame", nil, region)
        region.valueBox = CreateFrame("EditBox", nil, region)
        if i == 1 then row._leftRegion = region else row._rightRegion = region end
    end
    return row, 50
end

local ab = { db = { profile = { bars = {}, barPositions = {} } } }
local nsAB = { EAB = ab }
EllesmereUI._ModuleNS.EllesmereUIActionBars = nsAB
for _, key in ipairs({ "MainBar", "Bar2", "Bar3" }) do
    ab.db.profile.bars[key] = { buttonWidth = 24, buttonHeight = 24, keybindFontSize = 10, countFontSize = 9 }
    local frame = CreateFrame("Frame", "EABBar_" .. key, UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 100, 80)
    frame:SetSize(206, 24)
end
function ab:ApplyButtonSizeForBar(key)
    Mock.writes = Mock.writes + 1
    local cfg = self.db.profile.bars[key]
    if Mock.refreshError == key then error("simulated layout error") end
    _G["EABBar_" .. key]:SetSize(cfg.buttonWidth * 8 + 14, cfg.buttonHeight)
end
function ab:ApplyFontsForBar(key)
    local cfg = self.db.profile.bars[key]
    _G["EABBar_" .. key].fontSize = cfg.keybindFontSize
end

local cd = { db = { profile = { cdmBars = { bars = {} }, cdmBarPositions = {} } } }
local nsCD = { ECME = cd, frames = {} }
EllesmereUI._ModuleNS.EllesmereUICooldownManager = nsCD
for _, key in ipairs({ "cooldowns", "utility" }) do
    cd.db.profile.cdmBars.bars[#cd.db.profile.cdmBars.bars + 1] = { key = key, enabled = true, iconSize = 24, cooldownFontSize = 10, stackCountSize = 9, anchorTo = "none" }
    local f = CreateFrame("Frame", "CDM_" .. key, UIParent)
    f:SetSize(154, 24); f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    nsCD.frames[key] = f
end
function nsCD.GetBarData(key)
    for _, bar in ipairs(cd.db.profile.cdmBars.bars) do if bar.key == key then return bar end end
end
function nsCD.GetCDMBarFrame(key) return nsCD.frames[key] end
function nsCD.GetActiveLayoutName() return "Default" end
function nsCD.LayoutCDMBar(key)
    Mock.writes = Mock.writes + 1
    local cfg = nsCD.GetBarData(key)
    nsCD.frames[key]:SetSize(cfg.iconSize * 6 + 10, cfg.iconSize)
end
function nsCD.RefreshCDMIconAppearance(key) nsCD.frames[key].fontSize = nsCD.GetBarData(key).cooldownFontSize end
function nsCD.BuildAllCDMBars() for key in pairs(nsCD.frames) do nsCD.LayoutCDMBar(key) end end

Mock.ab, Mock.cd, Mock.nsCD = ab, cd, nsCD

function Mock.EnablePluginAPI()
    local e = EllesmereUI
    e.PLUGIN_API_VERSION, e.plugins = 1, {}
    function e.RegisterPlugin(id, spec)
        assert(not e.plugins[id], "duplicate plugin registration")
        assert(not spec.label:find("^EUI") and not spec.label:find("^EllesmereUI"))
        e.plugins[id] = spec
        return true
    end
    function e.OpenPlugin(id)
        if Mock.combat then return false end
        local module = e.plugins[id].modules[1]
        e:Show()
        if not e.pluginParent then
            e.pluginParent = CreateFrame("Frame", nil, e.host)
            e.pageHeight = module.buildPage(module.pages[1], e.pluginParent, -10)
        elseif e.activePlugin ~= id then
            module.onPageCacheRestore(module.pages[1])
        end
        e.activePlugin = id
        return true
    end
    function e.GetPluginModuleKey(id, key) return "plugin:" .. id .. ":" .. key end
    function e:GetActiveModule() return self.activePlugin and e.GetPluginModuleKey(self.activePlugin, "Gradient") end
    function e.IsSearchPrebuild() return Mock.searchPrebuild or false end
end
return Mock

local _, G = ...
local B = { slots = setmetatable({}, { __mode = "k" }), failures = {} }
G.NativeControls = B
local moduleNames = { EllesmereUIActionBars = "action", EllesmereUICooldownManager = "cooldown" }
local fields = {
    action = {
        ["Icon Size"] = { field = "buttonWidth", category = "icon", tier = "icon" },
        ["Keybind Text Size"] = { field = "keybindFontSize", category = "text", tier = "text" },
        ["Charges Text Size"] = { field = "countFontSize", category = "text", tier = "count" },
    },
    cooldown = {
        ["Icon Scale"] = { field = "iconSize", category = "icon", tier = "icon" },
        ["Duration Size"] = { field = "cooldownFontSize", category = "text", tier = "text" },
        ["Charge/Stack Size"] = { field = "stackCountSize", category = "text", tier = "count" },
    },
}

local function hasEditBox(frame)
    if frame.GetObjectType and frame:GetObjectType() == "EditBox" then return true end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do if hasEditBox(child) then return true end end
    end
    return false
end

function B:Managed(slot)
    local e = G.Engine
    if not e or not e.entry or not G.Adapter.Probe() or e.suspended[slot.binding.module] then return false end
    if not G.Compatibility:CanReplay(slot.binding.module, e.entry.applied.contracts[slot.binding.module]) then return false end
    local id = slot.binding.id .. "/" .. slot.field.field
    local target = G.Adapter.Resolve(slot.binding)
    return target and e.journal:Owns(id, { object = target.config, key = slot.field.field }) or false
end

function B:RefreshSlot(region, slot)
    local managed = self:Managed(slot)
    slot.managed = managed
    for _, original in ipairs(slot.originals) do
        if managed then
            if original.frame.ClearFocus then original.frame:ClearFocus() end
            original.frame:Hide()
        elseif original.wasShown then original.frame:Show() end
    end
    if managed then
        local tier = slot.binding[slot.field.tier]
        slot.overlay:SetText("使用第 " .. tier:sub(2) .. " 档 · 调整梯度")
        slot.overlay:Show()
    else slot.overlay:Hide() end
end

function B:RefreshSlots()
    for region, slot in pairs(self.slots) do self:RefreshSlot(region, slot) end
end

function B:AttachSlot(region, binding, field)
    if not region or not region._control then
        self.failures[binding.module] = "原尺寸入口结构不匹配，已暂停此模块"
        G.Engine:Schedule("尺寸入口不匹配")
        return false
    end
    if self.slots[region] then return true end
    local slot = { binding = binding, field = field, originals = {} }
    -- The v9.3 factory's track and value-box are separate children. Preserve cogs/swatches.
    for _, child in ipairs({ region:GetChildren() }) do
        if child == region._control or hasEditBox(child) then
            slot.originals[#slot.originals + 1] = { frame = child, wasShown = child:IsShown() }
            child:HookScript("OnShow", function(frame) if slot.managed then frame:Hide() end end)
        end
    end
    local overlay = G.Editor.Button(region, "", 205, function() G.Bridge:Open() end)
    overlay:SetPoint("RIGHT", region, "RIGHT", -20, 0)
    overlay:SetFrameLevel(region:GetFrameLevel() + 25)
    slot.overlay = overlay
    self.slots[region] = slot
    self:RefreshSlot(region, slot)
    return true
end

function B:HookWidgets()
    local e = EllesmereUI
    if not G.Adapter.Probe() or not e.Widgets then return end
    local firstInstall = self.widgetFunction ~= e.Widgets.DualRow
    G.PostHook(e.Widgets, "DualRow", function(_, parent, _, left, right)
        if not G.Adapter.Probe() or e._prebuilding or (e.IsSearchPrebuild and e.IsSearchPrebuild()) then return end
        local module = moduleNames[e._buildingModule]
        local selector = e._buildingSelector
        local binding = module and selector and G.FindBinding(module, selector.key)
        if not binding then return end
        local found = {}
        -- Match the actual cfg identity, not a localized label or a coincidental numeric value.
        for _, row in ipairs({ parent:GetChildren() }) do
            for _, pair in ipairs({ { row._leftRegion, left }, { row._rightRegion, right } }) do
                local region, cfg = pair[1], pair[2]
                if region and cfg and region._widgetCfg == cfg and cfg.type == "slider" then
                    local field = fields[module][cfg.text]
                    if field then found[cfg] = self:AttachSlot(region, binding, field) end
                end
            end
        end
        for _, cfg in pairs({ left, right }) do
            if cfg.type == "slider" and fields[module][cfg.text] and not found[cfg] then
                self.failures[module] = "原尺寸入口结构不匹配，已暂停此模块"
                G.Engine:Schedule("尺寸入口不匹配")
            end
        end
    end)
    self.widgetFunction = e.Widgets.DualRow
    -- Options may have been built before the first host OnShow callback. Rebuild once
    -- via the host API so those existing controls are captured by the new post-hook.
    if firstInstall and e.GetMainFrame and e:GetMainFrame() and e.RefreshPage then
        C_Timer.After(0, function() e:RefreshPage(true) end)
    end
end

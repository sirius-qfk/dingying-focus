local _, G = ...
local U = { cells = {} }
G.Editor = U

function U.Text(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local font, _, flags = fs:GetFont()
    fs:SetFont(font, size or 13, flags)
    fs:SetTextColor(0.9, 0.94, 0.96)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

function U.Backdrop(frame, alpha)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.045, 0.065, 0.085, alpha or 1)
    frame:SetBackdropBorderColor(0.16, 0.3, 0.34, 1)
end

function U.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 28)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

function U:Create(host, pageOffset)
    if self.panel then
        if pageOffset ~= nil then
            self.closing = true
            self.panel:SetParent(host)
            self.panel:ClearAllPoints()
            self.panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, pageOffset)
            self.panel:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, pageOffset)
            self.panel:SetHeight(610)
            self.closing = false
        end
        return
    end
    local panel = CreateFrame("Frame", "EllesmereUIGradientEditor", host, "BackdropTemplate")
    if pageOffset ~= nil then
        panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, pageOffset)
        panel:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, pageOffset)
        panel:SetHeight(610)
    else
        panel:SetPoint("TOPLEFT", host, "TOPLEFT", 210, -82)
        panel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -20, 56)
    end
    panel:SetFrameLevel(host:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    U.Backdrop(panel)
    panel:Hide()
    self.panel = panel

    local title = U.Text(panel, "梯度设置", 22)
    title:SetPoint("TOPLEFT", 24, -22)
    local subtitle = U.Text(panel, "只调整三档数值；绑定和布局由插件处理。", 12)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

    local tierNames = { "第一档", "第二档", "第三档" }
    for i, name in ipairs(tierNames) do
        local label = U.Text(panel, name, 14)
        label:SetPoint("TOPLEFT", 180 + (i - 1) * 150, -90)
    end
    local rows = {
        { label = "文字字号", category = "text" },
        { label = "图标尺寸", category = "icon" },
        { label = "矩形宽度", category = "regions", axis = "width" },
        { label = "矩形高度", category = "regions", axis = "height" },
    }
    for rowIndex, row in ipairs(rows) do
        local y = -124 - (rowIndex - 1) * 48
        local label = U.Text(panel, row.label, 14)
        label:SetPoint("TOPLEFT", 24, y - 3)
        for i, tier in ipairs(G.Model.tiers) do
            local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
            box:SetSize(100, 28)
            box:SetPoint("TOPLEFT", 185 + (i - 1) * 150, y)
            box:SetAutoFocus(false)
            box:SetNumeric(true)
            box:SetMaxLetters(5)
            box.category, box.tier, box.axis = row.category, tier, row.axis
            box:SetScript("OnTextChanged", function(input, userInput)
                if not userInput or U.syncing then return end
                G.Engine:Change(input.category, input.tier, input.axis, tonumber(input:GetText()))
            end)
            box:SetScript("OnEnterPressed", function(input) input:ClearFocus() end)
            box:SetScript("OnEscapePressed", function(input) input:ClearFocus() end)
            self.cells[#self.cells + 1] = box
        end
    end

    self.status = U.Text(panel, "", 12)
    self.status:SetPoint("TOPLEFT", 24, -334)
    self.status:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    self.status:SetWordWrap(true)
    self.status:SetHeight(46)
    self.coverage = U.Text(panel, "", 11)
    self.coverage:SetPoint("TOPLEFT", 24, -390)
    self.coverage:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    self.coverage:SetWordWrap(true)
    self.coverage:SetHeight(106)

    local hint = U.Text(panel, "鼠标拖动矩形四边可调整范围。数字采用游戏 UI 坐标，不是物理像素。", 11)
    hint:SetPoint("BOTTOMLEFT", 24, 58)
    self.apply = U.Button(panel, "应用", 92, function() G.Engine:Apply() end)
    self.apply:SetPoint("BOTTOMRIGHT", -24, 18)
    local cancel = U.Button(panel, "取消 / 返回", 110, function() self:RequestClose() end)
    cancel:SetPoint("RIGHT", self.apply, "LEFT", -10, 0)
    local restore = U.Button(panel, "恢复原设置", 110, function()
        self:Confirm("恢复接管前设置并退出接管？后续外部改动会保留。", function() G.Engine:Restore() end)
    end)
    restore:SetPoint("BOTTOMLEFT", 24, 18)
    local preview = U.Button(panel, "布局预览", 100, function()
        local ok, err = G.Adapter.SetCollapsed(true)
        if not ok then G.Engine:Notify(err) end
    end)
    preview:SetPoint("LEFT", restore, "RIGHT", 10, 0)

    panel:SetScript("OnHide", function()
        if not self.folded and G.Regions then G.Regions:Hide() end
        if not self.closing and G.Engine.editing then G.Engine:Cancel() end
    end)
    G.On("state", function() self:Sync() end)
    G.On("context", function()
        self:CloseViews()
        G.Message("EUI 配置或专精已切换，旧草稿已关闭。")
    end)
    G.On("closed", function()
        self:CloseViews()
    end)
end

function U:Confirm(message, action)
    if self.confirm then
        self.confirm.label:SetText(message)
        self.confirm.action = action
        self.confirm:Show()
        return
    end
    local f = CreateFrame("Frame", nil, self.panel, "BackdropTemplate")
    f:SetSize(450, 130)
    f:SetPoint("CENTER")
    f:SetFrameLevel(self.panel:GetFrameLevel() + 30)
    f:EnableMouse(true)
    U.Backdrop(f)
    local label = U.Text(f, message, 13)
    label:SetPoint("TOPLEFT", 18, -18)
    label:SetWidth(414)
    label:SetWordWrap(true)
    f.label, f.action = label, action
    U.Button(f, "确定", 90, function() f:Hide(); f.action() end):SetPoint("BOTTOMRIGHT", -18, 16)
    U.Button(f, "返回编辑", 100, function() f:Hide() end):SetPoint("BOTTOMLEFT", 18, 16)
    self.confirm = f
end

function U:CloseViews()
    self.closing, self.folded = true, nil
    if self.panel then self.panel:Hide() end
    if self.confirm then self.confirm:Hide() end
    if self.previewBar then self.previewBar:Hide() end
    if G.Regions then G.Regions:Hide() end
    self.closing = false
end

function U:SetCollapsed(on)
    if not self.panel or not G.Engine.editing then return end
    self.folded, self.closing = on, true
    if on then
        if self.confirm then self.confirm:Hide() end
        self.panel:Hide()
        if not self.previewBar then
            local bar = CreateFrame("Frame", nil, G.SettingsHost:PreviewParent(), "BackdropTemplate")
            bar:SetSize(300, 94)
            bar:SetFrameLevel(self.panel:GetFrameLevel() + 1)
            bar:EnableMouse(true)
            U.Backdrop(bar)
            bar.label = U.Text(bar, "", 11)
            bar.label:SetPoint("TOPLEFT", 10, -8)
            bar.label:SetWidth(280)
            bar.label:SetHeight(40)
            bar.label:SetWordWrap(true)
            U.Button(bar, "返回设置", 110, function() G.Adapter.SetCollapsed(false) end):SetPoint("BOTTOMLEFT", 10, 8)
            bar.apply = U.Button(bar, "应用", 90, function() G.Engine:Apply() end)
            bar.apply:SetPoint("BOTTOMRIGHT", -10, 8)
            self.previewBar = bar
        end
        self.previewBar:ClearAllPoints()
        self.previewBar:SetPoint("TOPRIGHT", G.SettingsHost:PreviewAnchor(), "BOTTOMRIGHT", 0, -4)
        self.previewBar:Show()
    else
        if self.previewBar then self.previewBar:Hide() end
        self.panel:Show()
    end
    self.closing = false
    self:Sync()
end

function U:RequestClose()
    local function cancel()
        self.requestedClose = true
        G.Engine:Cancel()
    end
    if G.Engine.dirty then
        self:Confirm("放弃这次尚未应用的更改？", cancel)
    else cancel() end
end

function U:Show()
    if not self.panel then return end
    local ok, err = G.Engine:BeginEdit()
    self.readOnly = not ok
    for _, cell in ipairs(self.cells) do cell:SetEnabled(not self.readOnly) end
    self.panel:Show()
    if not ok then
        self.status:SetText(err or "配置不可用")
        self.coverage:SetText("配置已保留。此版本未通过完整接管检查，未启用第二套数值入口。")
        self.apply:SetEnabled(false)
        G.Regions:Hide()
        return
    end
    self:Sync()
end

function U:Sync()
    if not self.panel or (not self.panel:IsShown() and not self.folded) then return end
    if self.readOnly then return end
    local settings = G.Engine.draft or (G.Engine.entry and G.Engine.entry.settings)
    if not settings then return end
    if G.Regions then G.Regions:Refresh(settings) end
    if self.previewBar and self.folded then
        self.previewBar.label:SetText(G.Engine.message or "拖动矩形边缘调整范围")
        self.previewBar.apply:SetEnabled(not InCombatLockdown() and not G.Engine.error)
    end
    if not self.panel:IsShown() then return end
    self.syncing = true
    for _, cell in ipairs(self.cells) do
        local value = cell.axis and settings[cell.category][cell.tier][cell.axis] or settings[cell.category][cell.tier]
        if not cell:HasFocus() then cell:SetText(tostring(value or "")) end
    end
    self.syncing = false
    self.status:SetText(G.Engine.message or "尚未修改")
    self.status:SetTextColor(G.Engine.error and 1 or 0.35, G.Engine.error and 0.45 or 0.85, 0.6)
    local lines = {}
    for _, binding in ipairs(G.Bindings) do
        local state = G.Engine.status[binding.id]
        if not state then
            local target, reason = G.Adapter.Resolve(binding)
            state = target and "可接管，应用后生效" or reason
        end
        lines[#lines + 1] = binding.label .. "：" .. tostring(state)
    end
    self.coverage:SetText(table.concat(lines, "\n"))
    self.apply:SetEnabled(not InCombatLockdown() and not G.Engine.error)
end

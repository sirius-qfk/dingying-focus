local _, G = ...
local R = { frames = {}, highlights = {} }
G.Regions = R
local colors = { { 0.3, 0.9, 0.75 }, { 0.35, 0.68, 1 }, { 0.75, 0.55, 1 } }

function R:StopDrag()
    if self.drag then self.drag.handle:SetScript("OnUpdate", nil) end
    self.drag = nil
end

function R:Create()
    if self.frames[1] then return end
    for i, tier in ipairs(G.Model.tiers) do
        local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(5 + i)
        frame:SetPoint("CENTER", UIParent, "CENTER")
        frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropBorderColor(colors[i][1], colors[i][2], colors[i][3], 0.85)
        frame.label = G.Editor.Text(frame, "空间第 " .. i .. " 档", 12)
        frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 4, 4)
        for _, edge in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
            local handle = CreateFrame("Button", nil, frame)
            handle:SetSize(18, 18)
            handle:SetPoint("CENTER", frame, edge)
            local texture = handle:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints()
            texture:SetColorTexture(colors[i][1], colors[i][2], colors[i][3], 0.85)
            handle:SetScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" or InCombatLockdown() or not G.Engine.editing then return end
                R:StopDrag()
                R.drag = { handle = handle }
                handle:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") or InCombatLockdown() then R:StopDrag(); return end
                    local x, y = GetCursorPosition()
                    local scale = UIParent:GetEffectiveScale()
                    local w, h = G.Screen()
                    local axis = (edge == "LEFT" or edge == "RIGHT") and "width" or "height"
                    local value = axis == "width" and math.abs(x / scale - w / 2) * 2 or math.abs(y / scale - h / 2) * 2
                    value = math.floor(value + 0.5)
                    if G.Engine.draft.regions[tier][axis] ~= value then G.Engine:Change("regions", tier, axis, value) end
                end)
            end)
            handle:SetScript("OnMouseUp", function() R:StopDrag() end)
        end
        self.frames[i] = frame
    end
end

function R:Refresh(settings)
    if InCombatLockdown() or not G.Engine.editing then self:Hide(); return end
    self:Create()
    for i, tier in ipairs(G.Model.tiers) do
        local r, frame = settings.regions[tier], self.frames[i]
        if G.Finite(r.width) and G.Finite(r.height) and r.width > 0 and r.height > 0 then
            frame:SetSize(r.width, r.height)
            frame.label:SetText("空间第 " .. i .. " 档 · " .. r.width .. " × " .. r.height)
            frame:Show()
        else frame:Hide() end
    end
    for _, highlight in ipairs(self.highlights) do highlight:Hide() end
    for i, target in ipairs(G.Engine.targets or {}) do
        local highlight = self.highlights[i]
        if not highlight then
            highlight = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            highlight:SetFrameStrata("HIGH")
            highlight:SetFrameLevel(3)
            highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
            highlight:SetBackdropBorderColor(0.4, 1, 0.8, 0.9)
            self.highlights[i] = highlight
        end
        highlight:ClearAllPoints()
        highlight:SetAllPoints(target.frame)
        if target.frame:IsShown() then highlight:Show() end
    end
end

function R:Hide()
    self:StopDrag()
    for _, frame in ipairs(self.frames) do frame:Hide() end
    for _, frame in ipairs(self.highlights) do frame:Hide() end
end

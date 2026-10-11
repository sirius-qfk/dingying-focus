local _, G = ...
local H = {}
G.SettingsHost = H

function H:PublicAPI()
    local e = EllesmereUI
    return e and type(e.PLUGIN_API_VERSION) == "number" and e.PLUGIN_API_VERSION >= 1
        and type(e.RegisterPlugin) == "function" and type(e.OpenPlugin) == "function"
end

function H:Mode()
    if self:PublicAPI() then return "plugin" end
    local contract = G.Compatibility.versions[G.Compatibility:Version()]
    return contract and contract.settings == "legacy" and "legacy" or nil
end

function H:Leave()
    if self.leaving then return end
    self.leaving = true
    G.Editor:CloseViews()
    if G.Engine.editing then G.Engine:Cancel() end
    self.leaving = nil
end

function H:Build(_, parent, offset)
    local e = EllesmereUI
    if e.IsSearchPrebuild and e.IsSearchPrebuild() then return 0 end
    G.NativeControls:HookWidgets()
    G.Editor:Create(parent, offset or 0)
    G.Editor:Show()
    return 610 + math.abs(offset or 0)
end

function H:AttachLegacy()
    if self:Mode() ~= "legacy" or not G.Adapter.Probe() then return end
    local host = EllesmereUI:GetMainFrame()
    if not host then return end
    G.Editor:Create(host)
    if not self.button then
        self.button = G.Editor.Button(host, "梯度设置", 105, function() self:Open() end)
        self.button:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 220, 16)
        self.button:SetFrameLevel(host:GetFrameLevel() + 50)
    end
    if EllesmereUI._panelCollapsed then self.button:Hide() else self.button:Show() end
    if self.openPending then self.openPending = nil; G.Editor:Show() end
end

function H:Install()
    local e, mode = EllesmereUI, self:Mode()
    if not mode then return nil, G.Compatibility:Summary() end
    if mode == "plugin" and not self.registered then
        self.registered = e.RegisterPlugin(G.name, {
            label = "梯度", position = "bottom",
            modules = { {
                key = "Gradient", title = "梯度设置", pages = { "视觉梯度" },
                description = "只调整三档数值，元素绑定与布局由插件统一处理。",
                searchPrebuild = false,
                buildPage = function(...) return self:Build(...) end,
                onPageCacheRestore = function() G.Editor:Show() end,
                onModuleLeave = function() self:Leave() end,
            } },
        })
        if not self.registered then return nil, "EUI 拒绝注册梯度页；未覆盖原设置页" end
    end
    if not self.installed then
        self.installed = true
        if e.RegisterOnShow then e:RegisterOnShow(function()
            self:AttachLegacy(); G.NativeControls:HookWidgets(); G.Engine:Schedule("打开设置")
        end) end
        if e.RegisterOnHide then e:RegisterOnHide(function() self:Leave() end) end
        if e.RegisterOnCollapse then e:RegisterOnCollapse(function(on)
            if self.button then if on then self.button:Hide() else self.button:Show() end end
            G.Editor:SetCollapsed(on)
        end) end
        G.On("closed", function()
            local requested = G.Editor.requestedClose
            G.Editor.requestedClose = nil
            if requested and not self.leaving and self:Mode() == "plugin" and e.Hide then e:Hide() end
        end)
    end
    G.NativeControls:HookWidgets()
    self:AttachLegacy()
    return true
end

function H:Open()
    if G.Runtime.InCombat() then G.Message("脱战后才能打开梯度编辑器"); return end
    local ok, err = self:Install()
    if not ok then G.Message(err); return nil, err end
    if self:Mode() == "plugin" then
        local e = EllesmereUI
        local opened = e.OpenPlugin(G.name, "Gradient", "视觉梯度")
        -- Selecting the already-active module can be a native no-op. Context
        -- changes close our draft, so explicitly revive the existing own page.
        if opened and G.Editor.panel and e.GetPluginModuleKey and e.GetActiveModule
            and e:GetActiveModule() == e.GetPluginModuleKey(G.name, "Gradient") then
            G.Editor:Show()
        end
        return opened
    end
    self.openPending = true
    EllesmereUI:Show()
    self:AttachLegacy()
    return true
end

-- Folding and its mini-frame remain private, versioned conveniences. No public
-- API claim is made for them, or for NativeControls/element resizing.
function H:SetCollapsed(on)
    if not G.Adapter.Probe() or type(EllesmereUI._SetPanelCollapsed) ~= "function"
        or type(EllesmereUI.RegisterOnCollapse) ~= "function" then
        return nil, "折叠入口未验证，请移动设置窗口查看布局"
    end
    EllesmereUI._SetPanelCollapsed(on)
    return true
end

function H:PreviewAnchor()
    local e = EllesmereUI
    return e and (e._panelMini or (e.GetMainFrame and e:GetMainFrame())) or UIParent
end

function H:PreviewParent()
    local e = EllesmereUI
    return e and e.GetMainFrame and e:GetMainFrame() or UIParent
end

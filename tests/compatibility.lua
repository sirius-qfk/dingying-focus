-- Source-contract fixtures. These are not a substitute for the actual EUI UI,
-- protected frames, combat taint or a real saved-variable /reload.
local files = {
    "Core.lua", "Runtime.lua", "Model.lua", "Bindings.lua", "Journal.lua",
    "Integrations/EUI/Compatibility.lua", "Integrations/EUI/ActionBars.lua",
    "Integrations/EUI/Cooldowns.lua", "Integrations/EUI/Elements.lua", "Store.lua",
    "Engine.lua", "UI/Editor.lua", "UI/Regions.lua", "Integrations/EUI/NativeControls.lua",
    "Integrations/EUI/SettingsHost.lua", "UI/EUIBridge.lua", "Bootstrap.lua",
}
local function fixture(saved, seed)
    local m = assert(loadfile("tests/mock.lua"))()
    m.version = "9.4"; m.EnablePluginAPI()
    local g = {}
    for _, file in ipairs(files) do assert(loadfile(file))("EllesmereUIGradient", g) end
    if seed then seed(m, g) end
    g.Engine:Init(saved or {})
    g.Adapter.InstallHooks(); g.Bridge:Install(); m.Flush()
    return g, m, g.Engine
end
local function apply(g, m)
    assert(g.Bridge:Open()); assert(g.Engine:Apply()); m.Flush()
end
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1; print("ok - " .. name)
end

test("9.4 registers a real plugin section exactly once", function()
    local g, m = fixture(); local e = EllesmereUI
    g.Bridge:Install(); apply(g, m)
    assert(e.plugins[g.name] and not g.SettingsHost.button)
    assert(g.Editor.panel:GetParent() == e.pluginParent and e.pageHeight == 620)
    assert(#g.Editor.cells == 12 and #g.Engine.targets == 5)
end)

test("plugin page caching preserves saved values and reopens editing", function()
    local g, m, engine = fixture(); apply(g, m)
    engine:Change("icon", "t2", nil, 39); m.Flush()
    EllesmereUI.plugins[g.name].modules[1].onModuleLeave(); m.Flush()
    assert(not engine.editing and m.ab.db.profile.bars.MainBar.buttonWidth == 36)
    assert(g.Bridge:Open()); m.Flush()
    assert(engine.editing and engine.draft.icon.t2 == 36)
end)

test("page rebuild reuses own editor without duplicate named frames", function()
    local g, m = fixture(); apply(g, m)
    local panel = g.Editor.panel
    local parent = CreateFrame("Frame", nil, EllesmereUI.host)
    g.SettingsHost:Build("视觉梯度", parent, -20)
    assert(g.Editor.panel == panel and panel:GetParent() == parent and #g.Editor.cells == 12)
end)

test("search prebuild has no hooks preview frames or writes", function()
    local g, m, e = fixture(); local writes = m.writes
    m.searchPrebuild = true
    assert(g.SettingsHost:Build("视觉梯度", UIParent, 0) == 0)
    assert(not g.Editor.panel and not e.editing and m.writes == writes)
    assert(EllesmereUI.plugins[g.name].modules[1].searchPrebuild == false)
end)

test("all five managed groups replace their three numeric entries", function()
    local g, m = fixture(); apply(g, m)
    local e = EllesmereUI
    for _, binding in ipairs(g.Bindings) do
        e._buildingModule = binding.module == "action" and "EllesmereUIActionBars" or "EllesmereUICooldownManager"
        e._buildingSelector = { key = binding.key }
        local labels = binding.module == "action" and { "Icon Size", "Keybind Text Size", "Charges Text Size" }
            or { "Icon Scale", "Duration Size", "Charge/Stack Size" }
        for _, label in ipairs(labels) do
            local row = e.Widgets:DualRow(e.host, 0, { type = "slider", text = label })
            local region = row._leftRegion
            assert(not region._control:IsShown() and not region.valueBox:IsShown())
            assert(g.NativeControls.slots[region].overlay:IsShown())
        end
    end
end)

test("unbound native controls remain untouched", function()
    local g, m = fixture(); apply(g, m)
    local e = EllesmereUI
    e._buildingModule, e._buildingSelector = "EllesmereUIActionBars", { key = "Bar9" }
    local row = e.Widgets:DualRow(e.host, 0, { type = "slider", text = "Icon Size" })
    assert(not g.NativeControls.slots[row._leftRegion] and row._leftRegion._control:IsShown())
end)

test("folded plugin preview toolbar is outside hidden page content", function()
    local g, m, e = fixture(); apply(g, m)
    e:Change("icon", "t2", nil, 40); m.Flush()
    assert(g.Adapter.SetCollapsed(true))
    assert(g.Editor.previewBar:GetParent() == EllesmereUI.host)
    assert(e.editing and e.dirty and g.Editor.previewBar:IsShown())
    assert(g.Adapter.SetCollapsed(false) and g.Editor.panel:IsShown())
end)

test("unknown host permits public diagnostics but never private writes", function()
    local g, m, e = fixture(nil, function(mock) mock.version = "99.0" end)
    assert(g.Bridge:Open()); m.Flush()
    assert(EllesmereUI.plugins[g.name] and g.Editor.readOnly and not g.Editor.apply.enabled)
    assert(not e:Run(g.Model.Defaults()) and m.writes == 0)
end)

test("no EUI still loads storage and status without hard dependency", function()
    local g, m, e = fixture(nil, function() EllesmereUI = nil end)
    assert(e.db and e.db.schema == 2 and not e.entry)
    SlashCmdList.ELLESMEREUIGRADIENT("status")
    assert(not g.Bridge:Open() and m.writes == 0)
end)

test("missing official API cannot silently fall back to a covering panel", function()
    local g, m, e = fixture(nil, function() EllesmereUI.RegisterPlugin = nil end)
    assert(not g.Bridge:Open() and not g.Editor.panel)
    assert(not e:Run(g.Model.Defaults()) and m.writes == 0)
end)

test("missing cooldown capability leaves action bars usable", function()
    local g, m, e = fixture(nil, function(mock) mock.nsCD.LayoutCDMBar = nil end)
    apply(g, m)
    assert(e.partial and #e.targets == 3 and m.ab.db.profile.bars.MainBar.buttonWidth == 36)
    assert(m.nsCD.GetBarData("cooldowns").iconSize == 24)
end)

test("mixed component versions pause only never-acquired mismatching module", function()
    local g, m, e = fixture(nil, function(mock) mock.versions = { EllesmereUICooldownManager = "9.3" } end)
    apply(g, m)
    assert(e.partial and #e.targets == 3)
    assert(e.status["cooldown.cooldowns"]:find("版本未验证"))
end)

test("external action change freezes action module but allows safe cooldown changes", function()
    local g, m, e = fixture(); apply(g, m)
    m.ab.db.profile.bars.MainBar.buttonWidth = 77
    e:Change("icon", "t1", nil, 44); m.Flush()
    assert(not e.error and e.partial and e.suspended.action)
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 77)
    assert(m.ab.db.profile.bars.Bar2.buttonWidth == 30)
    assert(m.nsCD.GetBarData("cooldowns").iconSize == 44)
    assert(e.entry.applied.leases["action.MainBar/buttonWidth"].original == 24)
end)

test("unmeasurable frozen module blocks related layout without refreshing others", function()
    local g, m, e = fixture(); apply(g, m)
    EllesmereUI._ModuleNS.EllesmereUIActionBars = nil
    local writes = m.writes
    e:Change("icon", "t1", nil, 44); m.Flush()
    assert(e.error and m.writes == writes and m.nsCD.GetBarData("cooldowns").iconSize == 42)
end)

test("overlap with frozen module rolls healthy changes back", function()
    local g, m, e = fixture(); apply(g, m)
    m.ab.db.profile.bars.MainBar.buttonWidth = 77
    e:Change("regions", "t2", "height", e.draft.regions.t3.height - 2); m.Flush()
    assert(e.error and e.error:find("重叠"))
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 77)
    assert(m.nsCD.GetBarData("utility").iconSize == 36)
end)

test("unknown restoration contract is retained without baseline writes", function()
    local g, m, e = fixture(); apply(g, m)
    e.entry.applied.contracts.action.contract = "future-bars"
    assert(e:Restore()); m.Flush()
    assert(e.entry.applied.leases["action.MainBar/buttonWidth"])
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 36)
    assert(m.nsCD.GetBarData("cooldowns").iconSize == 24 and not e.entry.enabled)
end)

test("game interface change blocks apply and restore even if functions exist", function()
    local g, m, e = fixture(); apply(g, m)
    m.interface = 120101; local writes = m.writes
    assert(not e:Run(e.entry.settings) and not e:Restore())
    assert(m.writes == writes and e.entry.applied.leases["action.MainBar/buttonWidth"])
end)

test("first preview persists provenance before a reload", function()
    local g, m, e = fixture(); assert(g.Bridge:Open())
    e:Change("icon", "t2", nil, 40); m.Flush()
    assert(not e.entry.enabled and e.entry.applied.contracts.action.host == "9.4")
    local saved, ab, cd = g.Copy(e.db), g.Copy(m.ab.db.profile), g.Copy(m.cd.db.profile)
    local _, mock, engine = fixture(saved, function(mm) mm.ab.db.profile, mm.cd.db.profile = ab, cd end)
    engine:Schedule("reload"); mock.Flush()
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
    assert(not next(engine.entry.applied.leases))
end)

test("schema one migrates tiers and records actual 9.3 writer", function()
    local g, m, e = fixture(nil, function(mock) mock.version = "9.3" end); apply(g, m)
    local saved, ab, cd = g.Copy(e.db), g.Copy(m.ab.db.profile), g.Copy(m.cd.db.profile)
    saved.schema = 1
    for _, entry in pairs(saved.profiles) do
        entry.leases, entry.points, entry.applied = entry.applied.leases, entry.applied.points, nil
    end
    local _, mock, engine = fixture(saved, function(mm) mm.ab.db.profile, mm.cd.db.profile = ab, cd end)
    assert(engine.db.schema == 2 and engine.entry.settings.icon.t2 == 36)
    assert(engine.entry.applied.contracts.action.host == "9.3")
    assert(engine:Restore()); mock.Flush()
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
end)

test("failed migration leaves all profiles and schema byte-equivalent", function()
    local g, _, e = fixture()
    local saved = { schema = 1, profiles = {
        good = { enabled = false, settings = g.Model.Defaults(), leases = {}, points = {} },
        bad = { enabled = false, settings = g.Model.Defaults(), leases = "broken", points = {} },
    } }
    local before = g.Copy(saved)
    e:Init(saved)
    assert(e.blocked and g.Equal(saved, before))
end)

test("future schema remains unchanged even with no EUI", function()
    local saved = { schema = 99, sentinel = "keep" }
    local g, m, e = fixture(saved, function() EllesmereUI = nil end)
    assert(e.blocked and not e.db and saved.schema == 99 and saved.sentinel == "keep" and m.writes == 0)
    SlashCmdList.ELLESMEREUIGRADIENT("status")
end)

test("unknown prior writer cannot be trusted solely by matching contract name", function()
    local g, m, e = fixture(); apply(g, m)
    e.entry.applied.contracts.action.host = "99.0"
    assert(e:Restore()); m.Flush()
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 36)
    assert(e.entry.applied.leases["action.MainBar/buttonWidth"])
end)

test("broken original control structure pauses the entire affected module", function()
    local g, m, e = fixture(); apply(g, m)
    local host = EllesmereUI
    host._buildingModule, host._buildingSelector = "EllesmereUIActionBars", { key = "MainBar" }
    host.Widgets.DualRow = function(_, parent, _, cfg)
        local row = CreateFrame("Frame", nil, parent)
        row._leftRegion = CreateFrame("Frame", nil, row)
        row._leftRegion._widgetCfg = cfg
        return row
    end
    g.NativeControls:HookWidgets()
    host.Widgets:DualRow(host.host, 0, { type = "slider", text = "Icon Size" })
    local writes = m.writes; m.Flush()
    assert(g.NativeControls.failures.action and e.error and m.writes == writes)
    assert(e.entry.applied.leases["action.MainBar/buttonWidth"])
end)

test("settings plugin registration rejection never enables element writes", function()
    local g, m, e = fixture(nil, function() EllesmereUI.RegisterPlugin = function() return false end end)
    assert(not g.Bridge:Open() and not g.Editor.panel and m.writes == 0)
    -- A failed registration must also reject explicit engine calls.
    assert(not e:Run(g.Model.Defaults()))
end)

test("read-only diagnostics can close safely without a current profile", function()
    local g, m, e = fixture(nil, function(mock) mock.version = "99.0" end)
    assert(g.Bridge:Open() and not e.entry)
    g.Editor:RequestClose(); m.Flush()
    assert(not EllesmereUI.host:IsShown() and m.writes == 0)
end)

test("hiding a plugin page for navigation does not close the EUI host", function()
    local g, m, e = fixture(); apply(g, m)
    g.Editor.panel:Hide(); m.Flush()
    assert(not e.editing and EllesmereUI.host:IsShown())
end)

test("ambiguous schema does not discard newer restoration records", function()
    local g, _, e = fixture()
    local saved = g.Copy(e.db); saved.schema = 1
    local before = g.Copy(saved)
    e:Init(saved)
    assert(e.blocked and g.Equal(before, saved))
end)

test("active cached plugin page reopens after a profile change closes its draft", function()
    local g, m, e = fixture(); apply(g, m)
    EllesmereUI.SwitchProfile("Second"); m.Flush()
    assert(not e.editing and not g.Editor.panel:IsShown())
    assert(g.Bridge:Open()); m.Flush()
    assert(e.editing and g.Editor.panel:IsShown())
end)

print("Compatibility tests passed: " .. passed .. " (not in-game verification)")

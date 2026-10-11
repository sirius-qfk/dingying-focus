-- Isolated fixtures for interruption, reload, host UI and restoration boundaries.
local function fixture(saved, seed)
    local mock = assert(loadfile("tests/mock.lua"))()
    local g = {}
    for _, file in ipairs({ "Core.lua", "Runtime.lua", "Model.lua", "Bindings.lua", "Journal.lua", "Integrations/EUI/Compatibility.lua", "Integrations/EUI/ActionBars.lua", "Integrations/EUI/Cooldowns.lua", "Integrations/EUI/Elements.lua", "Store.lua", "Engine.lua", "UI/Editor.lua", "UI/Regions.lua", "Integrations/EUI/NativeControls.lua", "Integrations/EUI/SettingsHost.lua", "UI/EUIBridge.lua", "Bootstrap.lua" }) do
        assert(loadfile(file))("EllesmereUIGradient", g)
    end
    if seed then seed(mock, g) end
    g.Engine:Init(saved or {})
    g.Adapter.InstallHooks(); g.Bridge:Install(); mock.Flush()
    return g, mock, g.Engine
end

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1; print("ok - " .. name)
end
local function apply(g, mock)
    g.Bridge:Open(); assert(g.Engine:Apply()); mock.Flush()
end
local function position(frame)
    local p, _, rp, x, y = frame:GetPoint()
    return { point = p, relPoint = rp, x = x, y = y }
end
local function snapshot(g, mock)
    return { saved = g.Copy(g.Engine.db), ab = g.Copy(mock.ab.db.profile), cd = g.Copy(mock.cd.db.profile) }
end
local function reload(snap)
    return fixture(snap.saved, function(mock)
        mock.ab.db.profile, mock.cd.db.profile = snap.ab, snap.cd
        for key, pos in pairs(snap.ab.barPositions) do
            _G["EABBar_" .. key]:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end)
end

test("restore preserves anchors when host position table was replaced", function()
    local g, mock, e = fixture(); apply(g, mock)
    local projected = position(EABBar_MainBar)
    mock.ab.db.profile.barPositions = g.Copy(mock.ab.db.profile.barPositions)
    assert(e:Restore()); mock.Flush()
    assert(g.Equal(projected, position(EABBar_MainBar)))
    assert(mock.ab.db.profile.barPositions.MainBar)
end)
test("replaced config table restores native editable slider", function()
    local g, mock = fixture(); apply(g, mock)
    local host = EllesmereUI
    host._buildingModule, host._buildingSelector = "EllesmereUIActionBars", { key = "MainBar" }
    local row = host.Widgets:DualRow(host.host, 0, { type = "slider", text = "Icon Size" })
    assert(not row._leftRegion._control:IsShown())
    mock.ab.db.profile.bars.MainBar = g.Copy(mock.ab.db.profile.bars.MainBar)
    g.Bridge:RefreshSlots()
    assert(row._leftRegion._control:IsShown())
end)
test("cancel on external conflict closes draft and pauses takeover", function()
    local g, mock, e = fixture(); apply(g, mock)
    e:Change("icon", "t2", nil, 40); mock.Flush()
    mock.ab.db.profile.bars.MainBar.buttonWidth = 77
    assert(e:Cancel()); mock.Flush()
    assert(not e.editing and not e.entry.enabled and not e.draft)
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 77)
    assert(mock.ab.db.profile.bars.Bar2.buttonWidth == 24)
    assert(e.entry.settings.icon.t2 == 36)
end)
test("absent module is restored when it becomes ready again", function()
    local g, mock, e = fixture(); apply(g, mock)
    local all = EllesmereUI._ModuleNS
    local ns = all.EllesmereUIActionBars; all.EllesmereUIActionBars = nil
    assert(e:Restore()); mock.Flush()
    assert(e.entry.applied.leases["action.MainBar/buttonWidth"])
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 36)
    all.EllesmereUIActionBars = ns
    e:Schedule("ADDON_LOADED"); mock.Flush()
    assert(not next(e.entry.applied.leases) and mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
end)
test("unchanged native refresh does not cause redundant resize", function()
    local g, mock = fixture(); apply(g, mock)
    local count = mock.writes
    mock.ab:ApplyButtonSizeForBar("MainBar"); mock.Flush()
    assert(mock.writes == count + 1)
end)
test("overlap rejects the whole preview and preserves last valid layout", function()
    local g, mock, e = fixture(); apply(g, mock)
    local before = snapshot(g, mock); local pos = position(EABBar_MainBar)
    e:Change("regions", "t2", "height", e.draft.regions.t1.height + 2); mock.Flush()
    assert(e.error and e.error:find("重叠"))
    assert(g.Equal(before.ab, mock.ab.db.profile) and g.Equal(before.cd, mock.cd.db.profile))
    assert(g.Equal(pos, position(EABBar_MainBar)))
end)
test("shared-table profile switch restores baseline values and anchors", function()
    local g, mock, e = fixture(); local original = position(EABBar_MainBar)
    apply(g, mock); EllesmereUI.SwitchProfile("Second"); mock.Flush()
    assert(not e.editing and not e.entry.enabled)
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
    assert(g.Equal(original, position(EABBar_MainBar)))
    EllesmereUI.SwitchProfile("Default"); mock.Flush()
    assert(e.entry.enabled and mock.ab.db.profile.bars.MainBar.buttonWidth == 36)
end)
test("reload cancels a first uncommitted preview", function()
    local g, mock, e = fixture(); g.Bridge:Open()
    e:Change("icon", "t2", nil, 40); mock.Flush()
    local fresh, m, engine = reload(snapshot(g, mock))
    engine:Schedule("PLAYER_LOGIN"); m.Flush()
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 24)
    assert(not engine.entry.enabled and not next(engine.entry.applied.leases))
    assert(position(EABBar_MainBar).x == 100)
    assert(not fresh.Engine.editing)
end)
test("reload reapplies saved tiers not the uncommitted draft", function()
    local g, mock, e = fixture(); apply(g, mock)
    e:Change("icon", "t2", nil, 40); mock.Flush()
    local _, m, engine = reload(snapshot(g, mock))
    engine:Schedule("PLAYER_LOGIN"); m.Flush()
    assert(engine.entry.enabled and m.ab.db.profile.bars.MainBar.buttonWidth == 36)
    assert(engine:Restore()); m.Flush()
    assert(m.ab.db.profile.bars.MainBar.buttonWidth == 24)
end)
test("unknown host version will not restore persisted values", function()
    local g, mock, e = fixture(); apply(g, mock)
    mock.version = "99.0"; local before = snapshot(g, mock); local writes = mock.writes
    assert(not e:Restore()); e:Schedule("version"); mock.Flush()
    assert(g.Equal(before.ab, mock.ab.db.profile) and mock.writes == writes)
end)
test("malformed saved lease is preserved and blocks takeover", function()
    local g, mock = fixture(); apply(g, mock); local snap = snapshot(g, mock)
    snap.saved.profiles[g.Engine.context].applied.leases["action.MainBar/buttonWidth"] = "broken"
    local fresh, m, e = reload(snap)
    assert(e.blocked and snap.saved.profiles[g.Engine.context].applied.leases["action.MainBar/buttonWidth"] == "broken")
    local writes = m.writes; assert(not e:BeginEdit()); assert(m.writes == writes and fresh.Engine.blocked)
end)
test("malformed saved anchors block takeover without discarding data", function()
    local g, mock = fixture(); apply(g, mock); local snap = snapshot(g, mock)
    snap.saved.profiles[g.Engine.context].applied.points["action.MainBar"] = { { "BAD", "UIParent", "CENTER", 1, 2 } }
    local _, _, e = reload(snap); assert(e.blocked)
end)
test("font overrides in shared stores conservatively skip cooldown groups", function()
    local g, mock, e = fixture()
    mock.cd.db.profile.customActiveStates = { [123] = { cooldownFontSize = 21 } }
    apply(g, mock)
    assert(mock.nsCD.GetBarData("cooldowns").iconSize == 24)
    assert(e.status["cooldown.cooldowns"]:find("字号覆盖"))
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 36)
end)
test("font overrides in inherited bar tiers skip the group", function()
    local g, mock, e = fixture()
    mock.nsCD.GetBarSpellData = function(key) if key == "utility" then return { barSettings = { stackCountSize = 22 } } end end
    apply(g, mock)
    assert(mock.nsCD.GetBarData("utility").iconSize == 24)
    assert(e.status["cooldown.utility"]:find("字号覆盖"))
end)
test("folded layout preview keeps draft and region interaction alive", function()
    local g, mock, e = fixture(); g.Bridge:Open()
    e:Change("icon", "t2", nil, 40); mock.Flush()
    assert(g.Adapter.SetCollapsed(true))
    assert(e.editing and e.dirty and not g.Editor.panel:IsShown())
    assert(g.Editor.previewBar:IsShown() and g.Regions.frames[1]:IsShown())
    e:Change("regions", "t1", "height", 400); mock.Flush()
    assert(position(mock.nsCD.frames.cooldowns).y == -200)
    assert(g.Adapter.SetCollapsed(false))
    assert(g.Editor.panel:IsShown() and not g.Editor.previewBar:IsShown() and e.draft.icon.t2 == 40)
end)
test("closing EUI while folded cancels preview and hides guides", function()
    local g, mock, e = fixture(); g.Bridge:Open()
    e:Change("icon", "t2", nil, 40); mock.Flush(); g.Adapter.SetCollapsed(true)
    EllesmereUI:Hide(); mock.Flush()
    assert(not e.editing and not g.Editor.previewBar:IsShown() and not g.Regions.frames[1]:IsShown())
    assert(mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
end)
test("combat close is deferred and does not resize protected targets", function()
    local g, mock, e = fixture(); g.Bridge:Open()
    e:Change("icon", "t2", nil, 40); mock.Flush(); g.Adapter.SetCollapsed(true)
    mock.combat = true; local writes = mock.writes
    EllesmereUI:Hide(); mock.Flush(); assert(mock.writes == writes and e.pending)
    mock.combat = false; e:Schedule("PLAYER_REGEN_ENABLED"); mock.Flush()
    assert(not e.editing and mock.ab.db.profile.bars.MainBar.buttonWidth == 24)
end)
test("cooldown size widgets link to tiers and restore their edit boxes", function()
    local g, mock, e = fixture(); apply(g, mock)
    local host = EllesmereUI
    host._buildingModule, host._buildingSelector = "EllesmereUICooldownManager", { key = "cooldowns" }
    for _, label in ipairs({ "Icon Scale", "Duration Size", "Charge/Stack Size" }) do
        local row = host.Widgets:DualRow(host.host, 0, { type = "slider", text = label })
        assert(g.NativeControls.slots[row._leftRegion] and not row._leftRegion.valueBox:IsShown())
    end
    e:Restore(); mock.Flush()
    for region, slot in pairs(g.NativeControls.slots) do assert(region.valueBox:IsShown() and not slot.overlay:IsShown()) end
end)
test("late widget factory installation rebuilds the first existing page once", function()
    local g, mock = fixture(); apply(g, mock)
    local host = EllesmereUI; local row
    host._buildingModule, host._buildingSelector = "EllesmereUIActionBars", { key = "MainBar" }
    mock.buildPage = function() row = host.Widgets:DualRow(host.host, 0, { type = "slider", text = "Icon Size" }) end
    -- Forget only bridge installation identity, representing first hookup after deferred load.
    g.NativeControls.widgetFunction = nil
    local before = mock.pageRefreshes or 0
    g.NativeControls:HookWidgets(); mock.Flush()
    assert(mock.pageRefreshes == before + 1 and g.NativeControls.slots[row._leftRegion])
    g.NativeControls:HookWidgets(); mock.Flush(); assert(mock.pageRefreshes == before + 1)
end)
test("equivalent native growth anchor does not trigger reassertion", function()
    local g, mock, e = fixture(); apply(g, mock)
    local target = e.targets[4]; local writes = mock.writes
    target.frame:SetPoint("BOTTOMLEFT", UIParent, "CENTER", target.position.x - target.extent.width / 2, target.position.y)
    mock.Flush(); assert(mock.writes == writes and g.Adapter.PlacementMatches(target))
end)
test("new native size matching blocks reapply without touching host", function()
    local g, mock, e = fixture(); apply(g, mock)
    mock.matched = "MainBar"; local writes = mock.writes
    assert(not e:Run(e.entry.settings)); assert(mock.writes == writes)
end)
test("custom row sizing is not silently overridden", function()
    local g, mock, e = fixture()
    mock.nsCD.GetBarData("cooldowns").customTopRowSizeEnabled = true
    apply(g, mock)
    assert(mock.nsCD.GetBarData("cooldowns").iconSize == 24)
    assert(e.status["cooldown.cooldowns"]:find("分行图标"))
end)
test("cyclic saved data blocks before copy or mutation", function()
    local g, mock = fixture(); apply(g, mock); local snap = snapshot(g, mock)
    local entry = snap.saved.profiles[g.Engine.context]; entry.settings.cycle = entry.settings
    local _, _, e = reload(snap); assert(e.blocked)
end)
test("legacy position without relative point survives reload and restore", function()
    local g, mock, e = fixture()
    mock.ab.db.profile.barPositions.MainBar = { point = "CENTER", x = 23, y = 45 }
    apply(g, mock)
    local _, m, fresh = reload(snapshot(g, mock))
    assert(not fresh.blocked); fresh:Schedule("PLAYER_LOGIN"); m.Flush(); assert(fresh:Restore())
    assert(m.ab.db.profile.barPositions.MainBar.relPoint == nil and m.ab.db.profile.barPositions.MainBar.x == 23)
end)
print("Lifecycle contract tests passed: " .. passed .. " (not in-game verification)")

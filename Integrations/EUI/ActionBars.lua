local _, G = ...
local D = { addon = "EllesmereUIActionBars" }
G.ElementDrivers.action = D

function D.Probe(all)
    local owner = all.EllesmereUIActionBars and all.EllesmereUIActionBars.EAB
    if type(owner) ~= "table" then return nil, "动作条模块未加载" end
    if type(owner.ApplyButtonSizeForBar) ~= "function" or type(owner.ApplyFontsForBar) ~= "function" then
        return nil, "动作条刷新接口不匹配"
    end
    return true
end

function D.Resolve(all, binding, restoring)
    local ns = all.EllesmereUIActionBars
    local t = { binding = binding, ns = ns, owner = ns.EAB, elementKey = binding.key }
    t.profile = t.owner.db and t.owner.db.profile
    t.config = t.profile and t.profile.bars and t.profile.bars[binding.key]
    t.positions = t.profile and t.profile.barPositions
    t.frame = _G["EABBar_" .. binding.key]
    if type(t.config) ~= "table" or type(t.positions) ~= "table" then return nil, "动作条配置尚未就绪" end
    if not restoring and t.config.alwaysHidden then return nil, "该动作条已隐藏，未接管" end
    return t
end

function D.Fields(_, plan)
    return { buttonWidth = plan.icon, buttonHeight = plan.icon, keybindFontSize = plan.text, countFontSize = plan.count }
end

function D.Refresh(t)
    t.owner:ApplyButtonSizeForBar(t.binding.key)
    t.owner:ApplyFontsForBar(t.binding.key)
end

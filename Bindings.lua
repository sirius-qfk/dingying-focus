local _, G = ...
-- Developer-owned, explicit semantic bindings. Equal pixel values never imply equal roles.
G.Bindings = {
    { id = "action.MainBar", module = "action", key = "MainBar", label = "主动作条", icon = "t2", text = "t2", count = "t3", region = "t3", lane = 0 },
    { id = "action.Bar2", module = "action", key = "Bar2", label = "动作条 2", icon = "t3", text = "t3", count = "t3", region = "t3", lane = 1 },
    { id = "action.Bar3", module = "action", key = "Bar3", label = "动作条 3", icon = "t3", text = "t3", count = "t3", region = "t3", lane = 2 },
    { id = "cooldown.cooldowns", module = "cooldown", key = "cooldowns", label = "核心冷却组", icon = "t1", text = "t1", count = "t3", region = "t1" },
    { id = "cooldown.utility", module = "cooldown", key = "utility", label = "辅助冷却组", icon = "t2", text = "t2", count = "t3", region = "t2" },
}

function G.FindBinding(module, key)
    for _, binding in ipairs(G.Bindings) do
        if binding.module == module and binding.key == key then return binding end
    end
end

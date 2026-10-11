local _, G = ...
local B = {}
G.Bridge = B

function B:RefreshSlots()
    G.NativeControls:RefreshSlots()
end

function B:Open()
    return G.SettingsHost:Open()
end

function B:Install()
    G.SettingsHost:Install()
end

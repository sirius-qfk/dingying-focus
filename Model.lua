local _, G = ...
local M = {}
G.Model = M
M.tiers = { "t1", "t2", "t3" }
M.schema = 1

function M.Defaults(width, height)
    width, height = width or 1920, height or 1080
    return {
        text = { t1 = 16, t2 = 13, t3 = 11 },
        icon = { t1 = 42, t2 = 36, t3 = 30 },
        regions = {
            t1 = { width = math.floor(width * 0.42), height = math.floor(height * 0.32) },
            t2 = { width = math.floor(width * 0.65), height = math.floor(height * 0.56) },
            t3 = { width = math.floor(width * 0.90), height = math.floor(height * 0.88) },
        },
    }
end

function M.Validate(settings, width, height)
    if type(settings) ~= "table" then return nil, "缺少梯度配置" end
    for _, category in ipairs({ "text", "icon" }) do
        if type(settings[category]) ~= "table" then return nil, "缺少 " .. category .. " 档位" end
        local lo, hi = 8, 30
        if category == "icon" then lo, hi = 16, 96 end
        for _, tier in ipairs(M.tiers) do
            local value = settings[category][tier]
            if not G.Finite(value) or value < lo or value > hi or value % 1 ~= 0 then
                return nil, (category == "text" and "字号" or "图标尺寸") .. "应为 " .. lo .. "–" .. hi .. " 的整数"
            end
        end
    end
    if type(settings.regions) ~= "table" then return nil, "缺少矩形配置" end
    local previousW, previousH = 0, 0
    for _, tier in ipairs(M.tiers) do
        local r = settings.regions[tier]
        if type(r) ~= "table" or not G.Finite(r.width) or not G.Finite(r.height) then return nil, "矩形尺寸无效" end
        if r.width < 100 or r.height < 80 or r.width % 1 ~= 0 or r.height % 1 ~= 0 then return nil, "矩形宽高须为整数，至少 100 × 80" end
        if r.width <= previousW or r.height <= previousH then return nil, "外层矩形的宽、高都必须大于内层" end
        if (width and r.width > width) or (height and r.height > height) then return nil, "矩形超出当前屏幕，请缩小后再应用" end
        previousW, previousH = r.width, r.height
    end
    return true
end

-- Coordinates are in UIParent units. Bottom lanes grow inwards from the region edge.
function M.Position(binding, settings, extent, laneHeight)
    if not binding.region then return nil end
    local r = settings.regions[binding.region]
    local gap = binding.gap or 8
    local lane = binding.lane or 0
    local x = binding.offsetX or 0
    local y = -r.height / 2 + lane * ((laneHeight or extent.height) + gap)
    if extent.width > r.width then return nil, "组件比所属矩形宽，需扩大矩形或缩小图标" end
    if y + extent.height > r.height / 2 then return nil, "组件组放不进所属矩形" end
    return { point = "BOTTOM", relPoint = "CENTER", x = x, y = y }
end

function M.Plan(settings, bindings)
    local out = {}
    for _, binding in ipairs(bindings) do
        if not settings.icon[binding.icon] or not settings.text[binding.text] or not settings.text[binding.count] then
            return nil, "绑定引用了不存在的档位：" .. tostring(binding.id)
        end
        if binding.region and not settings.regions[binding.region] then return nil, "绑定引用了不存在的矩形" end
        out[#out + 1] = {
            binding = binding, icon = settings.icon[binding.icon],
            text = settings.text[binding.text], count = settings.text[binding.count],
        }
    end
    return out
end

function M.CheckOverlap(targets)
    for i = 1, #targets do
        local a = targets[i]
        for j = i + 1, #targets do
            local b = targets[j]
            local overlapX = math.min(a.position.x + a.extent.width / 2, b.position.x + b.extent.width / 2)
                - math.max(a.position.x - a.extent.width / 2, b.position.x - b.extent.width / 2)
            local overlapY = math.min(a.position.y + a.extent.height, b.position.y + b.extent.height)
                - math.max(a.position.y, b.position.y)
            if overlapX > 1 and overlapY > 1 then
                return nil, a.binding.label .. "与" .. b.binding.label .. "重叠，请拉开矩形边界或缩小图标"
            end
        end
    end
    return true
end

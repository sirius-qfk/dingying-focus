local _, G = ...
local S = { schema = 2 }
G.Store = S

local anchors = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local function validPosition(p, original)
    if original and p == false then return true end
    if type(p) ~= "table" or not anchors[p.point] then return false end
    if (not anchors[p.relPoint] and not (original and p.relPoint == nil))
        or (not G.Finite(p.x) and not (original and p.x == nil))
        or (not G.Finite(p.y) and not (original and p.y == nil)) then return false end
    for key, value in pairs(p) do
        if type(key) ~= "string" or (type(value) ~= "string" and type(value) ~= "boolean" and not G.Finite(value)) then return false end
    end
    return true
end

function S.ValidEntry(entry)
    if type(entry) ~= "table" or not G.ValidData(entry) or not G.Model.Validate(entry.settings) or type(entry.enabled) ~= "boolean"
        or type(entry.applied) ~= "table" or type(entry.applied.contracts) ~= "table"
        or (entry.applied.leases ~= nil and type(entry.applied.leases) ~= "table") or (entry.applied.points ~= nil and type(entry.applied.points) ~= "table") then return false end
    for group, stamp in pairs(entry.applied.contracts) do
        if type(group) ~= "string" or type(stamp) ~= "table" or type(stamp.contract) ~= "string"
            or type(stamp.host) ~= "string" or type(stamp.component) ~= "string" then return false end
    end
    for id, lease in pairs(entry.applied.leases or {}) do
        local b, field = G.Adapter.LeaseBinding(id)
        if not b or type(lease) ~= "table" then return false end
        if field == "position" then
            if not validPosition(lease.last) or (lease.original ~= nil and not validPosition(lease.original, true)) then return false end
        elseif not G.Finite(lease.last) or (lease.original ~= nil and not G.Finite(lease.original)) then return false end
    end
    for id, points in pairs(entry.applied.points or {}) do
        if type(id) ~= "string" or not G.Adapter.LeaseBinding(id .. "/position") or type(points) ~= "table" then return false end
        local count = 0
        for i, point in pairs(points) do
            count = count + 1
            if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > 9 or type(point) ~= "table"
                or not anchors[point[1]] or type(point[2]) ~= "string" or not anchors[point[3]]
                or not G.Finite(point[4]) or not G.Finite(point[5]) then return false end
        end
        if count ~= #points then return false end
    end
    return true
end

function S.Init(db)
    if type(db) ~= "table" then return nil, "保存的数据不是有效配置，已停止写入" end
    if db.schema and db.schema ~= 1 and db.schema ~= S.schema then return nil, "配置格式来自其他版本，已停止写入" end
    if db.profiles and type(db.profiles) ~= "table" then return nil, "配置列表无效，已停止写入" end
    local migrated = {}
    -- Validate everything before replacing anything, including inactive profiles.
    for key, entry in pairs(db.profiles or {}) do
        if type(key) ~= "string" or type(entry) ~= "table" or not G.ValidData(entry) then
            return nil, "配置损坏，已保留原数据并停止接管"
        end
        local candidate = G.Copy(entry)
        if db.schema ~= S.schema then
            if candidate.applied ~= nil then return nil, "配置格式与版本标记不一致，保留原数据" end
            candidate.applied = { leases = candidate.leases or {}, points = candidate.points or {}, contracts = {} }
            candidate.leases, candidate.points = nil, nil
            -- The only shipped schema-1 writer was the EUI 9.3 alpha. Do not
            -- infer provenance from whichever EUI happens to be installed now.
            if type(candidate.applied.leases) ~= "table" then return nil, "恢复记录损坏，已保留原数据" end
            for id in pairs(candidate.applied.leases) do
                local binding = G.Adapter.LeaseBinding(id)
                if binding then
                    candidate.applied.contracts[binding.module] = G.Adapter.LegacyStamp(binding.module)
                end
            end
        end
        if not S.ValidEntry(candidate) then return nil, "配置损坏，已保留原数据并停止接管" end
        migrated[key] = candidate
    end
    db.profiles, db.schema = migrated, S.schema
    return true
end

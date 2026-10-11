local _, G = ...
local J = {}
J.__index = J
G.Journal = J

function J.New(saved)
    return setmetatable({ saved = saved or {}, live = {}, undo = {} }, J)
end

function J:Owns(id, ref)
    local lease, previous = self.saved[id], self.live[id]
    return lease and ref and (not previous or (previous.object == ref.object and previous.key == ref.key))
        and G.Equal(rawget(ref.object, ref.key), lease.last) or false
end

function J:Begin()
    self.undo = {}
    self.before = G.Copy(self.saved)
end

function J:Write(id, object, key, value)
    local current = rawget(object, key)
    local lease = self.saved[id]
    local previous = self.live[id]
    if lease and previous and (previous.object ~= object or previous.key ~= key) then
        return nil, "配置对象已更换，未覆盖：" .. id
    end
    if lease and not G.Equal(current, lease.last) then
        return nil, "检测到外部修改，未覆盖：" .. id
    end
    if not lease then
        lease = { original = G.Copy(current), last = G.Copy(current) }
        self.saved[id] = lease
    end
    self.live[id] = { object = object, key = key }
    self.undo[#self.undo + 1] = { object = object, key = key, value = G.Copy(current) }
    object[key] = G.Copy(value)
    lease.last = G.Copy(value)
    return true
end

function J:Rollback()
    for i = #self.undo, 1, -1 do
        local change = self.undo[i]
        change.object[change.key] = G.Copy(change.value)
    end
    if self.before then
        for key in pairs(self.saved) do self.saved[key] = nil end
        for key, value in pairs(self.before) do self.saved[key] = value end
    end
    self.undo, self.before = {}, nil
end

function J:Commit()
    self.undo, self.before = {}, nil
end

-- Conditional restoration preserves later user/host writes; nil originals are valid.
function J:Restore(resolve)
    local conflicts, unresolved = {}, {}
    for id, lease in pairs(self.saved) do
        local ref
        if resolve then ref = resolve(id) else ref = self.live[id] end
        if ref then
            if self:Owns(id, ref) then
                ref.object[ref.key] = G.Copy(lease.original)
            else
                conflicts[#conflicts + 1] = id
            end
            self.saved[id] = nil
            self.live[id] = nil
        else
            unresolved[#unresolved + 1] = id
        end
    end
    return conflicts, unresolved
end

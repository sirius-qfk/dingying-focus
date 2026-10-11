local _, G = ...
local E = { status = {}, targets = {}, revision = 0, suspended = {} }
G.Engine = E

function E:Notify(message)
    self.message = message
    G.Emit("state", self)
end

function E:LeaseRef(id)
    local binding = G.Adapter.LeaseBinding(id)
    if not binding or not self.entry or not G.Adapter.CanReplay(binding.module, self.entry.applied.contracts[binding.module]) then return nil end
    return G.Adapter.LeaseRef(id)
end

function E:Init(db)
    local ok, err = G.Store.Init(db)
    if not ok then self.blocked = err; return end
    self.db = db
    self:SyncContext()
end

function E:SyncContext()
    if self.blocked or not self.db then return false end
    local available, reason = G.Adapter.Probe()
    if not available then self:Notify(reason); return false end
    local key = G.Adapter.Context()
    if key == self.context then return true end
    -- Release the old live tables, not newly selected host tables. No host refresh here.
    if self.journal then
        self.contextRestores = {}
        for _, b in ipairs(G.Bindings) do
            local id = b.id .. "/position"
            local lease, oldRef = self.entry.applied.leases[id], self.journal.live[id]
            local currentRef = self:LeaseRef(id)
            if lease and oldRef and currentRef and oldRef.object == currentRef.object
                and G.Equal(rawget(oldRef.object, oldRef.key), lease.last) then
                local t = G.Adapter.Resolve(b, true)
                if t and t.frame then
                    self.contextRestores[#self.contextRestores + 1] = { target = t, points = G.Copy(self.entry.applied.points[b.id]) }
                end
            end
        end
        local _, unresolved = self.journal:Restore(function(id)
            local binding = G.Adapter.LeaseBinding(id)
            if binding and G.Adapter.CanReplay(binding.module, self.entry.applied.contracts[binding.module]) then
                return self.journal.live[id]
            end
        end)
        if #unresolved == 0 then self.entry.applied.points = {} end
    end
    self.context, self.pending, self.draft, self.editing = key, nil, nil, false
    self.targets, self.status, self.error, self.dirty, self.suspended = {}, {}, nil, false, {}
    local width, height = G.Screen()
    local entry = self.db.profiles[key]
    if not entry then
        entry = { enabled = false, settings = G.Model.Defaults(width, height), applied = { leases = {}, points = {}, contracts = {} } }
        self.db.profiles[key] = entry
    end
    if not G.Store.ValidEntry(entry) then
        self.blocked = "当前配置损坏，已保留原数据并停止接管"
        self:Notify(self.blocked)
        return false
    end
    entry.applied.leases, entry.applied.points = entry.applied.leases or {}, entry.applied.points or {}
    self.entry = entry
    self.journal = G.Journal.New(entry.applied.leases)
    -- Hydrate restoration references after reload before any new writes occur.
    for id in pairs(entry.applied.leases) do self.journal.live[id] = self:LeaseRef(id) end
    self.revision = self.revision + 1
    G.Emit("context", self)
    return true
end

function E:Guard()
    if self.blocked then return nil, self.blocked end
    return G.Adapter.Guard()
end

function E:BeginEdit()
    if G.Runtime.InCombat() then return nil, "请脱战后编辑" end
    if not self:SyncContext() then return nil, self.blocked or self.message or "配置尚未就绪" end
    local ok, err = self:Guard()
    if not ok then self:Notify(err); return nil, err end
    if not self.editing then
        self.draft = G.Copy(self.entry.settings)
        self.editing, self.dirty = true, false
        self:Notify("调整后预览；应用保存，取消恢复。单位：游戏 UI 坐标")
    end
    return true
end

function E:Run(settings)
    local ok, err = self:Guard()
    if not ok then return nil, err end
    if G.Runtime.InCombat() then return nil, "战斗中暂停修改，等待脱战" end
    local width, height = G.Screen()
    ok, err = G.Model.Validate(settings, width, height)
    if not ok then return nil, err end
    local plans
    plans, err = G.Model.Plan(settings, G.Bindings)
    if not plans then return nil, err end
    if not self.entry then return nil, "配置尚未就绪" end
    local targets, status, frozen = {}, {}, {}
    self.suspended, self.partial = {}, false
    -- Freeze the entire native module if any of its owned fields loses its
    -- contract or ownership. Other modules may proceed only with provable bounds.
    for id in pairs(self.entry.applied.leases) do
        local binding = G.Adapter.LeaseBinding(id)
        local target, reason = G.Adapter.Resolve(binding)
        if not target and reason and (reason:find("锚定") or reason:find("联动")) then
            return nil, "已暂停关联布局：" .. reason
        end
        if not self.journal:Owns(id, self:LeaseRef(id)) then
            self.suspended[binding.module] = "接管记录不兼容或被外部修改；请检查后恢复再应用"
        elseif not target then self.suspended[binding.module] = reason end
    end
    for _, plan in ipairs(plans) do
        local target, reason = G.Adapter.Resolve(plan.binding)
        if self.suspended[plan.binding.module] then target, reason = nil, self.suspended[plan.binding.module] end
        status[plan.binding.id] = reason or "可接管"
        if target then
            target.plan = plan
            local points, pointError = G.Adapter.Points(target.frame)
            if points then
                target.beforePoints = points
                targets[#targets + 1] = target
            else status[plan.binding.id] = pointError; self.partial = true end
        else
            self.partial = true
            if self.entry.applied.leases[plan.binding.id .. "/position"] then
                local boundary = G.Adapter.FrozenBounds(plan.binding)
                if not boundary then
                    self.status = status
                    return nil, "已暂停关联布局：无法确认旧接管组的边界；配置及恢复记录已保留"
                end
                frozen[#frozen + 1] = boundary
            end
        end
    end
    self.status = status
    if #targets == 0 then return nil, "没有可安全接管的目标，请查看覆盖状态" end
    self.busy = true
    self.journal:Begin()
    local savedPoints = G.Copy(self.entry.applied.points)
    local success, failure = pcall(function()
        for _, t in ipairs(targets) do
            if not self.entry.applied.points[t.binding.id] then self.entry.applied.points[t.binding.id] = G.Copy(t.beforePoints) end
            for field, value in pairs(G.Adapter.Fields(t, t.plan)) do
                local written, reason = self.journal:Write(t.binding.id .. "/" .. field, t.config, field, value)
                if not written then error(reason, 0) end
            end
            G.Adapter.Refresh(t)
            t.extent = G.Adapter.Extent(t)
        end
        local laneHeights = {}
        for _, t in ipairs(targets) do
            local r = t.binding.region
            laneHeights[r] = math.max(laneHeights[r] or 0, t.extent.height)
        end
        for _, t in ipairs(targets) do
            local pos, reason = G.Model.Position(t.binding, settings, t.extent, laneHeights[t.binding.region])
            if not pos then error(t.binding.label .. "：" .. tostring(reason), 0) end
            t.position = pos
        end
        local bounds = {}
        for _, t in ipairs(targets) do bounds[#bounds + 1] = t end
        for _, t in ipairs(frozen) do bounds[#bounds + 1] = t end
        local fits, overlap = G.Model.CheckOverlap(bounds)
        if not fits then error(overlap, 0) end
        for _, t in ipairs(targets) do
            local pos = t.position
            local written, writeError = self.journal:Write(t.binding.id .. "/position", t.positions, t.binding.key, pos)
            if not written then error(writeError, 0) end
            G.Adapter.Place(t, pos)
            G.Adapter.Watch(t)
            status[t.binding.id] = "已绑定：图标 " .. t.binding.icon .. " / 文字 " .. t.binding.text
        end
    end)
    if not success then
        self.journal:Rollback()
        self.entry.applied.points = savedPoints
        local recoveryErrors = 0
        for _, t in ipairs(targets) do
            if not pcall(G.Adapter.Refresh, t) then recoveryErrors = recoveryErrors + 1 end
            if not pcall(G.Adapter.RestorePoints, t.frame, t.beforePoints) then recoveryErrors = recoveryErrors + 1 end
        end
        self.busy = false
        if recoveryErrors > 0 then return nil, "数值已回退，但布局重绘失败，请 /reload 并报告错误：" .. tostring(failure) end
        return nil, "未应用，已回退：" .. tostring(failure)
    end
    self.journal:Commit()
    for _, t in ipairs(targets) do
        self.entry.applied.contracts[t.binding.module] = G.Adapter.Stamp(t.binding.module)
    end
    self.targets, self.busy = targets, false
    return true
end

function E:Change(category, tier, axis, value)
    if not self.editing then return end
    if category == "regions" then self.draft.regions[tier][axis] = value else self.draft[category][tier] = value end
    self.dirty, self.error = true, nil
    self:Schedule("编辑预览")
end

function E:Schedule(reason)
    if self.busy or self.blocked or not self.db then return end
    self.reason = reason
    if self.scheduled then return end
    self.scheduled = true
    G.Runtime.After(0, function()
        self.scheduled = false
        if G.Runtime.InCombat() then self:Notify("战斗中暂停，脱战后处理最新设置"); return end
        if not self:SyncContext() then return end
        if self.contextRestores then
            self.busy = true
            for _, restore in ipairs(self.contextRestores) do
                pcall(G.Adapter.Refresh, restore.target)
                pcall(G.Adapter.RestorePoints, restore.target.frame, restore.points)
            end
            self.busy, self.contextRestores = false, nil
        end
        if self.pending then
            local pending = self.pending; self.pending = nil
            if pending.context == self.context then
                if pending.kind == "restore" then self:Restore() else self:Cancel() end
            end
            return
        end
        local settings = self.editing and self.dirty and self.draft or (self.entry.enabled and self.entry.settings)
        if settings then
            local ok, err = self:Run(settings)
            self.error = not ok and err or nil
            self:Notify(err or (self.partial and "部分组件已应用；其余暂停，请查看下方状态")
                or (self.editing and self.dirty and "预览中；尚未保存" or "已保存配置生效"))
        else
            -- A /reload during an uncommitted first preview must restore the host.
            if next(self.entry.applied.leases) then self:Restore() end
        end
        if G.Bridge then G.Bridge:RefreshSlots() end
    end)
end

function E:Apply()
    if not self.editing then return end
    if self.context ~= G.Adapter.Context() then self:Schedule("配置已切换"); return nil, "配置已切换，请重新打开编辑器" end
    if G.Runtime.InCombat() then self:Notify("请脱战后点击应用；草稿已保留"); return end
    local ok, err = self:Run(self.draft)
    if not ok then self.error = err; self:Notify(err); return nil, err end
    self.entry.settings = G.Copy(self.draft)
    self.entry.enabled = true
    self.dirty, self.error = false, nil
    self:Notify(self.partial and "档位已保存；部分组件暂停，见下方状态" or "已保存并应用")
    if G.Bridge then G.Bridge:RefreshSlots() end
    return true
end

function E:Restore()
    if not self.entry then return nil, self.blocked or "没有可恢复的当前配置" end
    if G.Runtime.InCombat() then
        self.pending = { kind = "restore", context = self.context }
        self:Notify("恢复操作等待脱战")
        return
    end
    local ok, err = self:Guard()
    if not ok then self:Notify(err); return nil, err end
    if self.context ~= G.Adapter.Context() then self:Schedule("配置已切换"); return nil, "配置已切换" end
    self.busy = true
    local safePositions, touched = {}, {}
    for _, b in ipairs(G.Bindings) do
        local id = b.id .. "/position"
        safePositions[b.id] = self.journal:Owns(id, self:LeaseRef(id)) and G.Adapter.Resolve(b) ~= nil
    end
    for id in pairs(self.entry.applied.leases) do
        local b = G.Adapter.LeaseBinding(id)
        if b and self.journal:Owns(id, self:LeaseRef(id)) then touched[b.id] = true end
    end
    local conflicts, unresolved = self.journal:Restore(function(id) return self:LeaseRef(id) end)
    local refreshErrors = 0
    for _, b in ipairs(G.Bindings) do
        local t = G.Adapter.Resolve(b, true)
        if t and t.frame and touched[b.id] then
            if not pcall(G.Adapter.Refresh, t) then refreshErrors = refreshErrors + 1 end
            if safePositions[b.id] and not pcall(G.Adapter.RestorePoints, t.frame, self.entry.applied.points[b.id]) then refreshErrors = refreshErrors + 1 end
        end
    end
    self.entry.enabled = false
    if #unresolved == 0 then self.entry.applied.points = {} end
    self.targets, self.status, self.busy, self.dirty, self.error, self.suspended = {}, {}, false, false, nil, {}
    self.draft = self.editing and G.Copy(self.entry.settings) or nil
    local message = (#conflicts + #unresolved) > 0 and ("已退出接管；保留 " .. #conflicts .. " 项外部改动，" .. #unresolved .. " 项等待模块就绪后恢复") or "已恢复接管前设置"
    if refreshErrors > 0 then message = message .. "；布局重绘失败，请 /reload 并报告错误" end
    self:Notify(message)
    if G.Bridge then G.Bridge:RefreshSlots() end
    return true
end

function E:Cancel()
    if not self.entry or not self.editing then G.Emit("closed"); return true end
    if G.Runtime.InCombat() then
        self.pending = { kind = "cancel", context = self.context }
        self:Notify("取消预览等待脱战")
        return
    end
    local warning
    if self.entry.enabled then
        local ok, err = self:Run(self.entry.settings)
        if not ok or next(self.suspended) then
            -- Do not leave a hidden draft active or keep reasserting after a conflict.
            -- Saved tier values remain available for an explicit re-apply.
            self:Restore()
            self.entry.enabled = false
            warning = "预览已关闭，接管已暂停；" .. tostring(err or "部分组件存在外部冲突") .. "。已保留档位设置及外部改动，请检查后重新应用。"
        end
    else
        local restored, err = self:Restore()
        if not restored then warning = "预览已关闭，恢复尚未完成：" .. tostring(err) end
    end
    self.editing, self.dirty, self.draft, self.error = false, false, nil, nil
    self:Notify(warning or "已取消未保存的更改")
    if warning then G.Message(warning) end
    G.Emit("closed")
    return true
end

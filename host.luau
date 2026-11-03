-- Interactive-plan view. CodexBWAI, COMMANDER-993, MIT.
-- Identity is the explicitly selected source + immutable plan_id, never another pane number.
local view = require("./lib/plan_view")
local KIND = tern.plugin.id .. ".list"
local instances = {}
local POLL_MS = 1500

local function sourceValid(source)
    return type(source) == "table" and type(source.path) == "string" and source.path ~= ""
        and (source.ssh == nil or (type(source.ssh) == "string" and source.ssh ~= ""))
end
local function live(state)
    if instances[state.panel] ~= state then return false end
    for _, pane in tern.pane.list() do
        if pane.pane == state.panel then return pane.program == KIND end
    end
    instances[state.panel] = nil
    return false
end
local function redraw(state, cx)
    if live(state) then pcall(function() cx:render() end) end
end
local function refresh(state, cx)
    if not live(state) or not state.source or state.reading then return end
    state.reading = true
    local helper = tern.plugin.dir .. "/bin/estate_session_list.py"
    local argv = {"python3", "-I", helper, "source", "--plan", state.source.path}
    if tern.runtime.os == "windows" then argv = {"py", "-3", "-I", helper, "source", "--plan", state.source.path} end
    if state.source.ssh then table.insert(argv, "--ssh"); table.insert(argv, state.source.ssh) end
    local ok = pcall(function()
        tern.process.run(argv, {timeout_ms = 6000}, function(result)
            if not live(state) then return end
            state.reading = false
            local decoded, envelope = pcall(tern.json.decode, result.stdout or "")
            local plan = if decoded and type(envelope) == "table" then envelope.plan else nil
            if result.status ~= 0 or not decoded or envelope.ok ~= true or type(plan) ~= "table" then
                state.plan = nil
                state.error = if decoded and type(envelope) == "table" and type(envelope.error) == "string" then envelope.error else "Could not read the selected source. Check its location, access and Python 3."
            elseif type(plan.plan_id) ~= "string" or type(plan.checkpoints) ~= "table" or type(plan.title) ~= "string" then
                state.plan = nil; state.error = "Source returned an invalid checkpoint report."
            elseif state.plan_id ~= nil and state.plan_id ~= plan.plan_id then
                state.plan = nil; state.error = "This file now belongs to a different plan. Close this panel and explicitly attach the intended plan."
            else
                local firstBinding = state.plan_id == nil
                state.plan_id = plan.plan_id
                state.plan = plan
                state.error = nil
                state.updated = os.date("!%Y-%m-%d %H:%M:%S UTC")
                if firstBinding then pcall(function() cx:save() end) end
            end
            redraw(state, cx)
            tern.timer(POLL_MS, function() refresh(state, cx) end)
        end)
    end)
    if not ok then
        state.reading = false; state.plan = nil
        state.error = "Could not start the read-only source reader. Tern 0.9.10+ and Python 3 are required."
        redraw(state, cx)
        tern.timer(POLL_MS, function() refresh(state, cx) end)
    end
end

tern.block.define("list", {
    init = function(cx, args, saved)
        local state = {panel = cx.pane}
        -- A saved binding can only read the same selected source and stable plan id.
        -- Legacy bare-pane saves/args are deliberately not migrated or followed.
        if type(saved) == "table" and saved.schema == 2 and sourceValid(saved.source) and type(saved.plan_id) == "string" then
            state.source = saved.source; state.plan_id = saved.plan_id
        elseif saved == nil and args and type(args[1]) == "string" then
            local ok, source = pcall(tern.json.decode, args[1])
            if ok and sourceValid(source) then state.source = source end
        end
        if not state.source then state.error = "No plan is attached. Close this panel and use Interactive plan: attach to this tab." end
        instances[cx.pane] = state
        tern.timer(1, function() refresh(state, cx) end)
        return state
    end,
    view = function(state)
        local source = if state.source then (if state.source.ssh then "SSH " .. state.source.ssh .. ": " else "Local: ") .. state.source.path else ""
        return view.draw(tern.ui, state.plan, source, state.error, state.updated)
    end,
    title = function(state) return if state.plan then state.plan.title else "Interactive plan" end,
    save = function(state)
        if state.source and state.plan_id then return {schema = 2, source = state.source, plan_id = state.plan_id} end
        return {schema = 2}
    end,
    -- No checkpoint editing, canonical writes, prompt sending or work adoption.
})

-- Estate window projection. CodexBWAI, COMMANDER-993, MIT.
-- Only opens a native block; never calls agents:ask or sends any prompt.
local function show(cx, pane)
    local existing = tern.kv.get("estate-panel:" .. tostring(pane))
    if type(existing) == "number" and cx.session:pane(existing) ~= nil then return existing end
    local info = cx.session:pane(pane)
    if info and info.block == tern.plugin.id .. ".list" then return pane end
    return cx:new_block(tern.plugin.id .. ".list", {tostring(pane)}, "beside",
        {target = pane, dir = "right", ratio = 0.25, focus = false})
end
local function tick(cx)
    if cx then
        for _, info in cx.session:panes() do
            local key = "estate-open:" .. tostring(info.pane)
            if tern.kv.get(key) ~= nil then
                local ok = pcall(show, cx, info.pane)
                if ok then tern.kv.set(key, nil) end
            end
        end
    end
    tern.timer(500, tick)
end
tern.timer(500, tick)
tern.command({id = "show", title = "Session view: show for this tab", icon = "list", run = function(cx)
    local pane = cx.session:focused()
    if pane ~= nil then show(cx, pane) end
end})

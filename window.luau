-- English-first local/SSH source selection. Native Tern only. CodexBWAI; MIT.
local KIND = tern.plugin.id .. ".list"
local function existingInTab(cx, target)
    local owner = cx.session:pane(target)
    if not owner then return true end
    for _, pane in cx.session:panes() do
        if pane.tab == owner.tab and pane.block == KIND then return true end
    end
    return false
end
local function openSource(cx, target, source)
    if existingInTab(cx, target) then
        cx:toast("info", "This tab already has a plan view. Close it before attaching another plan.")
        return
    end
    cx:new_block(KIND, {tern.json.encode(source)}, "beside", {target = target, dir = "right", ratio = 0.3, focus = false})
end
local function sameContext(cx, target, tab, host)
    local info = cx.session:pane(target)
    local current = cx.hosts:current()
    return info ~= nil and info.tab == tab and current.id == host and current.state == "connected"
end
local function pathPrompt(cx, target, ssh, tab, host)
    cx:prompt({placeholder = "Absolute plan path on the agent's machine"}):next(function(path, err, fresh)
        if not fresh or not path or path == "" then return end
        if not sameContext(fresh, target, tab, host) then
            fresh:toast("error", "The host or tab changed. Attach the plan again in the intended session.")
            return
        end
        openSource(fresh, target, {path = path, ssh = ssh})
    end)
end
tern.command({id = "show", title = "Interactive plan: attach to this tab", icon = "list", run = function(cx)
    local target = cx.session:focused()
    if not target then return end
    local tab = cx.session:pane(target).tab
    local host = cx.hosts:current().id
    if existingInTab(cx, target) then cx:toast("info", "This tab already has a plan view."); return end
    cx:pick({placeholder = "Where does the agent keep its plan?", items = {
        {label = "Local", detail = "On this Tern session host", mode = "local"},
        {label = "SSH", detail = "On an explicitly approved SSH destination", mode = "ssh"},
    }}):next(function(choice, err, fresh)
        if not fresh or not choice or not sameContext(fresh, target, tab, host) then return end
        if choice.mode == "local" then pathPrompt(fresh, target, nil, tab, host)
        else
            fresh:prompt({placeholder = "Reviewed ordinary SSH alias or user@host (not a forced agent launcher)"}):next(function(destination, err2, latest)
                if latest and destination and destination ~= "" and sameContext(latest, target, tab, host) then pathPrompt(latest, target, destination, tab, host) end
            end)
        end
    end)
end})

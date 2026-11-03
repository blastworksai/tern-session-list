-- English-first native checklist, derived from Felipe Carneiro's MIT session-list renderer.
-- Interactive plans only. CodexBWAI, COMMANDER-993.
local view = {}
function view.draw(ui, plan, source, errorText, updated)
    if errorText then
        return {main = ui.node("checklist", {mode = "full", phases = {{id = "error", items = {{id = "error", text = "Plan unavailable", status = "blocked", note = errorText}}}}})}
    end
    if not plan then
        return {main = ui.text({ui.span("Reading the selected interactive plan…", "muted")})}
    end
    local items, done, active = {}, 0, false
    for _, cp in plan.checkpoints do
        table.insert(items, {id = cp.id, text = if plan.current == cp.id then "Current · " .. cp.text else cp.text,
            status = cp.state, note = cp.reason})
        if cp.state == "done" then done += 1 end
        if cp.state == "active" then active = true end
    end
    return {main = ui.col({
        ui.node("tool", {name = "todo", title = plan.title, target = tostring(done) .. "/" .. tostring(#items),
            targetKind = "text", frame = "card", collapsible = true, collapsed = false,
            preview = "none", status = if active then "running" else if done == #items then "done" else "pending"}, {
            ui.node("checklist", {mode = "full", phases = {{id = "checkpoints", items = items}}}),
        }),
        ui.text({ui.span(source, "muted")}),
        ui.text({ui.span("Read-only plan view · Last read " .. tostring(updated), "muted")}),
    })}
end
return view

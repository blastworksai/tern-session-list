-- Estate projection host. CodexBWAI, COMMANDER-993, MIT.
-- Reuses Felipe Carneiro's native checklist renderer; canonical state is read-only.
local vista = require("./lib/vista")
local textos = require("./lib/textos")
local D = tern.plugin.data
local epoch = string.format("host-%d-%d-%d", os.time(), math.floor(tern.now()), math.random(1, 999999999))
local epochs = {}
local generation = 0
local blocks = {}
local signatures = {}
local opened = {}
local status = { pending = "aberto", active = "fazendo", done = "feito", blocked = "travado" }

-- No old numeric pane can inherit a snapshot from a different host load.
local function snapshot(pane)
    local path = D .. "/views/" .. tostring(pane) .. ".json"
    local ok, result = pcall(function()
        if not tern.fs.exists(path) then return nil end
        return tern.json.decode(tern.fs.read(path, 1024 * 1024))
    end)
    if not ok or type(result) ~= "table" or result.epoch ~= epochs[pane] or result.pane ~= pane then
        return nil
    end
    if type(result.work_id) ~= "string" or type(result.items) ~= "table" then return nil end
    return result
end

local function viewModel(s)
    local items = {}
    for _, item in s.items do
        if type(item.text) == "string" and status[item.state] then
            table.insert(items, {id = item.id, texto = item.text, estado = status[item.state], motivo = item.note})
        end
    end
    if s.error then
        items = {{id = "source-error", texto = "Source unavailable", estado = "travado", motivo = tostring(s.error)}}
    end
    return {id = s.work_id, assunto = s.work_id .. " · " .. tostring(s.title or "Source error"), itens = items}
end

tern.on("spawn", function(spec)
    local pane = tonumber(spec.env.TERN_PANE)
    if pane == nil then return nil end
    generation += 1
    epochs[pane] = epoch .. "-" .. tostring(generation)
    spec.env.SESSION_LIST_DATA = D
    spec.env.SESSION_LIST_EPOCH = epochs[pane]
    return spec
end)

tern.block.define("list", {
    init = function(cx, args, saved)
        local pane = tonumber(args and args[1]) or (type(saved) == "table" and tonumber(saved.pane)) or cx.pane
        tern.kv.set("estate-panel:" .. tostring(pane), cx.pane)
        blocks[pane] = blocks[pane] or {}
        table.insert(blocks[pane], cx)
        return {pane = pane}
    end,
    view = function(state, cx)
        local s = snapshot(state.pane)
        if s == nil then
            return {main = tern.ui.text({tern.ui.span("No current binding. Bind this pane's assigned PLAN/FORGE work.", "muted")})}
        end
        return vista.desenha({lista = viewModel(s), orfas = {}, ilegiveis = {}, readonly = true,
            source = (s.plan or table.concat(s.forge or {}, ", ")) .. " · Read " .. tostring(s.updated_at) .. " · Snapshot; refresh from source"},
            tern.ui, textos.textos("en"))
    end,
    title = function(state)
        local s = snapshot(state.pane)
        return if s then s.work_id else "Session view"
    end,
    save = function(state) return {pane = state.pane} end,
    -- Deliberately no mutation key/event handler or orphan adoption action.
})

local function tick()
    for _, info in tern.pane.list() do
        local s = snapshot(info.pane)
        if s then
            local signature = tern.json.encode(s)
            if signatures[info.pane] ~= signature then
                signatures[info.pane] = signature
                for _, cx in blocks[info.pane] or {} do pcall(function() cx:render() end) end
            end
            if opened[info.pane] ~= s.work_id then
                tern.kv.set("estate-open:" .. tostring(info.pane), s.work_id)
                opened[info.pane] = s.work_id
            end
        end
    end
    tern.timer(500, tick)
end
tern.timer(500, tick)

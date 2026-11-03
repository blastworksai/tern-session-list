-- The block's drawing: this pane's list beside the tab, with the lists closed
-- tabs left offered on top. Pure: no `tern` global; `ui` has the functions of
-- tern.ui (the host passes tern.ui, tests pass a fake), `t` is a textos table.
--
--   vista.desenha(estado, ui, t) -> { main = node, dock = node?, layer = node? }
--   estado = { lista = Lista?, orfas = {Lista}, ilegiveis = {string}, sel = number?,
--              brilho = boolean? }
--   brilho = true while the "part done" ring shows (lib/brilho.luau decides
--   when; the host clears it after brilho.DURACAO_MS): drawn in the layer
--   region as sl-brilho > sl-brilho-bloom > sl-brilho-band + sl-brilho-ring,
--   the same structure as Tern's .tn-glow (styles.css animates it).
--   vista.selecao(sel, n) -> number?   the selected item index, clamped to 1..n
--   vista.assinatura(lista) -> string   everything the block draws of a list
--                                       (id, subject, each item's id, estado,
--                                       motivo, texto); equal = same drawing
--
-- NATIVE NODES (measured live 2026-11-02, Tern 0.9.8, isolated Tern): Tern draws
-- a `tool` node as a card (head: the todo icon for name = "todo", title, target)
-- and a `checklist` node as rows with the state icon (done = green check,
-- active = ring with a dot, blocked = warning triangle with the note under it,
-- pending = empty ring), done text struck through. A phase with no title draws
-- no phase header, so one untitled phase = the list itself. A checklist with no
-- phases draws nothing. Checklist items do NOT emit clicks (an `actions` prop on
-- an item never fires); a click on a phase header only folds it, client side.
-- So the list is driven by keys (host `key`), and an `el` button with
-- `actions = {click = "<act>=<value>"}` is the only clickable thing here.
--
-- STATUS MAP (item estado -> checklist status)
--   aberto -> pending · fazendo -> active · feito -> done · travado -> blocked
--   (note = the reason)
--
-- ROLES (data-role on the tool card; styles.css keys on them)
--   sl.lista          this pane's list, nothing selected
--   sl.lista.sel.<n>  this pane's list with item n selected (styles.css paints
--                     the selected row while the block has focus)
--   sl.orfa           a list a closed tab left
--
-- CSS CLASSES (only the custom bits; everything else is Tern's own)
--   sl-botoes                    the row holding an orphan's two buttons
--   sl-botao + sl-continuar      "Continue here" (action adopt=<listId>)
--   sl-botao + sl-descartar      "Discard" (action discard=<listId>)
--
-- ACTIONS (UiEvent: a name with `=` arrives split into act and value)
--   adopt=<listId>    sl-continuar
--   discard=<listId>  sl-descartar

local vista = {}

local PROP_ACAO = "actions"
local MAX_ITENS_DA_ORFA = 5

vista.PROP_ACAO = PROP_ACAO
vista.MAX_ITENS_DA_ORFA = MAX_ITENS_DA_ORFA

local STATUS = { aberto = "pending", fazendo = "active", feito = "done", travado = "blocked" }
vista.STATUS = STATUS

function vista.selecao(sel: number?, n: number): number?
	if n <= 0 then
		return nil
	end
	local s = math.floor(tonumber(sel) or 1)
	if s < 1 then
		return 1
	end
	if s > n then
		return n
	end
	return s
end

function vista.assinatura(lista): string
	local partes = { string.format("%q", tostring(lista.id)), string.format("%q", tostring(lista.assunto)) }
	for _, i in lista.itens do
		for _, x in { i.id, i.estado, i.motivo or "", i.texto } do
			table.insert(partes, string.format("%q", tostring(x)))
		end
	end
	return table.concat(partes, "|")
end

local function itemDoChecklist(i)
	local x = { id = i.id, text = i.texto, status = STATUS[i.estado] or "pending" }
	if i.estado == "travado" and i.motivo ~= nil and i.motivo ~= "" then
		x.note = i.motivo
	end
	return x
end

local function contagem(itens): string
	local feitos = 0
	for _, i in itens do
		if i.estado == "feito" then
			feitos += 1
		end
	end
	return `{feitos}/{#itens}`
end

local function cartao(ui, props, itens, depois)
	props.name = "todo"
	props.targetKind = "text"
	props.frame = "card"
	props.collapsible = true
	props.collapsed = false
	props.preview = "none"
	local filhos = {
		ui.node("checklist", { mode = "full", phases = { { id = "p0", items = itens } } }),
	}
	for _, x in depois or {} do
		table.insert(filhos, x)
	end
	return ui.node("tool", props, filhos)
end

local function botao(ui, tipo, texto, acao)
	return ui.el("button", { class = "sl-botao " .. tipo, text = texto, [PROP_ACAO] = { click = acao } })
end

local function orfa(ui, t, lista)
	local pendentes = {}
	for _, i in lista.itens do
		if i.estado ~= "feito" then
			table.insert(pendentes, i)
		end
	end
	local itens = {}
	for n = 1, math.min(#pendentes, MAX_ITENS_DA_ORFA) do
		table.insert(itens, itemDoChecklist(pendentes[n]))
	end
	local depois = {}
	local resto = #pendentes - MAX_ITENS_DA_ORFA
	if resto > 0 then
		table.insert(depois, ui.text({ ui.span(t.eMais(resto), "muted") }))
	end
	table.insert(depois, ui.el("div", { class = "sl-botoes" }, {
		botao(ui, "sl-continuar", t.continuarAqui, "adopt=" .. lista.id),
		botao(ui, "sl-descartar", t.descartar, "discard=" .. lista.id),
	}))
	return cartao(ui, {
		role = "sl.orfa",
		-- no target: the long title would cut it, and the rows already show
		-- what is still open
		title = t.ficouDeAbaFechada(lista.assunto),
		status = "pending",
	}, itens, depois)
end

local function minha(ui, t, lista, sel, readonly)
	local itens = if lista then lista.itens else {}
	if #itens == 0 then
		return ui.text({ ui.span(t.nadaCombinado, "muted") })
	end
	local fazendo = false
	local linhas = {}
	for _, i in itens do
		if i.estado == "fazendo" then
			fazendo = true
		end
		table.insert(linhas, itemDoChecklist(i))
	end
	local assunto = lista.assunto
	if assunto == nil or assunto == "" then
		assunto = t.tituloPainel
	end
	local s = vista.selecao(sel, #itens)
	return cartao(ui, {
		role = if s then `sl.lista.sel.{s}` else "sl.lista",
		title = assunto,
		target = contagem(itens),
		-- an item in progress = the work is running (Tern's live bar)
		status = if fazendo then "running" else if readonly and contagem(itens) ~= `{#itens}/{#itens}` then "pending" else "done",
	}, linhas)
end

-- The key hint under the list. Each key stays glued to its word (no-break
-- space) so a narrow block wraps between pairs, never inside one. Every word
-- comes from textos (selecionar, feito, fazendo, tirar).
local NBSP = "\u{00A0}"
local function dica(ui, t)
	local partes = {}
	local function par(tecla, palavra)
		if #partes > 0 then
			table.insert(partes, "  ")
		end
		table.insert(partes, ui.span(tecla, "key"))
		table.insert(partes, ui.span(NBSP .. palavra, "muted"))
	end
	par("↑↓", t.selecionar)
	par("space", t.feito)
	par("d", t.fazendo)
	par("x", t.tirar)
	return ui.text(partes)
end

-- The "part done" ring, Tern's .tn-glow structure (bloom holds the blurred band).
local function anel(ui)
	return ui.el("div", { class = "sl-brilho" }, {
		ui.el("div", { class = "sl-brilho-bloom" }, { ui.el("div", { class = "sl-brilho-band" }) }),
		ui.el("div", { class = "sl-brilho-ring" }),
	})
end

function vista.desenha(estado, ui, t)
	local filhos = {}
	for _, o in estado.orfas or {} do
		table.insert(filhos, orfa(ui, t, o))
	end
	table.insert(filhos, minha(ui, t, estado.lista, estado.sel, estado.readonly))
	if estado.readonly then
		table.insert(filhos, ui.text({ui.span(estado.source or "Read-only canonical view", "muted")}))
	end
	for _, arquivo in estado.ilegiveis or {} do
		table.insert(filhos, ui.text({ ui.span(t.ilegivel(arquivo), "warn") }))
	end
	local temItens = estado.lista ~= nil and #estado.lista.itens > 0
	return {
		main = ui.col(filhos),
		dock = if temItens and not estado.readonly then ui.col({ dica(ui, t) }) else nil,
		layer = if estado.brilho then ui.col({ anel(ui) }) else nil,
	}
end

return vista

-- Tests for lib/vista.luau: a fake `ui` records the nodes; the tests walk the
-- tree by node kind / role / class and check the native tool + checklist props.

local vista = require("../lib/vista")
local T = require("../lib/textos")

local ACT = vista.PROP_ACAO

-- The action name a click on node `n` sends (nil when it sends none).
local function acao(n)
	local a = n.p[ACT]
	return a and a.click
end

local fakeUi = {
	el = function(tag, props, filhos)
		return { k = "el", tag = tag, p = props or {}, c = filhos or {} }
	end,
	col = function(filhos)
		return { k = "col", p = {}, c = filhos }
	end,
	row = function(filhos)
		return { k = "row", p = {}, c = filhos }
	end,
	text = function(s)
		return { k = "text", p = { t = s }, c = {} }
	end,
	span = function(s, st)
		return { t = s, s = st }
	end,
	rule = function(l)
		return { k = "rule", p = { label = l }, c = {} }
	end,
	node = function(k, p, c)
		return { k = k, p = p or {}, c = c or {} }
	end,
}

local function temClasse(n, c)
	local cl = n.p and n.p.class
	if type(cl) ~= "string" then
		return false
	end
	for w in string.gmatch(cl, "%S+") do
		if w == c then
			return true
		end
	end
	return false
end

-- Every node with class `c`, depth-first in drawing order.
local function acha(raiz, c, out)
	out = out or {}
	if temClasse(raiz, c) then
		table.insert(out, raiz)
	end
	for _, f in raiz.c or {} do
		acha(f, c, out)
	end
	return out
end

-- Every node of kind `k`, depth-first in drawing order.
local function kind(raiz, k, out)
	out = out or {}
	if raiz.k == k then
		table.insert(out, raiz)
	end
	for _, f in raiz.c or {} do
		kind(f, k, out)
	end
	return out
end

-- Every span text under a node, joined.
local function spans(n)
	local out = {}
	local function walk(x)
		if x.k == "text" then
			for _, sp in x.p.t do
				table.insert(out, if type(sp) == "table" then sp.t else sp)
			end
		end
		for _, f in x.c or {} do
			walk(f)
		end
	end
	walk(n)
	return table.concat(out, "")
end

local function eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end

local function item(id, txt, estado, motivo)
	return { id = id, texto = txt, estado = estado, motivo = motivo }
end

local function lista(itens, assunto, id)
	return { id = id or "l_abcd1234", assunto = assunto or "", itens = itens }
end

local function desenha(estado, idioma)
	local v = vista.desenha(estado, fakeUi, T.textos(idioma or "en"))
	assert(v.main and v.main.k == "col", "main is a col")
	return v.main, v.dock, v.layer
end

-- The checklist items of a tool card (its one phase).
local function linhas(tool)
	local ck = kind(tool, "checklist")[1]
	assert(ck, "card has a checklist")
	eq(ck.p.mode, "full", "mode")
	eq(#ck.p.phases, 1, "one phase")
	eq(ck.p.phases[1].title, nil, "untitled phase (no header row)")
	return ck.p.phases[1].items
end

local function cartoes(raiz, role)
	local out = {}
	for _, n in kind(raiz, "tool") do
		if role == nil or string.sub(n.p.role, 1, #role) == role then
			table.insert(out, n)
		end
	end
	return out
end

return {
	{ "empty pane: Nothing agreed yet, no card, no key hint", function()
		local r, dock = desenha({ lista = nil, orfas = {}, ilegiveis = {} })
		eq(spans(r), "Nothing agreed yet.")
		eq(#kind(r, "tool"), 0, "no card")
		eq(dock, nil, "no dock")
		local r2 = desenha({ lista = lista({}), orfas = {}, ilegiveis = {} })
		eq(spans(r2), "Nothing agreed yet.")
	end },

	{ "own list: native todo card, done/total, status map, order", function()
		local r, dock = desenha({ lista = lista({
			item("i1", "a", "feito"), item("i2", "b", "fazendo"),
			item("i3", "c", "travado", "Juan"), item("i4", "d", "aberto"),
		}, "Work"), orfas = {}, ilegiveis = {} })
		local c = cartoes(r, "sl.lista")
		eq(#c, 1, "one card")
		local p = c[1].p
		eq(p.name, "todo"); eq(p.title, "Work"); eq(p.target, "1/4"); eq(p.targetKind, "text"); eq(p.frame, "card")
		eq(p.status, "running", "an item in progress -> running")
		local it = linhas(c[1])
		eq(#it, 4)
		eq(it[1].id, "i1"); eq(it[1].text, "a"); eq(it[1].status, "done")
		eq(it[2].status, "active")
		eq(it[3].status, "blocked"); eq(it[3].note, "Juan")
		eq(it[4].status, "pending"); eq(it[4].note, nil)
		assert(dock ~= nil, "key hint in the dock")
		local d = spans(dock)
		assert(string.find(d, "space", 1, true) and string.find(d, "done", 1, true) and string.find(d, "in progress", 1, true), "hint: " .. d)
	end },

	{ "no subject -> panel title; nothing in progress -> status done", function()
		local r = desenha({ lista = lista({ item("i1", "a", "aberto") }), orfas = {}, ilegiveis = {} })
		local p = cartoes(r, "sl.lista")[1].p
		eq(p.title, "Session list"); eq(p.status, "done"); eq(p.target, "0/1")
	end },

	{ "all done: n/n, every row done, no extra line", function()
		local r = desenha({ lista = lista({ item("i1", "a", "feito"), item("i2", "b", "feito") }), orfas = {}, ilegiveis = {} })
		local c = cartoes(r, "sl.lista")[1]
		eq(c.p.target, "2/2")
		for _, x in linhas(c) do
			eq(x.status, "done")
		end
		eq(#r.c, 1, "only the card")
	end },

	{ "selection: role carries the clamped index", function()
		local its = { item("i1", "a", "aberto"), item("i2", "b", "aberto"), item("i3", "c", "aberto") }
		eq(cartoes(desenha({ lista = lista(its), sel = 2 }), "sl.lista")[1].p.role, "sl.lista.sel.2")
		eq(cartoes(desenha({ lista = lista(its), sel = 9 }), "sl.lista")[1].p.role, "sl.lista.sel.3", "clamped high")
		eq(cartoes(desenha({ lista = lista(its) }), "sl.lista")[1].p.role, "sl.lista.sel.1", "default first")
		eq(vista.selecao(0, 3), 1); eq(vista.selecao(nil, 0), nil); eq(vista.selecao(2, 3), 2)
	end },

	{ "orphan with 7 pending items: 5 + and 2 more, both buttons, before own list", function()
		local its = {}
		for n = 1, 7 do
			table.insert(its, item("i" .. n, "t" .. n, "aberto"))
		end
		table.insert(its, item("i8", "done one", "feito"))
		local r = desenha({ lista = lista({ item("i1", "mine", "aberto") }), orfas = { lista(its, "Old", "l_orfa0001") }, ilegiveis = {} })
		local o = cartoes(r, "sl.orfa")
		eq(#o, 1, "one orphan")
		eq(o[1].p.title, "Left open by a closed tab: Old")
		eq(o[1].p.target, nil); eq(o[1].p.status, "pending")
		eq(#linhas(o[1]), 5, "5 pending rows")
		assert(string.find(spans(o[1]), "and 2 more", 1, true), "and 2 more")
		local c = acha(o[1], "sl-continuar")[1]
		local d = acha(o[1], "sl-descartar")[1]
		eq(c.tag, "button"); eq(acao(c), "adopt=l_orfa0001"); eq(c.p.text, "Continue here")
		eq(acao(d), "discard=l_orfa0001"); eq(d.p.text, "Discard")
		assert(temClasse(c, "sl-botao") and temClasse(d, "sl-botao"), "sl-botao")
		eq(r.c[1].p.role, "sl.orfa", "orphan first")
		eq(string.sub(r.c[2].p.role, 1, 8), "sl.lista", "own list after")
	end },

	{ "assinatura: changes with each drawn field, equal for the same content", function()
		local base = function()
			return lista({ item("i1", "a", "aberto"), item("i2", "b", "travado", "Juan") }, "S")
		end
		local s0 = vista.assinatura(base())
		eq(vista.assinatura(base()), s0, "same content, same signature")
		local x = base(); x.atualizada = "other"; eq(vista.assinatura(x), s0, "atualizada does not count")
		local muda = {
			function(l) l.itens[1].estado = "fazendo" end,
			function(l) l.itens[2].motivo = "Lu" end,
			function(l) l.itens[1].texto = "a2" end,
			function(l) l.assunto = "T" end,
			function(l) l.id = "l_other000" end,
			function(l) l.itens[2].id = "i9" end,
			function(l) table.remove(l.itens, 2) end,
			function(l) l.itens[1].texto = "a|b" ; l.itens[2].texto = "" end,
		}
		for n, f in muda do
			local l = base(); f(l)
			assert(vista.assinatura(l) ~= s0, "change " .. n .. " must change the signature")
		end
	end },

	{ "unreadable files listed", function()
		local r = desenha({ lista = nil, orfas = {}, ilegiveis = { "l_bad00001.json", "l_bad00002.json" } })
		local s = spans(r)
		assert(string.find(s, "unreadable list: l_bad00001.json", 1, true), s)
		assert(string.find(s, "unreadable list: l_bad00002.json", 1, true), s)
	end },

	{ "pt-BR renders", function()
		local r, dock = desenha({ lista = lista({ item("i1", "a", "feito") }), orfas = { lista({ item("i1", "x", "travado", "Lu") }, "", "l_orfa0002") }, ilegiveis = { "l_x.json" } }, "pt-BR")
		local o = cartoes(r, "sl.orfa")[1]
		eq(o.p.title, "Ficou de uma aba fechada")
		eq(linhas(o)[1].note, "Lu")
		eq(acha(r, "sl-continuar")[1].p.text, "Continuar aqui")
		eq(acha(r, "sl-descartar")[1].p.text, "Descartar")
		eq(cartoes(r, "sl.lista")[1].p.title, "Lista da sessão")
		local d = spans(dock)
		for _, w in { "selecionar", "feito", "fazendo agora", "tirar" } do
			assert(string.find(d, w, 1, true), "pt hint has " .. w .. ": " .. d)
		end
		for _, w in { "select", "done", "remove", "progress" } do
			assert(not string.find(d, w, 1, true), "pt hint has no English " .. w)
		end
		assert(string.find(spans(r), "lista ilegível: l_x.json", 1, true), "pt unreadable")
		eq(spans(desenha({ orfas = {}, ilegiveis = {} }, "pt-BR")), "Nada combinado ainda.")
	end },

	{ "glow: the ring is in the layer only while brilho is set", function()
		local l = lista({ item("i1", "a", "feito") })
		local r, _, layer = desenha({ lista = l, orfas = {}, ilegiveis = {} })
		eq(layer, nil, "no ring by default")
		eq(#acha(r, "sl-brilho"), 0, "never in main")
		local r2, _, layer2 = desenha({ lista = l, orfas = {}, ilegiveis = {}, brilho = true })
		assert(layer2 and layer2.k == "col", "layer is a col")
		eq(#acha(layer2, "sl-brilho"), 1, "one ring")
		eq(#acha(layer2, "sl-brilho-bloom"), 1, "bloom")
		eq(#acha(layer2, "sl-brilho-band"), 1, "band")
		eq(#acha(layer2, "sl-brilho-ring"), 1, "ring")
		eq(#acha(r2, "sl-brilho"), 0, "main unchanged")
	end },
	-- COMMANDER-993: read-only projection must not advertise edit keys or claim completion.
	{ "estate readonly pending card", function()
		local r, dock = desenha({lista = lista({item("i1", "canonical", "aberto")}), readonly = true, source = "PLAN.md"})
		eq(cartoes(r, "sl.lista")[1].p.status, "pending")
		eq(dock, nil)
		assert(string.find(spans(r), "PLAN.md", 1, true))
	end },

}

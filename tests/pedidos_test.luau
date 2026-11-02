-- Tests for lib/pedidos.luau: request parsing, every verb through a real
-- nucleo over an in-memory store (json_tern, fixed clock and ids), the error
-- paths, the stop-check rules, start, both languages, and the rendering drift
-- check against the Claude Code mod's descreveMinha.

local nucleo = require("../lib/nucleo")
local pedidos = require("../lib/pedidos")
local T = require("../lib/textos")
local json = require("./json_tern")

local EN = T.textos("en")
local PT = T.textos("pt-BR")

local testes = {}
local function teste(nome: string, fn: () -> ())
	table.insert(testes, { nome, fn })
end

local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(string.format("%sexpected\n%s\ngot\n%s", msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
	end
end

local function contem(s: string, parte: string, msg: string?)
	if string.find(s, parte, 1, true) == nil then
		error(string.format("%sexpected to contain %q in\n%s", msg and (msg .. ": ") or "", parte, s), 2)
	end
end

local function semConter(s: string, parte: string)
	if string.find(s, parte, 1, true) ~= nil then
		error(string.format("expected NOT to contain %q in\n%s", parte, s), 2)
	end
end

local function ambiente()
	local arquivos: { [string]: string } = {}
	local store = {
		list = function()
			local r = {}
			for k in arquivos do
				table.insert(r, k)
			end
			table.sort(r)
			return r
		end,
		read = function(nome)
			return arquivos[nome]
		end,
		write = function(nome, texto)
			arquivos[nome] = texto
		end,
		remove = function(nome)
			arquivos[nome] = nil
		end,
		move = function(nome, paraPasta)
			local base = string.match(nome, "[^/]+$")
			arquivos[paraPasta .. "/" .. base] = arquivos[nome]
			arquivos[nome] = nil
		end,
	}
	local segundo, idN = 0, 0
	local N = nucleo.novo(store, {
		json = json,
		agora = function()
			segundo += 1
			return string.format("2026-11-02T10:%02d:%02d-03:00", segundo // 60, segundo % 60)
		end,
		novoId = function()
			idN += 1
			return string.format("l_aaaa%04d", idN)
		end,
	})
	return N, arquivos
end

-- builds a request the way the command writes it
local function req(pane: number?, verb: string, args: { string }?, extra: { [string]: string }?): string
	local l = { "v=1" }
	if pane then
		table.insert(l, "pane=" .. pane)
	end
	table.insert(l, "verb=" .. verb)
	for _, a in args or {} do
		table.insert(l, "arg=" .. a)
	end
	for _, k in { "subject", "again", "noorphans", "stopinput" } do
		if extra and extra[k] then
			table.insert(l, k .. "=" .. extra[k])
		end
	end
	table.insert(l, "end=1")
	return table.concat(l, "\n") .. "\n"
end

local function roda(N, texto: string, t, opts)
	local p = pedidos.parse(texto)
	assert(p.erro == nil and p.incompleto == nil, "request did not parse")
	return pedidos.executa(p, N, t or EN, opts or { maxLembretes = 1, json = json })
end

-- parse ---------------------------------------------------------------------

teste("parse: keys, = inside values, repeated args in order, unknown keys", function()
	local p = pedidos.parse("v=1\npane=89\nverb=add\narg=a=b\narg=second\narg=x==y\nsubject=s=1\nagain=1\nnoorphans=1\nfoo=bar\nstopinput={\"a\":\"=\"}\nend=1\n")
	eq(p.v, "1")
	eq(p.pane, 89)
	eq(p.verb, "add")
	eq(#p.args, 3)
	eq(p.args[1], "a=b")
	eq(p.args[2], "second")
	eq(p.args[3], "x==y")
	eq(p.subject, "s=1")
	eq(p.again, true)
	eq(p.noorphans, true)
	eq(p.stopinput, '{"a":"="}')
	eq((p :: any).foo, nil)
end)

teste("parse: defaults and a large pane id", function()
	local p = pedidos.parse("v=1\npane=133143986179\nverb=show\nend=1\n")
	eq(p.pane, 133143986179)
	eq(#p.args, 0)
	eq(p.again, false)
	eq(p.noorphans, false)
	eq(p.subject, nil)
end)

teste("parse: wrong or missing v is an error", function()
	eq(pedidos.parse("v=2\npane=1\nverb=show\nend=1\n").erro, "versao")
	eq(pedidos.parse("pane=1\nverb=show\nend=1\n").erro, "versao")
end)

teste("parse: without the end=1 line it is incomplete", function()
	eq(pedidos.parse("v=1\npane=1\nverb=show\n").incompleto, true)
	eq(pedidos.parse("v=1\npane=1\nverb=show\nend=").incompleto, true)
	eq(pedidos.parse("").incompleto, true)
	eq(pedidos.parse("v=1\npane=1\nverb=show\nend=1").incompleto, nil)
	eq(pedidos.parse("v=1\r\npane=1\r\nverb=show\r\nend=1\r\n").pane, 1)
end)

teste("respostaArquivo: status line then the text", function()
	eq(pedidos.respostaArquivo({ status = "ok", texto = "a\nb" }), "status=ok\na\nb")
	eq(pedidos.respostaArquivo({ status = "remind", texto = "" }), "status=remind\n")
end)

-- verbs ---------------------------------------------------------------------

teste("show on an empty store: the empty list", function()
	local N = ambiente()
	local r = roda(N, req(5, "show"))
	eq(r.status, "ok")
	eq(r.texto, EN.listaVazia)
end)

teste("add: items, subject, answer is the list", function()
	local N = ambiente()
	local r = roda(N, req(5, "add", { "part 1", "part 2" }, { subject = "Workshop" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list: Workshop\n☐ i1 part 1\n☐ i2 part 2")
end)

teste("add with nothing: error nada-pra-anotar plus the list", function()
	local N = ambiente()
	local r = roda(N, req(5, "add", { " " }))
	eq(r.status, "error")
	eq(r.texto, EN.erro["nada-pra-anotar"] .. "\n\n" .. EN.listaVazia)
end)

teste("done / undo / remove with notices and Not found", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a", "b", "c" }))
	local r = roda(N, req(5, "done", { "i1", "i9" }))
	eq(r.status, "ok")
	eq(r.texto, "Not found: i9.\n\nThis tab's session list\n☐ i2 b\n☐ i3 c\n☑ i1 a (done)")
	r = roda(N, req(5, "done", { "i1" }))
	eq(r.texto, EN.jaFeito("i1") .. "\n\nThis tab's session list\n☐ i2 b\n☐ i3 c\n☑ i1 a (done)")
	r = roda(N, req(5, "undo", { "i2" }))
	contem(r.texto, EN.naoFeito("i2"))
	r = roda(N, req(5, "undo", { "i1" }))
	eq(r.texto, "This tab's session list\n☐ i1 a\n☐ i2 b\n☐ i3 c")
	r = roda(N, req(5, "remove", { "i2" }))
	eq(r.texto, "This tab's session list\n☐ i1 a\n☐ i3 c")
end)

teste("remove by the agent is not a removal by the person: add again works", function()
	local N = ambiente()
	roda(N, req(5, "add", { "x" }))
	roda(N, req(5, "remove", { "i1" }))
	local r = roda(N, req(5, "add", { "x" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list\n☐ i1 x")
end)

teste("add of a text the person removed: refused, --again re-adds", function()
	local N = ambiente()
	roda(N, req(5, "add", { "x", "y" }))
	N.tira(5, { "i1" }, { pelaPessoa = true })
	local r = roda(N, req(5, "add", { "X" }))
	eq(r.status, "error")
	eq(r.texto, EN.tiradoPelaPessoa("X") .. "\n\nThis tab's session list\n☐ i2 y")
	r = roda(N, req(5, "add", { "x", "z" }))
	eq(r.status, "ok")
	eq(r.texto, EN.tiradoPelaPessoa("x") .. "\n\nThis tab's session list\n☐ i2 y\n☐ i3 z")
	r = roda(N, req(5, "add", { "x" }, { again = "1" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list\n☐ i2 y\n☐ i3 z\n☐ i4 x")
end)

teste("name joins the args; empty subject and no list are errors", function()
	local N = ambiente()
	local r = roda(N, req(5, "name", { "Work" }))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-lista"])
	roda(N, req(5, "add", { "a" }))
	r = roda(N, req(5, "name", { "The", "big", "one" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list: The big one\n☐ i1 a")
	r = roda(N, req(5, "name", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["assunto-vazio"])
end)

teste("block / unblock: blocked after open, before done, with the reason", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a", "b", "c" }))
	roda(N, req(5, "done", { "i3" }))
	local r = roda(N, req(5, "block", { "i1", "waiting", "for", "Juan" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list\n☐ i2 b\n⊘ i1 a (blocked: waiting for Juan)\n☑ i3 c (done)")
	r = roda(N, req(5, "block", { "i1", "waiting for Juan" }))
	contem(r.texto, EN.jaTravado("i1"))
	r = roda(N, req(5, "unblock", { "i2" }))
	contem(r.texto, EN.naoTravado("i2"))
	r = roda(N, req(5, "unblock", { "i1" }))
	eq(r.texto, "This tab's session list\n☐ i1 a\n☐ i2 b\n☑ i3 c (done)")
end)

teste("doing: in progress first with ▶, one at a time, notices and errors", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a", "b", "c" }))
	roda(N, req(5, "done", { "i3" }))
	roda(N, req(5, "block", { "i1", "Juan" }))
	local r = roda(N, req(5, "doing", { "i2" }))
	eq(r.status, "ok")
	eq(r.texto, "This tab's session list\n▶ i2 b (in progress)\n⊘ i1 a (blocked: Juan)\n☑ i3 c (done)")
	r = roda(N, req(5, "doing", { "i2" }))
	eq(r.texto, EN.jaFazendo("i2") .. "\n\nThis tab's session list\n▶ i2 b (in progress)\n⊘ i1 a (blocked: Juan)\n☑ i3 c (done)")
	r = roda(N, req(5, "doing", { "i3" }))
	eq(r.texto, "This tab's session list\n▶ i3 c (in progress)\n☐ i2 b\n⊘ i1 a (blocked: Juan)")
	r = roda(N, req(5, "unblock", { "i3" }))
	contem(r.texto, EN.naoTravado("i3"))
	r = roda(N, req(5, "doing", { "i9" }))
	contem(r.texto, "Not found: i9.")
	r = roda(N, req(5, "doing", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-id"])
	r = roda(N, req(5, "check"))
	eq(r.status, "remind")
	eq(r.texto, EN.lembrete(2, { "i2 b", "i3 c" }))
	r = roda(N, req(5, "done", { "i3" }))
	eq(r.texto, "This tab's session list\n☐ i2 b\n⊘ i1 a (blocked: Juan)\n☑ i3 c (done)")
end)

teste("doing in pt-BR and without a list", function()
	local N = ambiente()
	local r = roda(N, req(5, "doing", { "i1" }), PT)
	eq(r.status, "error")
	contem(r.texto, PT.erro["sem-lista"])
	roda(N, req(5, "add", { "parte 1" }), PT)
	r = roda(N, req(5, "doing", { "i1" }), PT)
	eq(r.texto, "Lista da sessão desta aba\n▶ i1 parte 1 (fazendo agora)")
end)

teste("block without reason or id, unblock without id: errors", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	local r = roda(N, req(5, "block", { "i1" }))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-motivo"])
	r = roda(N, req(5, "block", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-id"])
	r = roda(N, req(5, "unblock", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-id"])
	r = roda(N, req(5, "done", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-id"])
end)

teste("done without a list: sem-lista error plus the empty list", function()
	local N = ambiente()
	local r = roda(N, req(5, "done", { "i1" }))
	eq(r.status, "error")
	eq(r.texto, EN.erro["sem-lista"] .. "\n\n" .. EN.listaVazia)
end)

local function deixaOrfa(N)
	roda(N, req(1, "add", { "left 1", "left 2" }, { subject = "Old" }))
	roda(N, req(1, "block", { "i2", "Juan" }))
	N.orfaniza(1)
	return N.orfas().orfas[1].id
end

teste("show lists the orphans; noorphans hides them", function()
	local N = ambiente()
	local id = deixaOrfa(N)
	roda(N, req(5, "add", { "mine" }))
	local r = roda(N, req(5, "show"))
	eq(r.texto, `This tab's session list\n☐ i1 mine\n{EN.orfasCabecalho}\n- {id} (Old): left 1; left 2`)
	r = roda(N, req(5, "show", nil, { noorphans = "1" }))
	eq(r.texto, "This tab's session list\n☐ i1 mine")
end)

teste("adopt into an empty pane, then refusals", function()
	local N = ambiente()
	local id = deixaOrfa(N)
	local r = roda(N, req(5, "adopt", { id }))
	eq(r.status, "ok")
	eq(r.texto, EN.puxei(id) .. "\n\nThis tab's session list: Old\n☐ i1 left 1\n⊘ i2 left 2 (blocked: Juan)")
	r = roda(N, req(5, "adopt", { id }))
	eq(r.status, "error")
	contem(r.texto, EN.naoPuxei("minha"))
	r = roda(N, req(6, "adopt", { id }))
	contem(r.texto, EN.naoPuxei("viva"))
	r = roda(N, req(6, "adopt", { "l_zzzz9999" }))
	contem(r.texto, EN.naoPuxei("sumiu"))
	r = roda(N, req(6, "adopt", {}))
	eq(r.status, "error")
	contem(r.texto, EN.erro["sem-id"])
end)

teste("adopt into a pane with a list appends with new ids", function()
	local N = ambiente()
	local id = deixaOrfa(N)
	roda(N, req(5, "add", { "mine" }))
	local r = roda(N, req(5, "adopt", { id }))
	eq(r.texto, EN.puxei(id) .. "\n\nThis tab's session list: Old\n☐ i1 mine\n☐ i2 left 1\n⊘ i3 left 2 (blocked: Juan)")
end)

teste("adopt / discard of an unreadable file: refused, file untouched", function()
	local N, arquivos = ambiente()
	arquivos["listas/l_ruim0001.json"] = "{not json"
	local r = roda(N, req(5, "discard", { "l_ruim0001" }))
	eq(r.status, "error")
	contem(r.texto, EN.naoDescartei("ilegivel"))
	contem(r.texto, EN.ilegivelModelo("l_ruim0001.json"))
	r = roda(N, req(5, "adopt", { "l_ruim0001" }))
	contem(r.texto, EN.naoPuxei("ilegivel"))
	eq(arquivos["listas/l_ruim0001.json"], "{not json")
end)

teste("discard moves the orphan away", function()
	local N, arquivos = ambiente()
	local id = deixaOrfa(N)
	local r = roda(N, req(5, "discard", { id }))
	eq(r.status, "ok")
	eq(r.texto, EN.descartei(id) .. "\n\n" .. EN.listaVazia)
	eq(arquivos["listas/" .. id .. ".json"], nil)
	assert(arquivos["descartadas/" .. id .. ".json"] ~= nil, "moved to descartadas/")
	r = roda(N, req(5, "discard", { id }))
	contem(r.texto, EN.naoDescartei("sumiu"))
end)

teste("unknown verb, missing verb and missing pane", function()
	local N = ambiente()
	local r = roda(N, req(5, "apaga-tudo"))
	eq(r.status, "error")
	eq(r.texto, EN.erro["verbo-invalido"])
	r = pedidos.executa(pedidos.parse("v=1\npane=5\nend=1\n"), N, EN, {})
	eq(r.texto, EN.erro["verbo-invalido"])
	r = roda(N, req(nil, "show"))
	eq(r.status, "error")
	eq(r.texto, EN.erro["sem-pane"])
	r = roda(N, "v=1\npane=abc\nverb=add\narg=x\nend=1\n")
	eq(r.texto, EN.erro["sem-pane"])
end)

teste("help answers the help screen", function()
	local N = ambiente()
	local r = roda(N, req(5, "help"))
	eq(r.status, "ok")
	eq(r.texto, EN.ajuda)
	eq(roda(N, req(nil, "help")).texto, EN.ajuda)
end)

-- check ---------------------------------------------------------------------

teste("check: remind once, then quiet until the list changes", function()
	local N = ambiente()
	eq(roda(N, req(5, "check")).status, "ok", "no list")
	roda(N, req(5, "add", { "a", "b" }))
	local r = roda(N, req(5, "check"))
	eq(r.status, "remind")
	eq(r.texto, EN.lembrete(2, { "i1 a", "i2 b" }))
	r = roda(N, req(5, "check"))
	eq(r.status, "ok")
	eq(r.texto, "")
	roda(N, req(5, "done", { "i1" }))
	r = roda(N, req(5, "check"))
	eq(r.status, "remind")
	eq(r.texto, EN.lembrete(1, { "i2 b" }))
end)

teste("check: the cap comes from opts.maxLembretes", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	local o = { maxLembretes = 2, json = json }
	eq(roda(N, req(5, "check"), EN, o).status, "remind")
	eq(roda(N, req(5, "check"), EN, o).status, "remind")
	eq(roda(N, req(5, "check"), EN, o).status, "ok")
end)

teste("check: blocked and done items are not counted", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a", "b" }))
	roda(N, req(5, "block", { "i1", "Juan" }))
	roda(N, req(5, "done", { "i2" }))
	eq(roda(N, req(5, "check")).status, "ok")
	roda(N, req(5, "add", { "c" }))
	local r = roda(N, req(5, "check"))
	eq(r.status, "remind")
	eq(r.texto, EN.lembrete(1, { "i3 c" }))
end)

teste("check: stop_hook_active never reminds and spends no reminder", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	local r = roda(N, req(5, "check", nil, { stopinput = '{"stop_hook_active":true,"last_assistant_message":"done"}' }))
	eq(r.status, "ok")
	eq(r.texto, "")
	r = roda(N, req(5, "check", nil, { stopinput = '{"stop_hook_active":false,"last_assistant_message":"done."}' }))
	eq(r.status, "remind")
end)

teste("check: a last message ending in ? waits for the person", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	local r = roda(N, req(5, "check", nil, { stopinput = '{"stop_hook_active":false,"last_assistant_message":"Shall I go on?  \\n"}' }))
	eq(r.status, "ok")
	r = roda(N, req(5, "check", nil, { stopinput = '{"stop_hook_active":false,"last_assistant_message":"Is it? No, it is done."}' }))
	eq(r.status, "remind")
end)

teste("check: stopinput with newlines escaped between tokens still decodes", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	local r = roda(N, req(5, "check", nil, { stopinput = '{\\n  "stop_hook_active": true\\n}' }))
	eq(r.status, "ok")
	eq(roda(N, req(5, "check")).status, "remind", "the reminder was not spent")
end)

-- start ---------------------------------------------------------------------
-- The rule comes first, so an agent wired only through the SessionStart hook
-- learns it without anyone editing its instructions file; then a blank line
-- and the start context (orphan questions, the open list), when there is one.

local function comRegra(t, ctx: string): string
	return t.regra .. "\n\n" .. ctx
end

teste("start: nothing → the rule alone, no trailing blank line", function()
	local N = ambiente()
	local r = roda(N, req(5, "start"))
	eq(r.status, "ok")
	eq(r.texto, EN.regra)
	eq(roda(N, req(5, "start"), PT).texto, PT.regra)
end)

teste("start: the rule, then the open list", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a", "b" }))
	roda(N, req(5, "done", { "i2" }))
	local r = roda(N, req(5, "start"))
	eq(r.texto, comRegra(EN, EN.abertoNestaAba("This tab's session list\n☐ i1 a\n☑ i2 b (done)")))
end)

teste("start: a finished list is cleared and gives the rule alone", function()
	local N = ambiente()
	roda(N, req(5, "add", { "a" }))
	roda(N, req(5, "done", { "i1" }))
	eq(roda(N, req(5, "start")).texto, EN.regra)
	eq(N.daPane(5), nil)
end)

teste("start: the rule, then orphan questions, then the list; noorphans drops them", function()
	local N = ambiente()
	local id = deixaOrfa(N)
	roda(N, req(5, "add", { "mine" }))
	local r = roda(N, req(5, "start"))
	local pergunta = EN.orfaParaModelo({ id = id, itens = { "left 1", "left 2" } })
	eq(r.texto, comRegra(EN, pergunta .. "\n\n" .. EN.abertoNestaAba("This tab's session list\n☐ i1 mine")))
	r = roda(N, req(5, "start", nil, { noorphans = "1" }))
	eq(r.texto, comRegra(EN, EN.abertoNestaAba("This tab's session list\n☐ i1 mine")))
	semConter(r.texto, id)
	r = roda(N, req(7, "start"))
	eq(r.texto, comRegra(EN, pergunta))
	eq(roda(N, req(7, "start", nil, { noorphans = "1" })).texto, EN.regra)
end)

-- languages -----------------------------------------------------------------

teste("pt-BR answers in Portuguese", function()
	local N = ambiente()
	local r = roda(N, req(5, "add", { "parte 1", "parte 2" }, { subject = "Organização" }), PT)
	eq(r.texto, "Lista da sessão desta aba: Organização\n☐ i1 parte 1\n☐ i2 parte 2")
	r = roda(N, req(5, "done", { "i1", "i9" }), PT)
	eq(r.texto, "Não achei: i9.\n\nLista da sessão desta aba: Organização\n☐ i2 parte 2\n☑ i1 parte 1 (feito)")
	r = roda(N, req(5, "block", { "i2", "o", "Juan" }), PT)
	contem(r.texto, "⊘ i2 parte 2 (travado: o Juan)")
	eq(roda(N, req(5, "apaga"), PT).texto, PT.erro["verbo-invalido"])
	roda(N, req(5, "unblock", { "i2" }), PT)
	r = roda(N, req(5, "check"), PT)
	eq(r.status, "remind")
	eq(r.texto, PT.lembrete(1, { "i2 parte 2" }))
	contem(roda(N, req(5, "start"), PT).texto, "O que ficou combinado nesta aba")
end)

teste("en and pt-BR give different, non-empty texts for the same request", function()
	for _, verb in { "show", "help", "apaga" } do
		local N = ambiente()
		local a = roda(N, req(5, verb), EN).texto
		local b = roda(N, req(5, verb), PT).texto
		assert(a ~= "" and b ~= "" and a ~= b, verb)
	end
end)

-- contract drift with the Claude Code mod ----------------------------------

teste("renderLista matches the mod's descreveMinha lines (2 open, 1 done)", function()
	-- ported from WS/src/lista-da-sessao/tests/ferramenta.test.ts ("the tool in English")
	local lista = {
		versao = 1, id = "l_aaaa0001", pane = 5, assunto = "Workshop", criada = "x", atualizada = "x",
		lembretes = 0, tirados = {},
		itens = {
			{ id = "i1", texto = "part 1", estado = "aberto" },
			{ id = "i2", texto = "part 2", estado = "aberto" },
			{ id = "i3", texto = "part 3", estado = "feito", feitoEm = "x" },
		},
	}
	eq(pedidos.renderLista(lista, {}, EN), "This tab's session list: Workshop\n☐ i1 part 1\n☐ i2 part 2\n☑ i3 part 3 (done)")
	-- the mod's own pt-BR fixture line (ferramenta.test.ts:273)
	local pt = {
		versao = 1, id = "l_aaaa0001", pane = 5, assunto = "Organização", criada = "x", atualizada = "x",
		lembretes = 0, tirados = {},
		itens = {
			{ id = "i1", texto = "Organização 2/3", estado = "feito", feitoEm = "x" },
			{ id = "i2", texto = "Organização 3/3", estado = "aberto" },
		},
	}
	eq(pedidos.renderLista(pt, nil, PT), "Lista da sessão desta aba: Organização\n☐ i2 Organização 3/3\n☑ i1 Organização 2/3 (feito)")
	eq(pedidos.renderLista(nil, {}, EN), EN.listaVazia)
end)

return testes

-- Tests for lib/nucleo.luau over an in-memory store, an advancing fixed clock
-- and a deterministic id source. Every environment is seeded with unreadable
-- files, and every nucleo call is followed by the invariant sweep: those
-- files must be byte-identical (never written, moved or deleted).

local nucleo = require("../lib/nucleo")
local json = require("./json_tern")

local testes = {}
local function teste(nome: string, fn: () -> ())
	table.insert(testes, { nome, fn })
end

local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
	end
end

local function verdade(c: any, msg: string?)
	if not c then
		error(msg or "expected true", 2)
	end
end

local function idsDe(itens): string
	local r = {}
	for _, i in itens do
		table.insert(r, i.id)
	end
	return table.concat(r, ",")
end

local ILEGIVEIS = {
	["listas/l_ruim0001.json"] = "{not json",
	["listas/l_ruim0002.json"] = '{"versao":1,"id":"l_ruim0002"}\n',
	["listas/l_ruim0003.json"] = '{"versao":1,"id":"l_outro999","pane":7,"assunto":"","criada":"x","atualizada":"x","itens":[],"tirados":[],"lembretes":0}\n',
	["listas/l_ruim0004.json"] = '{"versao":1,"id":"l_ruim0004","pane":7,"assunto":"","criada":"x","atualizada":"x","itens":[{"id":"i1","texto":"a","estado":"talvez"}],"tirados":[],"lembretes":0}\n',
}

local varreduras = 0

-- A fresh environment: { N, arquivos, json }.
local function ambiente(semIlegiveis: boolean?)
	local arquivos: { [string]: string } = {}
	if not semIlegiveis then
		for k, v in ILEGIVEIS do
			arquivos[k] = v
		end
	end
	arquivos["listas/notas.txt"] = "not a list name"
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
	local deps = {
		json = json,
		agora = function()
			segundo += 1
			return string.format("2026-11-02T10:%02d:%02d-03:00", segundo // 60, segundo % 60)
		end,
		novoId = function()
			idN += 1
			return string.format("l_aaaa%04d", idN)
		end,
	}
	local real = nucleo.novo(store, deps)
	local N = {}
	for nome, f in real do
		N[nome] = function(...)
			local r = table.pack(f(...))
			if not semIlegiveis then
				for k, v in ILEGIVEIS do
					if arquivos[k] ~= v then
						error("invariant: unreadable " .. k .. " changed by " .. nome, 2)
					end
				end
				varreduras += 1
			end
			return table.unpack(r, 1, r.n)
		end
	end
	local function le(id: string)
		local t = arquivos["listas/" .. id .. ".json"]
		return t and json.decode(t)
	end
	return { N = N, arquivos = arquivos, le = le, store = store, deps = deps }
end

-- A list in pane 1 with i1 aberto, i2 feito, i3 travado.
local function tresEstados()
	local a = ambiente()
	local N = a.N
	N.anota(1, { "um", "dois", "tres" })
	N.risca(1, { "i2" })
	N.trava(1, "i3", "waiting for Juan")
	return a, N
end

local function item(lista, id)
	for _, i in lista.itens do
		if i.id == id then
			return i
		end
	end
	return nil
end

-- json_tern quirks ---------------------------------------------------------

teste("json_tern drops null object members and tags arrays", function()
	local x = json.decode('{"a":null,"b":[],"c":[1,null]}')
	eq(x.a, nil)
	verdade(json.isArray(x.b), "decoded [] is tagged")
	eq(json.encode(x.b), "[]")
	eq(x.c[2], json.null)
	eq(json.encode({}), "{}")
	eq(json.encode(json.array()), "[]")
	eq(json.encode(json.array({})), "[]")
	eq(json.encode({ b = 2, a = "x\"\n" }), '{"a":"x\\"\\n","b":2}')
	eq(json.decode('"\\u00e9\\ud83d\\ude00"'), "é😀")
end)

-- cold start / steady state ------------------------------------------------

teste("cold start: empty store, first anota creates the list file", function()
	local a = ambiente(true)
	a.arquivos["listas/notas.txt"] = nil
	eq(a.N.daPane(1), nil)
	local r = a.N.anota(1, { "  parte 1 ", "parte 2", "   " }, { assunto = " Deploy " })
	verdade(r.ok)
	eq(r.lista.id, "l_aaaa0001")
	eq(r.lista.pane, 1)
	eq(r.lista.assunto, "Deploy")
	eq(idsDe(r.lista.itens), "i1,i2")
	eq(r.lista.itens[1].texto, "parte 1")
	local f = a.le("l_aaaa0001")
	verdade(nucleo.ehLista(f, "l_aaaa0001"), "file validates")
	eq(f.criada, f.atualizada)
end)

teste("steady state: anota appends with max+1 ids, others never renumbered", function()
	local a = ambiente()
	a.N.anota(1, { "a", "b", "c" })
	a.N.tira(1, { "i2" })
	local r = a.N.anota(1, { "d" })
	eq(idsDe(r.lista.itens), "i1,i3,i4")
	eq(r.lista.id, "l_aaaa0001", "same list")
	r = a.N.anota(1, { "e" }, { assunto = "  " })
	eq(r.lista.assunto, "", "blank subject ignored")
end)

teste("anota with nothing to note", function()
	local a = ambiente()
	eq(a.N.anota(1, { "  ", "" }).codigo, "nada-pra-anotar")
	eq(a.N.anota(1, {}).codigo, "nada-pra-anotar")
	eq(a.N.daPane(1), nil)
end)

teste("anota retries a colliding id", function()
	local a = ambiente()
	a.arquivos["listas/l_aaaa0001.json"] = "{taken"
	local r = a.N.anota(1, { "x" })
	eq(r.lista.id, "l_aaaa0002")
	eq(a.arquivos["listas/l_aaaa0001.json"], "{taken")
end)

teste("one list per pane; other panes separate", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.anota(2, { "b" })
	eq(a.N.daPane(1).itens[1].texto, "a")
	eq(a.N.daPane(2).itens[1].texto, "b")
	eq(#a.N.leTodas().listas, 2)
end)

-- the status × operation grid ----------------------------------------------

teste("grid aberto: done → feito with feitoEm", function()
	local _, N = tresEstados()
	local i = item(N.daPane(1), "i2")
	eq(i.estado, "feito")
	verdade(i.feitoEm ~= nil)
	eq(i.motivo, nil)
end)

teste("grid ★ aberto: undo is a no-op with notice", function()
	local a, N = tresEstados()
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	local r = N.desrisca(1, { "i1" })
	verdade(r.ok)
	eq(r.aviso, "nao-feito")
	eq(r.avisos[1].id, "i1")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes, "nothing written")
end)

teste("grid ★ aberto: unblock is a no-op with notice", function()
	local a, N = tresEstados()
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	eq(N.destrava(1, "i1").aviso, "nao-travado")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes)
end)

teste("grid aberto: block → travado; remove → gone", function()
	local _, N = tresEstados()
	local r = N.trava(1, "i1", "later")
	eq(item(r.lista, "i1").estado, "travado")
	eq(item(r.lista, "i1").motivo, "later")
	r = N.tira(1, { "i1" })
	eq(item(r.lista, "i1"), nil)
end)

teste("grid ★ feito: done is a no-op with notice", function()
	local a, N = tresEstados()
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	local r = N.risca(1, { "i2" })
	eq(r.aviso, "ja-feito")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes)
end)

teste("grid feito: undo → aberto, feitoEm removed", function()
	local _, N = tresEstados()
	local i = item(N.desrisca(1, { "i2" }).lista, "i2")
	eq(i.estado, "aberto")
	eq(i.feitoEm, nil)
end)

teste("grid ★ feito: block → travado, feitoEm cleared", function()
	local a, N = tresEstados()
	N.trava(1, "i2", "reopened, waits")
	local i = item(a.le("l_aaaa0001"), "i2")
	eq(i.estado, "travado")
	eq(i.feitoEm, nil)
	eq(i.motivo, "reopened, waits")
end)

teste("grid ★ feito: unblock is a no-op", function()
	local _, N = tresEstados()
	local r = N.destrava(1, "i2")
	eq(r.aviso, "nao-travado")
	eq(item(r.lista, "i2").estado, "feito")
end)

teste("grid ★ travado: done → feito, motivo cleared", function()
	local a, N = tresEstados()
	N.risca(1, { "i3" })
	local i = item(a.le("l_aaaa0001"), "i3")
	eq(i.estado, "feito")
	eq(i.motivo, nil)
	verdade(i.feitoEm ~= nil)
end)

teste("grid ★ travado: undo is a no-op", function()
	local _, N = tresEstados()
	local r = N.desrisca(1, { "i3" })
	eq(r.aviso, "nao-feito")
	eq(item(r.lista, "i3").estado, "travado")
end)

teste("grid ★ travado: block again replaces the reason; same reason is a no-op", function()
	local a, N = tresEstados()
	local r = N.trava(1, "i3", "waiting for Ana")
	eq(r.aviso, nil)
	eq(item(a.le("l_aaaa0001"), "i3").motivo, "waiting for Ana")
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	r = N.trava(1, "i3", "  waiting for Ana ")
	eq(r.aviso, "ja-travado")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes)
end)

teste("grid travado: unblock → aberto, motivo removed; remove → gone", function()
	local a, N = tresEstados()
	N.destrava(1, "i3")
	local i = item(a.le("l_aaaa0001"), "i3")
	eq(i.estado, "aberto")
	eq(i.motivo, nil)
	eq(item(N.tira(1, { "i3" }).lista, "i3"), nil)
end)

teste("grid ★ check: travado is NOT counted as open; feito is not open", function()
	local _, N = tresEstados()
	local l = N.daPane(1)
	eq(idsDe(N.abertos(l)), "i1")
	eq(idsDe(N.pendentes(l)), "i1,i3")
	N.risca(1, { "i1" })
	local r = N.confere(1, 5)
	eq(r.lembrar, false, "only a blocked item left: no reminder")
end)

teste("grid ★ in tirados: add refused unless denovo", function()
	local a = ambiente()
	local N = a.N
	N.anota(1, { "Parte  UM", "dois" })
	N.tira(1, { "i1" }, { pelaPessoa = true })
	eq(a.le("l_aaaa0001").tirados[1], "parte um")
	local r = N.anota(1, { "  parte um " })
	eq(r.ok, false)
	eq(r.codigo, "tirado-pela-pessoa")
	eq(r.recusados[1], "parte um")
	r = N.anota(1, { "parte um", "tres" })
	verdade(r.ok, "partial add is ok")
	eq(r.aviso, "tirado-pela-pessoa")
	eq(idsDe(r.lista.itens), "i2,i3")
	r = N.anota(1, { "PARTE UM" }, { denovo = true })
	verdade(r.ok)
	eq(r.lista.itens[3].texto, "PARTE UM")
	eq(#a.le("l_aaaa0001").tirados, 0, "denovo clears it from tirados")
end)

teste("agent remove does not add to tirados; person remove dedupes", function()
	local a = ambiente()
	a.N.anota(1, { "x", "x", "y" })
	a.N.tira(1, { "i3" })
	eq(#a.le("l_aaaa0001").tirados, 0)
	a.N.tira(1, { "i1", "i2" }, { pelaPessoa = true })
	eq(#a.le("l_aaaa0001").tirados, 1)
end)

-- fazendo (in progress, verb doing) ------------------------------------------

teste("grid fazendo: doing on aberto → fazendo; one at a time per list", function()
	local a, N = tresEstados()
	local r = N.faz(1, "i1")
	verdade(r.ok)
	eq(r.aviso, nil)
	eq(item(a.le("l_aaaa0001"), "i1").estado, "fazendo")
	verdade(nucleo.ehLista(a.le("l_aaaa0001"), "l_aaaa0001"), "fazendo validates")
	N.anota(1, { "quatro" })
	N.faz(1, "i4")
	local l = a.le("l_aaaa0001")
	eq(item(l, "i4").estado, "fazendo")
	eq(item(l, "i1").estado, "aberto", "the previous fazendo goes back to aberto")
	local n = 0
	for _, i in l.itens do
		if i.estado == "fazendo" then
			n += 1
		end
	end
	eq(n, 1, "only one fazendo")
	eq(item(l, "i2").estado, "feito", "others untouched")
	eq(item(l, "i3").estado, "travado")
end)

teste("grid ★ fazendo: doing again is a no-op with notice", function()
	local a, N = tresEstados()
	N.faz(1, "i1")
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	local r = N.faz(1, "i1")
	verdade(r.ok)
	eq(r.aviso, "ja-fazendo")
	eq(r.avisos[1].id, "i1")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes, "nothing written")
end)

teste("grid ★ feito: doing reopens it as fazendo, feitoEm cleared", function()
	local a, N = tresEstados()
	N.faz(1, "i2")
	local i = item(a.le("l_aaaa0001"), "i2")
	eq(i.estado, "fazendo")
	eq(i.feitoEm, nil)
end)

teste("grid ★ travado: doing → fazendo, motivo removed", function()
	local a, N = tresEstados()
	N.faz(1, "i3")
	local i = item(a.le("l_aaaa0001"), "i3")
	eq(i.estado, "fazendo")
	eq(i.motivo, nil)
	verdade(not string.find(a.arquivos["listas/l_aaaa0001.json"], "waiting for Juan", 1, true))
end)

teste("grid fazendo: done → feito; undo → aberto", function()
	local a, N = tresEstados()
	N.faz(1, "i1")
	N.risca(1, { "i1" })
	local i = item(a.le("l_aaaa0001"), "i1")
	eq(i.estado, "feito")
	verdade(i.feitoEm ~= nil)
	N.faz(1, "i1")
	local r = N.desrisca(1, { "i1" })
	eq(r.aviso, nil)
	eq(item(a.le("l_aaaa0001"), "i1").estado, "aberto")
end)

teste("grid fazendo: block → travado; unblock is a no-op with notice; remove → gone", function()
	local a, N = tresEstados()
	N.faz(1, "i1")
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	local r = N.destrava(1, "i1")
	eq(r.aviso, "nao-travado")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes)
	eq(item(r.lista, "i1").estado, "fazendo")
	r = N.trava(1, "i1", "needs Ana")
	eq(item(r.lista, "i1").estado, "travado")
	eq(item(r.lista, "i1").motivo, "needs Ana")
	N.faz(1, "i1")
	eq(item(N.tira(1, { "i1" }).lista, "i1"), nil)
end)

teste("grid ★ check: fazendo counts as open and as pending", function()
	local _, N = tresEstados()
	N.faz(1, "i1")
	local l = N.daPane(1)
	eq(idsDe(N.abertos(l)), "i1")
	eq(idsDe(N.pendentes(l)), "i1,i3")
	local r = N.confere(1, 5)
	eq(r.lembrar, true, "the agent stopped mid-part")
	eq(idsDe(r.itens), "i1")
end)

teste("faz errors: sem-lista, sem-id, unknown id", function()
	local a = ambiente()
	eq(a.N.faz(1, "i1").codigo, "sem-lista")
	a.N.anota(1, { "a" })
	eq(a.N.faz(1, "").codigo, "sem-id")
	eq(a.N.faz(1, nil :: any).codigo, "sem-id")
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	local r = a.N.faz(1, "i9")
	eq(r.naoAchei[1], "i9")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes)
end)

teste("orfaniza keeps fazendo in the file; adopt into an empty pane turns it aberto", function()
	local a = ambiente()
	a.N.anota(1, { "a", "b" })
	a.N.faz(1, "i2")
	eq(a.N.orfaniza(1).orfanizadas[1], "l_aaaa0001", "fazendo is pending")
	eq(item(a.le("l_aaaa0001"), "i2").estado, "fazendo", "orphan file keeps it")
	local r = a.N.puxa(9, "l_aaaa0001")
	verdade(r.ok)
	eq(item(r.lista, "i2").estado, "aberto")
	eq(item(a.le("l_aaaa0001"), "i2").estado, "aberto")
end)

teste("adopt into a pane with a list: fazendo arrives aberto, the pane's own fazendo stays", function()
	local a = ambiente()
	a.N.anota(1, { "o1" })
	a.N.faz(1, "i1")
	a.N.orfaniza(1)
	a.N.anota(2, { "m1" })
	a.N.faz(2, "i1")
	local r = a.N.puxa(2, "l_aaaa0001")
	verdade(r.ok)
	eq(item(r.lista, "i1").estado, "fazendo")
	eq(item(r.lista, "i2").texto, "o1")
	eq(item(r.lista, "i2").estado, "aberto")
	verdade(nucleo.ehLista(a.le("l_aaaa0002"), "l_aaaa0002"))
end)

-- errors -------------------------------------------------------------------

teste("errors: sem-lista, sem-id, sem-motivo, assunto-vazio, naoAchei", function()
	local a = ambiente()
	local N = a.N
	eq(N.risca(1, { "i1" }).codigo, "sem-lista")
	eq(N.desrisca(1, { "i1" }).codigo, "sem-lista")
	eq(N.tira(1, { "i1" }).codigo, "sem-lista")
	eq(N.nomeia(1, "x").codigo, "sem-lista")
	eq(N.trava(1, "i1", "r").codigo, "sem-lista")
	eq(N.destrava(1, "i1").codigo, "sem-lista")
	N.anota(1, { "a" })
	eq(N.risca(1, {}).codigo, "sem-id")
	eq(N.trava(1, "", "r").codigo, "sem-id")
	eq(N.destrava(1, " ").codigo, "sem-id")
	eq(N.trava(1, "i1", "  ").codigo, "sem-motivo")
	eq(N.nomeia(1, "  ").codigo, "assunto-vazio")
	local r = N.risca(1, { "i9", "i1" })
	verdade(r.ok)
	eq(r.naoAchei[1], "i9")
	eq(item(r.lista, "i1").estado, "feito")
	local antes = a.arquivos["listas/l_aaaa0001.json"]
	r = N.trava(1, "i9", "r")
	eq(r.naoAchei[1], "i9")
	eq(a.arquivos["listas/l_aaaa0001.json"], antes, "unknown id writes nothing")
end)

teste("nomeia names the list and trims", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	eq(a.N.nomeia(1, "  Release ").lista.assunto, "Release")
	eq(a.le("l_aaaa0001").assunto, "Release")
end)

-- confere / lembretes ------------------------------------------------------

teste("confere: cap, then reset by any change", function()
	local a = ambiente()
	local N = a.N
	eq(N.confere(1).lembrar, false, "no list")
	N.anota(1, { "a", "b" })
	local r = N.confere(1, 1)
	eq(r.lembrar, true)
	eq(idsDe(r.itens), "i1,i2")
	eq(a.le("l_aaaa0001").lembretes, 1)
	eq(N.confere(1, 1).lembrar, false, "capped")
	eq(N.confere(1).lembrar, false, "default cap 1")
	eq(N.confere(1, 2).lembrar, true, "higher cap")
	N.risca(1, { "i1" })
	eq(a.le("l_aaaa0001").lembretes, 0, "change resets")
	eq(N.confere(1, 1).lembrar, true)
	N.nomeia(1, "x")
	eq(a.le("l_aaaa0001").lembretes, 0, "nomeia resets")
	N.confere(1, 1)
	N.risca(1, { "i1" }) -- no-op
	eq(a.le("l_aaaa0001").lembretes, 1, "a no-op does not reset")
	N.risca(1, { "i2" })
	eq(N.confere(1, 9).lembrar, false, "all done")
end)

teste("confere does not move atualizada", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	local antes = a.le("l_aaaa0001").atualizada
	a.N.confere(1)
	eq(a.le("l_aaaa0001").atualizada, antes)
end)

-- orphan rules -------------------------------------------------------------

teste("orfaniza: pane gone with open items → orphan (pane key absent)", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	local r = a.N.orfaniza(1)
	eq(r.orfanizadas[1], "l_aaaa0001")
	local f = a.le("l_aaaa0001")
	eq(f.pane, nil)
	verdade(not string.find(a.arquivos["listas/l_aaaa0001.json"], '"pane"'), "no pane key written")
	verdade(nucleo.ehLista(f, "l_aaaa0001"))
	eq(a.N.daPane(1), nil)
	eq(a.N.orfas().orfas[1].id, "l_aaaa0001")
end)

teste("orfaniza: only blocked items → still an orphan", function()
	local a = ambiente()
	a.N.anota(1, { "a", "b" })
	a.N.risca(1, { "i1" })
	a.N.trava(1, "i2", "Juan")
	eq(a.N.orfaniza(1).orfanizadas[1], "l_aaaa0001")
	eq(item(a.le("l_aaaa0001"), "i2").motivo, "Juan")
end)

teste("orfaniza: only done items → deleted", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.risca(1, { "i1" })
	local r = a.N.orfaniza(1)
	eq(r.apagadas[1], "l_aaaa0001")
	eq(a.arquivos["listas/l_aaaa0001.json"], nil)
end)

teste("orfaniza on a reused pane id (spawn) frees the pane for a new list", function()
	local a = ambiente()
	a.N.anota(5, { "old tab work" })
	a.N.orfaniza(5) -- a new program spawned in pane 5
	eq(a.N.daPane(5), nil, "the new tab does not inherit it")
	local r = a.N.anota(5, { "new tab work" })
	eq(r.lista.id, "l_aaaa0002")
	eq(#r.lista.itens, 1)
	eq(a.N.orfas(5).orfas[1].id, "l_aaaa0001")
end)

teste("orfaniza touches only that pane; orphans are not re-orphaned", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.anota(2, { "b" })
	a.N.orfaniza(1)
	local r = a.N.orfaniza(1)
	eq(#r.orfanizadas + #r.apagadas, 0)
	eq(a.N.daPane(2).id, "l_aaaa0002")
end)

teste("orfanizaAusentes: numbers or {id} records; live panes kept", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.anota(2, { "b" })
	a.N.anota(3, { "c" })
	a.N.risca(3, { "i1" })
	local r = a.N.orfanizaAusentes({ { id = 2 } })
	eq(table.concat(r.orfanizadas, ","), "l_aaaa0001")
	eq(table.concat(r.apagadas, ","), "l_aaaa0003")
	eq(a.N.daPane(2).id, "l_aaaa0002")
	r = a.N.orfanizaAusentes({ 2 })
	eq(#r.orfanizadas + #r.apagadas, 0)
	r = a.N.orfanizaAusentes({})
	eq(r.orfanizadas[1], "l_aaaa0002")
end)

teste("orfas: newest first, finished orphans not offered", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.anota(2, { "b" })
	a.N.orfaniza(1)
	a.N.orfaniza(2)
	local o = a.N.orfas()
	eq(o.orfas[1].id, "l_aaaa0002")
	eq(o.orfas[2].id, "l_aaaa0001")
	eq(#o.ilegiveis, 4)
	eq(o.ilegiveis[1], "l_ruim0001.json")
end)

-- puxa / descarta ----------------------------------------------------------

teste("puxa into an empty pane adopts the orphan whole", function()
	local a = ambiente()
	a.N.anota(1, { "a", "b" }, { assunto = "S" })
	a.N.trava(1, "i2", "Juan")
	a.N.orfaniza(1)
	local r = a.N.puxa(9, "l_aaaa0001")
	verdade(r.ok)
	eq(r.lista.id, "l_aaaa0001")
	eq(r.lista.pane, 9)
	eq(a.le("l_aaaa0001").pane, 9)
	eq(idsDe(r.lista.itens), "i1,i2")
	eq(a.N.daPane(9).assunto, "S")
end)

teste("puxa into a pane with a list appends pending items with new ids", function()
	local a = ambiente()
	a.N.anota(1, { "o1", "o2", "o3" }, { assunto = "Orphan" })
	a.N.risca(1, { "i1" })
	a.N.trava(1, "i3", "Juan")
	a.N.orfaniza(1)
	a.N.anota(2, { "m1", "m2", "m3" })
	a.N.tira(2, { "i2" })
	local r = a.N.puxa(2, "l_aaaa0001")
	verdade(r.ok)
	eq(r.lista.id, "l_aaaa0002")
	eq(idsDe(r.lista.itens), "i1,i3,i4,i5")
	eq(r.lista.itens[3].texto, "o2")
	eq(r.lista.itens[3].estado, "aberto")
	eq(r.lista.itens[4].texto, "o3")
	eq(r.lista.itens[4].estado, "travado")
	eq(r.lista.itens[4].motivo, "Juan")
	eq(r.lista.assunto, "Orphan", "empty subject takes the orphan's")
	eq(a.arquivos["listas/l_aaaa0001.json"], nil, "orphan file deleted")
	verdade(nucleo.ehLista(a.le("l_aaaa0002"), "l_aaaa0002"))
end)

teste("puxa keeps the pane's own subject when set", function()
	local a = ambiente()
	a.N.anota(1, { "o" }, { assunto = "Orphan" })
	a.N.orfaniza(1)
	a.N.anota(2, { "m" }, { assunto = "Mine" })
	eq(a.N.puxa(2, "l_aaaa0001").lista.assunto, "Mine")
end)

teste("descarta moves the orphan to descartadas", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.orfaniza(1)
	local texto = a.arquivos["listas/l_aaaa0001.json"]
	local r = a.N.descarta(3, "l_aaaa0001")
	verdade(r.ok)
	eq(r.id, "l_aaaa0001")
	eq(a.arquivos["listas/l_aaaa0001.json"], nil)
	eq(a.arquivos["descartadas/l_aaaa0001.json"], texto)
	eq(#a.N.orfas().orfas, 0)
end)

teste("refusals: sumiu, viva, minha, ilegivel (puxa and descarta)", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.anota(2, { "b" })
	for _, op in { "puxa", "descarta" } do
		local f = a.N[op]
		eq(f(1, "l_zzzz9999").motivo, "sumiu", op .. " unknown")
		eq(f(1, "bogus").motivo, "sumiu", op .. " bad id")
		eq(f(1, "../x").motivo, "sumiu", op .. " path")
		eq(f(1, "l_aaaa0002").motivo, "viva", op .. " live list")
		eq(f(1, "l_aaaa0001").motivo, "minha", op .. " own list")
		eq(f(1, "l_ruim0001").motivo, "ilegivel", op .. " unreadable")
		eq(f(1, "l_ruim0002").motivo, "ilegivel", op .. " missing fields")
		eq(f(1, "l_ruim0003").ok, false, op .. " id mismatch")
	end
	eq(a.le("l_aaaa0002").pane, 2)
end)

-- inicio -------------------------------------------------------------------

teste("inicio deletes a pane's finished list and returns orphans", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.risca(1, { "i1" })
	a.N.anota(2, { "b" })
	a.N.orfaniza(2)
	local r = a.N.inicio(1)
	eq(r.lista, nil)
	eq(a.arquivos["listas/l_aaaa0001.json"], nil)
	eq(r.orfas[1].id, "l_aaaa0002")
	eq(#r.ilegiveis, 4)
end)

teste("inicio keeps a list with pending items (blocked counts)", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.trava(1, "i1", "x")
	local r = a.N.inicio(1)
	eq(r.lista.id, "l_aaaa0001")
	eq(#r.orfas, 0)
	eq(a.N.inicio(4).lista, nil, "pane with no list")
end)

-- unreadable files ---------------------------------------------------------

teste("unreadable files are reported and never become a pane's list", function()
	local a = ambiente()
	local t = a.N.leTodas()
	eq(#t.listas, 0)
	eq(table.concat(t.ilegiveis, ","), "l_ruim0001.json,l_ruim0002.json,l_ruim0003.json,l_ruim0004.json")
	eq(a.N.daPane(7), nil, "l_ruim0003 claims pane 7 but does not validate")
	local r = a.N.anota(7, { "x" })
	eq(r.lista.id, "l_aaaa0001")
	a.N.orfanizaAusentes({})
	a.N.orfaniza(7)
	eq(a.arquivos["listas/notas.txt"], "not a list name")
end)

-- encoding -----------------------------------------------------------------

teste("empty arrays encode as []", function()
	local a = ambiente()
	a.N.anota(1, { "a" })
	a.N.tira(1, { "i1" })
	local texto = a.arquivos["listas/l_aaaa0001.json"]
	verdade(string.find(texto, '"itens":[]', 1, true), "itens is [] in " .. texto)
	verdade(string.find(texto, '"tirados":[]', 1, true), "tirados is []")
	verdade(nucleo.ehLista(json.decode(texto), "l_aaaa0001"))
end)

teste("orphan and items without motivo/feitoEm survive encode → decode", function()
	local a = ambiente()
	a.N.anota(1, { "a", "b" })
	a.N.trava(1, "i2", "r")
	a.N.destrava(1, "i2")
	a.N.orfaniza(1)
	local texto = a.arquivos["listas/l_aaaa0001.json"]
	verdade(not string.find(texto, "null", 1, true), "no nulls written")
	local x = json.decode(texto)
	eq(x.pane, nil)
	eq(x.itens[2].motivo, nil)
	eq(x.itens[1].feitoEm, nil)
	verdade(nucleo.ehLista(x, "l_aaaa0001"))
	local again = json.decode(json.encode(x))
	verdade(nucleo.ehLista(again, "l_aaaa0001"))
	-- a file written by Tern with explicit nulls still validates
	local comNulls = string.gsub(texto, '"assunto"', '"pane":null,"assunto"')
	verdade(nucleo.ehLista(json.decode(comNulls), "l_aaaa0001"))
end)

teste("normaliza trims, lowercases, collapses spaces", function()
	eq(nucleo.normaliza("  Foo \t  BAR\nbaz "), "foo bar baz")
end)

teste("invariant sweep ran after operations", function()
	verdade(varreduras > 100, "sweeps: " .. varreduras)
end)

return testes

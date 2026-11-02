-- The list model of the Tern session-list plugin: pure, no `tern` global.
-- Mirrors WS/src/lista-da-sessao/hooks/listas.ts without owner processes or
-- locks (the host half is the only writer now).
--
-- CONSTRUCTION
--   nucleo.novo(store, deps) -> N
--   store = {
--     list()            -> {name}   names relative to the data folder; every
--                                    "listas/l_<8 [a-z0-9]>.json" must be in it,
--                                    any other name is ignored
--     read(name)        -> string?  nil when the file is not there
--     write(name, text)             whole-file replace
--     remove(name)
--     move(name, toDir)             "listas/l_x.json", "descartadas" ->
--                                    "descartadas/l_x.json"
--   }
--   deps = { json = {encode, decode, array}, agora() -> ISO string,
--            novoId() -> "l_<8 [a-z0-9]>" }
--
-- LIST (the file "listas/<id>.json")
--   { versao = 1, id, pane? (number; absent = orphan), assunto, criada,
--     atualizada, itens = {Item}, tirados = {string}, lembretes = number }
--   Item = { id = "i<n>", texto, estado = "aberto"|"fazendo"|"feito"|"travado",
--            motivo? (travado only), feitoEm? (feito only) }
--   "fazendo" = in progress; at most one per list (`faz` turns any other back
--   to "aberto"). It counts as pending and as open (abertos, confere).
--   No key is ever nil-valued on purpose: optional keys are absent.
--
-- RESULTS (never throws for expected cases)
--   failure  { ok = false, codigo = <code> }      (operations on this pane)
--            { ok = false, motivo = <motivo> }     (puxa / descarta)
--   codes:   "sem-lista" "nada-pra-anotar" "assunto-vazio" "sem-id"
--            "sem-motivo" "tirado-pela-pessoa"
--   motivos: "sumiu" "viva" "minha" "ilegivel"
--   notices on success: `avisos = {{id, codigo}}` ({texto, codigo} in anota) (codigo "ja-feito",
--            "nao-feito", "ja-travado", "nao-travado", "ja-fazendo", "tirado-pela-pessoa")
--            and `aviso` = the first notice's codigo (nil when none).
--
-- FUNCTIONS (pane is always a number)
--   N.leTodas()                       -> {listas = {Lista}, ilegiveis = {"l_x.json"} (sorted)}
--   N.daPane(pane)                    -> Lista?   newest `atualizada` among lists with that pane
--   N.anota(pane, textos, opts?)      opts = {assunto?, denovo?}
--                                     -> {ok, lista, naoAchei = {}, avisos, aviso, recusados = {texto}}
--                                        | {ok=false, codigo="nada-pra-anotar"}
--                                        | {ok=false, codigo="tirado-pela-pessoa", recusados}
--   N.risca(pane, ids)                -> {ok, lista, naoAchei, avisos, aviso} | {ok=false, codigo}
--   N.desrisca(pane, ids)             -> same shape; feito or fazendo → aberto
--   N.tira(pane, ids, opts?)          opts = {pelaPessoa?} -> same shape
--   N.nomeia(pane, assunto)           -> {ok, lista, naoAchei = {}, avisos = {}} | {ok=false, codigo}
--   N.trava(pane, id, motivo)         -> {ok, lista, naoAchei, avisos, aviso} | {ok=false, codigo}
--   N.destrava(pane, id)              -> same shape
--   N.faz(pane, id)                   -> same shape; id → "fazendo" (from aberto, feito:
--                                        feitoEm cleared, travado: motivo cleared), any
--                                        other "fazendo" item → "aberto"; already
--                                        fazendo → notice "ja-fazendo", nothing written
--   N.orfas(excetoPane?)              -> {orfas = {Lista} (newest first), ilegiveis}
--                                     orphans have no pane, so excetoPane never
--                                     matches one; kept for the mod's signature
--   N.orfaniza(pane)                  -> {orfanizadas = {id}, apagadas = {id}}
--   N.orfanizaAusentes(panesVivos)    panesVivos = {number} or {{id = number}}
--                                     -> {orfanizadas = {id}, apagadas = {id}}
--   N.puxa(pane, listaId)             -> {ok = true, lista} | {ok = false, motivo}
--                                     adopted "fazendo" items arrive as "aberto"
--                                     (the closed tab is not working on them)
--   N.descarta(pane, listaId)         -> {ok = true, id} | {ok = false, motivo}
--   N.abertos(lista)                  -> {Item}  "aberto" + "fazendo" (what a stop is reminded of)
--   N.pendentes(lista)                -> {Item}  everything not "feito"
--   N.confere(pane, max?)             max defaults to 1
--                                     -> {lembrar = bool, itens = abertos(lista), lista = Lista?}
--   N.inicio(pane)                    -> {lista = Lista?, orfas = {Lista}, ilegiveis}
--   N.normaliza(texto)                -> string  (trim, lowercase, collapse spaces)
--
-- Rules: a file that does not decode or lacks fields is "ilegivel" and is
-- never written, moved or deleted. Every real change sets `atualizada`,
-- resets `lembretes` to 0 and writes the whole file; a no-op writes nothing.
-- `confere` only bumps `lembretes` (atualizada untouched). New item ids are
-- max + 1 of the ids present (as listas.ts proximoItem): other items are never
-- renumbered, but removing the highest id lets that id come back.

local nucleo = {}

local PASTA = "listas/"
local DESCARTADAS = "descartadas"

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function normaliza(s: string): string
	return (string.gsub(string.lower(trim(s)), "%s+", " "))
end

local function ehIdLista(id: any): boolean
	return type(id) == "string" and string.match(id, "^l_[a-z0-9]+$") ~= nil and #id == 10
end

local function idDoNome(nome: string): string?
	local id = string.match(nome, "^listas/(l_[a-z0-9]+)%.json$")
	if id and #id == 10 then
		return id
	end
	return nil
end

local function ehSequencia(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		if type(k) ~= "number" then
			return false
		end
		n += 1
	end
	return n == #t
end

local ESTADOS = { aberto = true, fazendo = true, feito = true, travado = true }

local function ehItem(i: any): boolean
	return type(i) == "table"
		and type(i.id) == "string"
		and type(i.texto) == "string"
		and ESTADOS[i.estado] == true
		and (i.motivo == nil or type(i.motivo) == "string")
		and (i.feitoEm == nil or type(i.feitoEm) == "string")
end

local function ehLista(x: any, id: string): boolean
	if type(x) ~= "table" then
		return false
	end
	if not (x.versao == 1 and x.id == id and (x.pane == nil or type(x.pane) == "number")
		and type(x.assunto) == "string" and type(x.criada) == "string"
		and type(x.atualizada) == "string" and type(x.lembretes) == "number"
		and ehSequencia(x.itens) and ehSequencia(x.tirados)) then
		return false
	end
	for _, i in x.itens do
		if not ehItem(i) then
			return false
		end
	end
	for _, t in x.tirados do
		if type(t) ~= "string" then
			return false
		end
	end
	return true
end

local function filtra(itens, f)
	local r = {}
	for _, i in itens do
		if f(i) then
			table.insert(r, i)
		end
	end
	return r
end

local function abertos(lista)
	return filtra(lista.itens, function(i)
		return i.estado == "aberto" or i.estado == "fazendo"
	end)
end

local function pendentes(lista)
	return filtra(lista.itens, function(i)
		return i.estado ~= "feito"
	end)
end

local function proximoItem(itens): number
	local max = 0
	for _, i in itens do
		local n = tonumber(string.match(i.id, "^i(%d+)$"))
		if n and n > max then
			max = n
		end
	end
	return max + 1
end

local function maisNovaPrimeiro(a, b): boolean
	if a.atualizada ~= b.atualizada then
		return a.atualizada > b.atualizada
	end
	return a.id < b.id
end

function nucleo.novo(store, deps)
	local json = deps.json
	local N = {}

	local function arquivoDe(id: string): string
		return PASTA .. id .. ".json"
	end

	-- { lista } | { ilegivel = true } | { sumiu = true }
	local function leArquivo(id: string)
		local texto = store.read(arquivoDe(id))
		if texto == nil then
			return { sumiu = true }
		end
		local ok, x = pcall(json.decode, texto)
		if ok and ehLista(x, id) then
			return { lista = x }
		end
		return { ilegivel = true }
	end

	local function grava(lista)
		lista.itens = json.array(lista.itens)
		lista.tirados = json.array(lista.tirados)
		store.write(arquivoDe(lista.id), json.encode(lista) .. "\n")
	end

	local function mudou(lista, quando: string?)
		lista.atualizada = quando or deps.agora()
		lista.lembretes = 0
		grava(lista)
	end

	function N.leTodas()
		local listas, ilegiveis = {}, {}
		local nomes = table.clone(store.list())
		table.sort(nomes)
		for _, nome in nomes do
			local id = idDoNome(nome)
			if id then
				local lido = leArquivo(id)
				if lido.lista then
					table.insert(listas, lido.lista)
				elseif lido.ilegivel then
					table.insert(ilegiveis, id .. ".json")
				end
			end
		end
		table.sort(ilegiveis)
		return { listas = listas, ilegiveis = ilegiveis }
	end

	local function daPaneEm(listas, pane: number)
		local achada = nil
		for _, l in listas do
			if l.pane == pane and (achada == nil or maisNovaPrimeiro(l, achada)) then
				achada = l
			end
		end
		return achada
	end

	function N.daPane(pane: number)
		return daPaneEm(N.leTodas().listas, pane)
	end

	function N.anota(pane: number, textos: { string }, opts)
		opts = opts or {}
		local limpos = {}
		for _, t in textos or {} do
			local l = trim(t)
			if l ~= "" then
				table.insert(limpos, l)
			end
		end
		if #limpos == 0 then
			return { ok = false, codigo = "nada-pra-anotar" }
		end
		local quando = deps.agora()
		local lista = N.daPane(pane)
		if lista == nil then
			local id = deps.novoId()
			for _ = 1, 5 do
				if store.read(arquivoDe(id)) == nil then
					break
				end
				id = deps.novoId()
			end
			lista = {
				versao = 1, id = id, pane = pane, assunto = "", criada = quando,
				atualizada = quando, itens = {}, tirados = {}, lembretes = 0,
			}
		end
		local tirado = {}
		for k, t in lista.tirados do
			tirado[t] = k
		end
		local aceitos, recusados = {}, {}
		for _, t in limpos do
			local chave = normaliza(t)
			if tirado[chave] and not opts.denovo then
				table.insert(recusados, t)
			else
				table.insert(aceitos, t)
			end
		end
		if #aceitos == 0 then
			return { ok = false, codigo = "tirado-pela-pessoa", recusados = recusados }
		end
		if opts.denovo then
			local fica = {}
			local reAdicionados = {}
			for _, t in aceitos do
				reAdicionados[normaliza(t)] = true
			end
			for _, t in lista.tirados do
				if not reAdicionados[t] then
					table.insert(fica, t)
				end
			end
			lista.tirados = fica
		end
		local n = proximoItem(lista.itens)
		for _, t in aceitos do
			table.insert(lista.itens, { id = "i" .. n, texto = t, estado = "aberto" })
			n += 1
		end
		if type(opts.assunto) == "string" and trim(opts.assunto) ~= "" then
			lista.assunto = trim(opts.assunto)
		end
		mudou(lista, quando)
		local avisos = {}
		for _, t in recusados do
			table.insert(avisos, { texto = t, codigo = "tirado-pela-pessoa" })
		end
		return {
			ok = true, lista = lista, naoAchei = {}, recusados = recusados,
			avisos = avisos, aviso = avisos[1] and avisos[1].codigo,
		}
	end

	-- Applies `muda(lista, item) -> (mudou: bool, aviso: string?)` to each id.
	local function mudaItens(pane: number, ids: { string }, muda)
		if ids == nil or #ids == 0 then
			return { ok = false, codigo = "sem-id" }
		end
		local lista = N.daPane(pane)
		if lista == nil then
			return { ok = false, codigo = "sem-lista" }
		end
		local naoAchei, avisos = {}, {}
		local algo = false
		for _, id in ids do
			local item = nil
			for _, i in lista.itens do
				if i.id == id then
					item = i
					break
				end
			end
			if item == nil then
				table.insert(naoAchei, id)
			else
				local m, aviso = muda(lista, item)
				algo = algo or m
				if aviso then
					table.insert(avisos, { id = id, codigo = aviso })
				end
			end
		end
		if algo then
			mudou(lista)
		end
		return {
			ok = true, lista = lista, naoAchei = naoAchei,
			avisos = avisos, aviso = avisos[1] and avisos[1].codigo,
		}
	end

	function N.risca(pane: number, ids: { string })
		return mudaItens(pane, ids, function(_, item)
			if item.estado == "feito" then
				return false, "ja-feito"
			end
			item.estado = "feito"
			item.motivo = nil
			item.feitoEm = deps.agora()
			return true
		end)
	end

	function N.desrisca(pane: number, ids: { string })
		return mudaItens(pane, ids, function(_, item)
			if item.estado ~= "feito" and item.estado ~= "fazendo" then
				return false, "nao-feito"
			end
			item.estado = "aberto"
			item.feitoEm = nil
			return true
		end)
	end

	function N.tira(pane: number, ids: { string }, opts)
		local pelaPessoa = opts ~= nil and opts.pelaPessoa == true
		return mudaItens(pane, ids, function(lista, item)
			lista.itens = filtra(lista.itens, function(i)
				return i ~= item
			end)
			if pelaPessoa then
				local chave = normaliza(item.texto)
				if not table.find(lista.tirados, chave) then
					table.insert(lista.tirados, chave)
				end
			end
			return true
		end)
	end

	function N.nomeia(pane: number, assunto: string)
		local nome = trim(assunto or "")
		if nome == "" then
			return { ok = false, codigo = "assunto-vazio" }
		end
		local lista = N.daPane(pane)
		if lista == nil then
			return { ok = false, codigo = "sem-lista" }
		end
		lista.assunto = nome
		mudou(lista)
		return { ok = true, lista = lista, naoAchei = {}, avisos = {} }
	end

	function N.trava(pane: number, id: string, motivo: string)
		if id == nil or trim(id) == "" then
			return { ok = false, codigo = "sem-id" }
		end
		local razao = trim(motivo or "")
		if razao == "" then
			return { ok = false, codigo = "sem-motivo" }
		end
		return mudaItens(pane, { id }, function(_, item)
			if item.estado == "travado" and item.motivo == razao then
				return false, "ja-travado"
			end
			item.estado = "travado"
			item.motivo = razao
			item.feitoEm = nil
			return true
		end)
	end

	function N.destrava(pane: number, id: string)
		if id == nil or trim(id) == "" then
			return { ok = false, codigo = "sem-id" }
		end
		return mudaItens(pane, { id }, function(_, item)
			if item.estado ~= "travado" then
				return false, "nao-travado"
			end
			item.estado = "aberto"
			item.motivo = nil
			return true
		end)
	end

	function N.faz(pane: number, id: string)
		if id == nil or trim(id) == "" then
			return { ok = false, codigo = "sem-id" }
		end
		return mudaItens(pane, { id }, function(lista, item)
			if item.estado == "fazendo" then
				return false, "ja-fazendo"
			end
			for _, outro in lista.itens do
				if outro.estado == "fazendo" then
					outro.estado = "aberto"
				end
			end
			item.estado = "fazendo"
			item.motivo = nil
			item.feitoEm = nil
			return true
		end)
	end

	function N.orfas(excetoPane: number?)
		local todas = N.leTodas()
		local achadas = {}
		for _, l in todas.listas do
			if l.pane == nil and #pendentes(l) > 0 then
				table.insert(achadas, l)
			end
		end
		table.sort(achadas, maisNovaPrimeiro)
		return { orfas = achadas, ilegiveis = todas.ilegiveis }
	end

	-- Orphans (pending items) or deletes (finished) every list `fica(l)` says goes.
	local function orfanizaOnde(vai)
		local orfanizadas, apagadas = {}, {}
		for _, l in N.leTodas().listas do
			if l.pane ~= nil and vai(l.pane) then
				if #pendentes(l) > 0 then
					l.pane = nil
					mudou(l)
					table.insert(orfanizadas, l.id)
				else
					store.remove(arquivoDe(l.id))
					table.insert(apagadas, l.id)
				end
			end
		end
		table.sort(orfanizadas)
		table.sort(apagadas)
		return { orfanizadas = orfanizadas, apagadas = apagadas }
	end

	function N.orfaniza(pane: number)
		return orfanizaOnde(function(p)
			return p == pane
		end)
	end

	function N.orfanizaAusentes(panesVivos)
		local vivo = {}
		for _, p in panesVivos or {} do
			local id = if type(p) == "table" then p.id else p
			id = tonumber(id)
			if id then
				vivo[id] = true
			end
		end
		return orfanizaOnde(function(p)
			return not vivo[p]
		end)
	end

	-- The checks puxa and descarta share: { lista } | { motivo }.
	local function alvo(pane: number, id: string)
		if not ehIdLista(id) then
			return { motivo = "sumiu" }
		end
		local lido = leArquivo(id)
		if lido.sumiu then
			return { motivo = "sumiu" }
		end
		if lido.ilegivel then
			return { motivo = "ilegivel" }
		end
		if lido.lista.pane == pane then
			return { motivo = "minha" }
		end
		if lido.lista.pane ~= nil then
			return { motivo = "viva" }
		end
		return { lista = lido.lista }
	end

	function N.puxa(pane: number, listaId: string)
		local a = alvo(pane, listaId)
		if a.motivo then
			return { ok = false, motivo = a.motivo }
		end
		local orfa = a.lista
		local minha = N.daPane(pane)
		for _, i in orfa.itens do
			if i.estado == "fazendo" then
				i.estado = "aberto"
			end
		end
		if minha == nil then
			orfa.pane = pane
			mudou(orfa)
			return { ok = true, lista = orfa }
		end
		local n = proximoItem(minha.itens)
		for _, i in pendentes(orfa) do
			local novo = { id = "i" .. n, texto = i.texto, estado = i.estado }
			if i.estado == "travado" then
				novo.motivo = i.motivo
			end
			table.insert(minha.itens, novo)
			n += 1
		end
		if minha.assunto == "" then
			minha.assunto = orfa.assunto
		end
		mudou(minha)
		store.remove(arquivoDe(listaId))
		return { ok = true, lista = minha }
	end

	function N.descarta(pane: number, listaId: string)
		local a = alvo(pane, listaId)
		if a.motivo then
			return { ok = false, motivo = a.motivo }
		end
		store.move(arquivoDe(listaId), DESCARTADAS)
		return { ok = true, id = listaId }
	end

	function N.confere(pane: number, max: number?)
		local limite = max or 1
		local lista = N.daPane(pane)
		if lista == nil then
			return { lembrar = false, itens = {} }
		end
		local itens = abertos(lista)
		if #itens == 0 or lista.lembretes >= limite then
			return { lembrar = false, itens = itens, lista = lista }
		end
		lista.lembretes += 1
		grava(lista)
		return { lembrar = true, itens = itens, lista = lista }
	end

	function N.inicio(pane: number)
		local lista = N.daPane(pane)
		if lista ~= nil and #pendentes(lista) == 0 then
			store.remove(arquivoDe(lista.id))
			lista = nil
		end
		local o = N.orfas(pane)
		return { lista = lista, orfas = o.orfas, ilegiveis = o.ilegiveis }
	end

	N.abertos = abertos
	N.pendentes = pendentes
	N.normaliza = normaliza
	return N
end

nucleo.abertos = abertos
nucleo.pendentes = pendentes
nucleo.normaliza = normaliza
nucleo.ehLista = ehLista

return nucleo

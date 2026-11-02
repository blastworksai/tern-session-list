-- Host half of the Tern session-list plugin (runs in Tern's session daemon).
-- The ONLY writer of the lists: it applies the request files the
-- `session-list` command drops (THE REQUEST PROTOCOL in the plan), owns the
-- orphan rules, and injects SESSION_LIST_DATA into new panes (real id only).

local nucleo = require("./lib/nucleo")
local pedidos = require("./lib/pedidos")
local textos = require("./lib/textos")
local vista = require("./lib/vista")
local brilho = require("./lib/brilho")

local D = tern.plugin.data
local EH_REAL = tern.plugin.id == "session-list"

local TICK_MS = 250
local MAX_POR_TICK = 20
local VELHO_MS = 60000
local LIMITE_LEITURA = 4 * 1024 * 1024

local function caminho(nome: string): string
	return D .. "/" .. nome
end

local function pastaDe(nome: string): string?
	return string.match(nome, "^(.*)/[^/]*$")
end

local function garantePasta(pasta: string)
	if not tern.fs.exists(caminho(pasta)) then
		tern.fs.mkdir(caminho(pasta))
	end
end

-- The real store over tern.fs, rooted at the data folder. Names are relative
-- ("listas/l_x.json"). Writes are whole and synchronous; no process, no rename.
local store = {}

function store.list(): { string }
	local nomes = {}
	if tern.fs.exists(caminho("listas")) then
		for _, n in tern.fs.list(caminho("listas")) do
			table.insert(nomes, "listas/" .. n)
		end
	end
	return nomes
end

function store.read(nome: string): string?
	if not tern.fs.exists(caminho(nome)) then
		return nil
	end
	return tern.fs.read(caminho(nome), LIMITE_LEITURA)
end

function store.write(nome: string, texto: string)
	local pasta = pastaDe(nome)
	if pasta then
		garantePasta(pasta)
	end
	tern.fs.write(caminho(nome), texto)
end

function store.remove(nome: string)
	if tern.fs.exists(caminho(nome)) then
		tern.fs.remove(caminho(nome))
	end
end

function store.move(nome: string, paraPasta: string)
	local texto = store.read(nome)
	if texto == nil then
		return
	end
	local base = string.match(nome, "([^/]*)$") or nome
	store.write(paraPasta .. "/" .. base, texto)
	store.remove(nome)
end

-- `os.date` gives "-0300"; the list files use "-03:00".
local function agora(): string
	local s = os.date("%Y-%m-%dT%H:%M:%S%z")
	return (string.gsub(s, "([+-]%d%d)(%d%d)$", "%1:%2"))
end

math.randomseed(math.floor(os.time() + tern.now()))
local ALFABETO = "abcdefghijklmnopqrstuvwxyz0123456789"
local function novoId(): string
	local cs = {}
	for k = 1, 8 do
		local i = math.random(1, #ALFABETO)
		cs[k] = string.sub(ALFABETO, i, i)
	end
	return "l_" .. table.concat(cs)
end

local N = nucleo.novo(store, { json = tern.json, agora = agora, novoId = novoId })

-- kv values the host reads on every request.
local function kv(chave: string)
	local ok, v = pcall(tern.kv.get, chave)
	if ok then
		return v
	end
	return nil
end

-- Blocks following each pane, so a tick can re-render them.
local blocosPorPane: { [number]: { any } } = {}

local function renderiza(pane: number)
	local lista = blocosPorPane[pane]
	if lista == nil then
		return
	end
	local vivos = {}
	for _, cx in lista do
		if pcall(function()
			cx:render()
		end) then
			table.insert(vivos, cx)
		end
	end
	blocosPorPane[pane] = if #vivos > 0 then vivos else nil
end

local function renderizaTodos()
	local panes = {}
	for pane in blocosPorPane do
		table.insert(panes, pane)
	end
	for _, pane in panes do
		renderiza(pane)
	end
end

-- What the pane's list looks like, to tell a change and a first item. The
-- signature compares content (vista.assinatura), not `atualizada`: two changes
-- in the same second (block then doing) must still redraw.
local function retrato(pane: number)
	local ok, lista = pcall(N.daPane, pane)
	if not ok or lista == nil then
		return { id = nil, assinatura = "", itens = 0 }
	end
	return { id = lista.id, assinatura = vista.assinatura(lista), itens = #lista.itens }
end

local function chaveAbrir(pane: number): string
	return "abrir:" .. string.format("%d", pane)
end

-- Spawn / exit queue, filled by the event hooks (spawn waits at most 50 ms),
-- applied by the tick.
local fila: { number } = {}

local function aplicaFila(): boolean
	local mudou = false
	local agoraFila = fila
	fila = {}
	for _, pane in agoraFila do
		local ok, r = pcall(N.orfaniza, pane)
		if not ok then
			tern.log.warn("session-list: orfaniza failed", pane, r)
		elseif #r.orfanizadas > 0 or #r.apagadas > 0 then
			mudou = true
		end
	end
	return mudou
end

local function panesVivos(): { number }
	local ids = {}
	for _, info in tern.pane.list() do
		table.insert(ids, info.pane)
	end
	return ids
end

local function orfanizaAusentes(): boolean
	local ok, r = pcall(function()
		return N.orfanizaAusentes(panesVivos())
	end)
	if not ok then
		tern.log.warn("session-list: orfanizaAusentes failed", r)
		return false
	end
	return #r.orfanizadas > 0 or #r.apagadas > 0
end

-- One request, in the protocol's host order: read -> delete .req -> apply ->
-- write .res -> write .done. Returns true when the request was consumed.
local function atende(base: string): boolean
	local nomeReq = "pedidos/" .. base .. ".req"
	local okLe, texto = pcall(tern.fs.read, caminho(nomeReq), LIMITE_LEITURA)
	local pedido = nil
	if okLe then
		pedido = pedidos.parse(texto)
		if pedido.incompleto then
			return false -- still being written; next tick (swept after 60 s)
		end
	end
	pcall(tern.fs.remove, caminho(nomeReq))

	local idioma = textos.idiomaDe(kv("idioma"))
	local t = textos.textos(idioma)
	local res
	if not okLe then
		tern.log.warn("session-list: unreadable request", base, texto)
		res = { status = "error", texto = "session-list: the request could not be read." }
	elseif pedido.erro then
		res = { status = "error", texto = "session-list: unsupported request version." }
	else
		local pane = pedido.pane
		local antes = if type(pane) == "number" then retrato(pane) else nil
		local okEx, r = pcall(pedidos.executa, pedido, N, t, {
			maxLembretes = tonumber(kv("max_lembretes")) or 1,
			json = tern.json,
		})
		if okEx then
			res = r
		else
			tern.log.warn("session-list: request failed", base, r)
			res = { status = "error", texto = "session-list: internal error: " .. tostring(r) }
		end
		if antes ~= nil then
			local depois = retrato(pane)
			if depois.id ~= antes.id or depois.assinatura ~= antes.assinatura or depois.itens ~= antes.itens then
				if depois.itens > 0 and (antes.id == nil or antes.itens == 0 or depois.id ~= antes.id) then
					pcall(tern.kv.set, chaveAbrir(pane), depois.id)
				end
				renderiza(pane)
			end
			-- adopt/discard also change the orphan offer every other block shows
			if res.status == "ok" and (pedido.verb == "adopt" or pedido.verb == "discard") then
				renderizaTodos()
			end
		end
	end

	local okEs, erro = pcall(function()
		garantePasta("respostas")
		tern.fs.write(caminho("respostas/" .. base .. ".res"), pedidos.respostaArquivo(res))
		tern.fs.write(caminho("respostas/" .. base .. ".done"), "")
	end)
	if not okEs then
		tern.log.warn("session-list: could not write the answer", base, erro)
	end
	return true
end

local function atendePedidos(): boolean
	if not tern.fs.exists(caminho("pedidos")) then
		return false
	end
	local feitos = 0
	for _, nome in tern.fs.list(caminho("pedidos")) do
		if feitos >= MAX_POR_TICK then
			break
		end
		local base = string.match(nome, "^(.+)%.req$")
		if base then
			local ok, consumido = pcall(atende, base)
			if not ok then
				tern.log.warn("session-list: request loop error", nome, consumido)
			elseif consumido then
				feitos += 1
			end
		end
	end
	return feitos > 0
end

-- Stale sweep: anything in pedidos/ or respostas/ seen for more than 60 s
-- (monotonic clock) is deleted. No wall clock needed.
local primeiraVez: { [string]: number } = {}

local function varreVelhos()
	local agoraMs = tern.now()
	local vistos = {}
	for _, pasta in { "pedidos", "respostas" } do
		if tern.fs.exists(caminho(pasta)) then
			for _, n in tern.fs.list(caminho(pasta)) do
				local nome = pasta .. "/" .. n
				vistos[nome] = true
				local desde = primeiraVez[nome]
				if desde == nil then
					primeiraVez[nome] = agoraMs
				elseif agoraMs - desde > VELHO_MS then
					pcall(tern.fs.remove, caminho(nome))
					primeiraVez[nome] = nil
				end
			end
		end
	end
	for nome in primeiraVez do
		if not vistos[nome] then
			primeiraVez[nome] = nil
		end
	end
end

local contador = 0
local idiomaVisto = kv("idioma")

local function tick()
	contador += 1
	local ok, erro = pcall(function()
		local orfasMudaram = aplicaFila()
		atendePedidos()
		if contador % 4 == 0 then
			if orfanizaAusentes() then
				orfasMudaram = true
			end
			varreVelhos()
		end
		local idioma = kv("idioma")
		if idioma ~= idiomaVisto then
			idiomaVisto = idioma
			orfasMudaram = true -- the blocks speak the new language
		end
		if orfasMudaram then
			renderizaTodos()
		end
	end)
	if not ok then
		tern.log.warn("session-list: tick failed", erro)
	end
	tern.timer(TICK_MS, tick)
end

tern.on("pane_exited", function(ev)
	local pane = tonumber(ev and ev.pane)
	if pane then
		table.insert(fila, pane)
	end
end)

tern.on("spawn", function(spec)
	local pane = tonumber(spec and spec.env and spec.env.TERN_PANE)
	if pane then
		table.insert(fila, pane)
	end
	if EH_REAL then
		spec.env.SESSION_LIST_DATA = D
		return spec
	end
	return nil
end)

-- The block beside a pane: that pane's list as Tern's native todo card, and
-- the lists closed tabs left offered on top. Its keys and clicks run here, in
-- the host VM, so they call nucleo directly (one writer: no request files).
local function textosAgora()
	return textos.textos(textos.idiomaDe(kv("idioma")))
end

local function segue(state): number
	return state.segue
end

-- The item of the followed pane's list with that id, or nil.
local function itemDe(pane: number, id: string)
	local ok, lista = pcall(N.daPane, pane)
	if not ok or lista == nil then
		return nil
	end
	for _, i in lista.itens do
		if i.id == id then
			return i
		end
	end
	return nil
end

-- Toasts a refused change: puxa/descarta give `motivo`, the rest `codigo`.
local function recusa(cx, t, r, id: string)
	local texto
	if r.motivo and t.recusa[r.motivo] then
		texto = t.recusa[r.motivo](id)
	elseif r.codigo and t.erro[r.codigo] then
		texto = t.erro[r.codigo]
	else
		texto = tostring(r.motivo or r.codigo or "?")
	end
	pcall(function()
		cx:toast("error", texto)
	end)
end

-- Applies one change the person asked for in the block (a key or a button).
-- Returns true when something changed (already re-rendered).
local function aplica(state, acao: string, valor: string, cx): boolean
	local pane = segue(state)
	local t = textosAgora()
	local ok, r
	if acao == "toggle" then
		local item = itemDe(pane, valor)
		if item == nil then
			return false
		end
		if item.estado == "feito" then
			ok, r = pcall(N.desrisca, pane, { valor })
		else
			ok, r = pcall(N.risca, pane, { valor })
		end
	elseif acao == "doing" then
		local item = itemDe(pane, valor)
		if item == nil then
			return false
		end
		if item.estado == "fazendo" then
			ok, r = pcall(N.desrisca, pane, { valor }) -- d again: back to open
		elseif N.faz then
			ok, r = pcall(N.faz, pane, valor)
		else
			return false
		end
	elseif acao == "remove" then
		ok, r = pcall(N.tira, pane, { valor }, { pelaPessoa = true })
	elseif acao == "adopt" then
		ok, r = pcall(N.puxa, pane, valor)
	elseif acao == "discard" then
		ok, r = pcall(N.descarta, pane, valor)
	else
		return false
	end
	if not ok then
		tern.log.warn("session-list: block action failed", acao, valor, r)
		return false
	end
	if not r.ok then
		recusa(cx, t, r, valor)
		return false
	end
	if acao == "adopt" or acao == "discard" then
		renderizaTodos() -- the orphan offer changed for every block
	else
		renderiza(pane)
	end
	return true
end

-- Keys (checklist rows emit no clicks, measured): up/down (k/j) move the
-- selection, space/enter tick or untick, d marks in progress (again: back to
-- open), x/backspace/delete remove (by the person).
local TECLA = {
	space = "toggle", enter = "toggle", d = "doing",
	x = "remove", backspace = "remove", delete = "remove",
}

tern.block.define("list", {
	init = function(cx, args, saved)
		local pane = tonumber(args and args[1]) or (type(saved) == "table" and tonumber(saved.segue)) or cx.pane
		local lista = blocosPorPane[pane] or {}
		table.insert(lista, cx)
		blocosPorPane[pane] = lista
		return { segue = pane, sel = 1 }
	end,
	view = function(state, cx)
		local t = textosAgora()
		local okL, lista = pcall(N.daPane, segue(state))
		if not okL then
			lista = nil
		end
		-- A part newly done lights the ring for brilho.DURACAO_MS; a newer done
		-- restarts the clock (the generation tells the timers apart).
		local acende
		acende, state.visto = brilho.decide(state.visto, lista)
		if acende then
			state.geracao = (state.geracao or 0) + 1
			state.brilho = true
			local geracao = state.geracao
			tern.timer(brilho.DURACAO_MS, function()
				if state.geracao == geracao then
					state.brilho = false
					pcall(function()
						cx:render()
					end)
				end
			end)
		end
		local okO, o = pcall(N.orfas)
		return vista.desenha({
			lista = lista,
			orfas = if okO then o.orfas else {},
			ilegiveis = if okO then o.ilegiveis else {},
			sel = state.sel,
			brilho = state.brilho == true,
		}, tern.ui, t)
	end,
	title = function(state)
		local ok, lista = pcall(N.daPane, segue(state))
		if ok and lista ~= nil and lista.assunto ~= "" then
			return lista.assunto
		end
		return textosAgora().tituloPainel
	end,
	key = function(state, k, cx)
		if k.ctrl or k.alt or k.meta then
			return false
		end
		local ok, lista = pcall(N.daPane, segue(state))
		local itens = if ok and lista ~= nil then lista.itens else {}
		local s = vista.selecao(state.sel, #itens)
		if s == nil then
			return false
		end
		local nome = k.name
		if nome == "up" or nome == "k" then
			state.sel = math.max(1, s - 1)
			return state.sel ~= s
		elseif nome == "down" or nome == "j" then
			state.sel = math.min(#itens, s + 1)
			return state.sel ~= s
		end
		local acao = TECLA[nome]
		if acao == nil then
			return false
		end
		state.sel = s
		local mudou = aplica(state, acao, itens[s].id, cx)
		return if mudou then true else false
	end,
	event = function(state, ev, cx)
		if ev.ev ~= "action" then
			return
		end
		local acao, valor = ev.act, ev.value
		if type(acao) == "string" and valor == nil then
			-- a TSP event sent by name (cx.session:event) arrives unsplit
			local a, v = string.match(acao, "^([^=]+)=(.*)$")
			if a then
				acao, valor = a, v
			end
		end
		if type(acao) ~= "string" or type(valor) ~= "string" then
			return
		end
		aplica(state, acao, valor, cx)
	end,
	save = function(state)
		return { segue = state.segue }
	end,
})

-- Start: protocol folders exist, and lists of panes gone while the host was
-- down become orphans.
pcall(garantePasta, "pedidos")
pcall(garantePasta, "respostas")
orfanizaAusentes()
tern.timer(TICK_MS, tick)

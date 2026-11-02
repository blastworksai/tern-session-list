-- Window half of the Tern session-list plugin (one per Tern window).
-- Opens the list block beside a pane once per list: the host sets kv
-- `abrir:<pane>` when a pane gets its first item (or a new list); the window
-- that holds that pane opens the block and clears the key. A block the person
-- closes stays closed until "show for this tab" or a new list in that pane.
-- Never writes lists or answers (the host is the only writer).

local textos = require("./lib/textos")
local lembrete = require("./lib/lembrete")

local KIND = tern.plugin.id .. ".list"
local LOOP_MS = 1000
local D = tern.plugin.data
local ESPERA_AGENTE_MS = 500
local SONDA_MS = 100
local PRAZO_MS = 5000
local LIMITE_RESPOSTA = 1024 * 1024

math.randomseed(math.floor(tern.now() * 1000) + os.time())

local function kv(chave: string)
	local ok, v = pcall(tern.kv.get, chave)
	if ok then
		return v
	end
	return nil
end

local function chaveAbrir(pane: number): string
	return "abrir:" .. string.format("%d", pane)
end

local function abreBloco(cx, pane: number)
	return cx:new_block(KIND, { string.format("%d", pane) }, "beside", {
		target = pane,
		dir = "right",
		ratio = 0.25,
		focus = false,
	})
end

-- Only this window's panes are read, so two windows never touch the same key.
local function abreOsPendentes(cx)
	local sozinho = kv("abrir_sozinho") ~= false
	for _, info in cx.session:panes() do
		local chave = chaveAbrir(info.pane)
		if kv(chave) ~= nil then
			if sozinho then
				local ok, erro = pcall(abreBloco, cx, info.pane)
				if not ok then
					tern.log.warn("session-list: could not open the block", info.pane, erro)
				end
			end
			-- cleared either way: with the switch off, nothing piles up to
			-- open later when it is turned back on
			pcall(tern.kv.set, chave, nil)
		end
	end
end

local function laco(cx)
	if cx ~= nil then
		local ok, erro = pcall(abreOsPendentes, cx)
		if not ok then
			tern.log.warn("session-list: open loop failed", erro)
		end
	end
	tern.timer(LOOP_MS, laco)
end

tern.timer(LOOP_MS, laco)

-- Agent-block stop reminder: when an agent block's turn ends "done" and the
-- agent is idle, ask the host `check` for that pane through one request file
-- (one tern.fs.write; `end=1` makes a half-written file harmless) and, on
-- `status=remind`, send the text to the agent. The host counts and caps
-- (max_lembretes), so the window holds no state. Never blocks: the answer is
-- polled on re-armed timers.

local function apaga(nome: string)
	pcall(tern.fs.remove, D .. "/" .. nome)
end

-- `cx` is the fresh one each timer receives (the event's is gone by now).
local function aguardaResposta(cx, base: string, pane: number, inicio: number)
	local feito = "respostas/" .. base .. ".done"
	local okEx, existe = pcall(tern.fs.exists, D .. "/" .. feito)
	if cx == nil or not (okEx and existe) then
		if tern.now() - inicio > PRAZO_MS then
			-- no answer: withdraw the request so a late host never counts it
			apaga("pedidos/" .. base .. ".req")
			apaga("respostas/" .. base .. ".res")
			apaga(feito)
			tern.log.warn("session-list: no answer to the reminder check", pane)
			return
		end
		tern.timer(SONDA_MS, function(cx2)
			aguardaResposta(cx2, base, pane, inicio)
		end)
		return
	end
	local okLe, texto = pcall(tern.fs.read, D .. "/respostas/" .. base .. ".res", LIMITE_RESPOSTA)
	apaga("respostas/" .. base .. ".res")
	apaga(feito)
	if not okLe then
		tern.log.warn("session-list: unreadable reminder answer", pane, texto)
		return
	end
	local r = lembrete.resposta(texto)
	if r ~= nil and r.status == "remind" and r.texto ~= "" then
		local ok, erro = pcall(function()
			cx.agents:ask(pane, r.texto)
		end)
		if not ok then
			tern.log.warn("session-list: could not remind the agent", pane, erro)
		end
	elseif r ~= nil and r.status == "error" then
		tern.log.warn("session-list: reminder check failed", pane, r.texto)
	end
end

local function pedeConferencia(cx, pane: number)
	local okL, agentes = pcall(function()
		return cx.agents:list()
	end)
	if not okL or not lembrete.deveLembrar(agentes, pane) then
		return
	end
	local base = lembrete.nome(tern.now(), lembrete.hex8(math.random))
	local ok, erro = pcall(function()
		if not tern.fs.exists(D .. "/pedidos") then
			tern.fs.mkdir(D .. "/pedidos")
		end
		tern.fs.write(D .. "/pedidos/" .. base .. ".req", lembrete.pedido(pane))
	end)
	if not ok then
		tern.log.warn("session-list: could not write the reminder check", pane, erro)
		return
	end
	local inicio = tern.now()
	tern.timer(SONDA_MS, function(cx2)
		aguardaResposta(cx2, base, pane, inicio)
	end)
end

tern.on("agent_finished", function(ev, cx)
	if not lembrete.comeca(ev) or cx == nil then
		return
	end
	-- only the window that holds that pane
	local okP, info = pcall(function()
		return cx.session:pane(ev.pane)
	end)
	if not okP or info == nil then
		return
	end
	local pane = ev.pane
	tern.timer(ESPERA_AGENTE_MS, function(cx2)
		if cx2 == nil then
			return
		end
		local ok, erro = pcall(pedeConferencia, cx2, pane)
		if not ok then
			tern.log.warn("session-list: reminder failed", pane, erro)
		end
	end)
end)

local t = textos.textos(textos.idiomaDe(kv("idioma")))

tern.command({
	id = "show",
	title = t.mostrarAqui,
	icon = "list",
	run = function(cx)
		local pane = cx.session:focused()
		if pane == nil then
			return
		end
		local info = cx.session:pane(pane)
		if info ~= nil and info.block == KIND then
			return -- the focused pane is a list block already
		end
		abreBloco(cx, pane)
	end,
})

tern.command({
	id = "language",
	title = t.idioma,
	icon = "list",
	run = function(cx)
		cx:pick({
			items = {
				{ label = "English", idioma = "en" },
				{ label = "Português (Brasil)", idioma = "pt-BR" },
			},
			placeholder = t.idioma,
		}):next(function(item)
			if item ~= nil then
				tern.kv.set("idioma", item.idioma)
			end
		end)
	end,
})

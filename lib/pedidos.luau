-- The request protocol of the Tern session-list plugin: pure, no `tern` global.
-- Parses one request file (THE REQUEST PROTOCOL in the plan), runs its verb
-- against a nucleo instance and renders the answer the command prints.
-- Mirrors WS/src/lista-da-sessao/hooks/ferramenta.ts (descreveMinha,
-- descreveOrfas, aoChamarLista, contextoInicial).
--
--   pedidos.parse(text)       -> pedido | {erro = "versao"} | {incompleto = true}
--     pedido = { v, pane: number?, verb: string?, args = {string}, subject: string?,
--                again: bool, noorphans: bool, stopinput: string? }
--   pedidos.executa(pedido, N, t, opts) -> { status = "ok"|"error"|"remind", texto }
--     N = nucleo.novo(...), t = textos.textos(idioma),
--     opts = { maxLembretes = number?, json = {decode} }
--   pedidos.renderLista(lista, orfas, t, ilegiveis?) -> string
--   pedidos.contextoInicial(lista, orfas, t)         -> string ("" when nothing)
--   pedidos.respostaArquivo(res)                     -> "status=<s>\n<texto>"

local nucleo = require("./nucleo")

local pedidos = {}

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function pedidos.parse(text: string)
	local linhas = {}
	for linha in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(linhas, (string.gsub(linha, "\r$", "")))
	end
	-- the last non-empty line must be `end=1` (a request still being written is not)
	local ultima = nil
	for k = #linhas, 1, -1 do
		if linhas[k] ~= "" then
			ultima = linhas[k]
			break
		end
	end
	if ultima ~= "end=1" then
		return { incompleto = true }
	end
	local p = { args = {}, again = false, noorphans = false }
	local v = nil
	for _, linha in linhas do
		local k, valor = string.match(linha, "^([^=]*)=(.*)$")
		if k == "v" then
			v = valor
		elseif k == "pane" then
			p.pane = tonumber(valor)
		elseif k == "verb" then
			p.verb = valor
		elseif k == "arg" then
			table.insert(p.args, valor)
		elseif k == "subject" then
			p.subject = valor
		elseif k == "again" then
			p.again = valor == "1"
		elseif k == "noorphans" then
			p.noorphans = valor == "1"
		elseif k == "stopinput" then
			p.stopinput = valor
		end
	end
	if v ~= "1" then
		return { erro = "versao" }
	end
	p.v = v
	return p
end

-- One line per item, as descreveMinha: in progress, open, blocked, done.
local function descreveMinha(lista, t): string
	if lista == nil or #lista.itens == 0 then
		return t.listaVazia
	end
	local linhas = { t.cabecalhoLista(lista.assunto) }
	for _, i in lista.itens do
		if i.estado == "fazendo" then
			table.insert(linhas, `▶ {i.id} {i.texto} ({t.fazendo})`)
		end
	end
	for _, i in lista.itens do
		if i.estado == "aberto" then
			table.insert(linhas, `☐ {i.id} {i.texto}`)
		end
	end
	for _, i in lista.itens do
		if i.estado == "travado" then
			table.insert(linhas, `⊘ {i.id} {i.texto} ({t.travadoPor(i.motivo or "")})`)
		end
	end
	for _, i in lista.itens do
		if i.estado == "feito" then
			table.insert(linhas, `☑ {i.id} {i.texto} ({t.feito})`)
		end
	end
	return table.concat(linhas, "\n")
end

local function textosPendentes(lista): { string }
	local r = {}
	for _, i in nucleo.pendentes(lista) do
		table.insert(r, i.texto)
	end
	return r
end

function pedidos.renderLista(lista, orfas, t, ilegiveis): string
	local linhas = { descreveMinha(lista, t) }
	if orfas ~= nil and #orfas > 0 then
		table.insert(linhas, t.orfasCabecalho)
		for _, o in orfas do
			local assunto = if o.assunto == "" then "" else ` ({o.assunto})`
			table.insert(linhas, `- {o.id}{assunto}: {table.concat(textosPendentes(o), "; ")}`)
		end
	end
	for _, nome in ilegiveis or {} do
		table.insert(linhas, t.ilegivelModelo(nome))
	end
	return table.concat(linhas, "\n")
end

function pedidos.contextoInicial(lista, orfas, t): string
	local partes = {}
	for _, o in orfas or {} do
		table.insert(partes, t.orfaParaModelo({ id = o.id, itens = textosPendentes(o) }))
	end
	if lista ~= nil and #nucleo.pendentes(lista) > 0 then
		table.insert(partes, t.abertoNestaAba(descreveMinha(lista, t)))
	end
	return table.concat(partes, "\n\n")
end

function pedidos.respostaArquivo(res): string
	return "status=" .. res.status .. "\n" .. res.texto
end

-- notice lines from a nucleo result (naoAchei + avisos)
local function avisosDe(r, t): { string }
	local linhas = {}
	if r.naoAchei and #r.naoAchei > 0 then
		table.insert(linhas, t.naoAchei(table.concat(r.naoAchei, ", ")))
	end
	for _, a in r.avisos or {} do
		local f = t.aviso[a.codigo]
		if f then
			table.insert(linhas, f(a.id or a.texto))
		end
	end
	return linhas
end

local function decodeStop(json, s: string)
	local ok, x = pcall(json.decode, s)
	if ok and type(x) == "table" then
		return x
	end
	-- the command escaped raw newlines as \n, which is not valid between tokens
	ok, x = pcall(json.decode, (string.gsub(s, "\\n", " ")))
	if ok and type(x) == "table" then
		return x
	end
	return nil
end

local function check(p, N, t, opts)
	if p.stopinput ~= nil and opts.json ~= nil then
		local x = decodeStop(opts.json, p.stopinput)
		if x ~= nil then
			if x.stop_hook_active == true then
				return { status = "ok", texto = "" }
			end
			if type(x.last_assistant_message) == "string"
				and string.sub(trim(x.last_assistant_message), -1) == "?" then
				return { status = "ok", texto = "" }
			end
		end
	end
	local c = N.confere(p.pane, opts.maxLembretes)
	if not c.lembrar then
		return { status = "ok", texto = "" }
	end
	local itens = {}
	for _, i in c.itens do
		table.insert(itens, `{i.id} {i.texto}`)
	end
	return { status = "remind", texto = t.lembrete(#itens, itens) }
end

local VERBOS = {
	add = true, done = true, undo = true, remove = true, name = true, block = true,
	unblock = true, doing = true, show = true, adopt = true, discard = true, start = true,
	check = true, help = true,
}

function pedidos.executa(p, N, t, opts)
	opts = opts or {}
	if p.verb == nil or not VERBOS[p.verb] then
		return { status = "error", texto = t.erro["verbo-invalido"] }
	end
	if p.verb == "help" then
		return { status = "ok", texto = t.ajuda }
	end
	if type(p.pane) ~= "number" then
		return { status = "error", texto = t.erro["sem-pane"] }
	end
	local pane, args = p.pane, p.args or {}

	if p.verb == "check" then
		return check(p, N, t, opts)
	end
	if p.verb == "start" then
		local ini = N.inicio(pane)
		local orfas = if p.noorphans then {} else ini.orfas
		return { status = "ok", texto = pedidos.contextoInicial(ini.lista, orfas, t) }
	end

	local avisos, status = {}, "ok"
	local r = nil
	local v = p.verb
	if v == "add" then
		r = N.anota(pane, args, { assunto = p.subject, denovo = p.again })
		if r.ok == false and r.codigo == "tirado-pela-pessoa" then
			for _, texto in r.recusados do
				table.insert(avisos, t.tiradoPelaPessoa(texto))
			end
			status = "error"
			r = nil
		end
	elseif v == "done" then
		r = N.risca(pane, args)
	elseif v == "undo" then
		r = N.desrisca(pane, args)
	elseif v == "remove" then
		r = N.tira(pane, args)
	elseif v == "name" then
		r = N.nomeia(pane, table.concat(args, " "))
	elseif v == "block" then
		r = N.trava(pane, args[1], table.concat(args, " ", 2))
	elseif v == "unblock" then
		r = N.destrava(pane, args[1])
	elseif v == "doing" then
		r = N.faz(pane, args[1])
	elseif v == "adopt" or v == "discard" then
		local id = args[1]
		if id == nil or trim(id) == "" then
			table.insert(avisos, t.erro["sem-id"])
			status = "error"
		elseif v == "adopt" then
			local x = N.puxa(pane, id)
			table.insert(avisos, if x.ok then t.puxei(id) else t.naoPuxei(x.motivo))
			status = if x.ok then "ok" else "error"
		else
			local x = N.descarta(pane, id)
			table.insert(avisos, if x.ok then t.descartei(id) else t.naoDescartei(x.motivo))
			status = if x.ok then "ok" else "error"
		end
	end
	if r ~= nil then
		if r.ok == false then
			table.insert(avisos, t.erro[r.codigo] or r.codigo)
			status = "error"
		else
			for _, l in avisosDe(r, t) do
				table.insert(avisos, l)
			end
		end
	end

	local o = N.orfas(pane)
	local orfas = if p.noorphans then {} else o.orfas
	local estado = pedidos.renderLista(N.daPane(pane), orfas, t, o.ilegiveis)
	local texto = if #avisos == 0 then estado else table.concat(avisos, "\n") .. "\n\n" .. estado
	return { status = status, texto = texto }
end

return pedidos

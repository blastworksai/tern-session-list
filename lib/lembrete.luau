-- The agent-block stop reminder's pure parts (no `tern` global), used by
-- window.luau: when an agent block's turn ends, the window asks the host
-- `check` for that pane through one request file and, on `status=remind`,
-- sends the text to the agent.
--
--   lembrete.comeca(ev)                 -> boolean  (an agent_finished worth checking)
--   lembrete.deveLembrar(agentes, pane) -> boolean  (that pane's agent is `idle`)
--   lembrete.nome(agoraMs, hex8)        -> "<ms digits>-0-<hex8>"
--   lembrete.hex8(rand)                 -> 8 lowercase hex digits (rand(0, 255) per byte)
--   lembrete.pedido(pane)               -> the request file's text (ends with end=1)
--   lembrete.resposta(texto)            -> { status, texto } | nil (unreadable)

local lembrete = {}

function lembrete.comeca(ev): boolean
	return type(ev) == "table" and ev.result == "done" and type(ev.pane) == "number"
end

-- Only `idle`: `waiting_input` means the agent asked something and waits for
-- the person, so a reminder would talk over the question.
function lembrete.deveLembrar(agentes, pane: number): boolean
	if type(agentes) ~= "table" then
		return false
	end
	for _, a in agentes do
		if type(a) == "table" and a.pane == pane then
			return a.state == "idle"
		end
	end
	return false
end

-- `0` stands where the command puts its pid: the window has none.
function lembrete.nome(agoraMs: number, hex8: string): string
	return string.format("%d", math.floor(agoraMs)) .. "-0-" .. hex8
end

function lembrete.hex8(rand: (number, number) -> number): string
	local partes = {}
	for _ = 1, 4 do
		table.insert(partes, string.format("%02x", rand(0, 255)))
	end
	return table.concat(partes)
end

function lembrete.pedido(pane: number): string
	return "v=1\npane=" .. string.format("%d", pane) .. "\nverb=check\nend=1\n"
end

-- The answer file is "status=<s>\n<texto>" (pedidos.respostaArquivo).
function lembrete.resposta(texto: string)
	local status, resto = string.match(texto, "^status=([%a]+)\r?\n(.*)$")
	if status == nil then
		status = string.match(texto, "^status=([%a]+)\r?$")
		resto = ""
	end
	if status ~= "ok" and status ~= "error" and status ~= "remind" then
		return nil
	end
	return { status = status, texto = resto }
end

return lembrete

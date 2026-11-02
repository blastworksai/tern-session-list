-- Tests for lib/lembrete.luau: the agent-block reminder's request text (parsed
-- back by the host's own parser), its name, the answer parser (against the
-- host's own answer writer) and the "should remind" decision.

local lembrete = require("../lib/lembrete")
local pedidos = require("../lib/pedidos")

local testes = {}
local function teste(nome: string, fn: () -> ())
	table.insert(testes, { nome, fn })
end

local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
	end
end

teste("only a finished turn that is done starts a check", function()
	eq(lembrete.comeca({ pane = 5, result = "done" }), true)
	eq(lembrete.comeca({ pane = 5, result = "failed" }), false)
	eq(lembrete.comeca({ pane = 5, result = "exited" }), false)
	eq(lembrete.comeca({ pane = 5, result = "closed" }), false)
	eq(lembrete.comeca({ result = "done" }), false, "no pane")
	eq(lembrete.comeca(nil), false)
end)

teste("reminds only when that pane's agent is idle", function()
	local agentes = {
		{ pane = 1, state = "working" },
		{ pane = 133143986179, state = "idle" },
		{ pane = 3, state = "waiting_input" },
	}
	eq(lembrete.deveLembrar(agentes, 133143986179), true)
	eq(lembrete.deveLembrar(agentes, 3), false, "waiting_input")
	eq(lembrete.deveLembrar(agentes, 1), false, "working")
	eq(lembrete.deveLembrar({ { pane = 9, state = "exited" } }, 9), false, "exited")
	eq(lembrete.deveLembrar(agentes, 42), false, "pane not listed")
	eq(lembrete.deveLembrar({}, 1), false, "empty list")
	eq(lembrete.deveLembrar(nil, 1), false, "no list")
end)

teste("the request is a check for that pane, ending with end=1, as the host parses it", function()
	local texto = lembrete.pedido(133143986179)
	eq(texto, "v=1\npane=133143986179\nverb=check\nend=1\n")
	local p = pedidos.parse(texto)
	eq(p.incompleto, nil, "complete")
	eq(p.erro, nil, "version accepted")
	eq(p.pane, 133143986179)
	eq(p.verb, "check")
	eq(p.stopinput, nil, "no hook input")
	-- a half-written copy is left alone by the host
	eq(pedidos.parse(string.sub(texto, 1, #texto - 6)).incompleto, true)
end)

teste("the request name: monotonic ms digits, 0 for the pid, 8 hex", function()
	eq(lembrete.nome(12345.678, "0a1b2c3d"), "12345-0-0a1b2c3d")
	local feitos = { 0, 255, 16, 171 }
	local k = 0
	local hex = lembrete.hex8(function(a, b)
		eq(a, 0)
		eq(b, 255)
		k += 1
		return feitos[k]
	end)
	eq(hex, "00ff10ab")
	local nome = lembrete.nome(987654321.5, hex)
	eq(string.match(nome .. ".req", "^(.+)%.req$"), nome, "the host's name match")
	eq(string.match(nome, "^%d+%-0%-%x%x%x%x%x%x%x%x$") ~= nil, true)
end)

teste("the answer parser reads what the host writes", function()
	local r = lembrete.resposta(pedidos.respostaArquivo({ status = "remind", texto = "line 1\nline 2" }))
	eq(r.status, "remind")
	eq(r.texto, "line 1\nline 2")
	r = lembrete.resposta(pedidos.respostaArquivo({ status = "ok", texto = "" }))
	eq(r.status, "ok")
	eq(r.texto, "")
	r = lembrete.resposta("status=error\nboom")
	eq(r.status, "error")
	eq(r.texto, "boom")
	eq(lembrete.resposta("status=ok").status, "ok", "no newline")
	eq(lembrete.resposta("status=ok\r\nx").texto, "x", "CRLF")
	eq(lembrete.resposta(""), nil, "empty")
	eq(lembrete.resposta("garbage\nstatus=remind\nx"), nil, "status not first")
	eq(lembrete.resposta("status=maybe\nx"), nil, "unknown status")
end)

return testes

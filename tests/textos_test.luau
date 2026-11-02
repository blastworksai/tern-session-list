-- Tests for lib/textos.luau: both languages carry exactly the same keys, every
-- function answers a non-empty string, the language fallback, the help screen
-- and the rule text the plan fixes.

local T = require("../lib/textos")

local SUBTABELAS = { erro = true, motivo = true, recusa = true, aviso = true }

local KEYS = {
	"tituloPainel", "ficouDeAbaFechada", "eMais", "continuarAqui", "descartar",
	"nadaCombinado", "selecionar", "tirar", "ilegivel", "recusa", "motivo", "erro", "regra",
	"naoAchei", "puxei", "naoPuxei", "descartei", "naoDescartei", "listaVazia",
	"cabecalhoLista", "feito", "orfasCabecalho", "ilegivelModelo", "orfaParaModelo",
	"abertoNestaAba", "travado", "travadoPor", "jaTravado", "naoTravado", "jaFeito",
	"naoFeito", "tiradoPelaPessoa", "lembrete", "semResposta", "ajuda", "mostrarAqui",
	"abrirSozinho", "idioma", "aviso", "fazendo", "jaFazendo",
}

local SUBKEYS = {
	erro = { "sem-lista", "nada-pra-anotar", "assunto-vazio", "sem-pane", "verbo-invalido", "sem-id", "sem-motivo" },
	motivo = { "sumiu", "viva", "minha", "ilegivel" },
	recusa = { "sumiu", "viva", "minha", "ilegivel" },
	aviso = { "ja-feito", "nao-feito", "ja-travado", "nao-travado", "ja-fazendo", "tirado-pela-pessoa" },
}

local REGRA_EN = [[Session list: when you and the person agree on a piece of work in parts, note the parts right away with `session-list add "part 1" "part 2"`, not at the end. Mark the part you are working on with `session-list doing <id>`, and tick each part with `session-list done <id>` as soon as it is done; if a part waits on someone, `session-list block <id> <reason>`. The person can also ask "add this to the session list". This list is NOT the person's task list: never copy their tasks here, and never move items to another task list unless they ask.]]

local VERBOS = { "add", "done", "undo", "remove", "name", "block", "unblock", "doing", "show", "adopt", "discard", "start", "check", "help" }
local FLAGS = { "--subject", "--again", "--hook" }

-- Sample arguments per function key; a key with no entry is called with one string.
local AMOSTRAS = {
	eMais = { 3 },
	orfaParaModelo = { { id = "l_ab12cd34", itens = { "a", "b" } } },
	lembrete = { 2, { "a", "b" } },
	naoPuxei = { "viva" },
	naoDescartei = { "sumiu" },
}

local function chavesOrdenadas(t)
	local ks = {}
	for k in t do
		table.insert(ks, k)
	end
	table.sort(ks)
	return ks
end

local function mesmasChaves(a, b, onde)
	local ka, kb = chavesOrdenadas(a), chavesOrdenadas(b)
	assert(table.concat(ka, ",") == table.concat(kb, ","), `{onde}: keys differ\n en: {table.concat(ka, ",")}\n pt: {table.concat(kb, ",")}`)
	for k, v in a do
		if SUBTABELAS[k] and onde == "top" then
			assert(type(v) == "table" and type(b[k]) == "table", `{k} must be a table in both`)
			mesmasChaves(v, b[k], k)
		end
	end
end

local function exatas(t, esperadas, onde)
	local copia = table.clone(esperadas)
	table.sort(copia)
	local ks = chavesOrdenadas(t)
	assert(table.concat(ks, ",") == table.concat(copia, ","), `{onde}: expected {table.concat(copia, ",")}, got {table.concat(ks, ",")}`)
end

local function confereFuncoes(t, lang)
	for k, v in t do
		if type(v) == "function" then
			local args = AMOSTRAS[k] or { "x1" }
			local r = v(table.unpack(args))
			assert(type(r) == "string" and r ~= "", `{lang}.{k} returned an empty or non-string value`)
		elseif type(v) == "string" then
			assert(v ~= "", `{lang}.{k} is empty`)
		elseif type(v) == "table" then
			for sk, sv in v do
				if type(sv) == "function" then
					local r = sv("x1")
					assert(type(r) == "string" and r ~= "", `{lang}.{k}[{sk}] returned empty`)
				else
					assert(type(sv) == "string" and sv ~= "", `{lang}.{k}[{sk}] is empty or not a string`)
				end
			end
		else
			error(`{lang}.{k} has unexpected type {type(v)}`)
		end
	end
end

return {
	{
		name = "textos: IDIOMAS is en and pt-BR",
		fn = function()
			assert(#T.IDIOMAS == 2 and T.IDIOMAS[1] == "en" and T.IDIOMAS[2] == "pt-BR")
		end,
	},
	{
		name = "textos: both languages have exactly the same keys, recursively",
		fn = function()
			mesmasChaves(T.textos("en"), T.textos("pt-BR"), "top")
		end,
	},
	{
		name = "textos: the key set is exactly the plan's list",
		fn = function()
			for _, lang in T.IDIOMAS do
				local t = T.textos(lang)
				exatas(t, KEYS, lang)
				for sub, esperadas in SUBKEYS do
					exatas(t[sub], esperadas, `{lang}.{sub}`)
				end
			end
		end,
	},
	{
		name = "textos: every key answers a non-empty string",
		fn = function()
			for _, lang in T.IDIOMAS do
				confereFuncoes(T.textos(lang), lang)
			end
		end,
	},
	{
		name = "textos: aviso codes alias the named functions",
		fn = function()
			for _, lang in T.IDIOMAS do
				local t = T.textos(lang)
				assert(t.aviso["ja-feito"] == t.jaFeito)
				assert(t.aviso["nao-feito"] == t.naoFeito)
				assert(t.aviso["ja-travado"] == t.jaTravado)
				assert(t.aviso["nao-travado"] == t.naoTravado)
				assert(t.aviso["ja-fazendo"] == t.jaFazendo)
				assert(t.aviso["tirado-pela-pessoa"] == t.tiradoPelaPessoa)
			end
		end,
	},
	{
		name = "textos: idiomaDe falls back to en",
		fn = function()
			assert(T.idiomaDe("en") == "en")
			assert(T.idiomaDe("pt-BR") == "pt-BR")
			assert(T.idiomaDe(nil) == "en")
			assert(T.idiomaDe("") == "en")
			assert(T.idiomaDe("fr") == "en")
			assert(T.idiomaDe("pt-br") == "en")
			assert(T.idiomaDe(1) == "en")
			assert(T.textos("fr") == T.textos("en"))
			assert(T.textos("pt-BR").tituloPainel == "Lista da sessão")
		end,
	},
	{
		name = "textos: ajuda names every verb and flag",
		fn = function()
			for _, lang in T.IDIOMAS do
				local a = T.textos(lang).ajuda
				for _, v in VERBOS do
					assert(string.find(a, "session-list " .. v, 1, true), `{lang} ajuda misses verb {v}`)
				end
				for _, f in FLAGS do
					assert(string.find(a, f, 1, true), `{lang} ajuda misses flag {f}`)
				end
			end
		end,
	},
	{
		name = "textos: regra names doing in both languages; the in-progress word",
		fn = function()
			for _, lang in T.IDIOMAS do
				assert(string.find(T.textos(lang).regra, "`session-list doing <id>`", 1, true), `{lang} regra misses doing`)
			end
			assert(T.textos("en").fazendo == "in progress")
			assert(T.textos("pt-BR").fazendo == "fazendo agora")
		end,
	},
	{
		name = "textos: regra (en) is the plan's Task 4 text",
		fn = function()
			assert(T.textos("en").regra == REGRA_EN, "regra (en) differs from the plan")
		end,
	},
	{
		name = "textos: no text still points at the mod's tool",
		fn = function()
			for _, lang in T.IDIOMAS do
				local t = T.textos(lang)
				local tudo = {
					t.regra,
					t.orfaParaModelo({ id = "l_x", itens = { "a" } }),
					t.abertoNestaAba("L"),
					t.ajuda,
				}
				for _, s in tudo do
					assert(not string.find(s, "`lista`", 1, true), `{lang}: mentions the tool lista`)
					assert(not string.find(s, "acao ", 1, true), `{lang}: mentions acao`)
				end
			end
		end,
	},
	{
		name = "textos: orphan and reminder texts carry ids, counts and commands",
		fn = function()
			for _, lang in T.IDIOMAS do
				local t = T.textos(lang)
				local o = t.orfaParaModelo({ id = "l_ab12cd34", itens = { "alpha", "beta" } })
				assert(string.find(o, "session-list adopt l_ab12cd34", 1, true))
				assert(string.find(o, "session-list discard l_ab12cd34", 1, true))
				assert(string.find(o, "alpha; beta", 1, true))
				assert(string.find(o, "\n2. ", 1, true) and string.find(o, "\n3. ", 1, true))
				local r = t.lembrete(2, { "alpha", "beta" })
				assert(string.find(r, "2 ", 1, true) and string.find(r, "alpha; beta", 1, true))
				assert(string.find(r, "session-list done <id>", 1, true))
				assert(string.find(r, "session-list block <id>", 1, true))
			end
			assert(string.find(T.textos("en").lembrete(1, { "a" }), "1 open item on", 1, true))
		end,
	},
	{
		name = "textos: semResposta (en) is the protocol's timeout text",
		fn = function()
			assert(
				T.textos("en").semResposta
					== "Tern's session-list plugin did not answer: is Tern running with the plugin loaded? Run `tern plugin list`."
			)
			assert(T.textos("en").erro["sem-pane"] == "session-list only works inside a Tern pane.")
		end,
	},
}

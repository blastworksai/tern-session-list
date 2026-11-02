-- Every text the plugin shows the person or hands the agent, per language.
-- English is the default; `pt-BR` keeps the voice of the Claude Code mod
-- (src/lista-da-sessao/hooks/textos.ts). Both tables must have the same keys:
-- tests/textos_test.luau fails on any key missing from either language.

local IDIOMAS = { "en", "pt-BR" }

-- The `idioma` kv value; anything else (nil, "", "fr", a number) reads as "en".
local function idiomaDe(x)
	for _, i in IDIOMAS do
		if x == i then
			return i
		end
	end
	return "en"
end

-- `itens` arrives as a list of texts; a plain string is accepted as is.
local function junta(itens)
	if type(itens) == "table" then
		return table.concat(itens, "; ")
	end
	return tostring(itens)
end

local MOTIVO_EN = {
	["sumiu"] = "that list no longer exists (it was already adopted or discarded)",
	["viva"] = "the tab that owns that list is still open",
	["minha"] = "that is already this tab's list",
	["ilegivel"] = "that list's file is unreadable; I left it alone",
}

local MOTIVO_PT = {
	["sumiu"] = "essa lista não existe mais (já foi puxada ou descartada)",
	["viva"] = "a aba dona dessa lista ainda está aberta",
	["minha"] = "essa já é a lista desta aba",
	["ilegivel"] = "o arquivo dessa lista está ilegível; não mexi nele",
}

local function comAvisos(t)
	t.aviso = {
		["ja-feito"] = t.jaFeito,
		["nao-feito"] = t.naoFeito,
		["ja-travado"] = t.jaTravado,
		["nao-travado"] = t.naoTravado,
		["ja-fazendo"] = t.jaFazendo,
		["tirado-pela-pessoa"] = t.tiradoPelaPessoa,
	}
	return t
end

local EN = comAvisos({
	-- The block beside the pane.
	tituloPainel = "Session list",
	ficouDeAbaFechada = function(assunto)
		if assunto == nil or assunto == "" then
			return "Left open by a closed tab"
		end
		return "Left open by a closed tab: " .. assunto
	end,
	eMais = function(n)
		return `and {n} more`
	end,
	continuarAqui = "Continue here",
	descartar = "Discard",
	nadaCombinado = "Nothing agreed yet.",
	selecionar = "select",
	tirar = "remove",
	ilegivel = function(arquivo)
		return "unreadable list: " .. arquivo
	end,
	recusa = {
		["sumiu"] = function(_id)
			return "That list is no longer there."
		end,
		["viva"] = function(_id)
			return "That list's tab is still open."
		end,
		["minha"] = function(_id)
			return "That list already belongs to this tab."
		end,
		["ilegivel"] = function(id)
			return `unreadable list: {id}.json`
		end,
	},
	-- The command's answers and the rule.
	motivo = MOTIVO_EN,
	erro = {
		["sem-lista"] = "This tab has no list yet: add the first item.",
		["nada-pra-anotar"] = "Nothing to add: send at least one text.",
		["assunto-vazio"] = "The subject came empty.",
		["sem-pane"] = "session-list only works inside a Tern pane.",
		["verbo-invalido"] = "Unknown command. Run `session-list help` to see the commands.",
		["sem-id"] = "Send at least one id, e.g. `session-list done i1` or `session-list adopt l_ab12cd34`.",
		["sem-motivo"] = "Say what it waits on: `session-list block <id> <reason>`.",
	},
	regra = 'Session list: when you and the person agree on a piece of work in parts, note the parts right away with `session-list add "part 1" "part 2"`, not at the end. Mark the part you are working on with `session-list doing <id>`, and tick each part with `session-list done <id>` as soon as it is done; if a part waits on someone, `session-list block <id> <reason>`. The person can also ask "add this to the session list". This list is NOT the person\'s task list: never copy their tasks here, and never move items to another task list unless they ask.',
	naoAchei = function(ids)
		return `Not found: {ids}.`
	end,
	puxei = function(id)
		return `Moved list {id} to this tab.`
	end,
	naoPuxei = function(m)
		return `Did not adopt: {MOTIVO_EN[m] or m}.`
	end,
	descartei = function(id)
		return `Discarded list {id} (moved to descartadas/, can be undone by hand).`
	end,
	naoDescartei = function(m)
		return `Did not discard: {MOTIVO_EN[m] or m}.`
	end,
	-- The list as handed to the agent.
	listaVazia = "This tab's session list: nothing noted yet.",
	cabecalhoLista = function(assunto)
		if assunto == nil or assunto == "" then
			return "This tab's session list"
		end
		return "This tab's session list: " .. assunto
	end,
	feito = "done",
	orfasCabecalho = "Lists closed tabs left with open items:",
	ilegivelModelo = function(nome)
		return "Unreadable list (left alone): " .. nome
	end,
	orfaParaModelo = function(o)
		local n = #o.itens
		local coisas = if n == 1 then "open item" else "open items"
		return table.concat({
			`Orphan list {o.id}: a closed tab left {n} {coisas}.`,
			`1. In your FIRST reply of this conversation, BEFORE anything else (before answering what the person said and before running any command), ask the person with exactly these words: "A tab you closed left {n} {coisas}: {junta(o.itens)}. Continue here?"`,
			`2. Never adopt or discard this list on your own, even if it looks like a test, old or abandoned. Only after the person answers: "yes" → run \`session-list adopt {o.id}\`; "no" → run \`session-list discard {o.id}\`.`,
			"3. If the person talks about something else without answering, leave this list alone: it stays offered until they answer.",
		}, "\n")
	end,
	abertoNestaAba = function(lista)
		return "What was agreed in this tab and is still open (command `session-list`):\n" .. lista
	end,
	-- New in the Tern plugin.
	travado = "blocked",
	travadoPor = function(motivo)
		return "blocked: " .. motivo
	end,
	jaTravado = function(id)
		return `{id} was already blocked with that reason; nothing changed.`
	end,
	naoTravado = function(id)
		return `{id} is not blocked: nothing to unblock.`
	end,
	fazendo = "in progress",
	jaFazendo = function(id)
		return `{id} was already in progress.`
	end,
	jaFeito = function(id)
		return `{id} was already done.`
	end,
	naoFeito = function(id)
		return `{id} is not done: nothing to undo.`
	end,
	tiradoPelaPessoa = function(texto)
		return `The person removed "{texto}" by hand; add it again only if they ask (\`session-list add --again "{texto}"\`).`
	end,
	lembrete = function(n, itens)
		local quantos = n or (if type(itens) == "table" then #itens else 0)
		local coisas = if quantos == 1 then "open item" else "open items"
		return `You stopped with {quantos} {coisas} on this tab's session list: {junta(itens)}. Continue with them, or tick what is finished (\`session-list done <id>\`), or mark what waits on someone (\`session-list block <id> <reason>\`).`
	end,
	semResposta = "Tern's session-list plugin did not answer: is Tern running with the plugin loaded? Run `tern plugin list`.",
	ajuda = table.concat({
		"session-list: this Tern tab's session list (the parts of the work agreed with the person that are still open).",
		"",
		'  session-list add "<text>"...      add items, one per argument',
		"      --subject <s>                 also name the list",
		"      --again                       re-add a text the person removed by hand",
		"  session-list doing <id>           mark the item you are working on (one at a time)",
		"  session-list done <id>...         tick items as done",
		"  session-list undo <id>...         untick done items",
		"  session-list remove <id>...       remove items",
		"  session-list name <subject>       name the list",
		"  session-list block <id> <reason>  mark an item as waiting on someone",
		"  session-list unblock <id>         back to open",
		"  session-list show                 show this tab's list and lists closed tabs left",
		"  session-list adopt <listId>       take over a list a closed tab left",
		"  session-list discard <listId>     discard a list a closed tab left",
		"  session-list start                session-start hook: the list and orphan questions",
		"  session-list check                stop hook: reminds of open items",
		"      --hook                        read the hook's JSON on stdin, exit 2 to remind",
		"  session-list help                 this screen",
		"",
		"Every answer is the list as it now stands.",
	}, "\n"),
	mostrarAqui = "Session list: show for this tab",
	abrirSozinho = "Session list: open beside the tab by itself",
	idioma = "Session list: language",
})

local PT = comAvisos({
	tituloPainel = "Lista da sessão",
	ficouDeAbaFechada = function(assunto)
		if assunto == nil or assunto == "" then
			return "Ficou de uma aba fechada"
		end
		return "Ficou de uma aba fechada: " .. assunto
	end,
	eMais = function(n)
		return `e mais {n}`
	end,
	continuarAqui = "Continuar aqui",
	descartar = "Descartar",
	nadaCombinado = "Nada combinado ainda.",
	selecionar = "selecionar",
	tirar = "tirar",
	ilegivel = function(arquivo)
		return "lista ilegível: " .. arquivo
	end,
	recusa = {
		["sumiu"] = function(_id)
			return "Essa lista já não está mais lá."
		end,
		["viva"] = function(_id)
			return "A aba dessa lista ainda está aberta."
		end,
		["minha"] = function(_id)
			return "Essa lista já é desta aba."
		end,
		["ilegivel"] = function(id)
			return `lista ilegível: {id}.json`
		end,
	},
	motivo = MOTIVO_PT,
	erro = {
		["sem-lista"] = "Esta aba ainda não tem lista: anote o primeiro item.",
		["nada-pra-anotar"] = "Nada pra anotar: mande pelo menos um texto.",
		["assunto-vazio"] = "O assunto veio vazio.",
		["sem-pane"] = "session-list só funciona dentro de um painel do Tern.",
		["verbo-invalido"] = "Comando desconhecido. Rode `session-list help` pra ver os comandos.",
		["sem-id"] = "Mande pelo menos um id, ex. `session-list done i1` ou `session-list adopt l_ab12cd34`.",
		["sem-motivo"] = "Diga do que depende: `session-list block <id> <motivo>`.",
	},
	regra = 'Lista da sessão: quando você e a pessoa combinarem um trabalho em partes, anote as partes na hora com `session-list add "parte 1" "parte 2"`, não no fim. Marque a parte em que você está trabalhando com `session-list doing <id>`, e risque cada parte com `session-list done <id>` assim que terminar; se uma parte depende de alguém, `session-list block <id> <motivo>`. A pessoa também pode pedir "anota isso na lista da sessão". Esta lista NÃO é a lista de tarefas da pessoa: nunca copie tarefas dela pra cá, e nunca passe itens pra outra lista de tarefas sem ela pedir.',
	naoAchei = function(ids)
		return `Não achei: {ids}.`
	end,
	puxei = function(id)
		return `Puxei a lista {id} pra esta aba.`
	end,
	naoPuxei = function(m)
		return `Não puxei: {MOTIVO_PT[m] or m}.`
	end,
	descartei = function(id)
		return `Descartei a lista {id} (foi pra descartadas/, dá pra desfazer à mão).`
	end,
	naoDescartei = function(m)
		return `Não descartei: {MOTIVO_PT[m] or m}.`
	end,
	listaVazia = "Lista da sessão desta aba: nada anotado ainda.",
	cabecalhoLista = function(assunto)
		if assunto == nil or assunto == "" then
			return "Lista da sessão desta aba"
		end
		return "Lista da sessão desta aba: " .. assunto
	end,
	feito = "feito",
	orfasCabecalho = "Listas que abas fechadas deixaram com coisas pendentes:",
	ilegivelModelo = function(nome)
		return "Lista ilegível (não mexi): " .. nome
	end,
	orfaParaModelo = function(o)
		local n = #o.itens
		local coisas = if n == 1 then "coisa pendente" else "coisas pendentes"
		return table.concat({
			`Lista órfã {o.id}: uma aba fechada deixou {n} {coisas}.`,
			`1. Na sua PRIMEIRA resposta desta conversa, ANTES de qualquer outra coisa (antes de responder ao que a pessoa disse e antes de rodar qualquer comando), pergunte à pessoa exatamente com estas palavras: "Uma aba que tu fechou deixou {n} {coisas}: {junta(o.itens)}. Continuar aqui?"`,
			`2. Nunca puxe nem descarte essa lista por conta própria, nem que ela pareça teste, velha ou abandonada. Só depois da resposta da pessoa: "sim" → rode \`session-list adopt {o.id}\`; "não" → rode \`session-list discard {o.id}\`.`,
			"3. Se a pessoa falar de outra coisa sem responder, não mexa nessa lista: ela continua oferecida até a pessoa responder.",
		}, "\n")
	end,
	abertoNestaAba = function(lista)
		return "O que ficou combinado nesta aba e ainda está aberto (comando `session-list`):\n" .. lista
	end,
	travado = "travado",
	travadoPor = function(motivo)
		return "travado: " .. motivo
	end,
	jaTravado = function(id)
		return `{id} já estava travado com esse motivo; nada mudou.`
	end,
	naoTravado = function(id)
		return `{id} não está travado: nada pra destravar.`
	end,
	fazendo = "fazendo agora",
	jaFazendo = function(id)
		return `{id} já estava sendo feito.`
	end,
	jaFeito = function(id)
		return `{id} já estava feito.`
	end,
	naoFeito = function(id)
		return `{id} não está feito: nada pra desfazer.`
	end,
	tiradoPelaPessoa = function(texto)
		return `A pessoa tirou "{texto}" à mão; só anote de novo se ela pedir (\`session-list add --again "{texto}"\`).`
	end,
	lembrete = function(n, itens)
		local quantos = n or (if type(itens) == "table" then #itens else 0)
		local coisas = if quantos == 1 then "coisa aberta" else "coisas abertas"
		return `Você parou com {quantos} {coisas} na lista da sessão desta aba: {junta(itens)}. Continue com elas, ou risque o que terminou (\`session-list done <id>\`), ou marque o que depende de alguém (\`session-list block <id> <motivo>\`).`
	end,
	semResposta = "O plugin session-list do Tern não respondeu: o Tern está aberto com o plugin carregado? Rode `tern plugin list`.",
	ajuda = table.concat({
		"session-list: a lista da sessão desta aba do Tern (as partes do trabalho combinado com a pessoa que ainda estão abertas).",
		"",
		'  session-list add "<texto>"...     anota itens, um por argumento',
		"      --subject <s>                 também dá nome à lista",
		"      --again                       anota de novo um texto que a pessoa tirou à mão",
		"  session-list doing <id>           marca o item em que você está trabalhando (um por vez)",
		"  session-list done <id>...         risca itens",
		"  session-list undo <id>...         desfaz o risco",
		"  session-list remove <id>...       tira itens",
		"  session-list name <assunto>       dá nome à lista",
		"  session-list block <id> <motivo>  marca um item como dependendo de alguém",
		"  session-list unblock <id>         volta a aberto",
		"  session-list show                 mostra a lista desta aba e as que abas fechadas deixaram",
		"  session-list adopt <listId>       puxa pra cá uma lista que uma aba fechada deixou",
		"  session-list discard <listId>     descarta uma lista que uma aba fechada deixou",
		"  session-list start                hook de início de sessão: a lista e as perguntas das órfãs",
		"  session-list check                hook de parada: lembra o que está aberto",
		"      --hook                        lê o JSON do hook no stdin, sai com 2 pra lembrar",
		"  session-list help                 esta tela",
		"",
		"Toda resposta é a lista como ficou.",
	}, "\n"),
	mostrarAqui = "Lista da sessão: mostrar nesta aba",
	abrirSozinho = "Lista da sessão: abrir ao lado da aba sozinha",
	idioma = "Lista da sessão: idioma",
})

local TEXTOS = { ["en"] = EN, ["pt-BR"] = PT }

local function textos(idioma)
	return TEXTOS[idiomaDe(idioma)]
end

return {
	IDIOMAS = IDIOMAS,
	idiomaDe = idiomaDe,
	textos = textos,
}

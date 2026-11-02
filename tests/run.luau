-- Unit test runner: `luau tests/run.luau`.
-- Each *_test.luau returns a list of { name, fn }; fn fails by erroring.
-- To add a test file, add one line to `arquivos`.

local arquivos = {
	{ "nucleo_test", require("./nucleo_test") },
	{ "textos_test", require("./textos_test") },
	{ "pedidos_test", require("./pedidos_test") },
	{ "vista_test", require("./vista_test") },
	{ "lembrete_test", require("./lembrete_test") },
	{ "brilho_test", require("./brilho_test") },
}

local passou, falhou = 0, 0
for _, arq in arquivos do
	local nomeArq, testes = arq[1], arq[2]
	for _, t in testes do
		local nome = t.name or t[1]
		local fn = t.fn or t[2]
		local ok, err = pcall(fn)
		if ok then
			passou += 1
		else
			falhou += 1
			print(string.format("FAIL %s :: %s\n     %s", nomeArq, tostring(nome), tostring(err)))
		end
	end
end

print(string.format("%d passed, %d failed", passou, falhou))
if falhou > 0 then
	error(string.format("%d test(s) failed", falhou), 0)
end

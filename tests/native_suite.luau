-- Runs the retained library battery inside an isolated real Tern Luau VM.
-- CodexBWAI, COMMANDER-993. Required by the smoke harness, never production.
local suites = {
    require("./nucleo_test"), require("./textos_test"), require("./pedidos_test"),
    require("./vista_test"), require("./lembrete_test"), require("./brilho_test"),
}
local passed, failures = 0, {}
for _, suite in suites do
    for _, test in suite do
        local ok, reason = pcall(test.fn or test[2])
        if ok then passed += 1 else table.insert(failures, tostring(test.name or test[1]) .. ": " .. tostring(reason)) end
    end
end
return {passed = passed, failures = failures}

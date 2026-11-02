-- When the block glows: a part of the list newly ticked done lights the pane
-- with Tern's own "finished" ring for a moment. Pure: no `tern` global.
--
--   brilho.decide(antes, lista) -> (acende: boolean, depois)
--     antes  = what this block saw last time (nil on its first drawing)
--     lista  = the list it draws now (nil when the pane has none)
--     depois = what it sees now; keep it for the next call
--   Glows only when the SAME list (same id) has an item done now that was not
--   done before. A first drawing (block opened, plugin reloaded), a list that
--   changed id (adopted, a new list) and redraws with nothing newly done never
--   glow.
--
-- MEASURED (Tern 0.9.8, 2026-11-02): a plugin block cannot raise Tern's own
-- glow. Tern draws it on `.tn-pane.finished .tn-glow` when a program in a
-- TERMINAL pane reports `ESC ] 7501 ; state=done ESC \` (the class stays
-- ~1.5 s); the report lives on the terminal screen, plugin blocks have no
-- way to send one (cx:frame with status ops: no effect), and plugin CSS
-- cannot reach the pane frame (no :has()). So styles.css draws Tern's
-- rainbow "working" ring (Felipe's pick, 2026-11-02) inside the block, once:
-- one full turn plus fade in DURACAO_MS (keep in step with styles.css 2.4s).

local brilho = {}

brilho.DURACAO_MS = 2400

local function retrato(lista)
	if lista == nil then
		return nil
	end
	local feitos = {}
	for _, i in lista.itens or {} do
		if i.estado == "feito" then
			feitos[i.id] = true
		end
	end
	return { id = lista.id, feitos = feitos }
end

function brilho.decide(antes, lista): (boolean, any)
	local depois = retrato(lista)
	if antes == nil or depois == nil or antes.id ~= depois.id then
		return false, depois
	end
	for id in depois.feitos do
		if not antes.feitos[id] then
			return true, depois
		end
	end
	return false, depois
end

return brilho

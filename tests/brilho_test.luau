-- Tests for lib/brilho.luau: only a NEW done glows.

local brilho = require("../lib/brilho")

local function eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end

local function lista(id, estados)
	local itens = {}
	for n, e in estados do
		table.insert(itens, { id = "i" .. n, texto = "t" .. n, estado = e })
	end
	return { id = id, assunto = "", itens = itens }
end

-- Runs decide over a sequence of lists, returns the glow answers.
-- `n` = how many steps (a nil step leaves a hole the table length skips).
local function sequencia(listas, n: number?)
	local out, visto = {}, nil
	for k = 1, n or #listas do
		local acende
		acende, visto = brilho.decide(visto, listas[k])
		out[k] = acende
	end
	return out
end

return {
	{ "first drawing never glows, even with items already done", function()
		local acende, visto = brilho.decide(nil, lista("l_a", { "feito", "feito" }))
		eq(acende, false)
		assert(visto and visto.feitos.i1 and visto.feitos.i2, "remembers what was done")
	end },

	{ "an item newly done on the same list glows once", function()
		local r = sequencia({
			lista("l_a", { "aberto", "aberto" }),
			lista("l_a", { "feito", "aberto" }),
			lista("l_a", { "feito", "aberto" }), -- redraw, nothing new
		})
		eq(r[1], false, "open")
		eq(r[2], true, "new done")
		eq(r[3], false, "redraw")
	end },

	{ "redraws that change other things never glow", function()
		local r = sequencia({
			lista("l_a", { "aberto", "feito" }),
			lista("l_a", { "fazendo", "feito" }), -- doing
			lista("l_a", { "travado", "feito" }), -- blocked
			lista("l_a", { "aberto", "feito", "aberto" }), -- added
			lista("l_a", { "aberto" }), -- removed the done one (ids shift: i1 stays open)
		})
		for n, v in r do
			eq(v, false, "step " .. n)
		end
	end },

	{ "undo then done again glows again", function()
		local r = sequencia({
			lista("l_a", { "feito" }),
			lista("l_a", { "aberto" }),
			lista("l_a", { "feito" }),
		})
		eq(r[2], false, "undo")
		eq(r[3], true, "done again")
	end },

	{ "a list that changes id (adopted, new list) never glows", function()
		local r = sequencia({
			lista("l_a", { "aberto" }),
			lista("l_b", { "feito", "feito" }), -- adopted with done items
			lista("l_b", { "feito", "feito", "feito" }), -- then one newly done
		})
		eq(r[2], false, "adopt")
		eq(r[3], true, "new done after adopt")
	end },

	{ "no list: no glow, and the next list starts fresh", function()
		local r = sequencia({
			lista("l_a", { "aberto" }),
			nil,
			lista("l_a", { "feito" }),
		}, 3)
		eq(r[2], false, "nil")
		eq(r[3], false, "after nil = first drawing")
	end },

	{ "two items done at once glow once", function()
		local r = sequencia({
			lista("l_a", { "aberto", "aberto" }),
			lista("l_a", { "feito", "feito" }),
		})
		eq(r[2], true)
	end },

	{ "duration matches styles.css (one rainbow turn + fade, 2.4 s)", function()
		eq(brilho.DURACAO_MS, 2400)
	end },
}

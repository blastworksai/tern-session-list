-- A small pure-Luau JSON for the unit tests that reproduces tern.json's quirks:
--   * decode drops object members whose value is null;
--   * decoded arrays come back tagged as arrays (so they re-encode as []);
--   * encode of an UNTAGGED empty table is {}, of a tagged one [] (array());
--   * `null` is a sentinel that encodes as null (decode gives it only
--     inside arrays, since null members of objects are dropped).
-- Object keys are encoded sorted, so output is deterministic.

local json = {}

local marcados = setmetatable({}, { __mode = "k" })

json.null = setmetatable({}, { __tostring = function()
	return "null"
end })

function json.array(t: any?)
	local a = t or {}
	marcados[a] = true
	return a
end

function json.isArray(t: any): boolean
	return marcados[t] == true
end

-- encode -------------------------------------------------------------------

local ESCAPES = {
	['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
	["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(s: string): string
	return '"' .. string.gsub(s, '[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end) .. '"'
end

local function ehSequencia(t): boolean
	local n = 0
	for k in t do
		if type(k) ~= "number" then
			return false
		end
		n += 1
	end
	return n > 0 and n == #t
end

local encodeValue

function encodeValue(v: any): string
	local tv = type(v)
	if v == json.null or v == nil then
		return "null"
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("json: cannot encode " .. tostring(v))
		end
		if math.floor(v) == v and math.abs(v) < 2 ^ 53 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	elseif tv == "string" then
		return encodeString(v)
	elseif tv == "table" then
		if marcados[v] or ehSequencia(v) then
			local partes = {}
			for i = 1, #v do
				partes[i] = encodeValue(v[i])
			end
			return "[" .. table.concat(partes, ",") .. "]"
		end
		local chaves = {}
		for k in v do
			if type(k) ~= "string" then
				error("json: object key is not a string: " .. tostring(k))
			end
			table.insert(chaves, k)
		end
		table.sort(chaves)
		local partes = {}
		for _, k in chaves do
			table.insert(partes, encodeString(k) .. ":" .. encodeValue(v[k]))
		end
		return "{" .. table.concat(partes, ",") .. "}"
	end
	error("json: cannot encode a " .. tv)
end

function json.encode(v: any): string
	return encodeValue(v)
end

-- decode -------------------------------------------------------------------

local function decode(s: string)
	local pos = 1

	local function falha(msg: string)
		error(string.format("json: %s at %d", msg, pos), 0)
	end

	local function espacos()
		pos = string.find(s, "[^ \t\r\n]", pos) or #s + 1
	end

	local valor

	local function lerString(): string
		pos += 1 -- opening quote
		local partes = {}
		while true do
			local c = string.sub(s, pos, pos)
			if c == "" then
				falha("unterminated string")
			elseif c == '"' then
				pos += 1
				break
			elseif c == "\\" then
				local e = string.sub(s, pos + 1, pos + 1)
				local mapa = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if mapa[e] then
					table.insert(partes, mapa[e])
					pos += 2
				elseif e == "u" then
					local cp = tonumber(string.sub(s, pos + 2, pos + 5), 16)
					if not cp then
						falha("bad \\u escape")
					end
					pos += 6
					if cp >= 0xD800 and cp <= 0xDBFF and string.sub(s, pos, pos + 1) == "\\u" then
						local lo = tonumber(string.sub(s, pos + 2, pos + 5), 16)
						if lo and lo >= 0xDC00 and lo <= 0xDFFF then
							cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
							pos += 6
						end
					end
					table.insert(partes, utf8.char(cp))
				else
					falha("bad escape")
				end
			elseif string.byte(c) < 0x20 then
				falha("control character in string")
			else
				local fim = string.find(s, '["\\%c]', pos) or #s + 1
				table.insert(partes, string.sub(s, pos, fim - 1))
				pos = fim
			end
		end
		return table.concat(partes)
	end

	function valor(): any
		espacos()
		local c = string.sub(s, pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			espacos()
			if string.sub(s, pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				espacos()
				if string.sub(s, pos, pos) ~= '"' then
					falha("expected key")
				end
				local k = lerString()
				espacos()
				if string.sub(s, pos, pos) ~= ":" then
					falha("expected ':'")
				end
				pos += 1
				local v = valor()
				if v ~= json.null then
					obj[k] = v -- null members are dropped (Tern quirk)
				end
				espacos()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					falha("expected ',' or '}'")
				end
			end
		elseif c == "[" then
			pos += 1
			local arr = json.array({})
			espacos()
			if string.sub(s, pos, pos) == "]" then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, valor())
				espacos()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					falha("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return lerString()
		elseif string.sub(s, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(s, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(s, pos, pos + 3) == "null" then
			pos += 4
			return json.null
		else
			local num = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if num == nil or num == "" then
				falha("unexpected character")
			end
			local n = tonumber(num)
			if n == nil then
				falha("bad number")
			end
			pos += #num
			return n
		end
	end

	local v = valor()
	espacos()
	if pos <= #s then
		falha("trailing characters")
	end
	return v
end

function json.decode(s: string): any
	if type(s) ~= "string" then
		error("json: decode expects a string")
	end
	return decode(s)
end

return json

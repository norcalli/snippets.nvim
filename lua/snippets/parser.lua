local combinators = require 'snippets.combinators'
local sym = combinators.sym
local pattern = combinators.pattern
local map = combinators.map
local any = combinators.any
local seq = combinators.seq
local many = combinators.many
local take_until = combinators.take_until
local separated = combinators.separated
local lazy = combinators.lazy
local SKIP = combinators.SKIP
local C = require 'snippets.common'

local format = string.format
local concat = table.concat
local insert = table.insert

local function vscode_parser()
	local dollar = sym("$")
	local open = sym("{")
	local close = sym("}")
	local colon = sym(":")
	local slash = sym("/")
	local comma = sym(",")
	local pipe = sym("|")

	local var = pattern("[_a-zA-Z][_a-zA-Z0-9]*")

	local int = map(pattern("%d+"), function(v) return tonumber(v) end)

	-- TODO: opt so we can avoid swallowing the close here
	local regex = map(
		seq(slash, take_until("/"), slash, take_until("/"), slash, any(take_until("}"), close)),
		function(v) return { type = "regex", value = v[1], format = v[2], options = v[3]} end
	)

	local tabstop, placeholder, choice, variable, anything

	-- need to make lazy so that tabstop/placeholder/variable aren't nil at
	-- declaration time because of mutual recursion.
	anything = lazy(function() return any(
		tabstop,
		placeholder,
		choice,
		variable
			-- -- text: we do this on a per usecase basis
	) end)

	tabstop = map(
		any(
			seq(dollar, int),
			seq(dollar, open, int, close)
		),
		function(v) return { type = "tabstop", id = v[1] } end
	)

	placeholder = map(
		-- match until $ or }
		seq(dollar, open, int, colon, many(any(anything, take_until("[%$}]"))), close),
		function(v) return { type = "placeholder", id = v[1], value = v[2] } end
	)

	choice = map(
		-- match until , or |
		seq(dollar, open, int, pipe, separated(comma, take_until("[,|]")), pipe, close),
		function(v) return { type = "choice", id = v[1], value = v[2] } end
	)

	variable = any(
		map(
			seq(dollar, var),
			function(v) return { type = "variable", name = v[1] } end
		),
		map(
			seq(dollar, open, var, colon, many(any(anything, take_until("}"))), close),
			function(v) return { type = "variable", name = v[1], default = v[2] } end
		),
		map(
			seq(dollar, open, var, regex), -- regex already eats the close
			function(v) return { type = "variable", name = v[1], regex = v[2] } end
		)
	)

	-- toplevel take_until matches until $
	local parse = many(any(anything, take_until("%$")))
end

local function lazy_any(array)
	local cached
	return lazy(function()
		if not cached then
			cached = any(unpack(array))
		end
		return cached
	end)
end

local function ashkan_parser()
	local dollar = sym("$")
	local open = sym("{")
	local close = sym("}")
	local colon = sym(":")
	local slash = sym("/")
	local comma = sym(",")
	local pipe = sym("|")
	local equals = sym("=")

	local var = pattern("[_a-zA-Z][_a-zA-Z0-9]*")

	local int = map(pattern("%-?%d+"), function(v) return tonumber(v) end)

	local function mkslash_escaped(inner)
		return map(
			pattern("\\."),
			function(v)
			  return v:sub(2):match(inner) or v
			  -- return v:sub(2):match(inner) or SKIP
			  -- return v:sub(2):match(inner) or error(format("Invalid escape sequence %q. Expected %s", v, inner))
			end
		)
	end

	local escaped = mkslash_escaped("[\\$]")
	local transform_escaped = mkslash_escaped("[\\|]")

	local variants = {}

	-- need to make lazy so that variants aren't empty at
	-- declaration time because of mutual recursion.
	local anything = lazy_any(variants)

	variants[#variants+1] = escaped

	variants[#variants+1] = map(
		seq(dollar, open, equals, take_until("}"), close),
		function(v)
			local expression = C.make_lambda(v[1], v[1])
			return C.structure_variable(false, nil, expression, -1, nil)
		end
	)

	variants[#variants+1] = map(
		seq(dollar, open, pipe, take_until("}"), close),
		function(v)
			local transform = C.make_lambda(v[1], v[1])
			return C.structure_variable(false, nil, nil, math.huge, transform)
		end
	)

	-- Basic style
	variants[#variants+1] = map(
		any(
			seq(dollar, int),
			seq(dollar, open, int, close)
		),
		function(v)
			local id = v[1]
			return C.structure_variable(id > 0, id, "", id, nil)
		end
	)

	local transform = map(
		seq(pipe, take_until("}")),
		function(v)
			return C.make_lambda(v[1], v[1])
		end
	)

	-- Placeholder style
	variants[#variants+1] = map(
		-- match until $ or }
		any(
			seq(dollar, open, int, colon, many(any(transform_escaped, anything, take_until("[\\$}|]"))), transform, close),
			seq(dollar, open, int, colon, many(any(anything, take_until("[\\$}]"))), close)
		),
		function(v)
			local id = v[1]
			local placeholder = v[2]
			if #placeholder > 1 or type(placeholder[1]) ~= 'string' then
				local evaluator = C.evaluate_snippet(placeholder)
				placeholder = function(context)
					local inputs = {}
					for i, v in ipairs(evaluator.inputs) do
						-- TODO(ashkan, Tue 18 Aug 2020 09:37:37 AM JST) ignore the v.default here?
						inputs[i] = context[v.id]
					end
					return concat(evaluator.evaluate_structure(inputs))
				end
			else
			  placeholder = placeholder[1]
			end
			return C.structure_variable(id > 0, id, placeholder, id, v[3])
		end
	)

	-- Expression style
	variants[#variants+1] = map(
		-- match until $ or }
		any(
			seq(dollar, open, int, equals, many(any(transform_escaped, take_until("[\\|}]"))), transform, close),
			seq(dollar, open, int, equals, take_until("}"), close)
		),
		function(v)
			local id = v[1]
			local expression = v[2]
			if type(expression) == 'table' then
			  expression = concat(expression)
			end
			expression = C.make_lambda(expression, expression)
			return C.structure_variable(id > 0, id, expression, id, v[3])
		end
	)

	-- Transform style
	variants[#variants+1] = map(
		seq(dollar, open, int, transform, close),
		function(v)
			local id = v[1]
			return C.structure_variable(id > 0, id, "", id, v[2])
		end
	)

	-- toplevel take_until matches until $
	return map(
		many(any(anything, take_until("[\\$]"))),
		C.make_snippet
	)
end

local lazily_initialized_parser

return {
	make_ashkan_parser = ashkan_parser;
	make_vscode_parser = vscode_parser;
	parse_snippet = function(s)
		if not lazily_initialized_parser then
			lazily_initialized_parser = ashkan_parser()
		end
		if s == "" then
			return {""}
		end
		local ok, snippet, pos = lazily_initialized_parser(s, 1)
		if not ok then
			error(format("Failed to parse snippet: %q", s))
		end
		if pos ~= #s+1 then
			error(format("Failed to parse snippet fully: %d != %d\n%s\n%s^", pos, #s+1, s, (" "):rep(pos-1)))
		end
		return snippet
	end;
}

-- vim:noet sw=3 ts=3

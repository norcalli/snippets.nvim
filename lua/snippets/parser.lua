--[[
snippet name
\tBody
\t${1:VALUE}
\t$1
\t$0
--]]
local U = require 'snippets.common'
local splitter = require 'snippets.splitter'
local format = string.format
local concat = table.concat
local insert = table.insert

local function parse_directives(s)
	if s:match("^%s*$") then return {} end
	local a, b = s:match("^(:[^|]*[^%%])(|.*)")
	if a then return {a, b} end
	local a = s:match("^(=.*)")
	if a then return {a} end
	local a = s:match("^(:.*)")
	if a then return {a} end
	local a = s:match("^(|.*)")
	if a then return {a} end
end

local format = string.format
local insert = table.insert
local function find_delimited(body, start, stop, start_pos)
	local subnodes = {}
	local escaped_start = "\\"..start
	local escaped_stop = "\\"..stop
	local started = nil
	local i = start_pos or 1
	while i <= #body do
		if body:sub(1, i):sub(-#stop) == stop and body:sub(1, i):sub(-#escaped_stop) ~= escaped_stop then
			-- if body:sub(1, i):sub(-#stop) == stop then
			if started then
				return {started, i, subnodes}
			end
			i = i + 1
		elseif body:sub(i, i+#start-1) == start and body:sub(i, i+#escaped_start-1) ~= escaped_start then
			-- elseif body:sub(i, i+#start-1) == start then
			if started then
				local x = find_delimited(body, start, stop, i)
				insert(subnodes, x)
				i = x[2]+1
			else
				started = i
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	if started then
		error(format("Couldn't find end starting from %d: %q", started, body:sub(started)))
	end
end

local function find_next_multiple(body, patterns, start_position)
	-- try to find a new variable to parse out.
	local next_value
	for i, pattern in ipairs(patterns) do
		local value
		if type(pattern) == 'string' then
			value = { body:find(pattern, start_position) }
		else
			assert(type(pattern) == 'function')
			value = { pattern(body, start_position)}
		end
		if #value > 0 then
			value.pattern_index = i
			local new_value
			if not next_value then
				new_value = value
			else
				-- TODO(ashkan): report which indices.
				if next_value[1] == value[1] then
					return nil, "Multiple patterns matched the same thing"
				end
				if next_value[1] > value[1] then
					U.LOG_INTERNAL("preferring", i, "over", next_index)
					new_value = value
				end
			end
			if new_value then
				next_value = new_value
			end
		end
	end
	if not next_value then
		return
	end
	return next_value
	-- return unpack(next_value)
end

local function find_sub(s, replacement, pattern, start, special)
	local x1, x2 = s:find(pattern, start, special)
	if x1 then
		return s:sub(1, x1-1)..replacement..s:sub(x2+1), x1, x2
	end
	return s
end

-- Take a string containing the variable substitutions and
-- turn it into a structural representation of a snippet and
-- a dictionary of the variables it uses.
--
-- Example:
-- parse_snippet("for ${1:i}, ${2:v} in ipairs(${3:t}) do $0 end")
--   == { 'for '; 1; ' '; 2; ' in ipairs('...
local function parse_snippet(body)
	local R = {}

	local inner_patterns = {
		-- Pattern for ${1:default body}
		"%${(%-?%d+)(.*)}",
		-- Pattern for placeholder as a lua function.
		"%${([=|].*)}",
	}

	local function parse_var(body)
		local next_value = find_next_multiple(body, inner_patterns)
		if not next_value then
			return
		end
		local i1, i2, p1, p2 = unpack(next_value, 1, 4)
		local var = {}
		local tail
		local var_id = tonumber(p1)
		if var_id then
			var.id = var_id
			tail = p2
		else
			if p2 then
				return nil, "var_id is not a number?"
			end
			tail = p1
		end

		if tail then
			local directives = parse_directives(tail) or error("Invalid directives "..vim.inspect(tail))
			for i, directive in ipairs(directives) do
				local kind = directive:sub(1,1)
				if kind == '=' then
					var.expression = directive:sub(2)
					-- local chunk_name = ("snippets[expression id=%s body=%q]"):format(tostring(var_id), body:sub(i1, i2))
					-- var.expression = U.make_lambda(directive:sub(2), chunk_name)
				elseif kind == '|' then
					var.transform = directive:sub(2)
					-- local chunk_name = ("snippets[transform id=%s body=%q]"):format(tostring(var_id), body:sub(i1, i2))
					-- var.transform = U.make_lambda(directive:sub(2), chunk_name)
				elseif kind == ':' then
					var.placeholder = directive:sub(2)
				else
					return nil, ("Invalid snippet component found:\nStart=%d, End=%d, P1=%q, P2=%q, Substring=%q"):format(i1, i2, p1, p2, body:sub(i1, i2))
				end
			end
		end
		return i1, i2, var
	end

	-- TODO(ashkan): error patterns that we can check which don't show up in here.
	-- Each pattern should return either 1 or 2 things:
	-- 1. { variable_id, }
	-- 2. { variable_id, kind, placeholder, }
	-- NOTE: Ordering is important!
	-- If one pattern may contain the other, it should be placed higher up.
	local patterns = {
		function(body, start)
			local r = find_delimited(body, "${", "}", start)
			if not r then
				return
			end
			local i1, i2, subnodes = unpack(r)
			local y = i2
			local var
			if not subnodes or #subnodes == 0 then
				_, _, var = parse_var(body:sub(i1, i2))
			else
				local original_body = body
				local removed = {}
				for i, v in ipairs(subnodes) do
					local rem = body:sub(v[1], v[2])
					insert(removed, rem)
					U.LOG_INTERNAL(i1, i2, #rem, rem)
					y = y - #rem + 1
				end
				for i = #subnodes, 1, -1 do
					local v = subnodes[i]
					body = body:sub(1, v[1]-1)..string.char(i)..body:sub(v[2]+1)
				end
				U.LOG_INTERNAL('body', body)
				local text = body:sub(i1, y)
				U.LOG_INTERNAL('text', text)
				local function reconstitute(x)
					for i, text in ipairs(removed) do
						x = find_sub(x, text, string.char(i), 1, true)
					end
					return x
				end
				_, _, var = parse_var(text)
				if var.placeholder then var.placeholder = reconstitute(var.placeholder) end
				if var.expression then var.expression = reconstitute(var.expression) end
				if var.transform then var.transform = reconstitute(var.transform) end
			end
			if var then
				if var.placeholder then
					local s = assert(parse_snippet(var.placeholder))
					if #s == 1 and type(s[1]) == 'string' then
						var.placeholder = s[1]
					else
						local evaluator = U.evaluate_snippet(s)
						var.placeholder = function(context)
							local inputs = {}
							for i, v in ipairs(evaluator.inputs) do
								-- TODO(ashkan, Tue 18 Aug 2020 09:37:37 AM JST) ignore the v.default here?
								inputs[i] = context[v.id]
							end
							return concat(evaluator.evaluate_structure(inputs))
						end
					end
				end
				return i1, i2, var
			end
		end;
		-- TODO(ashkan): allow an empty value in the :} part or throw an error?
		-- Pattern for $1, $2, etc..
		-- "%$(%-?%d+)",
		function(body, start)
			local i1, i2, var_id = body:find("%$(%-?%d+)", start)
			if i1 then
				return i1, i2, { id = tonumber(var_id) }
			end
		end;
	}

	local start_position = 1
	for LOOP_IDX = 1, 10000000 do
		-- try to find a new variable to parse out.
		local next_value = find_next_multiple(body, patterns, start_position)

		if not next_value then
			break
		end

		local i1, i2, var = unpack(next_value, 1, 3)
		U.LOG_INTERNAL("parse inner", i1, i2, var)
		if i1 ~= start_position then
			R[#R+1] = body:sub(start_position, i1 - 1)
		end
		start_position = i2+1

		assert(not (var.placeholder and var.expression), "Can't define both an expression and placeholder")

		-- TODO(ashkan): disallow placeholder for $0?

		if var.expression then
			local chunk_name = ("snippets[expression id=%s body=%q]"):format(tostring(var.id), body:sub(i1, i2))
			var.expression = U.make_lambda(var.expression, chunk_name)
		end
		if var.transform then
			local chunk_name = ("snippets[transform id=%s body=%q]"):format(tostring(var.id), body:sub(i1, i2))
			var.transform = U.make_lambda(var.transform, chunk_name)
		end

		R[#R+1] = U.structure_variable(
			(var.id or 0) > 0,
			var.id,
			var.placeholder or var.expression or "",
			-- TODO(ashkan, Tue 18 Aug 2020 09:30:38 AM JST) negative value order?
			var.id or -1,
			var.transform
		)
	end

	local tail = body:sub(start_position)
	if #tail > 0 then
		R[#R+1] = tail
	end
	U.LOG_INTERNAL("parse result", R)
	return R
end

-- local function parse_file(file_name)
-- 	local snippets = {}
-- 	for line in io.lines(file_name) do
-- 		local trigger = line:match("^snippet%s+(%S+)")
-- 		if trigger then
-- 			snippets[#snippets + 1] = {}
-- 	end
-- 	file:read "*a"
-- 	file:close
-- end

return {
	parse_snippet = parse_snippet;
}
-- vim:noet sw=3 ts=3

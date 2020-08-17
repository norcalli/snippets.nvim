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
	local r = splitter("[^%%]()()[=|]").collect(" "..s)
	r[1] = r[1]:sub(2)
	if r[1] == "" then
		table.remove(r, 1)
	end
	return r
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
			local directives = parse_directives(tail)
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
		-- TODO(ashkan): allow an empty value in the :} part or throw an error?
		-- Pattern for $1, $2, etc..
		-- "%$(%-?%d+)",
		function(body, start)
			local i1, i2, var_id = body:find("%$(%-?%d+)", start)
			if i1 then
				return i1, i2, { id = tonumber(var_id) }
			end
		end;
		function(body, start)
			local r = find_delimited(body, "${", "}", start)
			if not r then
				return
			end
			local i1, i2, subnodes = unpack(r)
			local y = i2
			if not subnodes or #subnodes == 0 then
				local _, _, var = parse_var(body:sub(i1, i2))
				return i1, i2, var
			end
			-- U.LOG_INTERNAL(i1, i2, body:sub(i1, i2))
			-- error("Recursive placeholders aren't supported.")
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
				-- U.LOG_INTERNAL(v, removed[i], body:sub(1, v[1]-1), body:sub(v[2]+1), #string.char(i))
				body = body:sub(1, v[1]-1)..string.char(i)..body:sub(v[2]+1)
			end
			U.LOG_INTERNAL('body', body)
			local text = body:sub(i1, y)
			U.LOG_INTERNAL('text', text)
			local function reconstitute(x)
				local had_sub = false
				for i, text in ipairs(removed) do
					local y
					x, y = find_sub(x, text, string.char(i), 1, true)
					had_sub = had_sub or y
				end
				return x, had_sub
			end
			local _, _, var = parse_var(text)
			if var then
				if var.placeholder then
					local had_sub
					var.placeholder, had_sub = reconstitute(var.placeholder)
					-- var.placeholder, had_sub = find_sub(var.placeholder, inner, marker, 1, true)
					if had_sub then
						local s, v = parse_snippet(var.placeholder)
						if not s then
							error(v)
						end
						var.placeholder = { structure = s; variables = v }
						U.LOG_INTERNAL('placeholder', var.placeholder)
					end
				end
				if var.expression then
					var.expression = reconstitute(var.expression)
					-- var.expression = find_sub(var.expression, inner, marker, 1, true)
				end
				if var.transform then
					var.transform = reconstitute(var.transform)
					-- var.transform = find_sub(var.transform, inner, marker, 1, true)
				end
				return i1, i2, var
			end
		end;
	}

	local variables = {}

	-- local verbatim_index = 1e10

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

		if var.id then
			local existing_var = variables[var.id]
			if existing_var then
				local v1 = var.placeholder or var.expression
				local v2 = existing_var.placeholder or existing_var.expression
				if v1 ~= nil and v2 ~= nil then
					return nil, ("Multiple placeholders defined for variable $%s: %s vs %s"):format(var.id, v1, v2)
				end
				existing_var.count = existing_var.count + 1
				existing_var.transforms[existing_var.count] = var.transform
			else
				variables[var.id] = {
					id = var.id;
					count = 1;
					-- expression = var.expression;
					-- placeholder = var.placeholder;
					placeholder = var.placeholder or var.expression or "";
					transforms = {var.transform};
				}
			end
			R[#R+1] = var.id
		elseif var.expression then
			if var.transform then
				R[#R+1] = function()
					var.transform(var.expression())
				end
			else
				R[#R+1] = var.expression
			end
		elseif var.transform then
			-- verbatim_index = verbatim_index + 1
			-- local var_id = verbatim_index
			-- variables[var_id] = {
			-- 	count = 1;
			-- 	placeholder = "";
			-- 	transforms = { var.transform };
			-- }
			-- R[#R+1] = var_id
			R[#R+1] = U.make_post_transform(var.transform)
		else
		end
	end

	local tail = body:sub(start_position)
	if #tail > 0 then
		R[#R+1] = tail
	end
	U.LOG_INTERNAL("parse result", R, variables)
	return R, variables
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

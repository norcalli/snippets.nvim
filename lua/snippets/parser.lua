-- Copyright (C) 2020 Ashkan Kiani
-- This is part of the snippets.nvim distribution.
-- https://github.com/norcalli/snippets.nvim
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local U = require 'snippets.common'
local splitter = require 'snippets.splitter'
local format = string.format
local concat = table.concat
local insert = table.insert
local char = string.char

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

-- TODO:
--  This is more boardly useful and should be extracted.
--    - ashkan, Thu 19 Aug 2020 00:35:42 PM JST
local function find_next_multiple(body, patterns, start_position)
	local result
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
			-- Prefer earlier values.
			if not result or value[1] < result[1] then
				result = value
			elseif value[1] == result[1] then
				return nil, format("Multiple patterns matched the same position: [%d,%d] & [%d,%d]\n%q vs %q",
						result[1], result[2], value[1], value[2],
						body:sub(result[1], result[2]),
						body:sub(value[1], value[2]))
			end
		end
	end
	if not result then
		return
	end
	return result
	-- return unpack(result)
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
--   == { 'for '; { id = 1; placeholder = "i"; }; ' '; { id = 2; placeholder = "v"; ' in ipairs('...
local function parse_snippet(body)
	U.LOG_INTERNAL("Parse Start:", body)
	local R = {}

	local inner_patterns = {
		-- Pattern for ${1:default body}
		"%${(%-?%d+)(.*)}",
		-- Pattern for placeholder as a lua function.
		"%${([=|].*)}",
	}

	local function parse_var(body)
		local next_value, err = find_next_multiple(body, inner_patterns)
		if err then
			error(err)
		end
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
				elseif kind == '|' then
					var.transform = directive:sub(2)
				elseif kind == ':' then
					var.placeholder = directive:sub(2)
				else
					error(("Invalid snippet component found:\nStart=%d, End=%d, P1=%q, P2=%q, Substring=%q"):format(i1, i2, p1, p2, body:sub(i1, i2)))
				end
			end
		end
		return var, i1, i2
	end

	-- Each pattern should return: `left, right, var` or `nil`
	-- Where `var` is { id, expression, placeholder, transform }
	-- NOTE:
	--  Ordering is deliberate. Patterns which may contain other patterns should
	--  come sooner (linearized).
	--    - ashkan, Thu 20 Aug 2020 03:47:25 PM JST
	local patterns = {
		function(body, start)
			local r = find_delimited(body, "${", "}", start)
			if not r then
				return
			end
			local i1, i2, subnodes = unpack(r)
			local var
			if not subnodes or #subnodes == 0 then
				var = assert(parse_var(body:sub(i1, i2)))
			else
				-- Remove the sub-snippets since they cause problems for parse_var
				-- to detect subsections.
				-- Replace them backwards so that indices aren't invalidated in the
				-- process.
				local removed = {}
				local new_i2 = i2
				for i = #subnodes, 1, -1 do
					local v = subnodes[i]
					local text = body:sub(v[1], v[2])
					removed[i] = text
					body = body:sub(1, v[1]-1)..char(i)..body:sub(v[2]+1)
					new_i2 = new_i2 - #text + 1
				end
				local text = body:sub(i1, new_i2)
				local function reconstitute(s)
					for i, text in ipairs(removed) do
						s = find_sub(s, text, char(i), 1, true)
					end
					return s
				end
				var = assert(parse_var(text))
				if var.placeholder then var.placeholder = reconstitute(var.placeholder) end
				if var.expression then var.expression = reconstitute(var.expression) end
				if var.transform then var.transform = reconstitute(var.transform) end
			end
			return i1, i2, var
		end;
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

		-- TODO:
		--  Disallow placeholder for $0 here?
		--    - ashkan, Thu 20 Aug 2020 04:18:00 PM JST

		if var.expression then
			local chunk_name = ("snippets[expression id=%s body=%q]"):format(tostring(var.id), body:sub(i1, i2))
			var.expression = U.make_lambda(var.expression, chunk_name)
		end
		if var.transform then
			local chunk_name = ("snippets[transform id=%s body=%q]"):format(tostring(var.id), body:sub(i1, i2))
			var.transform = U.make_lambda(var.transform, chunk_name)
		end
		-- TODO:
		--  Keep this here or move it into a companion function that replaces
		--  placeholders optionally with snippets? That way it could be used on
		--  the results of placeholders which return functions. I'm not sure how
		--  much to do automatically here.
		--    - ashkan, Thu 20 Aug 2020 04:12:01 PM JST
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

		local order
		if var.id then
			order = var.id
		elseif not var.id and var.transform then
			order = math.huge
		else
			order = -1
		end

		R[#R+1] = U.structure_variable(
			(var.id or 0) > 0,
			var.id,
			var.placeholder or var.expression or "",
			-- TODO:
			--  Keep negative ordering for variables with no id? And is -1 fine?
			--    - ashkan, Thu 20 Aug 2020 04:18:25 PM JST
			order,
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

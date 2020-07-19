--[[
snippet name
\tBody
\t${1:VALUE}
\t$1
\t$0
--]]
local U = require 'snippets.common'

-- Take a string containing the variable substitutions and
-- turn it into a structural representation of a snippet and
-- a dictionary of the variables it uses.
--
-- Example:
-- parse_snippet("for ${1:i}, ${2:v} in ipairs(${3:t}) do $0 end")
--   == { 'for '; 1; ' '; 2; ' in ipairs('...
local function parse_snippet(body, patterns)
	local R = {}
	-- TODO(ashkan): error patterns that we can check which don't show up in here.
	-- Each pattern should return either 1 or 2 things:
	-- 1. { variable_id, }
	-- 2. { variable_id, placeholder, }
	-- NOTE: Ordering is important!
	-- If one pattern may contain the other, it should be placed higher up.
	local patterns = patterns or {
		-- TODO(ashkan): allow an empty value in the :} part or throw an error?
		-- Pattern for ${1:default body}
		"%${(%d+):([^}]*)}",
		-- Pattern for $1, $2, etc..
		"%$(%d+)",
	}

	local variables = {}

	local start_position = 1
	for LOOP_IDX = 1, 10000000 do
		-- try to find a new variable to parse out.
		local next_value
		for i, pattern in ipairs(patterns) do
			local value = {body:find(pattern, start_position)}
			U.LOG_INTERNAL(LOOP_IDX, "checking", i, value)
			if #value > 0 then
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
			break
		end

		local left_pos, var_id, placeholder, right_pos
		if #next_value == 3 then
			left_pos, right_pos, var_id = unpack(next_value)
		else
			assert(#next_value == 4, #next_value)
			left_pos, right_pos, var_id, placeholder = unpack(next_value)
		end
		if not var_id then
			return nil, "var_id is nil"
		end
		var_id = tonumber(var_id)
		if not var_id then
			return nil, "var_id is not a number?"
		end

		if variables[var_id] then
			if placeholder ~= nil then
				return nil, "Multiple placeholders defined for variable $"..var_id
			end
		else
			variables[var_id] = {
				-- placeholder = placeholder;
				-- allows defining the placeholder later like: $1 ${1:alskdfj}
				placeholder = (variables[var_id] or {}).placeholder or placeholder;
			}
		end
		if left_pos ~= start_position then
			R[#R+1] = body:sub(start_position, left_pos - 1)
		end
		R[#R+1] = var_id
		start_position = right_pos+1
	end

	local tail = body:sub(start_position)
	if #tail > 0 then
		R[#R+1] = tail
	end
	return R, variables
end

return {
	parse_snippet = parse_snippet;
}
-- vim:noet sw=3 ts=3

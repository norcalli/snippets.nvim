-- Workflow:
-- 1. Turn a structure into a string to insert.
-- 2. Find the next marker.
-- 3. Substitute the text at that marker with the placeholder, if any.
-- 4. Allow switching to the next marker or undoing and going back to the previous.
-- 5. Repeat 2-4 until no more markers.
-- TODO(ashkan): bounds check to avoid going to markers which are from previous insertions or something like that?
local format = string.format
local api = vim.api
local splitter = require 'snippets.splitter'
local parser = require 'snippets.parser'
local U = require 'snippets.common'
local insert = table.insert
local concat = table.concat
local inspect = vim.inspect

local marker_with_placeholder_format = "<`{%d:%s}`>"
local replacement_marker_format = "<`%d`>"
local post_transform_marker_format = "<`|%d`>"
local zero_pattern = replacement_marker_format:format(0)

local stringify_structure

local function xor(a, b)
	return ((not a) ~= (not b)) and (a or b)
	-- return ((not a) ~= (not b)) and (a or b) or nil
end

local function get_placeholder(var)
	if var.placeholder then
		if type(var.placeholder) == 'function' then
			return tostring(var.placeholder())
		end
		if U.is_snippet(var.placeholder) then
			return var.placeholder
		end
		return tostring(var.placeholder)
	end
	return ""
end

local function null_if_empty(s)
	if s == "" then
		return
	end
	return s
end

local function check_merge(v1, v2, message)
	if v1 == v2 then
		return v1
	elseif (v1 or v2) ~= (v2 or v1) then
		error(message)
	else
		return (v1 or v2) 
	end
end

local function format_transform_marker(id)
	return post_transform_marker_format:format(id)
end

local TRANSFORM_CAPACITY = 100

local function merge_into_variables(v1, v2)
	local R = v1
	for var_id, var in pairs(v2) do
		local existing_var = v1[var_id]
		if existing_var then
			existing_var.transforms = vim.tbl_extend("error", existing_var.transforms, var.transforms)
			existing_var.placeholder = check_merge(
				existing_var.placeholder,
				var.placeholder,
				"Placeholder found in multiple places for var "..var_id.."\n"
					..inspect(existing_var.placeholder).." vs "..inspect(var.placeholder))
			existing_var.expression = check_merge(
				existing_var.expression,
				var.expression,
				"Expression found in multiple places for var "..var_id.."\n"
					..inspect(existing_var.expression).." vs "..inspect(var.expression))
			existing_var.transform = check_merge(
				existing_var.transform,
				var.transform,
				"Transform found in multiple places for var "..var_id.."\n"
					..inspect(existing_var.transform).." vs "..inspect(var.transform))
			existing_var.id = check_merge(
				existing_var.id,
				var.id,
				"id found in multiple places for var "..var_id)
			R[var_id] = existing_var
		else
			R[var_id] = var
		end
	end
	return R
end

stringify_structure = function(structure, variables)
	local seen = {}
	local transform_index = 0

	local function format_part(part)
		if type(part) == 'number' then
			local var_id = part
			local var = variables[var_id]
			-- $0 is special. It indicates the end of snippet. It should only
			-- occur once.
			if var_id == 0 then
				assert(not var or (var.placeholder or "") == "", "$0 shouldn't have a placeholder")
				assert(not seen[var_id], "$0 shouldn't occur more than once")
				seen[var_id] = 1
				U.LOG_INTERNAL("F", "zero var")
				return format(replacement_marker_format, var_id)
			else
				if not var then
					error(format("Variable %d found in structure, but not its variable dictionary", var_id))
				end
				if seen[var_id] then
					seen[var_id] = seen[var_id] + 1
					U.LOG_INTERNAL("F", "replacement var", var_id)
					-- var.count = var.count + 1
					-- TODO(ashkan): recursive snippets
					return replacement_marker_format:format(var_id)
				else
					seen[var_id] = 1
					-- var.count = (var.count or 0) + 1
					local placeholder = get_placeholder(var)
					local snippet
					if U.is_snippet(placeholder) then
						snippet = placeholder
					else
						local s, v = parser.parse_snippet(placeholder)
						snippet = { structure = s; variables = v; }
					end
					-- TODO(ashkan) do this here?
					merge_into_variables(variables, snippet.variables)
					local string_parts = {}
					for _, part in ipairs(snippet.structure) do
						insert(string_parts, format_part(part))
					end
					local stringified_placeholder = concat(string_parts)
					U.LOG_INTERNAL("F", "first var", var_id, stringified_placeholder)
					return marker_with_placeholder_format:format(var_id, stringified_placeholder)
				end
			end
		elseif type(part) == 'string' then
			U.LOG_INTERNAL("F", "normal string", part)
			return part
		elseif U.is_post_transform(part) then
			U.LOG_INTERNAL("F", "normal string", part)
			transform_index = transform_index + 1
			local var_id = transform_index / TRANSFORM_CAPACITY
			local marker = format_transform_marker(transform_index)
			variables[var_id] = {
				transforms = {part.transform};
				marker = marker;
			}
			return marker
			-- return replacement_marker_format:format(var_id)
		end
		error("Don't know how to stringify: "..inspect(part))
	end

	local R = {}
	for _, part in ipairs(structure) do
		R[#R+1] = format_part(part)
	end
	R = concat(R)

	for var_id, count in pairs(seen) do
		U.LOG_INTERNAL(var_id, count)
		variables[var_id] = variables[var_id] or {}
		variables[var_id].count = count
	end

	-- local R = format_part {
	-- 	structure = structure;
	-- 	variables = variables;
	-- }
	if not seen[0] then
		return R..zero_pattern
	end
	return R
end

local function apply_transforms(var, replacement_index, variables)
	assert(var.user_input)
	local transform = var.transforms[replacement_index]
	if transform then
		local chunkname = nil
		local params = U.make_params(var.id, var.user_input, variables)
		-- TODO(ashkan, 2020-08-16 02:33:21+0900) error instead?
		return U.evaluate_transform(transform, chunkname, params) or var.user_input
	end
	return var.user_input
end

local function entrypoint(structure, variables)
	U.LOG_INTERNAL(structure, variables)
	local body = assert(stringify_structure(structure, variables))
	U.LOG_INTERNAL('body', body)

	local row, col = unpack(api.nvim_win_get_cursor(0))
	local current_line = api.nvim_get_current_line()
	local lines = splitter("\n", true).collect(body)
	local line_count = #lines
	local tail_count = #lines[#lines]
	lines[1] = current_line:sub(1, col)..lines[1]
	lines[#lines] = lines[#lines]..current_line:sub(col+1)
	api.nvim_buf_set_lines(0, row-1, row, false, lines)
	local max_variable_index = 0
	for k in pairs(variables) do
		if k >= 1 then
			max_variable_index = math.max(k, max_variable_index)
		end
	end
	local current_variable_index = 0
	local R
	R = {
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance = function(offset)
			offset = offset or 1
			current_variable_index = current_variable_index + offset
			-- Go back and figure out what the user entered, and then replace all the
			-- instances of the replacement pattern with that.
			if current_variable_index > 1 then
				local var_id = current_variable_index-1
				local var = variables[var_id]
				if U.variable_needs_postprocessing(var, variables) then
					local what_the_user_wrote_pattern = marker_with_placeholder_format:format(var_id, "([^}]*)")
					local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
					-- Replace the first instance, which has a specific pattern and extract
					-- what the user wrote from inside of the pattern.
					for i, line in ipairs(tail) do
						var.user_input = line:match(what_the_user_wrote_pattern)
						if var.user_input then
							-- Do a transformation on post-processing.
							local replacement_text = apply_transforms(var, 1, variables)
							tail[i] = line:gsub(what_the_user_wrote_pattern, replacement_text)
							break
						end
					end
					local replacement_index = 1
					if var.user_input then
						local replacement_marker = replacement_marker_format:format(var_id)
						for i, line in ipairs(tail) do
							tail[i] = line:gsub(replacement_marker, function()
								replacement_index = replacement_index + 1
								return apply_transforms(var, replacement_index, variables)
							end)
						end
						api.nvim_buf_set_lines(0, row-1, -1, false, tail)
					else
						R.aborted = true
						-- TODO(ashkan, 2020-08-15 20:43:25+0900) consume all remaining things automatically?
						print(format(
								"Couldn't find what the user wrote for variable %d\n"..
								"This usually indicates that someone modified part of the markers we use to find the variable\n"..
								"For example the right brace (}) in <`{1:placeholder}`>",
								current_variable_index))
						print("Aborting the current snippet")
						api.nvim_command "mode"
						return true
					end
				end
			end
			U.LOG_INTERNAL("Current variable", current_variable_index)
			-- Jump to the 0 if we're done/finished
			if max_variable_index < current_variable_index then
				local post_transforms = {}
				for var_id, var in pairs(variables) do
					-- This is a post transform.
					if var_id > 0 and var_id < 1 then
						local tx_id = math.floor(var_id * TRANSFORM_CAPACITY)
						local fn = var.transforms[1]
						insert(post_transforms, {
							marker = assert(var.marker);
							-- marker = format_transform_marker(tx_id);
							-- fn = var.transforms[1];
							-- TODO(ashkan, 2020-08-17 12:59:28+0900) pcall?
							text = fn(U.make_params(nil, nil, variables));
							id = tx_id;
						})
					end
				end

				-- TODO(ashkan): can I figure out how much was inserted to determine
				-- the end region more granularly then until the entire end of file?
				-- TODO(ashkan, 2020-08-16 00:37:28+0900) use lazy loading interface.
				local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
				for i, line in ipairs(tail) do
					for _, transform in ipairs(post_transforms) do
						line = U.find_sub(line, transform.text, transform.marker, 1, true)
					end

					local j = line:find(zero_pattern, 1, true)
					if j then
						local col = j-1
						api.nvim_win_set_cursor(0, {row+i-1, col})
						local word = zero_pattern
						api.nvim_set_current_line(line:sub(1, col)..line:sub(col+#word+1))
						return true
					end
				end
				print(
					"Couldn't find end "..zero_pattern.."?\n"..
					"If you can reproduce this, a bug report would be appreciated.")
				return true
			end
			local var = variables[current_variable_index]

			-- if not var.count then
			-- 	var.count = 0
			-- 	for _, part in ipairs(structure) do
			-- 		if part == current_variable_index then
			-- 			var.count = var.count + 1
			-- 		end
			-- 	end
			-- end

			local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
			local marker_pattern = marker_with_placeholder_format:format(current_variable_index, "()([^}]*)()")
			for i, line in ipairs(tail) do
				local j, finish, inner_start, inner, inner_end = line:find(marker_pattern)
				if j then
					var.user_input = inner
					local col = j-1
					-- TODO(ashkan): how to make it highlight the word and then delete it
					-- if we type or jump ahead.
					if not U.variable_needs_postprocessing(var, variables) then
						local replacement_text = apply_transforms(var, current_variable_index, variables)
						api.nvim_win_set_cursor(0, {row+i-1, col})
						api.nvim_set_current_line(line:sub(1, col)..replacement_text..line:sub(finish+1))
						api.nvim_win_set_cursor(0, {row+i-1, col+#inner})
					else
						api.nvim_win_set_cursor(0, {row+i-1, inner_end-1})
					end
					return
				end
			end
			R.aborted = true
			return true
		end;
	}
	return R
end

return setmetatable({
	marker_with_placeholder_format = marker_with_placeholder_format;
	replacement_marker_format = replacement_marker_format;
	stringify_structure = stringify_structure;
}, {
	__call = function(_, ...) return entrypoint(...) end
})

-- vim:noet sw=3 ts=3


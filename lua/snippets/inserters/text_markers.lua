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
local post_transform_marker_format = "<`|%s`>"
-- local post_transform_marker_format = "<`|%d`>"
local zero_pattern = replacement_marker_format:format(0)

local function xor(a, b)
	return ((not a) ~= (not b)) and (a or b)
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

local function entrypoint(structure)
	local evaluator = U.evaluate_snippet(structure)

	local body
	do
		local inputs = {}
		for i, v in ipairs(evaluator.inputs) do
			inputs[i] = replacement_marker_format:format(v.id)
		end
		local S = evaluator.evaluate_structure(inputs)
		-- local placeholders = evaluator.evaluate_defaults({}, function(var)
		-- 	if type(var.default) == 'function' then
		-- 		return post_transform_marker_format:format(var.first_index)
		-- 	end
		-- 	return var.default
		-- end)
		local placeholders = evaluator.evaluate_inputs{}
		-- local placeholders = evaluator.evaluate_defaults({}, function(id)
			-- return replacement_marker_format:format(id)
		-- end)
		for i, v in ipairs(evaluator.inputs) do
			S[v.first_index] = marker_with_placeholder_format:format(v.id, placeholders[i])
		end
		for i, v in ipairs(evaluator.structure) do
			if U.is_variable(v) then
				if v.transform and not v.id then
					S[i] = post_transform_marker_format:format(i)
				end
			end
		end
		S[evaluator.zero_index or #S+1] = zero_pattern
		body = concat(S)
	end

	local undo_points = {}
	vim.cmd "let &undolevels = &undolevels"
	insert(undo_points, vim.fn.changenr())
	-- print("undo point", undo_points[#undo_points])

	U.LOG_INTERNAL('body', body)
	local row, col = unpack(api.nvim_win_get_cursor(0))
	local current_line = api.nvim_get_current_line()
	local lines = splitter("\n", true).collect(body)
	-- local line_count = #lines
	-- local tail_count = #lines[#lines]
	lines[1] = current_line:sub(1, col)..lines[1]
	lines[#lines] = lines[#lines]..current_line:sub(col+1)
	api.nvim_buf_set_lines(0, row-1, row, false, lines)

	local resolved_inputs = {}
	local current_index = 0

	local R
	R = {
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance = function(offset)
			offset = offset or 1
			if offset > 0 then
				-- Force an undopoint
				vim.cmd "let &undolevels = &undolevels"
				insert(undo_points, vim.fn.changenr())
				-- print("undo point", undo_points[#undo_points])
			else
				-- print("jumping to undo point", undo_points[#undo_points])
				vim.cmd("undo "..(table.remove(undo_points) - 1))
			end
			current_index = math.max(math.min(current_index + offset, #evaluator.inputs + 1), 0)
			-- D(current_index)
			if current_index == 0 then
				R.aborted = true
				return true
			end
			local updated_structure

			-- Go back and figure out what the user entered, and then replace all the
			-- instances of the replacement pattern with that.
			if current_index > 1 then
				local input_index = current_index - 1
				local var = evaluator.inputs[input_index]
				U.LOG_INTERNAL("advance post process", var.id, var)
				if true then
				-- if U.variable_needs_postprocessing(var, variables) then
					local user_input_pattern = marker_with_placeholder_format:format(var.id, "([^}]*)")
					local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
					-- Replace the first instance, which has a specific pattern and extract
					-- what the user wrote from inside of the pattern.
					for i, line in ipairs(tail) do
						-- if offset < 0 then
						-- 	D(i, line)
						-- end
						local user_input = line:match(user_input_pattern)
						if user_input then
							resolved_inputs[input_index] = user_input
							updated_structure = evaluator.evaluate_structure(resolved_inputs)
							tail[i] = line:gsub(user_input_pattern, updated_structure[var.first_index])
							break
						end
					end
					local replacement_index = var.first_index
					if updated_structure then
						local replacement_marker = replacement_marker_format:format(var.id)
						for i, line in ipairs(tail) do
							tail[i] = line:gsub(replacement_marker, function()
								for j = replacement_index + 1, #evaluator.structure do
									local v = updated_structure[j]
									if U.is_variable(v) and v.id == var.id then
										replacement_index = j
										return updated_structure[j]
									end
								end
								return updated_structure[var.first_index]
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
								current_index))
						print("Aborting the current snippet")
						api.nvim_command "mode"
						return true
					end
				end
			end

			U.LOG_INTERNAL("Current variable", current_index)
			-- Jump to the 0 if we're done/finished
			if current_index > #evaluator.inputs then
				local post_transforms = {}
				for i, v in pairs(evaluator.structure) do
					-- This is a post transform.
					if U.is_variable(v) and v.transform and not v.id then
						updated_structure = updated_structure or evaluator.evaluate_structure(resolved_inputs)
						insert(post_transforms, {
							marker = post_transform_marker_format:format(i);
							text = assert(updated_structure)[i];
							id = i;
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

			-- if not var.count then
			-- 	var.count = 0
			-- 	for _, part in ipairs(structure) do
			-- 		if part == current_index then
			-- 			var.count = var.count + 1
			-- 		end
			-- 	end
			-- end

			local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
			local marker_pattern = marker_with_placeholder_format:format(current_index, "()([^}]*)()")
			for i, line in ipairs(tail) do
				local j, finish, inner_start, inner, inner_end = line:find(marker_pattern)
				if j then
					local col = j-1
					-- TODO(ashkan, Tue 18 Aug 2020 01:34:59 PM JST) for fully resolved variables, skip the placeholder.
					local new_inner_text
					-- if type(evaluator.inputs[current_index].default) == 'function' then
					-- 	new_inner_text = evaluator.evaluate_inputs(resolved_inputs)
					-- end
					new_inner_text = evaluator.evaluate_inputs(resolved_inputs)[current_index]
					-- D("new_inner text", current_index, inner, new_inner_text)
					if new_inner_text then
						local text = new_inner_text
						api.nvim_win_set_cursor(0, {row+i-1, col})
						api.nvim_set_current_line(line:sub(1, inner_start-1)..text..line:sub(inner_end))
						api.nvim_win_set_cursor(0, {row+i-1, inner_start+#text-1})
					else
						api.nvim_win_set_cursor(0, {row+i-1, inner_end-1})
					end

					-- -- TODO(ashkan): how to make it highlight the word and then delete it
					-- -- if we type or jump ahead.
					-- if false then
					-- -- if not U.variable_needs_postprocessing(var, variables) then
					-- 	-- local replacement_text = apply_transforms(var, current_index, variables)
					-- 	-- api.nvim_win_set_cursor(0, {row+i-1, col})
					-- 	-- api.nvim_set_current_line(line:sub(1, col)..replacement_text..line:sub(finish+1))
					-- 	-- api.nvim_win_set_cursor(0, {row+i-1, col+#inner})
					-- else
					-- 	api.nvim_win_set_cursor(0, {row+i-1, inner_end-1})
					-- end
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


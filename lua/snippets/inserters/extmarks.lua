local api = vim.api
local U = require("snippets/common")
local ns = api.nvim_create_namespace("")

local marker_with_placeholder_format = "${%d:%s}"
local replacement_marker_format = "$%d"
local post_transform_marker_format = "${|%s}"
local zero_pattern = replacement_marker_format:format(0)

local function set_extmark(lnum, col, len)
	return api.nvim_buf_set_extmark(0, ns, lnum - 1, col, {
		end_col = col + len,
		hl_group = "Visual",
	})
end

local function cleanup_marks(marks)
	for _, v in ipairs(marks) do
		api.nvim_buf_del_extmark(0, ns, v)
	end
end

local function set_marks(lnum, structure, S, current_index)
	local row, col = 0, 0
	local marks = {}
	for i, v in ipairs(structure) do
		if U.is_variable(v) then
			local len = #S[i]
			if v.is_input and v.id >= current_index then
				local m = set_extmark(lnum + row, col, len)
				table.insert(marks, m)
			end

			col = col + len
		else
			local tail = v:gsub("[^\n]*\n", function()
				row = row + 1
				col = 0
				return ""
			end)
			col = col + #tail
		end
	end

	return marks
end

local function update_structure(evaluator, resolved_inputs)
	local inputs = {}
	for i, v in ipairs(evaluator.inputs) do
		inputs[i] = resolved_inputs[i] or replacement_marker_format:format(v.id)
	end

	local S = evaluator.evaluate_structure(inputs)

	local placeholders = evaluator.evaluate_inputs(resolved_inputs)
	for i, v in ipairs(evaluator.inputs) do
		if not resolved_inputs[i] then
			S[v.first_index] = marker_with_placeholder_format:format(v.id, placeholders[i])
		end
	end

	-- Add markers for anonymous transforms to be evaluated at the end of the expansion
	for i, v in ipairs(evaluator.structure) do
		if U.is_variable(v) and v.transform and not v.id then
			S[i] = post_transform_marker_format:format(i)
		end
	end

	-- Finally, place a marker for where the cursor should finish at the end of expansion
	S[evaluator.zero_index or #S + 1] = replacement_marker_format:format(0)

	return S
end

local function entrypoint(structure)
	local evaluator = U.evaluate_snippet(structure)

	local S = update_structure(evaluator, {})

	local body = table.concat(S)
	local lines = vim.split(body, "\n")

	local lnum_start, col = unpack(api.nvim_win_get_cursor(0))
	local lnum_end = lnum_start + #lines
	local current_line = api.nvim_get_current_line()

	lines[1] = current_line:sub(1, col) .. lines[1]
	lines[#lines] = lines[#lines] .. current_line:sub(col + 1)

	-- Write the snippet to the buffer
	api.nvim_buf_set_lines(0, lnum_start - 1, lnum_start, false, lines)

	local current_index = 0
	local resolved_inputs = {}
	local marks = {}

	local R
	R = {
		advance = function(offset)
			cleanup_marks(marks)
			offset = offset or 1
			current_index = math.max(math.min(current_index + offset, #evaluator.inputs + 1), 0)
			if current_index == 0 then
				R.aborted = true
				cleanup_marks(marks)
				return true
			end

			local snippet = api.nvim_buf_get_lines(0, lnum_start - 1, lnum_end, false)

			-- Find what the user entered for the previous variable and update the structure
			if current_index > 1 then
				local input_index = current_index - 1
				local var = evaluator.inputs[input_index]
				local user_input_pattern = marker_with_placeholder_format:format(var.id, "([^}]*)")

				for i, line in ipairs(snippet) do
					local user_input = line:match(user_input_pattern)
					if user_input then
						resolved_inputs[input_index] = user_input
						S = update_structure(evaluator, resolved_inputs)
						snippet[i] = line:gsub(user_input_pattern, S[var.first_index])
						break
					end
				end

				if resolved_inputs[input_index] then
					local replacement_index = var.first_index
					local replacement_marker = replacement_marker_format:format(var.id)
					for i, line in ipairs(snippet) do
						snippet[i] = line:gsub(replacement_marker, function()
							for j = replacement_index + 1, #evaluator.structure do
								local v = evaluator.structure[j]
								if U.is_variable(v) and v.id == var.id then
									replacement_index = j
									return S[j]
								end
							end
							return S[var.first_index]
						end)
					end
					-- set_marks(lnum_start, evaluator, updated_structure, current_index)
				else
					R.aborted = true
					print("Aborting the current snippet")
					api.nvim_command("mode")
					return true
				end
			end

			-- User has moved past the last variable, so apply transformations and move the cursor to the
			-- zero point
			if current_index > #evaluator.inputs then
				local post_transforms = {}
				for i, v in pairs(evaluator.structure) do
					if U.is_variable(v) and v.transform and not v.id then
						table.insert(post_transforms, {
							marker = post_transform_marker_format:format(i),
							text = assert(S)[i],
							id = i,
						})
					end
				end

				local zero_point
				local post_transform_index = 1
				for i, line in ipairs(snippet) do
					local j
					while post_transforms[post_transform_index] do
						local transform = post_transforms[post_transform_index]
						line, j = U.find_sub(line, transform.text, transform.marker, 1, true)
						if j then
							post_transform_index = post_transform_index + 1
						else
							break
						end
					end

					line, j = U.find_sub(line, "", zero_pattern, 1, true)
					if j then
						zero_point = { lnum_start + i - 1, j - 1 }
					end

					snippet[i] = line

					if zero_point and not post_transforms[post_transform_index] then
						break
					end
				end

				if zero_point then
					api.nvim_buf_set_lines(0, lnum_start - 1, -1, false, snippet)
					api.nvim_win_set_cursor(0, zero_point)
				end

				return true
			end

			-- Move the cursor to the next variable and update the placeholder text
			local marker_pattern = marker_with_placeholder_format:format(current_index, "()[^}]*()")
			local row
			for i, line in ipairs(snippet) do
				local j, _, inner_start, inner_end = line:find(marker_pattern)
				if j then
					row = lnum_start + i
					local placeholder = evaluator.evaluate_inputs(resolved_inputs)[current_index]
					if placeholder then
						snippet[i] = line:sub(1, inner_start - 1) .. placeholder .. line:sub(inner_end)
						col = inner_start + #placeholder
					else
						col = inner_end
					end
					break
				end
			end

			if row then
				api.nvim_buf_set_lines(0, lnum_start - 1, -1, false, snippet)
				api.nvim_win_set_cursor(0, { row - 1, col - 1 })
				marks = set_marks(lnum_start, evaluator.structure, S, current_index)
			else
				R.aborted = true
				return true
			end
		end,
	}

	return R
end

return entrypoint

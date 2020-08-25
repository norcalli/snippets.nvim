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

local vim = vim
local api = vim.api
local U = require 'snippets.common'
local nvim = require 'snippets.nvim'
local format = string.format
local concat = table.concat
local insert = table.insert
local max = math.max
local min = math.min

local M = {
	input_prompt = "┤ $%s ├";
	-- input_prompt = "Input $%s";
	current_input_format = "%s";
	-- current_input_format = "|%s|";
	highlight = 'Question';
}

local function char_length(s)
	return vim.str_utfindex(s)
end

local function floaty_popup(opts)
	opts = opts or {}
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(buf, 'bufhidden', 'delete')
	local win
	local uis = api.nvim_list_uis()
	local ui_min_width = math.huge
	local ui_min_height = math.huge
	for _, ui in ipairs(uis) do
		ui_min_width = math.min(ui.width, ui_min_width)
		ui_min_height = math.min(ui.height, ui_min_height)
	end
	local O = {
		relative = opts.relative or 'editor';
		width = opts.width or floor(ui_min_width * 50 / 100);
		height = opts.height or floor(ui_min_height * 50 / 100);
		win = opts.win;
		bufpos = opts.bufpos;
		col = opts.col;
		row = opts.row;
		anchor = 'NW';
		style = 'minimal';
		focusable = opts.focusable or false;
	}
	-- O.col = opts.col or floor((ui_min_width - O.width) / 2)
	-- O.row = opts.row or floor((ui_min_height - O.height) / 2)
	win = api.nvim_open_win(buf, 0, O)
	api.nvim_win_set_option(win, 'wrap', false)
	api.nvim_buf_set_option(buf, 'ul', -1)
	api.nvim_win_set_option(win, 'concealcursor', 'nc')
	return buf, win, O
end

local function max_line_length(lines)
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(#line, width)
	end
	return width
end

local function to_lines(s)
	if type(s) == 'table' then
		return to_lines(concat(s))
	end
	return vim.split(s, '\n', true)
end

local function center_pad(width, s)
	-- s = "┤"..s.."├"
	local n = char_length(s)
	local left = math.max(math.floor((width - n) / 2), 0)
	local right = width - n - left
	return ("─"):rep(left)..s..(("─"):rep(right))
end

local function lines_to_position(lines)
	return {
		math.max(#lines - 1, 0),
		#lines[#lines]
		-- math.max(char_length(lines[#lines]) - 1, 0)
	}
end

local function position_add(a, b)
	return {
		a[1] + b[1],
		a[2] + b[2]
	}
end

local ns = api.nvim_create_namespace("snippets-floaty")

local function entrypoint(structure)
	local window_width = api.nvim_win_get_width(0)
	local window_height = api.nvim_win_get_height(0)
	local evaluator = U.evaluate_snippet(structure)

	local ft = nvim.bo.filetype

	local dummy_text = vim.split(concat(evaluator.evaluate_structure(evaluator.evaluate_inputs{})), '\n', true)
	-- local dummy_text = vim.split(concat(evaluator.evaluate_structure(evaluator.evaluate_defaults({}, function() return (" "):rep(15) end))), '\n', true)
	local width = max(max_line_length(dummy_text), 10)

	local start_win = api.nvim_get_current_win()
	local start_buf = api.nvim_get_current_buf()
	local start_pos = api.nvim_win_get_cursor(start_win)
	local start_win_pos = api.nvim_win_get_position(start_win)
	local preview_buf, preview_win, preview_opts = floaty_popup {
		relative = 'win';
		win = start_win;
		bufpos = {start_pos[1]-1, start_pos[2]};
		col = start_win_pos[2];
		row = api.nvim_win_get_config(start_win).relative ~= "" and start_win_pos[1] or 0;
		width = width;
		height = #dummy_text;
	}
	local header_buf, header_win, header_opts = floaty_popup {
		relative = 'win';
		win = start_win;
		bufpos = {start_pos[1]-1, start_pos[2]};
		col = preview_opts.col;
		row = preview_opts.row + preview_opts.height;
		width = preview_opts.width;
		height = 1;
	}
	local input_buf, input_win, input_opts = floaty_popup {
		focusable = true;
		relative = 'win';
		win = start_win;
		bufpos = {start_pos[1]-1, start_pos[2]};
		col = header_opts.col;
		row = header_opts.row + header_opts.height;
		width = preview_opts.width;
		height = 3;
	}
	api.nvim_set_current_win(input_win)

	nvim.bo[preview_buf].filetype = ft

	local function set_text(S)
		local cursor_offset = {0, 0}
		for i, v in ipairs(S) do
			if i == evaluator.zero_index then
				break
			end
			local tail = v:gsub("[^\n]*\n", function()
				cursor_offset[1] = cursor_offset[1] + 1
				cursor_offset[2] = 0
				return ""
			end)
			cursor_offset[2] = cursor_offset[2] + #tail
		end

		local body = concat(S)
		U.LOG_INTERNAL("set_text", body)
		assert(type(body) == 'string')
		local R = {}

		local row, col = unpack(start_pos)
		local tail = api.nvim_buf_get_lines(start_buf, row-1, row, false)
		-- tail[1] = tail[1] or ""
		local c_line_start = tail[1]:sub(1, col)
		local c_line_end = tail[1]:sub(col+1)

		local lines = vim.split(body, "\n", true)
		-- local first_line_length = #lines[1]
		lines[1] = c_line_start..lines[1]
		lines[#lines] = lines[#lines]..c_line_end

		for i, line in ipairs(lines) do
			insert(R, line)
		end
		for i = 2, #tail do
			insert(R, tail[i])
		end

		U.LOG_INTERNAL("set_text output", lines)

		api.nvim_buf_set_lines(start_buf, row-1, row, false, R)
		api.nvim_set_current_win(start_win)
		api.nvim_win_set_cursor(start_win, {row + cursor_offset[1], (#lines == 1 and col or 0) + cursor_offset[2]})
	end

	local resolved_inputs = {}
	-- local resolved_inputs = evaluator.evaluate_defaults({}, function(var)
	-- 	return format("$%d", var.id)
	-- end)
	local current_index = 0

	local function update_preview(I, force)
		I = I or resolved_inputs
		local inputs = evaluator.evaluate_defaults(I, function(var)
			if type(var.default) == 'string' then
				return format("${%s:%s}", var.id, var.default)
			else
				return format("${%s}", var.id)
			end
		end)
		local structure = evaluator.evaluate_structure(inputs)
		local current_region
		if evaluator.inputs[current_index] then
			local first_index = evaluator.inputs[current_index].first_index
			local input_prefix = {unpack(structure, 1, first_index - 1)}
			local p1 = lines_to_position(to_lines(input_prefix))
			local p2 = lines_to_position(to_lines(structure[first_index]))
			current_region = {
				p1,
				{
					p2[1] + p1[1],
					(p2[1] > 0 and 0 or p1[2]) + p2[2],
				}
			}
		end
		local lines = to_lines(structure)
		local new_width = max(max_line_length(lines), 10)
		if I[current_index] then
			new_width = max(new_width, max_line_length(to_lines(I[current_index])) + 5)
		end
		new_width = min(new_width, window_width)
		local new_height = #lines
		new_height = min(new_height, math.floor(window_height * 0.5))
		local config_changed = force or false
		if new_width ~= preview_opts.width then
			config_changed = true
			preview_opts.width = new_width
			input_opts.width = new_width
			header_opts.width = new_width
		end
		if new_height ~= preview_opts.height then
			config_changed = true
			preview_opts.height = new_height
			header_opts.row = preview_opts.row + preview_opts.height
			input_opts.row = header_opts.row + header_opts.height
			-- TODO:
			--  calculate input height too.
			--    - ashkan, Sun 23 Aug 2020 07:33:28 PM JST
			-- input_opts.height = input_height
		end
		if config_changed then
			api.nvim_win_set_config(preview_win, preview_opts)
			api.nvim_win_set_config(input_win, input_opts)
			api.nvim_win_set_config(header_win, header_opts)
		end
		local current_variable = evaluator.inputs[current_index]
		local current_variable_name = "0"
		if current_variable then
			current_variable_name = current_variable.id
		end
		local header_lines = {
			center_pad(header_opts.width, M.input_prompt:format(current_variable_name))
		}
		api.nvim_buf_set_lines(header_buf, 0, -1, false, header_lines)
		api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
		if current_region then
			-- TODO:
			--  Pick a smarter region?
			--    - ashkan, Sun 23 Aug 2020 09:16:14 PM JST
			api.nvim_buf_clear_namespace(preview_buf, ns, 0, -1)
			local r1, c1, r2, c2 = current_region[1][1], current_region[1][2], current_region[2][1], current_region[2][2]
			if r1 == r2 then
				api.nvim_buf_add_highlight(preview_buf, ns, M.highlight, r1, c1, c2)
			else
				api.nvim_buf_add_highlight(preview_buf, ns, M.highlight, r1, c1, -1)
				for i = r1 + 1, r2 - 1 do
					api.nvim_buf_add_highlight(preview_buf, ns, M.highlight, i, 0, -1)
				end
				api.nvim_buf_add_highlight(preview_buf, ns, M.highlight, r2, 0, c2)
			end
		end
	end

	local function user_input()
		return concat(api.nvim_buf_get_lines(input_buf, 0, -1, false), '\n')
	end

	local function cleanup()
		api.nvim_win_close(preview_win, true)
		api.nvim_win_close(header_win, true)
		api.nvim_win_close(input_win, true)
		api.nvim_set_current_win(start_win)
		api.nvim_win_set_cursor(start_win, start_pos)
	end

	update_preview()

	api.nvim_buf_attach(input_buf, false, {
		on_lines = vim.schedule_wrap(function()
			local inputs = {}
			for i, v in ipairs(resolved_inputs) do
				inputs[i] = v
			end
			inputs[current_index] = M.current_input_format:format(user_input())
			update_preview(inputs)
		end);
	})

	api.nvim_buf_set_keymap(input_buf, 'i', '<c-g>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(0)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-c>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(0)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-k>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(1)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-j>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(-1)<cr>', { noremap = true; silent = true })

	local R

	function SNIPPETS_FLOATY_HANDLER(cmd)
		if cmd == 0 then
			cmd = -1000
		end
		if require'snippets'.has_active_snippet() then
			return require'snippets'.advance_snippet(cmd)
		end
		return R.advance(cmd)
	end

	R = {
		aborted = false;
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance = function(offset)
			offset = offset or 1
			current_index = max(min(current_index + offset, #evaluator.inputs + 1), 0)

			if current_index == 0 then
				R.aborted = true
				cleanup()
				return true
			end

			if offset > 0 and current_index > 1 then
				resolved_inputs[current_index - 1] = user_input()
			end

			-- Finished case.
			if current_index > #evaluator.inputs then
				R.finished = true
				cleanup()
				set_text(evaluator.evaluate_structure(resolved_inputs))
				return true
			else
				local evaluated_inputs, evaluated_vars = evaluator.evaluate_inputs(resolved_inputs)
				vim.schedule(function()
					update_preview()
					local data = vim.split(evaluated_inputs[current_index], '\n', true)
					api.nvim_buf_set_lines(input_buf, 0, -1, false, data)
					api.nvim_win_set_cursor(input_win, {#data, #data[#data]})
				end)
			end
		end
	}
	return R
end

return setmetatable(M, {
	__call = function(_, ...) return entrypoint(...) end;
})
-- vim:noet sw=3 ts=3


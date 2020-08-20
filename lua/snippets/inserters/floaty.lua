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

local M = {
	input_prompt = "Input $%d>";
}

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
		anchor = 'NW';
		style = 'minimal';
		focusable = opts.focusable or false;
	}
	O.col = opts.col
	O.row = opts.row
	-- O.col = opts.col or floor((ui_min_width - O.width) / 2)
	-- O.row = opts.row or floor((ui_min_height - O.height) / 2)
	win = api.nvim_open_win(buf, 0, O)
	api.nvim_win_set_option(win, 'wrap', false)
	api.nvim_buf_set_option(buf, 'ul', -1)
	api.nvim_win_set_option(win, 'concealcursor', 'nc')
	return buf, win, O
end

local function entrypoint(structure)
	local evaluator = U.evaluate_snippet(structure)

	local ft = nvim.bo.filetype

	local width = 0
	local dummy_text = vim.split(concat(evaluator.evaluate_structure(evaluator.evaluate_defaults({}, function() return (" "):rep(15) end))), '\n', true)
	for _, line in ipairs(dummy_text) do
		width = math.max(#line, width)
	end

	local start_win = api.nvim_get_current_win()
	local start_buf = api.nvim_get_current_buf()
	local start_pos = api.nvim_win_get_cursor(start_win)
	local preview_buf, preview_win, preview_opts = floaty_popup {
		relative = 'win';
		win = start_win;
		col = start_pos[2];
		row = start_pos[1] - 1;
		width = width;
		height = #dummy_text + 1;
	}
	local input_buf, input_win, input_opts = floaty_popup {
		focusable = true;
		relative = 'win';
		win = start_win;
		col = start_pos[2];
		row = start_pos[1] + preview_opts.height - 1;
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
		local tail = api.nvim_buf_get_lines(start_buf, row-1, -1, false)
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
	local current_index = 0

	local function update_preview(I)
		local inputs = evaluator.evaluate_defaults(I or resolved_inputs, function(var)
			if var.default == "" then
				return format("${%s}", var.id)
			end
		end)
		local lines = vim.split(concat(evaluator.evaluate_structure(inputs)), "\n", true)
		lines[preview_opts.height] = M.input_prompt:format(current_index)
		api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
	end

	local function user_input()
		return concat(api.nvim_buf_get_lines(input_buf, 0, -1, false), '\n')
	end

	local function cleanup()
		api.nvim_win_close(preview_win, true)
		api.nvim_win_close(input_win, true)
		api.nvim_set_current_win(start_win)
		api.nvim_win_set_cursor(start_win, start_pos)
	end

	update_preview()

	api.nvim_buf_attach(input_buf, false, {
		on_lines = vim.schedule_wrap(function()
			-- local inputs = evaluator.evaluate_defaults(resolved_inputs, function(var)
			-- 	if var.default == "" then
			-- 		return format("${%s}", var.id)
			-- 	end
			-- end)
			-- inputs[current_index] = user_input()
			-- update_preview(inputs)
			resolved_inputs[current_index] = user_input()
			update_preview()
		end);
	})

	api.nvim_buf_set_keymap(input_buf, 'i', '<c-g>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(0)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-c>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(0)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-k>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(1)<cr>', { noremap = true; silent = true })
	api.nvim_buf_set_keymap(input_buf, 'i', '<c-j>', '<Cmd>lua SNIPPETS_FLOATY_HANDLER(-1)<cr>', { noremap = true; silent = true })

	local R

	function SNIPPETS_FLOATY_HANDLER(cmd)
		if cmd == 0 then
			require'snippets'.advance_snippet(-1000)
		elseif cmd == 1 then
			require'snippets'.advance_snippet(1)
		elseif cmd == -1 then
			require'snippets'.advance_snippet(-1)
		end
	end

	R = {
		aborted = false;
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance = function(offset)
			offset = offset or 1
			current_index = math.max(math.min(current_index + offset, #evaluator.inputs + 1), 0)

			if current_index == 0 then
				R.aborted = true
				cleanup()
				return true
			end

			if current_index > 1 then
				resolved_inputs[current_index - 1] = user_input()
			end

			-- Finished case.
			if current_index > #evaluator.inputs then
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


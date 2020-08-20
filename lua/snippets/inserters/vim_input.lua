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

local function entrypoint(structure)
  local evaluator = U.evaluate_snippet(structure)

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

    local row, col = unpack(api.nvim_win_get_cursor(0))
    local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
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

    api.nvim_buf_set_lines(0, row-1, -1, false, R)
    api.nvim_win_set_cursor(0, {row + cursor_offset[1], (#lines == 1 and col or 0) + cursor_offset[2]})
  end

  local resolved_inputs = {}
  local current_index = 0

  local function render_input_display()
    local inputs = evaluator.evaluate_defaults(resolved_inputs, function(var)
      if var.default == "" then
        return format("${%s}", var.id)
      end
    end)
    return concat(evaluator.evaluate_structure(inputs))
  end

  local R
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
        return true
      end

      -- Finished case.
      if current_index > #evaluator.inputs then
        set_text(evaluator.evaluate_structure(resolved_inputs))
        return true
      end

      local evaluated_inputs, evaluated_vars = evaluator.evaluate_inputs(resolved_inputs)
      local current_input_id = evaluator.inputs[current_index].id
      local current_input_placeholder = evaluated_inputs[current_index]

      local ok = pcall(function()
        vim.cmd "mode"
        local value = nvim.fn.input(format("%s\n%s> ", render_input_display(), current_input_id), current_input_placeholder)
        resolved_inputs[current_index] = value
      end)
      return R.advance(ok and 1 or -1)
    end
  }
  return R
end

return entrypoint
-- vim:noet sw=3 ts=3

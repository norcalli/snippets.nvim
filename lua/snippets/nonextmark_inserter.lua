-- Workflow:
-- 1. Turn a structure into a string to insert.
-- 2. Find the next marker.
-- 3. Substitute the text at that marker with the placeholder, if any.
-- 4. Allow switching to the next marker or undoing and going back to the previous.
-- 5. Repeat 2-4 until no more markers.
-- TODO(ashkan): bounds check to avoid going to markers which are from previous insertions or something like that?
local format = string.format
local api = vim.api
local splitter = require 'splitter'
local parser = require 'snippets.parser'

local marker_with_placeholder_format = "<`{%d:%s}`>"
local replacement_marker_format = "<`%d`>"
local zero_pattern = replacement_marker_format:format(0)

local function stringify_structure(structure, variables)
  local R = {}

  local seen = {}
  for i, part in ipairs(structure) do
    if type(part) == 'number' then
      local var_id = part
      local var = variables[var_id]
      -- $0 is special. It indicates the end of snippet. It should only
      -- occur once.
      if var_id == 0 then
        assert(not var or var.placeholder == nil, "$0 shouldn't have a placeholder")
        assert(not seen[var_id], "$0 shouldn't occur more than once")
        part = format(replacement_marker_format, var_id)
        seen[var_id] = true
      else
        if not var then
          error(format("Variable %d found in structure but not variable dictionary", i))
        end
        if seen[var_id] then
          var.count = var.count + 1
          -- TODO(ashkan): recursive snippets
          part = format(replacement_marker_format, var_id)
        else
          var.count = (var.count or 0) + 1
          local placeholder = var.placeholder or ""
          do
            local s = parser.parse_snippet(placeholder)
            for i, part in ipairs(s) do
              if type(part) == 'number' then
                local subvar = assert(variables[part], "Encountered out of order variables.")
                subvar.count = (subvar.count or 0) + 1
                s[i] = replacement_marker_format:format(part)
              end
            end
            placeholder = table.concat(s)
          end
          part = format(marker_with_placeholder_format, var_id, placeholder)
          seen[var_id] = true
        end
      end
    elseif type(part) == 'string' then
    else
      error(format("Invalid type in structure: %d, %q", i, type(part)))
    end
    R[i] = part
  end
  if not seen[0] then
    R[#R+1] = zero_pattern
  end
  return table.concat(R)
end

local function entrypoint(structure, variables)
  local body = assert(stringify_structure(structure, variables))

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
    max_variable_index = math.max(k, max_variable_index)
  end
  local current_variable_index = 0
  return {
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
        if var.count > 1 then
          local what_the_user_wrote_pattern = marker_with_placeholder_format:format(var_id, "([^}]*)")
          print(what_the_user_wrote_pattern)
          local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
          local what_the_user_wrote
          for i, line in ipairs(tail) do
            what_the_user_wrote = line:match(what_the_user_wrote_pattern)
            if what_the_user_wrote then
              tail[i] = line:gsub(marker_with_placeholder_format:format(var_id, "[^}]*"), what_the_user_wrote)
              break
            end
          end
          if what_the_user_wrote then
            local replacement_marker = replacement_marker_format:format(var_id)
            for i, line in ipairs(tail) do
              tail[i] = line:gsub(replacement_marker, what_the_user_wrote)
            end
            api.nvim_buf_set_lines(0, row-1, -1, false, tail)
          else
            print("Someone dun did goofed.", current_variable_index)
          end
        end
      end
      print("Current variable", current_variable_index)
      -- Jump to the 0 if we're done
      if max_variable_index < current_variable_index then
        -- TODO(ashkan): can I figure out how much was inserted to determine
        -- the end region more granularly then until the entire end of file?
        local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
        for i, line in ipairs(tail) do
          local j = line:find(zero_pattern, 1, true)
          if j then
            local col = j-1
            api.nvim_win_set_cursor(0, {row+i-1, col})
            local word = zero_pattern
            api.nvim_set_current_line(line:sub(1, col)..line:sub(col+#word+1))
            return true
          end
        end
        error("Couldn't find end "..zero_pattern.."??????????")
      end
      local var = variables[current_variable_index]

      if not var.count then
        var.count = 0
        for _, part in ipairs(structure) do
          if part == current_variable_index then
            var.count = var.count + 1
          end
        end
      end

      local tail = api.nvim_buf_get_lines(0, row-1, -1, false)
      local marker_pattern = marker_with_placeholder_format:format(current_variable_index, "()([^}]*)()")
      for i, line in ipairs(tail) do
        local j, finish, inner_start, inner, inner_end = line:find(marker_pattern)
        if j then
          local col = j-1
          -- TODO(ashkan): how to make it highlight the word and then delete it
          -- if we type or jump ahead.
          if var.count == 1 then
            api.nvim_win_set_cursor(0, {row+i-1, col})
            api.nvim_set_current_line(line:sub(1, col)..inner..line:sub(finish+1))
            api.nvim_win_set_cursor(0, {row+i-1, col+#inner})
          else
            api.nvim_win_set_cursor(0, {row+i-1, inner_end-1})
          end
          break
        end
      end
    end;
  }
end

return setmetatable({
  marker_with_placeholder_format = marker_with_placeholder_format;
  replacement_marker_format = replacement_marker_format;
  stringify_structure = stringify_structure;
}, {
  __call = function(_, ...) return entrypoint(...) end
})

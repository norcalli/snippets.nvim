local api = vim.api
local U = require("snippets/common")

local ns = api.nvim_create_namespace("")

local M = {}

-- These are user-configurable
M.marker_with_placeholder_format = "${%d:%s}"
M.zero_pattern = "$0"
M.hl_group = "Visual"

local function set_extmark(bufnr, id, line, col, end_line, end_col, hl_group)
  api.nvim_buf_set_extmark(bufnr, ns, line, col, {
    id = id,
    end_line = end_line,
    end_col = end_col,
    hl_group = hl_group,
    right_gravity = false,
    end_right_gravity = true,
  })
end

local function get_extmark_pos(bufnr, id)
  local row, col, details = unpack(api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true }))
  return row, col, details and details.end_row or row, details and details.end_col or col
end

local function set_extmark_text(bufnr, id, text)
  local row, col, end_row, end_col = get_extmark_pos(bufnr, id)
  api.nvim_buf_set_text(bufnr, row, col, end_row, end_col, vim.split(text, "\n"))
end

local function cleanup(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.register_keystroke_callback(nil, ns)
end

local function entrypoint(structure)
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local evaluator = U.evaluate_snippet(structure)

  -- Evalute the structure and insert placeholder markers for input variables
  local S = evaluator.evaluate_structure({})

  local placeholders = evaluator.evaluate_inputs({})
  for i, v in ipairs(evaluator.inputs) do
    S[v.first_index] = M.marker_with_placeholder_format:format(v.id, placeholders[i])
  end

  -- If the snippet contains a $0, insert a marker for the where the cursor will end up
  if evaluator.zero_index then
    S[evaluator.zero_index] = M.zero_pattern
  end

  local cursor_mark_id

  -- Write the snippet to the buffer and create the extmarks
  do
    local lnum, col = unpack(api.nvim_win_get_cursor(win))

    local current_line = api.nvim_get_current_line()
    local prefix = current_line:sub(1, col)
    local suffix = current_line:sub(col + 1)

    local lines = vim.split(table.concat(S), "\n")
    lines[1] = prefix .. lines[1]
    lines[#lines] = lines[#lines] .. suffix
    api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, true, lines)

    for i, v in ipairs(evaluator.structure) do
      local s = S[i]
      if U.is_variable(v) then
        set_extmark(bufnr, i, lnum - 1, col, lnum - 1, col + #s)
        if i == evaluator.zero_index then
          cursor_mark_id = i
        end
      end

      local tail = s:gsub("[^\n]*\n", function()
        lnum = lnum + 1
        col = 0
        return ""
      end)

      col = col + #tail
    end

    if not cursor_mark_id then
      cursor_mark_id = api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, col, {})
    end
  end

  local current_index = 0
  local current_var
  local resolved_inputs = {}

  local R = { aborted = false, finished = false }

  function R.advance(offset)
    offset = offset or 1
    current_index = math.max(math.min(current_index + offset, #evaluator.inputs + 1), 0)
    if current_index == 0 then
      R.aborted = true
      cleanup(bufnr)
      return true
    end

    -- User has moved past the last variable, so apply transformations and move the cursor to the
    -- zero point
    if current_index > #evaluator.inputs then
      -- Move cursor to zero point
      local cur_row, cur_col, cur_end_row, cur_end_col = get_extmark_pos(bufnr, cursor_mark_id)
      api.nvim_buf_set_text(bufnr, cur_row, cur_col, cur_end_row, cur_end_col, {})
      api.nvim_win_set_cursor(win, { cur_row + 1, cur_col })

      R.finished = true
      cleanup(bufnr)
      return true
    end

    current_var = evaluator.inputs[current_index]

    -- Clear highlights on all extmarks except those for current variable
    for i, v in ipairs(evaluator.structure) do
      if U.is_variable(v) then
        local hl_group = v.order == current_index and M.hl_group or nil
        local row, col, end_row, end_col = get_extmark_pos(bufnr, i)
        set_extmark(bufnr, i, row, col, end_row, end_col, hl_group)
      end
    end

    -- Set unresolved variables to their placeholder values
    placeholders = evaluator.evaluate_inputs(resolved_inputs)
    for i, v in ipairs(evaluator.structure) do
      if U.is_variable(v) and v.is_input and (not resolved_inputs[v.id] or resolved_inputs[v.id] == "") then
        local text = placeholders[v.id]
        if v.id ~= current_var.id then
          text = M.marker_with_placeholder_format:format(v.id, text)
        end
        set_extmark_text(bufnr, i, text)
      end
    end

    do
      -- Move the cursor to the current variable
      local mark_row, _, _, mark_end_col = get_extmark_pos(bufnr, current_var.first_index)
      api.nvim_win_set_cursor(win, { mark_row + 1, mark_end_col })
    end

    -- Set resolved input to default value if one exists
    resolved_inputs[current_var.id] = current_var.default

    vim.register_keystroke_callback(
      vim.schedule_wrap(function()
        if R.finished or R.aborted then
          return
        end

        local mark_row, mark_col, _, mark_end_col = get_extmark_pos(bufnr, current_var.first_index)
        local line = api.nvim_buf_get_lines(bufnr, mark_row, mark_row + 1, true)[1]
        local mark_text = line:sub(mark_col + 1, mark_end_col)

        resolved_inputs[current_var.id] = mark_text
        S = evaluator.evaluate_structure(resolved_inputs)

        for i, v in ipairs(evaluator.structure) do
          if U.is_variable(v) then
            -- Update variables related to the current variable as well as
            -- anonymous transforms
            if v.order == current_index or v.transform and not v.id then
              set_extmark_text(bufnr, i, S[i])
            end
          end
        end
      end),
      ns
    )
  end

  return R
end

return setmetatable(M, {
  __call = function(_, ...)
    return entrypoint(...)
  end,
})

local function line_to_cursor()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  return line:sub(1, col)
end

local function make_hats(prefix)
  return ([[\hat{%s}]]):format(prefix)
end

local custom_triggers = { { "(%S+)hat", make_hats } }

local function fancy_expand()
  -- If we have an active snippet and it expands successfully, then return.
  -- Otherwise, continue trying to expand new snippets.
  if snippets.advance_snippet(1) == 0 then
    return true
  end

  -- Custom logic here.
  local line_to_cursor = line_to_cursor()
  for _, trigger in ipairs(custom_triggers) do
    -- For performance reasons, doing this would probably be a bad idea.
    -- It would be calling line_to_cursor() internally every time.
    -- local word = snippets.word_at_cursor(trigger)
    local i, j, word = line_to_cursor:find(trigger[1].."$") -- Add a "$" to only match the end.
    if i then
      local line_section = line_to_cursor:sub(i, j)
      local snippet = trigger[2](word)
      return snippets.expand_at_cursor(snippet, line_section)
    end
  end

  return snippets.expand_or_advance()
end

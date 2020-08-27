local vim = vim
local api = vim.api
local snippets = require 'snippets'
local format = string.format
local concat = table.concat
local insert = table.insert
local max = math.max

local callbacks = {}

function _SNIPPETS_CALLBACK_TEXT_CHANGEDI_COPYRIGHT_ASHKAN_2020(event_name)
  for k, callback in pairs(callbacks) do
  	pcall(callback, event_name)
  end
end

local global_callback_is_initialized = false

local function global_init()
  if not global_callback_is_initialized then
    global_callback_is_initialized = true
    vim.cmd 'augroup K_SNIPPETS'
    vim.cmd 'autocmd!'
    vim.cmd 'autocmd TextChangedI * lua _SNIPPETS_CALLBACK_TEXT_CHANGEDI_COPYRIGHT_ASHKAN_2020("TextChangedI")'
    vim.cmd 'autocmd InsertLeave * lua _SNIPPETS_CALLBACK_TEXT_CHANGEDI_COPYRIGHT_ASHKAN_2020("InsertLeave")'
    vim.cmd 'augroup END'
  end
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
	win = api.nvim_open_win(buf, 0, O)
	api.nvim_win_set_option(win, 'wrap', false)
	api.nvim_buf_set_option(buf, 'ul', -1)
	api.nvim_win_set_option(win, 'concealcursor', 'nc')
	return buf, win, O
end

local message_template = [[
Hey! Listen!
You have a snippet for that: %q]]

local function clippy_setup()
  global_init()

  local active
  local function close_active()
    if active then
      pcall(api.nvim_win_close, active.win, true)
      active = nil
      return true
    end
  end

  local ns = api.nvim_create_namespace('snippets.clippy')
  callbacks.clippy = function(event_name)
    if event_name == 'InsertLeave' then
      close_active()
      return
    end
    local word, snippet = snippets.lookup_snippet_at_cursor()
    if snippet then
      local message = format(message_template, word)
      local lines = vim.split(message, '\n', true)
      if active then
      else
        local buf, win, opts = floaty_popup {
          relative = 'cursor';
          row = -#lines;
          col = -#word;
          height = 1;
          focusable = false;
          width = 1;
        }
        active = {
          buf = buf;
          win = win;
          opts = opts;
        }
      end
      local m = 0
      for i, line in ipairs(lines) do
        m = max(#line, m)
      end
      api.nvim_win_set_config(active.win, {
        width = m;
        height = #lines;
      })
      api.nvim_buf_set_lines(active.buf, 0, -1, false, lines)
      do
        local searchers = vim.split(message_template:format('()'..word..'()'), '\n', true)
        for i, searcher in ipairs(searchers) do
          local a, b = lines[i]:match(searcher)
          if type(a) == 'number' then
            pcall(api.nvim_buf_add_highlight, active.buf, ns, 'Question', i-1, a-1, b-1)
          end
        end
      end
    else
      close_active()
    end
  end
end

return setmetatable({
  setup = clippy_setup;
}, {
  __newindex = function(_, k, v)
    if k == 'message_template' and type(v) == 'string' then
      message_template = v
    end
  end
})

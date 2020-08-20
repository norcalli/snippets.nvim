# snippets.nvim

Check the [Wiki](https://github.com/norcalli/snippets.nvim/wiki) for examples and contribute your own!

# Installation

`Plug norcalli/snippets.nvim`

# Usage:

```vim
lua require'snippets'.use_suggested_mappings()

" This variant will set up the mappings only for the *CURRENT* buffer.
lua require'snippets'.use_suggested_mappings(true)

" There are only two keybindings specified by the suggested keymappings, which is <C-k> and <C-j>
" They are exactly equivalent to:

" <c-k> will either expand the current snippet at the word or try to jump to
" the next position for the snippet.
inoremap <c-k> <cmd>lua return require'snippets'.expand_or_advance(1)<CR>

" <c-j> will jump backwards to the previous field.
" If you jump before the first field, it will cancel the snippet.
inoremap <c-j> <cmd>lua return require'snippets'.advance_snippet(-1)<CR>

```

The rest of the README is in Lua **NOT** VIM SCRIPT.

```lua
require'snippets'.snippets = {
  -- The _global dictionary acts as a global fallback.
  -- If a key is not found for the specific filetype, then
  --  it will be lookup up in the _global dictionary.
  _global = {
    -- Insert a basic snippet, which is a string.
    todo = "TODO(ashkan): ";

    uname = function() return vim.loop.os_uname().sysname end;
    date = os.date;

    -- Evaluate at the time of the snippet expansion and insert it. You
    --  can put arbitrary lua functions inside of the =... block as a
    --  dynamic placeholder. In this case, for an anonymous variable
    --  which doesn't take user input and is evaluated at the start.
    epoch = "${=os.time()}";
    -- Equivalent to above.
    epoch = function() return os.time() end;

    -- Use the expansion to read the username dynamically.
    note = [[NOTE(${=io.popen("id -un"):read"*l"}): ]];

    -- Do the same as above, but by using $1, we can make it user input.
    -- That means that the user will be prompted at the field during expansion.
    -- You can *EITHER* specify an expression as a placeholder for a variable
    --  or a literal string/snippet using `${var:...}`, but not both.
    note = [[NOTE(${1=io.popen("id -un"):read"*l"}): ]];
  };
  lua = {
    -- Snippets can be used inside of placeholders, but the variables used in
    -- the placeholder *must* be used outside of the placeholder. This could
    -- potentially change in the future if someone convinces me it's a good
    -- idea to support it. (it was a deliberate choice)
    req = [[local ${2:$1} = require '$1']];

    -- A snippet with a placeholder using :... and multiple variables.
    ["for"] = "for ${1:i}, ${2:v} in ipairs(${3:t}) do\n$0\nend";
    -- This is equivalent to above, but looks nicer (to me) using [[]] strings.
    -- Notice $0 to indicate where the cursor should go at the end of expansion.
    ["for"] = [[
for ${1:i}, ${2:v} in ipairs(${3:t}) do
  $0
end]];
  };
  c = {
    -- Variables can be repeated, and the value of what the user puts in will be
    -- expanded at every position where the bare variable is used (i.e. $1, $2...)
    ["#if"] = [[
#if ${1:CONDITION}
$0
#endif // $1
]];

    -- Here is where we get to advanced usage. The `|...` block is a transformation
    --  which is applied to the result of the variable *at the position*.
    -- Inside of this block, the special variable `S` is defined. Its usage should be
    --  obvious based on its usage in the following snippet. If not, read #Details below.
    --
    -- This is an important note:
    --   Transformations don't apply to every position for repeated variables, only
    --   at which it is defined.
    --
    -- You'll also see at the bottom `${|S[1]:gsub("%s+", "_")}`. This is a transformation
    --  just like above, except that without a variable name, it'll just be evaluated at
    --  the end of the snippet expansion. In this example, it's using the value of variable 1
    --  and replacing whitespace with underscores.
    guard = [[
#ifndef AK_${1:header name|S.v:upper():gsub("%s+", "_")}_H_
#define AK_$1_H_

// This is a header for $1

int ${1|S.v:lower():gsub("%s+", "_")} = 123;

$0

#endif // AK_${|S[1]:gsub("%s+", "_")}_H_
]];

    -- This is also illegal because it makes no sense, adding a transformation
    --  to an expression is redundant.
    -- ["inc"] = [[#include "${=vim.fn.expand("%:t")|S.v:upper()}"]];

    -- Just do this instead.
    inc = [[#include "${=vim.fn.expand("%:t"):upper()}"]];

    -- The final important note is the use of negative number variables.
    -- Negative variables *never* ask for user input, but otherwise behave
    --  like normal variables.
    -- This can be useful for storing the value of an expression, and repeating
    --  it in multiple locations.
    -- The following snippet will ask for the user's input using `input()` *once*,
    --  but use the value in multiple places.
    user_input = [[hey? ${-1=vim.fn.input("what's up? ")} = ${-1}]];
  };
}

-- And now for some examples of snippets I actually use.
local snippets = require'snippets'
local U = require'snippets.utils'
snippets.snippets = {
  lua = {
    req = [[local ${2:${1|S.v:match"([^.()]+)[()]*$"}} = require '$1']];
    func = [[function${1|vim.trim(S.v):gsub("^%S"," %0")}(${2|vim.trim(S.v)})$0 end]];
    ["local"] = [[local ${2:${1|S.v:match"([^.()]+)[()]*$"}} = ${1}]];
    -- Match the indentation of the current line for newlines.
    ["for"] = U.match_indentation [[
for ${1:i}, ${2:v} in ipairs(${3:t}) do
  $0
end]];
  };
  _global = {
    -- If you aren't inside of a comment, make the line a comment.
    copyright = U.force_comment [[Copyright (C) Ashkan Kiani ${=os.date("%Y")}]];
  };
}
```

By default no snippets are stored inside of `require'snippets'.snippets`.

You can assign to the the dictionary of the snippets whenever you want, *but you cannot modify it directly.*

What that means is you can do:

`require'snippets'.snippets = {}`

but you cannot do

`require'snippets'.snippets.c.guard = "ifndef boooo"`

If you wish to modify it like that, you can access the dictionary first to get a copy and assign it afterwards, like:

```lua
local S = require'snippets'
local snippets = S.snippets
snippets.c.guard = "ifndef boooo"
S.snippets = snippets
```

This is to discourage invalid access patterns.

# Details

A `snippet` is actually a very well defined format specified as a list of either
`string`s or `variable`s. These components will be concatenated together into the
final body of a snippet.

A `variable` looks like the following:

```lua
{
  order     = number;
  is_input  = nil | boolean;
  id        = nil | number | string;
  default   = nil | string | function;
  transform = nil | function;
}
```

You'll notice that the only required value is `order`, since it defines the order
in which dynamic components should be evaluated. Multiple components can have
the same `order`, in which case they'll be executed in the order they are found
in the list. The value `0` is special, and it indicates the cursor position at
the end of the snippet.

The next interesting component is `is_input`, which determines if this is a field
that should be stopped at to ask for user input to evaluate later. If it is
`false` or `nil`, then it won't prompt the user for input.

The `default` is a default value to be used for resolving the value of the
component.  The `default` **will always be a string** in the process of
evaluating a snippet.  If the `default` is a function, it will be evaluated. So
if a function returns `nil`, `""` the empty string will be used as a default.
If the variable is named using `id`, then only the **first** `default` found in
the list will be used, *so be careful*.

`transform` is a function which receives a context of the current state of the
snippet up to the point that the transform is being evaluated.
- This context will contain a member `v` representing the value of the current
  variable for **named variables only**.
- Otherwise, you can index it with the name of another variable to lookup. e.g.
  `transform = function(context) return context[1] end` would return the value
  of variable `1`.

`id` is the name of the variable. In the parser, this is restricted to numbers
only for simplicity, but technically any value could be used.

## Parsing result examples

- `${1} = $1 -> { is_input = true; id = 1; order = 1; }`
- `${-1} = $-1 -> { is_input = false; id = -1; order = -1; }`
- `$0 -> { id = 0; order = 0; }`
- `${1: a placeholder} -> { is_input = true; id = 1; default = " a placeholder" }`
- `${1=os.date()} -> { is_input = true; id = 1; order = 1; default = function(context) return os.date() end; }`
- `${=os.date()} -> { is_input = false; order = -1; default = function(context) return os.date() end; }`
- `${|os.date()} -> { is_input = false; order = math.huge; transform = function(context) return os.date() end; }`
- `${-1|os.date()} -> { is_input = false; id = -1; order = -1; transform = function(context) return os.date() end; }`
- `${-1:asdf|S[1]:upper()} -> { is_input = false; id = -1; order = -1; default = "asdf"; transform = function(context) return context[1]:upper() end; }`
- `${-1:$} -> { is_input = false; id = -1; order = -1; default = "asdf"; transform = function(context) return context[1]:upper() end; }`

## Snippet example

```lua
require'snippets.parser'.parse_snippet [[\usepackage[$2]{$1}]] == {
  "\\usepackage[", {default = "",id = 2,is_input = true,order = 2},
    "]{",
    { default = "",id = 1,is_input = true,order = 1},
    "}"
}

require'snippets.parser'.parse_snippet [[function${1|vim.trim(S.v):gsub("^%S"," %0")}(${2|vim.trim(S.v)})$0 end]] == {
  "function", { default = "",id = 1,is_input = true,order = 1,transform = <function 1>,<metatable> = <1>{}},
    "(", {default = "",id = 2,is_input = true,order = 2,transform = <function 2>,<metatable> = <table 1>},
    ")", {default = "",id = 0,is_input = false,order = 0,<metatable> = <table 1>},
    " end"
}
```

## Snippet manipulation example

```lua
local U = require'snippets.utils'

local function note_snippet(header)
  -- Put a dummy value for -1 and add a default later.
  local S = [[
${-1}:
 $0
   - ashkan, ${=os.date()}]]
  S = U.force_comment(S)
  S = U.match_indentation(S)
  return U.iterate_variables_by_id(S, -1, function(v)
    v.default = header
  end)
end

require'snippets'.snippets = {
  _global = {
    todo = note_snippet "TODO";
    note = note_snippet "NOTE";
  };
}
```

# TODO (because this is considered beta-level software)

- Document the utilities further.
- Parse existing formats like neosnippet/ultisnips maybe...
- Handle consistency across undo points.
  - Specifically, I need to be able to record an undo point at the right place
  right before a snippet is expanded and then potentially delete the
  active_snippet when an undo is called because we can't guarantee that a snippet
  will ever terminate then.
  - I could potentially then switch to a stack model of pushing new snippets so you could
  do multiple snippets at a time.
- Limit how far the scanning for snippet markers goes.

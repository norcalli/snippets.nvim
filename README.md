# snippets.nvim

# Installation

`Plug norcalli/snippets.nvim`

# Usage:

```vim
lua require'snippets'.use_suggested_mappings()

" This variant will set up the mappings only for the *CURRENT* buffer.
lua require'snippets'.use_suggested_mappings(true)

" There is only one keybinding specified by the suggested keymappings, which is <C-k>.
" This is exactly equivalent to
inoremap <c-k> <cmd>lua return require'snippets'.expand_or_advance()<CR>
" which will either expand the current snippet at the word
" or try to jump to the next position for the snippet.

```lua
require'snippets'.snippets = {
	lua = {
		["for"] = "for ${1:i}, ${2:v} in ipairs(${3:t}) do\n$0\nend";
	};
	[""] = { };
	c = {
		guard = [[
#ifndef AK_${1:NAME}_H_
#define AK_$1_H_

$0

#endif // AK_$1_H_
]];
    ["#if"] = [[
#if ${1:CONDITION}
$0
#endif // $1
]];
    ["inc"] = [[#include "$1"$0]];
    ["sinc"] = [[#include <$1>$0]];
    ["struct"] = [[
typedef struct ${1:name} {
  $0
} $1;
]];
    ["enum"] = [[
enum ${1:name} {
  $0
}
]];
    ["union"] = [[
union ${1:name} {
  $0
}
]];
	};
  -- The _global dictionary acts as a global fallback.
  -- If a key is not found for the specific filetype, then
  -- it will be lookup up in the _global dictionary.
  _global = {
		date = { {os.date}, {}; };
		epoch = { {os.time} };
		uname = { {function()return vim.loop.os_uname().sysname end}, {}; };
		todo = "TODO(ashkan): ";
		note = "NOTE(ashkan): ";
		important = "IMPORTANT(ashkan): ";
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

The dictionary either stores a string in the snippet format which uses `$0, $1, $2, ...` or
as an array of `{ structure, variables = {} }` in the abstract format (which is described below)
with the variable dictionary representing the information for the substitution variables.


# NOTES (because this is beta release software)

I haven't set up parsing of any particular snippet file, right now it's written
as a library intended to be extended with the ability to parse/be compatible
with as many snippet formats as possible by using an abstract snippet representation
via a list structure:

The word `structure` here is used to mean something like this:

```lua
{
	"for "; 1; " in pairs("; 2; ") do \n";
  os.date;
  0;
  "\nend";
}
```

In the above, you can see a few things:

- All parts of the list will be turned into a string and concatenated together to compose
the body of a string.
- Variable substitutions are represented by numbers. The variable 0 represents the terminal
variable, meaning the variable to go to at the end of completion.
- Variable information like what placeholders can be used are located in an accompanying
dictionary that looks like `{[1] = {placeholder="hello"}, [2] = {}}` etc.
- Variables can be specified multiple times. The value of a variable will be replaced at each instance.
- The variable 0 can only be specified once.
- You can use lua functions which will be evaluated at the time of the expansion and substituted
in within a structure after being coerced to a string with `tostring()`.
- Verbatim strings will be passed through as is.


# TODO

- handle consistency across undo points.
  - Specifically, I need to be able to record an undo point at the right place
  right before a snippet is expanded and then potentially delete the
  active_snippet when an undo is called because we can't guarantee that a snippet
  will ever terminate then.
  - I could potentially then switch to a stack model of pushing new snippets so you could
  do multiple snippets at a time.
- Limit how far the scanning for snippet markers goes.
- Matching outer indentation

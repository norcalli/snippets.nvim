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

-- TODO(ashkan, Tue 18 Aug 2020 09:39:52 AM JST) delete this and use neovim-plugin instead.
local type_names = {
  t='table', s='string', n='number', b='boolean', f='function', c='callable',
  ['table']='table', ['string']='string', ['number']='number',
  ['boolean']='boolean', ['function']='function', ['callable']='callable',
  ['nil']='nil', ['thread']='thread', ['userdata']='userdata',
}

local function error_out(key, expected_type, input_type)
  if type(expected_type) == 'table' then
    expected_type = table.concat(expected_type, ' or ')
  end
  error(string.format("validation_failed: %q: expected %s, received %s", key, expected_type, input_type))
end

local function is_callable(v)
  local input_type = type(v)
  if input_type == 'function' then
    return true
  elseif input_type == 'table' then
    local mt = getmetatable(v)
    if mt then
      return mt.__call
    end
  end
end

local function validate_one(value, expected_type, optional)
  if optional and value == nil then
    return true
  end
  expected_type = type_names[expected_type] or error(("validate: Invalid expected type specified: %q"):format(expected_type))
  if expected_type == 'callable' then
    return is_callable(value)
  end
  return type(value) == expected_type
end

local function validate_many(value, expected_type, optional)
  for _, ty in ipairs(expected_type) do
    if validate_one(value, ty, optional) then
      return true
    end
  end
  return false
end

local function validate(conf)
  assert(type(conf) == 'table')
  for key, v in pairs(conf) do
    local optional = v[3]
    local expected_type = v[2]
    local value = v[1]
    local validate_fn = type(expected_type) == 'table' and validate_many or validate_one
    if not validate_fn(value, expected_type, optional) then
      error_out(key, expected_type, type(value))
    end
  end
  return true
end

return validate
-- vim:noet sw=3 ts=3

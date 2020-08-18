local function entrypoint(structure)
  -- Do initialization and insert the text to the buffer here.

  local R
	R = {
    aborted = false;
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance = function(offset)
    end
  }
  return R
end


local M = {}

--- Creates a debounced version of a function (Trailing Edge).
---
--- The debounced function delays invoking `func` until `delay_ms` milliseconds have
--- elapsed since the last time the debounced function was invoked. Subsequent calls
--- during the delay period will reset the timer. The function executes only
--- after the calls have stopped for the specified duration.
---
--- Useful for rate-limiting execution in response to frequent events like
--- 'TextChanged', 'CursorMoved', window resizing, etc.
---
--- @param func function The function to debounce. Will be called with arguments
---   passed to the debounced function on the trailing edge.
--- @param delay_ms number The debounce delay in milliseconds. Must be non-negative.
--- @return function A new function that wraps the original `func` with trailing debounce logic.
---
--- @usage
---   local async = require("utils.async")
---   local my_update_func = function(arg1) print("Updating:", arg1) end
---   local debounced_update = async.debounce(my_update_func, 300)
---
---   -- Call multiple times rapidly:
---   debounced_update("first")  -- Does nothing immediately
---   debounced_update("second") -- Does nothing immediately, resets timer
---   -- After 300ms pause following the *last* call...
---   -- "Updating: second" will be printed.
---
--- @note Return Value: The debounced function itself does not return any value from `func`.
--- @note Handling 'self': If `func` is a method that relies on `self`, you need to ensure `self`
---       is correctly passed, e.g., by wrapping:
---       `async.debounce(function(...) obj:method(...) end, delay)`
function M.debounce(func, delay_ms)
  assert(type(func) == "function", "Debounce Error: 'func' argument must be a function.")
  assert(type(delay_ms) == "number" and delay_ms >= 0, "Debounce Error: 'delay_ms' must be a non-negative number.")

  local timer = nil

  return function(...)
    local args = { ... }

    if timer then
      timer:close()
      timer = nil
    end

    timer = vim.defer_fn(function()
      func(unpack(args))
      timer = nil
    end, delay_ms)
  end
end

return M

local helper = {}

-- Checks exact scalar equality.
-- Проверяет точное равенство скалярных значений.
function helper.assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      (message or "values differ") ..
      ": expected " .. tostring(expected) ..
      ", got " .. tostring(actual),
      2
    )
  end
end

return helper

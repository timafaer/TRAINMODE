local helper = {}

-- Raises a test failure at the caller location.
-- Вызывает ошибку теста на уровне вызывающего кода.
local function fail(message)
  error(message, 2)
end

-- Asserts exact equality for scalar values.
-- Проверяет точное равенство скалярных значений.
function helper.assert_equal(actual, expected, message)
  if actual ~= expected then
    fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

-- Asserts that a value is truthy.
-- Проверяет, что значение истинное.
function helper.assert_true(value, message)
  if not value then
    fail(message or "expected true")
  end
end

-- Asserts that a value is falsy.
-- Проверяет, что значение ложное.
function helper.assert_false(value, message)
  if value then
    fail(message or "expected false")
  end
end

-- Asserts that all expected item amounts are present in an item map.
-- Проверяет, что в таблице предметов есть все ожидаемые количества.
function helper.assert_table_contains_items(actual, expected, message)
  for item_name, amount in pairs(expected or {}) do
    if (actual or {})[item_name] ~= amount then
      fail((message or "item map differs") .. ": item " .. item_name .. " expected " .. tostring(amount) .. ", got " .. tostring((actual or {})[item_name]))
    end
  end
end

-- Counts keys in a map-like table.
-- Считает ключи в map-подобной таблице.
function helper.count_keys(source)
  local count = 0
  for _ in pairs(source or {}) do
    count = count + 1
  end
  return count
end

return helper

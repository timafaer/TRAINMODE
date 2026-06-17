local helper = {}

local function fail(message)
  error(message, 2)
end

function helper.assert_equal(actual, expected, message)
  if actual ~= expected then
    fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

function helper.assert_true(value, message)
  if not value then
    fail(message or "expected true")
  end
end

function helper.assert_false(value, message)
  if value then
    fail(message or "expected false")
  end
end

function helper.assert_table_contains_items(actual, expected, message)
  for item_name, amount in pairs(expected or {}) do
    if (actual or {})[item_name] ~= amount then
      fail((message or "item map differs") .. ": item " .. item_name .. " expected " .. tostring(amount) .. ", got " .. tostring((actual or {})[item_name]))
    end
  end
end

function helper.count_keys(source)
  local count = 0
  for _ in pairs(source or {}) do
    count = count + 1
  end
  return count
end

return helper

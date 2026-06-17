local table_utils = {}

-- Copies a string-keyed/value-keyed map one level deep.
-- Копирует map-таблицу на один уровень глубины.
function table_utils.copy_map(source)
  local result = {}
  if not source then
    return result
  end

  for key, value in pairs(source) do
    result[key] = value
  end

  return result
end

-- Copies an array-like table one level deep, preserving numeric order.
-- Копирует массивоподобную таблицу на один уровень, сохраняя числовой порядок.
function table_utils.copy_array(source)
  local result = {}
  if not source then
    return result
  end

  for index = 1, #source do
    result[index] = source[index]
  end

  return result
end

-- Sums all numeric values in a map.
-- Суммирует все числовые значения в map-таблице.
function table_utils.map_sum(source)
  local total = 0
  if not source then
    return total
  end

  for _, value in pairs(source) do
    total = total + value
  end

  return total
end

-- Counts how many map entries have a positive numeric value.
-- Считает, сколько записей в map-таблице имеют положительное числовое значение.
function table_utils.map_count_positive(source)
  local count = 0
  if not source then
    return count
  end

  for _, value in pairs(source) do
    if value and value > 0 then
      count = count + 1
    end
  end

  return count
end

-- Returns true if at least one map entry has a positive numeric value.
-- Возвращает true, если хотя бы одна запись в map-таблице положительная.
function table_utils.has_positive(source)
  if not source then
    return false
  end

  for _, value in pairs(source) do
    if value and value > 0 then
      return true
    end
  end

  return false
end

-- Returns positive-value keys sorted by amount descending, then by key name.
-- Возвращает ключи с положительными значениями, отсортированные по убыванию количества и имени.
function table_utils.sorted_keys_by_value_desc(source)
  local keys = {}
  for key, value in pairs(source or {}) do
    if value and value > 0 then
      keys[#keys + 1] = key
    end
  end

  table.sort(keys, function(left, right)
    local left_value = source[left] or 0
    local right_value = source[right] or 0
    if left_value == right_value then
      return tostring(left) < tostring(right)
    end
    return left_value > right_value
  end)

  return keys
end

-- Compares two shallow maps for exact key/value equality.
-- Сравнивает две плоские map-таблицы на точное совпадение ключей и значений.
function table_utils.shallow_equal_map(left, right)
  for key, value in pairs(left or {}) do
    if (right or {})[key] ~= value then
      return false
    end
  end

  for key, value in pairs(right or {}) do
    if (left or {})[key] ~= value then
      return false
    end
  end

  return true
end

return table_utils

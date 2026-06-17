local table_utils = require("scripts.core.table_utils")

local combinator = {}

local function join_order(order)
  local parts = {}
  for index = 1, #order do
    parts[index] = tostring(order[index])
  end
  return table.concat(parts, "\31")
end

local function add_unique_order(result, seen, order)
  local key = join_order(order)
  if seen[key] then
    return
  end

  seen[key] = true
  result[#result + 1] = table_utils.copy_array(order)
end

local function permute(values, index, result, seen, limit)
  if #result >= limit then
    return
  end

  if index > #values then
    add_unique_order(result, seen, values)
    return
  end

  for swap_index = index, #values do
    values[index], values[swap_index] = values[swap_index], values[index]
    permute(values, index + 1, result, seen, limit)
    values[index], values[swap_index] = values[swap_index], values[index]

    if #result >= limit then
      return
    end
  end
end

function combinator.generate_item_orders(items, options)
  options = options or {}
  local limit = options.limit or 120
  local result = {}
  local seen = {}

  local by_amount_desc = table_utils.sorted_keys_by_value_desc(items)
  add_unique_order(result, seen, by_amount_desc)

  local by_amount_asc = table_utils.copy_array(by_amount_desc)
  table.sort(by_amount_asc, function(left, right)
    local left_value = items[left] or 0
    local right_value = items[right] or 0
    if left_value == right_value then
      return tostring(left) < tostring(right)
    end
    return left_value < right_value
  end)
  add_unique_order(result, seen, by_amount_asc)

  if #by_amount_desc <= (options.max_permuted_items or 6) then
    local values = table_utils.copy_array(by_amount_desc)
    permute(values, 1, result, seen, limit)
  end

  return result
end

function combinator.sort_trains_by_capacity(trains)
  local result = {}
  for index = 1, #(trains or {}) do
    result[index] = trains[index]
  end

  table.sort(result, function(left, right)
    local left_capacity = left.capacity or 0
    local right_capacity = right.capacity or 0
    if left_capacity == right_capacity then
      return tostring(left.id) < tostring(right.id)
    end
    return left_capacity > right_capacity
  end)

  return result
end

function combinator.generate_train_orders(trains, options)
  options = options or {}
  local limit = options.limit or 60
  local result = {}
  local seen = {}

  local by_capacity_desc = combinator.sort_trains_by_capacity(trains)
  add_unique_order(result, seen, by_capacity_desc)

  local by_capacity_asc = table_utils.copy_array(by_capacity_desc)
  table.sort(by_capacity_asc, function(left, right)
    local left_capacity = left.capacity or 0
    local right_capacity = right.capacity or 0
    if left_capacity == right_capacity then
      return tostring(left.id) < tostring(right.id)
    end
    return left_capacity < right_capacity
  end)
  add_unique_order(result, seen, by_capacity_asc)

  if #by_capacity_desc <= (options.max_permuted_trains or 5) then
    local values = table_utils.copy_array(by_capacity_desc)
    permute(values, 1, result, seen, limit)
  end

  return result
end

return combinator

local route_data_provider = require("scripts.routing.route_data_provider")
local route_optimizer = require("scripts.routing.route_optimizer")
local get_ideal_routes = require("scripts.routing.get_ideal_routes")

local scheduler = {}
local scheduler_mt = { __index = scheduler }

local phase_rank = {
  route_search = 1,
  validation = 2,
  combinatorics = 3,
}

-- Compares jobs by phase, request priority, age, and stable id.
-- Сравнивает задачи по стадии, приоритету запроса, возрасту и стабильному id.
local function comes_before(left, right)
  local left_rank = phase_rank[left.phase] or 4
  local right_rank = phase_rank[right.phase] or 4

  if left_rank ~= right_rank then
    return left_rank < right_rank
  end
  if left.priority ~= right.priority then
    return left.priority > right.priority
  end
  if left.created_tick ~= right.created_tick then
    return left.created_tick < right.created_tick
  end
  return left.id < right.id
end

-- Finds the highest-priority runnable job without changing the queue.
-- Находит самую приоритетную выполняемую задачу без изменения очереди.
local function select_next_job(jobs)
  local selected
  for _, job in pairs(jobs) do
    if job.status == "running"
      and (not selected or comes_before(job, selected))
    then
      selected = job
    end
  end
  return selected
end

-- Creates an isolated scheduler suitable for tests or one storage partition.
-- Создает изолированный планировщик для тестов или одного раздела storage.
function scheduler.new(provider, job_factory, persisted_state)
  local selected_provider = provider or route_data_provider
  local state = persisted_state or {}
  state.jobs = state.jobs or {}
  state.results = state.results or {}
  return setmetatable({
    provider = selected_provider,
    job_factory = job_factory or function(request_id)
      return get_ideal_routes.with_provider(selected_provider, request_id)
    end,
    jobs = state.jobs,
    results = state.results,
  }, scheduler_mt)
end

-- Adds or replaces one planning job.
-- Добавляет или заменяет одну задачу планирования.
function scheduler:add(job)
  if job then
    self.jobs[job.id] = job
  end
  return job
end

-- Executes at most operation_budget logical planning operations.
-- Выполняет не более operation_budget логических операций планирования.
function scheduler:step(operation_budget)
  local performed = 0

  while performed < operation_budget do
    local job = select_next_job(self.jobs)
    if not job then
      break
    end

    route_optimizer.step(job, self.provider)
    performed = performed + 1

    if job.status == "completed" then
      self.results[job.id] = job.routes
      self.jobs[job.id] = nil
    elseif job.status == "restart_required" then
      local replacement = self.job_factory(job.request_id)
      self.jobs[job.id] = nil
      if replacement then
        self.jobs[replacement.id] = replacement
      end
    elseif job.status == "failed" then
      self.results[job.id] = {
        error = job.error,
        routes = job.routes,
      }
      self.jobs[job.id] = nil
    end
  end

  return performed
end

-- Returns completed routes without mutating scheduler state.
-- Возвращает готовые маршруты без изменения состояния планировщика.
function scheduler:get_result(job_id)
  return self.results[job_id]
end

-- Removes and returns a completed result.
-- Удаляет и возвращает готовый результат.
function scheduler:take_result(job_id)
  local result = self.results[job_id]
  self.results[job_id] = nil
  return result
end

-- Returns the current job for diagnostics and persistence tests.
-- Возвращает текущую задачу для диагностики и тестов сохранения состояния.
function scheduler:get_job(job_id)
  return self.jobs[job_id]
end

return scheduler

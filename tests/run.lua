package.path = "./?.lua;./?/init.lua;" .. package.path

local suites = {
  require("tests.dispatcher_core_test"),
  require("tests.planner_core_test"),
}

local total = 0
local failed = 0

-- Runs every test function exported by each suite module.
-- Запускает каждую тестовую функцию, которую экспортируют модули наборов тестов.
for _, suite in ipairs(suites) do
  for name, test in pairs(suite) do
    total = total + 1
    local ok, err = pcall(test)
    if ok then
      print("PASS " .. name)
    else
      failed = failed + 1
      print("FAIL " .. name)
      print(err)
    end
  end
end

print("TOTAL " .. tostring(total) .. ", FAILED " .. tostring(failed))

if failed > 0 then
  os.exit(1)
end

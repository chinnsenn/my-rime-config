-- ===================================================================
-- [INPUT]:  依赖 tests/test_moran_ja.lua 提供的行为测试集合
-- [OUTPUT]: 对外提供零依赖测试入口，以进程退出码表达测试结果
-- [POS]:    tests/ 的统一运行器，负责隔离失败并输出精确 RED/GREEN 结果
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

package.path = "./tests/?.lua;./lua/?.lua;" .. package.path

local tests = require("test_moran_ja")
local passed = 0
local failed = 0

for _, test in ipairs(tests) do
    io.write("TEST ", test.name, " ... ")
    local ok, err = xpcall(test.run, debug.traceback)
    if ok then
        passed = passed + 1
        io.write("PASS\n")
    else
        failed = failed + 1
        io.write("FAIL\n", err, "\n")
    end
end

io.write(string.format("\n%d passed, %d failed, %d total\n", passed, failed, passed + failed))
os.exit(failed == 0 and 0 or 1)

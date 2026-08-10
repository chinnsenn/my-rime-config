-- ===================================================================
-- [INPUT]: 依赖 tests/rime_fake 的 schema 配置读取能力
-- [OUTPUT]: 对外提供 moran_kagiroi_hybrid 的独立混输契约测试
-- [POS]:   tests/ 的 Kagiroi 集成规格，约束前缀、罗马字布局与中文方案隔离
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local fake = require("rime_fake")

local tests = {}

local function test(name, run)
    tests[#tests + 1] = { name = name, run = run }
end

local schema = "moran_kagiroi_hybrid.schema.yaml"

test("Kagiroi 混输方案保有独立 schema 标识", function()
    fake.equal(
        fake.schema_scalar(schema, { "schema" }, "schema_id"),
        "moran_kagiroi_hybrid",
        "新方案必须独立于现有 moran_ja_hybrid"
    )
end)

test("Kagiroi 前缀段使用分号并选择罗马字布局", function()
    fake.equal(fake.schema_scalar(schema, { "kagiroi" }, "prefix"), ";", "分号应进入 Kagiroi 段")
    fake.equal(fake.schema_scalar(schema, { "kagiroi" }, "layout"), "romaji", "日文段应使用 Kagiroi 罗马字布局")
    fake.equal(
        fake.schema_scalar(schema, { "recognizer", "patterns" }, "kagiroi"),
        "^;.*$",
        "转换后的假名输入应持续保留 Kagiroi 标签"
    )
end)

test("Kagiroi 显式处理词尾拨音", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    fake.contains(content, "xform/^(.*)n$/$1ん$/", "词尾单 n 应映射为拨音")
end)

return tests

-- ===================================================================
-- [INPUT]: 依赖 tests/rime_fake、混合方案 YAML、离线中日词表与 Trime 符号主题配置。
-- [OUTPUT]: 对外提供 Kagiroi 混输、离线日语释义与液态符号目录契约测试。
-- [POS]:   tests/ 的 Kagiroi 集成规格，约束日文输入、中文候选释义与跨平台方案结构。
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local fake = require("rime_fake")

local gloss_filter = require("moran_ja_gloss_filter")
local tests = {}

local function test(name, run)
    tests[#tests + 1] = { name = name, run = run }
end

local schema = "moran_kagiroi_hybrid.schema.yaml"

local function with_gloss_filter(enabled, body)
    local restore_globals = fake.install_rime_globals()
    local env = fake.environment({
        ["moran_ja_gloss/dictionary"] = "lua/zh_ja_wiki.txt",
    })
    env.engine.context:set_option("ja_gloss", enabled)
    gloss_filter.init(env)
    local ok, err = xpcall(function() body(env) end, debug.traceback)
    gloss_filter.fini(env)
    restore_globals()
    if not ok then error(err, 0) end
end

test("Kagiroi 混输方案保有独立 schema 标识", function()
    fake.equal(
        fake.schema_scalar(schema, { "schema" }, "schema_id"),
        "moran_kagiroi_hybrid",
        "新方案必须独立于现有 moran_ja_hybrid"
    )
end)

test("; 前缀进入 Kagiroi 段并选择罗马字布局", function()
    fake.equal(fake.schema_scalar(schema, { "kagiroi" }, "prefix"), ";", "Kagiroi 应使用跨平台的单字符 ; 前缀")
    fake.equal(fake.schema_scalar(schema, { "kagiroi" }, "layout"), "romaji", "日文段应使用 Kagiroi 罗马字布局")
    fake.equal(
        fake.schema_scalar(schema, { "kagiroi" }, "tag"),
        "kagiroi",
        "未转换的罗马字不应进入 Kagiroi 翻译器"
    )
end)

test("Kagiroi 假名处理器优先于魔然处理器", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    local kagiroi_processor = assert(content:find("    - lua_processor@*kagiroi/kagiroi_kana_speller", 1, true))
    local key_binder = assert(content:find("    - key_binder", 1, true))
    local moran_processor = assert(content:find("    - lua_processor@*moran_processor", 1, true))
    fake.truthy(kagiroi_processor < key_binder and kagiroi_processor < moran_processor, "Kagiroi 必须先接收 ; 后的罗马字")
    fake.contains(content, "kagiroi: \"^;.*$\"", "; 必须保留 Kagiroi 分段标签")
    fake.not_contains(content, "accept: Control+j", "跨平台方案不应依赖 Ctrl+J")
end)

test("Kagiroi 段保留数字序号选词", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    local kana_speller = assert(content:find("    - lua_processor@*kagiroi/kagiroi_kana_speller", 1, true))
    local selector = assert(content:find("    - lua_processor@*moran_kagiroi_selector", 1, true))
    fake.truthy(kana_speller < selector, "数字选择器必须在假名转写器之后处理按键")
end)

test("Kagiroi 数字选词保持当前候选页", function()
    local selector = require("moran_kagiroi_selector")
    local selected_index
    local segment = {
        selected_index = 10,
        menu = {
            prepare = function() return 20 end,
        },
        has_tag = function(_, tag) return tag == "kagiroi" end,
    }
    local context = {
        composition = {
            empty = function() return false end,
            back = function() return segment end,
        },
        select = function(_, index) selected_index = index end,
    }
    local env = {
        engine = {
            context = context,
            schema = { page_size = 10 },
        },
    }
    local key_event = {
        keycode = string.byte("2"),
        release = function() return false end,
        ctrl = function() return false end,
        alt = function() return false end,
        super = function() return false end,
    }

    fake.equal(selector.func(key_event, env), 1, "数字键应被 Kagiroi 选择器处理")
    fake.equal(selected_index, 11, "第 2 页按 2 应选择全局第 12 项")
end)

test("Kagiroi 混输接入与 moran_ja 相同的并行日语候选路径", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    fake.contains(content, "    - lua_translator@*moran_ja_translator", "nihon 必须同时获得日语词典候选")
    fake.contains(content, "    - lua_filter@*moran_ja_filter", "日语候选必须按 moran_ja 规则参与排序")
    fake.contains(content, "    - jaroomaji", "日语候选路径必须部署 jaroomaji 词典")
end)

test("Kagiroi 显式处理词尾拨音", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    fake.contains(content, "xform/^(.*)n$/$1ん$/", "词尾单 n 应映射为拨音")
end)

test("Kagiroi 混输部署汉字转换所需的直接依赖", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    fake.contains(content, "    - kagiroi_kanji", "Kagiroi 汉字词典 schema 必须参与部署")
    fake.contains(content, "    - kagiroi_matrix", "Kagiroi Viterbi 矩阵 schema 必须参与部署")
end)


test("离线词表为中文候选追加日语释义", function()
    with_gloss_filter(true, function(env)
        local output = fake.collect_filter(gloss_filter, fake.input({
            fake.candidate("table", "苹果"),
        }), env)
        fake.equal(output[1].text, "苹果", "释义过滤器应保留候选正文")
        fake.equal(output[1].comment, "〔日：リンゴ〕", "苹果应显示 Wikidict 日语释义")
    end)
end)

test("离线日语释义保留已有候选注释", function()
    with_gloss_filter(true, function(env)
        local output = fake.collect_filter(gloss_filter, fake.input({
            fake.candidate("table", "苹果", "⚡"),
        }), env)
        fake.equal(output[1].comment, "⚡ ¦ 〔日：リンゴ〕", "日语释义应追加在已有提示之后")
    end)
end)

test("离线释义可从文字转换候选回退到原始中文", function()
    with_gloss_filter(true, function(env)
        local genuine = fake.candidate("table", "苹果")
        local converted = fake.candidate("simplified", "蘋果", "", genuine)
        local output = fake.collect_filter(gloss_filter, fake.input({ converted }), env)
        fake.equal(output[1].text, "蘋果", "过滤器应保留最终显示字形")
        fake.equal(output[1].comment, "〔日：リンゴ〕", "转换后的候选应使用原始中文回查释义")
    end)
end)

test("日语来源候选不追加中文词典释义", function()
    with_gloss_filter(true, function(env)
        local output = fake.collect_filter(gloss_filter, fake.input({
            fake.candidate("jaroomaji", "日本"),
        }), env)
        fake.equal(output[1].comment, "", "并行日语候选应保持自身注释路径")
    end)
end)

test("关闭日译开关后候选保持原样", function()
    with_gloss_filter(false, function(env)
        local candidate = fake.candidate("table", "苹果", "原注释")
        local output = fake.collect_filter(gloss_filter, fake.input({ candidate }), env)
        fake.equal(output[1], candidate, "关闭开关应直接透传原候选")
        fake.equal(output[1].comment, "原注释", "关闭开关应保留原注释")
    end)
end)

test("混输方案在文字转换后接入离线日语释义", function()
    local file = assert(io.open(schema, "r"))
    local content = file:read("*a")
    file:close()
    local simplifier = assert(content:find("    - simplifier@simplifier", 1, true))
    local gloss = assert(content:find("    - lua_filter@*moran_ja_gloss_filter", 1, true))
    local uniquifier = assert(content:find("    - uniquifier", 1, true))
    fake.truthy(simplifier < gloss and gloss < uniquifier, "释义过滤器应读取最终字形并在去重前运行")
    fake.contains(content, "  - name: ja_gloss", "方案必须提供离线日译开关")
    fake.contains(content, "  dictionary: lua/zh_ja_wiki.txt", "方案必须部署 CC0 中日词表")
end)
return tests

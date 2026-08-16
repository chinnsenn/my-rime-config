-- ===================================================================
-- [INPUT]: 依赖 tests/rime_fake 的 schema 配置读取能力与 Trime 符号主题配置。
-- [OUTPUT]: 对外提供 moran_kagiroi_hybrid 的独立混输与液态符号目录契约测试。
-- [POS]:   tests/ 的 Kagiroi 集成规格，约束自动识别、罗马字布局、中文方案隔离与 Trime 符号入口。
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

test("Trime 符号键打开液态全量目录", function()
    local layout = assert(io.open("moran_kagiroi_hybrid.trime.yaml", "r"))
    local layout_content = layout:read("*a")
    layout:close()
    local palette = assert(io.open("moran_kagiroi_symbols.trime.yaml", "r"))
    local palette_content = palette:read("*a")
    palette:close()

    fake.contains(layout_content, "command: liquid_keyboard", "符号键必须调用 Trime 液态键盘")
    fake.contains(layout_content, "option: TABS", "符号键必须打开分类目录")
    fake.not_contains(layout_content, "_ios", "液态目录不应保留静态 iOS 符号页")
    fake.contains(palette_content, "type: TABS", "液态数据必须声明分类目录")
    fake.contains(palette_content, "type: SINGLE", "液态数据必须提供可滚动的字符分类")
end)

test("Trime 液态符号目录保持完整覆盖与紧凑网格", function()
    local palette = assert(io.open("moran_kagiroi_symbols.trime.yaml", "r"))
    local palette_content = palette:read("*a")
    palette:close()

    fake.contains(palette_content, "single_width: 40", "液态符号项必须形成紧凑触控网格")
    fake.contains(palette_content, "margin_x: 2", "液态符号项必须保留清晰分隔")
    fake.contains(palette_content, "source_groups: 201", "符号面板必须记录官方数据组总数")
    fake.contains(palette_content, "covered_source_groups: 201", "符号面板必须覆盖全部官方数据组")
    fake.contains(palette_content, "source_unique_entries: 3860", "符号面板必须记录去重后的官方条目数")
    fake.contains(palette_content, '"甲子"', "多字符符号条目必须保持为单个可提交项")
    fake.contains(palette_content, "ㆷ", "注音分类必须包含扩展注音尾项")
    fake.contains(palette_content, "⿕", "部首分类必须包含康熙部首尾项")
    fake.contains(palette_content, "➾", "箭头分类必须包含官方箭头尾项")
    fake.contains(palette_content, "ㇿ", "片假分类必须包含阿伊努小片假名尾项")
    fake.contains(palette_content, "﷼", "货币分类必须包含官方货币尾项")
    fake.not_contains(palette_content, "    - 其他", "完整分类后不应残留无语义的其他入口")
end)
return tests

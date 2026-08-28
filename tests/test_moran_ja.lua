-- ===================================================================
-- [INPUT]:  依赖生产 moran_ja_processor/moran_ja_filter/moran_ja_gloss_filter 公开接口、混合方案 YAML、Rime fake
-- [OUTPUT]: 对外提供日语混输语言追踪、排序、预览、释义与前缀模式行为测试集合
-- [POS]:    tests/ 的核心回归规格，驱动状态机与 schema 修复的 RED→GREEN 循环
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local fake = require("rime_fake")
local processor = require("moran_ja_processor")
local filter = require("moran_ja_filter")
local translator = require("moran_ja_translator")
local language = require("moran_ja_language")
local gloss_filter = require("moran_ja_gloss_filter")

local tests = {}

local function test(name, run)
    tests[#tests + 1] = { name = name, run = run }
end

local function state_config(overrides)
    local values = {
        ["moran_ja/state_machine/enabled"] = true,
        ["moran_ja/state_machine/window_size"] = 8,
        ["moran_ja/state_machine/decay_seconds"] = 45,
        ["moran_ja/state_machine/ja_threshold"] = 3,
        ["moran_ja/state_machine/zh_threshold"] = 2,
        ["moran_ja/telemetry/enabled"] = false,
    }
    for key, value in pairs(overrides or {}) do
        values[key] = value
    end
    return values
end

local function with_processor(config, body)
    local env = fake.environment(config)
    processor.init(env)
    local ok, err = xpcall(function() body(env) end, debug.traceback)
    processor.fini(env)
    if not ok then
        error(err, 0)
    end
end

local function with_filter(input_text, state, body, default_position)
    local restore_globals = fake.install_rime_globals()
    local env = fake.environment({
        ["moran_ja/default_position"] = default_position or 2,
        ["kagiroi/prefix"] = ";",
    })
    env.engine.context.input = input_text
    env.engine.context:set_property("moran_ja/state", state or "neutral")
    filter.init(env)
    local ok, err = xpcall(function() body(env) end, debug.traceback)
    filter.fini(env)
    restore_globals()
    if not ok then
        error(err, 0)
    end
end

local function with_translator(body)
    local restore_globals = fake.install_rime_globals()
    local env = fake.environment()
    translator.init(env)
    local ok, err = xpcall(function() body(env) end, debug.traceback)
    translator.fini(env)
    restore_globals()
    if not ok then
        error(err, 0)
    end
end

local function with_gloss_filter(body)
    local restore_globals = fake.install_rime_globals()
    local env = fake.environment({
        ["moran_ja_gloss/dictionaries"] = { "lua/zh_ja_custom.txt" },
    })
    env.engine.context:set_option("ja_gloss", true)
    gloss_filter.init(env)
    local ok, err = xpcall(function() body(env) end, debug.traceback)
    gloss_filter.fini(env)
    restore_globals()
    if not ok then
        error(err, 0)
    end
end

test("jaroomaji 纯汉字候选达到阈值后形成日语偏置", function()
    with_processor(state_config(), function(env)
        local candidate = fake.candidate("jaroomaji", "日本")
        env:commit(candidate)
        env:commit(candidate)
        fake.equal(env.state.current, processor.neutral, "阈值前应保持 neutral")
        env:commit(candidate)
        fake.equal(env.state.current, processor.ja_bias, "第三次 jaroomaji 提交应达到 ja_threshold")
    end)
end)

test("ShadowCandidate 的 genuine jaroomaji 类型参与日语累计", function()
    with_processor(state_config({ ["moran_ja/state_machine/ja_threshold"] = 1 }), function(env)
        env:commit(fake.shadow_candidate("shadow", "東京", "", "jaroomaji"))
        fake.equal(env.state.current, processor.ja_bias, "genuine type 应识别为 jaroomaji")
    end)
end)

test("Kagiroi 纯汉字候选参与日语累计", function()
    with_processor(state_config({ ["moran_ja/state_machine/ja_threshold"] = 1 }), function(env)
        env:commit(fake.candidate("kagiroi", "創価"))
        fake.equal(env.state.current, processor.ja_bias, "Kagiroi 纯汉字候选应建立日语偏置")
    end)
end)

test("纯汉字日语自定义短语经翻译器携带日语身份并累计偏置", function()
    local custom_translator = require("moran_ja_custom_translator")
    local restore_globals = fake.install_rime_globals()
    local env = fake.environment(state_config({ ["moran_ja/state_machine/ja_threshold"] = 1 }))
    env:set_component_candidates({ fake.candidate("phrase", "東京", "自定义") })
    processor.init(env)
    custom_translator.init(env)

    local ok, err = xpcall(function()
        local output = fake.collect_yields(function()
            custom_translator.func("tokyo", {}, env)
        end)
        fake.equal(#output, 1, "自定义日语翻译器应产出原候选")
        fake.equal(output[1].text, "東京", "包装候选应保留纯汉字文本")
        env:commit(output[1])
        fake.equal(env.state.current, processor.ja_bias, "纯汉字日语自定义短语应累计为日语")
    end, debug.traceback)

    custom_translator.fini(env)
    processor.fini(env)
    restore_globals()
    if not ok then error(err, 0) end
end)

test("英文数字和标点候选不会污染中日语言状态", function()
    with_processor(state_config({
        ["moran_ja/state_machine/ja_threshold"] = 1,
        ["moran_ja/state_machine/zh_threshold"] = 1,
    }), function(env)
        env:commit(fake.candidate("english", "hello"))
        env:commit(fake.candidate("number", "2026"))
        env:commit(fake.candidate("punct", "。"))
        fake.equal(env.state.current, processor.neutral, "非中日候选应被语言状态机忽略")
        fake.equal(#env.state.commit_history, 0, "忽略的候选不应占用滑动窗口")
    end)
end)

test("缺少已选候选的提交事件不会污染状态", function()
    with_processor(state_config({ ["moran_ja/state_machine/zh_threshold"] = 1 }), function(env)
        env:commit(nil, "临时文本")
        fake.equal(env.state.current, processor.neutral, "没有候选身份时应忽略提交事件")
        fake.equal(#env.state.commit_history, 0, "没有候选身份的事件不应进入窗口")
    end)
end)

test("空提交事件保持状态和窗口不变", function()
    with_processor(state_config(), function(env)
        env:commit(fake.candidate("jaroomaji", ""), "")
        fake.equal(env.state.current, processor.neutral, "空提交应保持 neutral")
        fake.equal(#env.state.commit_history, 0, "空提交不应进入窗口")
    end)
end)

test("关闭状态机后提交和按键均保持 neutral", function()
    with_processor(state_config({ ["moran_ja/state_machine/enabled"] = false }), function(env)
        env:commit(fake.candidate("jaroomaji", "かな"))
        processor.func(fake.key("space"), env)
        fake.equal(env.state.current, processor.neutral, "显式 false 应关闭状态迁移")
        fake.equal(#env.state.commit_history, 0, "关闭状态机后提交不应进入窗口")
    end)
end)

test("最近达到中文阈值可从日语偏置切换为中文偏置", function()
    with_processor(state_config(), function(env)
        local ja = fake.candidate("jaroomaji", "日本")
        local zh = fake.candidate("table", "中文")
        env:commit(ja)
        env:commit(ja)
        env:commit(ja)
        fake.equal(env.state.current, processor.ja_bias, "日语提交应先建立 ja_bias")
        env:commit(zh)
        env:commit(zh)
        fake.equal(env.state.current, processor.zh_bias, "最近达到 zh_threshold 应切换偏置")
    end)
end)

test("滑动窗口淘汰旧语言后按窗口内计数迁移", function()
    with_processor(state_config({ ["moran_ja/state_machine/window_size"] = 3 }), function(env)
        local ja = fake.candidate("jaroomaji", "かな")
        local zh = fake.candidate("table", "中文")
        env:commit(ja)
        env:commit(ja)
        env:commit(ja)
        env:commit(zh)
        env:commit(zh)
        fake.equal(#env.state.commit_history, 3, "窗口只保留最近三次有效语言提交")
        fake.equal(env.state.current, processor.zh_bias, "旧日语事件淘汰后应迁移到 zh_bias")
    end)
end)

test("每次有效语言提交刷新衰减活动时间", function()
    local real_time = os.time
    local now = 0
    os.time = function() return now end
    local ok, err = xpcall(function()
        with_processor(state_config(), function(env)
            local ja = fake.candidate("jaroomaji", "かな")
            now = 1
            env:commit(ja)
            now = 2
            env:commit(ja)
            now = 3
            env:commit(ja)
            fake.equal(env.state.current, processor.ja_bias, "前置条件应建立 ja_bias")
            now = 50
            env:commit(ja)
            now = 60
            processor.func(fake.key("a"), env)
            fake.equal(env.state.current, processor.ja_bias, "最近提交十秒后仍应保持 ja_bias")
        end)
    end, debug.traceback)
    os.time = real_time
    if not ok then error(err, 0) end
end)

test("无效日语罗马字不进入 jaroomaji 候选流", function()
    local invalid_inputs = { "ng vp gt", "bcd", "qz", "trm", "zzzz", "k a", "k'a" }
    with_translator(function(env)
        env:set_component_candidates({ fake.candidate("phrase", "机械假名") })
        for _, input_text in ipairs(invalid_inputs) do
            local output = fake.collect_yields(function()
                translator.func(input_text, {}, env)
            end)
            fake.equal(#output, 0, "孤立辅音序列不应进入日语翻译器: " .. input_text)
        end
    end)
end)

test("合法日语罗马字保留 jaroomaji 候选", function()
    local valid_inputs = {
        "nihon", "ni hon", "kitte", "matcha", "gakkou", "shinbun", "xtu",
        "qwa", "qi", "qa", "vi", "vyi", "vye", "xyi",
    }
    with_translator(function(env)
        env:set_component_candidates({ fake.candidate("phrase", "有効") })
        for _, input_text in ipairs(valid_inputs) do
            local output = fake.collect_yields(function()
                translator.func(input_text, {}, env)
            end)
            fake.equal(fake.sequence_text(output), "有効", "合法罗马字应进入日语翻译器: " .. input_text)
        end
    end)
end)

test("连续分隔符忽略空段且不跨段拼接", function()
    fake.truthy(language.is_valid_romaji("  ni''  hon  "), "连续空格和撇号应分隔独立合法段")
    fake.truthy(not language.is_valid_romaji("k a"), "空格两侧音节不得拼接为 ka")
    fake.truthy(not language.is_valid_romaji("k'a"), "撇号两侧音节不得拼接为 ka")
    fake.truthy(not language.is_valid_romaji("  ''  "), "纯分隔符输入应拒绝")
end)

test("超长合法罗马字使用迭代校验", function()
    fake.truthy(language.is_valid_romaji(string.rep("a", 20000)), "超长合法输入应通过且不消耗调用栈")
end)

test("基础假名词典的全部罗马字音节均通过结构校验", function()
    local file = assert(io.open("jaroomaji.kana_kigou.dict.yaml", "r"))
    local checked = 0
    for line in file:lines() do
        local text, code = string.match(line, "^([^#\t]+)\t([^\t]+)")
        local has_kana = false
        if text then
            for _, codepoint in utf8.codes(text) do
                if codepoint >= 0x3040 and codepoint <= 0x30FF then
                    has_kana = true
                    break
                end
            end
        end
        if has_kana and code == string.lower(code) then
            for token in string.gmatch(code, "%S+") do
                fake.truthy(language.is_valid_romaji(token), "词典音节应通过校验: " .. token)
                checked = checked + 1
            end
        end
    end
    file:close()
    fake.truthy(checked > 200, "结构校验应覆盖完整基础假名词典")
end)

test("促音派生辅音脱离后续音节时全部拒绝", function()
    for consonant in string.gmatch("k c q g s z j t d h f b v p m y r w", "%S+") do
        fake.truthy(not language.is_valid_romaji(consonant), "孤立促音辅音应拒绝: " .. consonant)
    end
end)

test("明确中文输入只保留非日语候选", function()
    with_filter("ng vp gt", "ja_bias", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "能准确"),
            fake.candidate("jaroomaji", "んっっっっっ"),
            fake.candidate("table", "能准过头"),
        }), env)
        fake.equal(fake.sequence_text(output), "能准确|能准过头", "无效日语结构应由当前输入直接裁决为中文")
    end)
end)

test("明确日语输入只保留日语候选", function()
    with_filter("kitte", "zh_bias", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "其他"),
            fake.candidate("jaroomaji", "切手"),
            fake.candidate("kagiroi", "切手帳"),
        }), env)
        fake.equal(fake.sequence_text(output), "切手|切手帳", "当前输入的明确日语特征应覆盖历史中文偏置")
    end)
end)

test("q x v 日语专属结构经过过滤器只保留日语候选", function()
    local explicit_japanese_inputs = { "qwa", "vyi", "vye", "xyi" }
    for _, input_text in ipairs(explicit_japanese_inputs) do
        with_filter(input_text, "zh_bias", function(env)
            local output = fake.collect_filter(filter, fake.input({
                fake.candidate("table", "其他"),
                fake.candidate("jaroomaji", "仮名"),
            }), env)
            fake.equal(fake.sequence_text(output), "仮名", "日语专属 q/x/v 结构应覆盖中文偏置: " .. input_text)
        end)
    end
end)

test("q x v 双拼重叠码继续保留中日混合候选", function()
    local ambiguous_inputs = { "qi", "qa", "vi", "xa" }
    for _, input_text in ipairs(ambiguous_inputs) do
        with_filter(input_text, "neutral", function(env)
            local output = fake.collect_filter(filter, fake.input({
                fake.candidate("table", "中文"),
                fake.candidate("jaroomaji", "仮名"),
            }), env)
            fake.equal(fake.sequence_text(output), "中文|仮名", "双拼与日语重叠码应保持混排: " .. input_text)
        end)
    end
end)

test("非法 UTF-8 候选文本安全降级", function()
    with_filter("ng", "neutral", function(env)
        local malformed = fake.candidate("unknown", string.char(0xFF), "原注释")
        local output = fake.collect_filter(filter, fake.input({ malformed }), env)
        fake.equal(#output, 1, "非法 UTF-8 候选应继续产出")
        fake.equal(output[1], malformed, "非法 UTF-8 候选应保持原对象")
    end)
end)

test("Kagiroi 前缀段只保留日语候选", function()
    with_filter(";nihon", "zh_bias", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "拟红"),
            fake.candidate("kagiroi", "日本"),
            fake.candidate("kagiroi", "日本語"),
        }), env)
        fake.equal(fake.sequence_text(output), "日本|日本語", "显式 Kagiroi 段应覆盖历史中文偏置")
    end)
end)

test("合法模糊输入继续保留中日混合候选", function()
    with_filter("nihon", "neutral", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "你红"),
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "霓虹"),
        }), env)
        fake.equal(fake.sequence_text(output), "你红|日本|霓虹", "中日都成立的罗马字应继续使用混合排序")
    end)
end)

test("过滤器产出首个候选无需等待源候选流耗尽", function()
    with_filter("nihon", "neutral", function(env)
        local candidates = {
            fake.candidate("table", "你"),
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "你好"),
            fake.candidate("table", "拟"),
        }
        local input = fake.input(candidates)
        local old_yield = _G.yield
        _G.yield = coroutine.yield
        local co = coroutine.create(function() filter.func(input, env) end)
        local ok, first = coroutine.resume(co)
        _G.yield = old_yield
        fake.truthy(ok, first)
        fake.equal(first.text, "你", "既定排序的首位应为第一个中文候选")
        fake.truthy(input.consumed < #candidates, "首个输出前不应耗尽整个源候选流")
    end)
end)

test("流式过滤保持中文首位和日语默认插位排序", function()
    with_filter("nihon", "neutral", function(env)
        local input = fake.input({
            fake.candidate("table", "你"),
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "你好"),
            fake.candidate("jaroomaji", "日本語"),
        })
        local output = fake.collect_filter(filter, input, env)
        fake.equal(fake.sequence_text(output), "你|日本|你好|日本語", "流式实现应保持 default_position=2 的稳定排序")
    end)
end)

test("日语偏置保持首中文后全部日语再其余中文的完整顺序", function()
    with_filter("nihon", "ja_bias", function(env)
        local input = fake.input({
            fake.candidate("table", "你"),
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "你好"),
            fake.candidate("jaroomaji", "日本語"),
            fake.candidate("table", "拟"),
        })
        local output = fake.collect_filter(filter, input, env)
        fake.equal(fake.sequence_text(output), "你|日本|日本語|你好|拟", "ja_bias 应保持既定分组与组内稳定顺序")
    end)
end)

test("日语偏置处理日语开头源流时每个候选只产出一次", function()
    with_filter("nihon", "ja_bias", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "你"),
            fake.candidate("jaroomaji", "日本語"),
            fake.candidate("table", "你好"),
        }), env)
        fake.equal(fake.sequence_text(output), "你|日本|日本語|你好", "日语开头源流应稳定分组且无重复")
    end)
end)

test("neutral 的 default_position 三保持第三位插入日语", function()
    with_filter("nihon", "neutral", function(env)
        local input = fake.input({
            fake.candidate("table", "你"),
            fake.candidate("jaroomaji", "日本"),
            fake.candidate("table", "你好"),
            fake.candidate("jaroomaji", "日本語"),
            fake.candidate("table", "拟"),
        })
        local output = fake.collect_filter(filter, input, env)
        fake.equal(fake.sequence_text(output), "你|你好|日本|拟|日本語", "default_position=3 应在两个中文候选后插入首个日语候选")
    end, 3)
end)

test("日语候选晚到仍按 default_position 二插入", function()
    with_filter("nihon", "neutral", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "你"),
            fake.candidate("table", "你好"),
            fake.candidate("jaroomaji", "日本"),
        }), env)
        fake.equal(fake.sequence_text(output), "你|日本|你好", "晚到的日语候选仍应占据第二位")
    end)
end)

test("日语候选晚到仍按 default_position 三插入", function()
    with_filter("nihon", "neutral", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("table", "你"),
            fake.candidate("table", "你好"),
            fake.candidate("table", "拟"),
            fake.candidate("jaroomaji", "日本"),
        }), env)
        fake.equal(fake.sequence_text(output), "你|你好|日本|拟", "晚到的日语候选仍应占据第三位")
    end, 3)
end)

test("假名预览追加到原候选注释", function()
    with_filter("shi", "neutral", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("jaroomaji", "詩", "原注释"),
        }), env)
        fake.contains(output[1].comment, "原注释", "预览候选应保留原注释")
        fake.contains(output[1].comment, "[し]", "预览候选应追加平假名")
    end)
end)

test("大写罗马字显示片假名预览", function()
    with_filter("SHI", "neutral", function(env)
        local output = fake.collect_filter(filter, fake.input({
            fake.candidate("jaroomaji", "詩", "音读"),
        }), env)
        fake.contains(output[1].comment, "[シ]", "大写 SHI 应预览为片假名 シ")
        fake.not_contains(output[1].comment, "[し]", "大写输入不应降为平假名预览")
    end)
end)

test("japanese_only 识别并转换大写片假名路径", function()
    local pattern = fake.schema_scalar("moran_ja_hybrid.schema.yaml", { "recognizer", "patterns" }, "japanese_only")
    fake.truthy(string.match(";jSHI", pattern), "recognizer 应接受 ;j 后的大写罗马字")
    local preedit = fake.apply_preedit("moran_ja_hybrid.schema.yaml", "japanese_only", ";jSHI")
    fake.equal(preedit, "シ", "japanese_only preedit 应将 ;jSHI 转换为片假名 シ")
end)

test("异常 genuine 访问安全降级且候选继续产出", function()
    with_gloss_filter(function(env)
        local broken_get_genuine = fake.candidate("table", "未收录词", "原注释一")
        broken_get_genuine.get_genuine = function()
            error("get_genuine failed")
        end

        local inaccessible_genuine = setmetatable({}, {
            __index = function(_, key)
                if key == "text" then
                    error("genuine.text failed")
                end
                return nil
            end,
        })
        local broken_genuine_text = fake.candidate("table", "未收录项", "原注释二", inaccessible_genuine)
        local output = fake.collect_filter(gloss_filter, fake.input({
            broken_get_genuine,
            broken_genuine_text,
        }), env)

        fake.equal(#output, 2, "异常 genuine 候选应全部继续产出")
        fake.equal(output[1], broken_get_genuine, "get_genuine 异常时应产出原候选")
        fake.equal(output[2], broken_genuine_text, "genuine.text 异常时应产出原候选")
        fake.equal(output[1].comment, "原注释一", "get_genuine 异常时不应追加释义")
        fake.equal(output[2].comment, "原注释二", "genuine.text 异常时不应追加释义")
    end)
end)

return tests

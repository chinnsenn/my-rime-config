-- ===================================================================
-- [INPUT]:  依赖生产 moran_ja_processor/moran_ja_filter 公开接口、混合方案 YAML、Rime fake
-- [OUTPUT]: 对外提供日语混输语言追踪、排序、预览与前缀模式行为测试集合
-- [POS]:    tests/ 的核心回归规格，驱动状态机与 schema 修复的 RED→GREEN 循环
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local fake = require("rime_fake")
local processor = require("moran_ja_processor")
local filter = require("moran_ja_filter")

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
    local env = fake.environment({ ["moran_ja/default_position"] = default_position or 2 })
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

return tests

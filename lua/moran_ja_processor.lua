-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (KeyEvent, Context, SchemaConfig, env)
-- [OUTPUT]: 对外提供共享候选语言语义的 moran_ja_processor
-- [POS]:    lua/ 目录的日语混输状态处理器，与过滤器共享语言判定
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local language = require("moran_ja_language")

local kNoop = 2

-- ===============================================
-- JSONL telemetry（最小骨架）
-- ===============================================
local function clamp_sample_rate(value)
    local n = tonumber(value) or 1.0
    if n < 0 then
        return 0
    end
    if n > 1 then
        return 1
    end
    return n
end

local function json_escape(s)
    local t = tostring(s or "")
    t = string.gsub(t, "\\", "\\\\")
    t = string.gsub(t, '"', '\\"')
    t = string.gsub(t, "\n", "\\n")
    t = string.gsub(t, "\r", "\\r")
    t = string.gsub(t, "\t", "\\t")
    return t
end

local function to_jsonl_line(event_table)
    local fields = {
        "ts",
        "event",
        "input",
        "input_len",
        "top1_lang",
        "selection_index",
        "committed_lang",
        "state",
    }

    local parts = {}
    for _, key in ipairs(fields) do
        local value = event_table and event_table[key]
        if value ~= nil then
            if type(value) == "number" or type(value) == "boolean" then
                parts[#parts + 1] = string.format('"%s":%s', key, tostring(value))
            else
                parts[#parts + 1] = string.format('"%s":"%s"', key, json_escape(value))
            end
        end
    end

    return "{" .. table.concat(parts, ",") .. "}\n"
end

local function emit_event(telemetry, event_table)
    if not telemetry or not telemetry.enabled then
        return
    end

    local log_file = telemetry.log_file
    if not log_file or log_file == "" then
        return
    end

    local sample_rate = clamp_sample_rate(telemetry.sample_rate)
    if sample_rate <= 0 then
        return
    end

    if sample_rate < 1 and math.random() > sample_rate then
        return
    end

    local payload = event_table or {}
    if payload.ts == nil then
        payload.ts = os.time()
    end
    if payload.event == nil then
        payload.event = "heartbeat"
    end

    pcall(function()
        local fp = io.open(log_file, "a")
        if not fp then
            return
        end
        fp:write(to_jsonl_line(payload))
        fp:close()
    end)
end

-- ===============================================
-- 已选候选语言读取
-- ===============================================
local function selected_language(context)
    local ok, candidate = pcall(function()
        return context:get_selected_candidate()
    end)
    if not ok or not candidate then
        return nil
    end
    return language.candidate_language(candidate)
end

-- ===============================================
-- 软状态机常量
-- ===============================================
local STATE_NEUTRAL = "neutral"
local STATE_JA_BIAS = "ja_bias"
local STATE_ZH_BIAS = "zh_bias"

local STATE_PROPERTY = "moran_ja/state"
local STATE_UPDATED_AT_PROPERTY = "moran_ja/state_updated_at"

local function safe_set_property(context, key, value)
    if not context then
        return
    end
    pcall(function()
        context:set_property(key, tostring(value or ""))
    end)
end

local function publish_state(env)
    local context = env and env.engine and env.engine.context
    local state = env and env.state
    if not context or not state then
        return
    end

    safe_set_property(context, STATE_PROPERTY, state.current)
    safe_set_property(context, STATE_UPDATED_AT_PROPERTY, state.last_decay_ts)
end

local function transition_state(env, next_state, now)
    local state = env and env.state
    if not state or not next_state then
        return
    end

    if state.current == next_state then
        return
    end

    state.current = next_state
    state.last_decay_ts = now or os.time()
    publish_state(env)
end

-- ===============================================
-- 滑动窗口：记录最近 N 次 commit 的语言
-- ===============================================
local function push_commit_lang(state, lang, window_size)
    local history = state.commit_history
    history[#history + 1] = lang
    -- 超出窗口时，移除最旧的记录
    while #history > window_size do
        table.remove(history, 1)
    end
end

local function count_langs(state)
    local ja_count = 0
    local zh_count = 0
    for _, lang in ipairs(state.commit_history) do
        if lang == "ja" then
            ja_count = ja_count + 1
        else
            zh_count = zh_count + 1
        end
    end
    return ja_count, zh_count
end

local function resolve_commit_state(committed_lang, ja_count, zh_count, cfg)
    if committed_lang == "ja" and ja_count >= cfg.ja_threshold then
        return STATE_JA_BIAS
    end
    if committed_lang == "zh" and zh_count >= cfg.zh_threshold then
        return STATE_ZH_BIAS
    end
    if ja_count >= cfg.ja_threshold then
        return STATE_JA_BIAS
    end
    if zh_count >= cfg.zh_threshold then
        return STATE_ZH_BIAS
    end
    return STATE_NEUTRAL
end

-- ===============================================
-- 配置读取工具
-- ===============================================
local function config_get_bool(config, key, default_value)
    if not config then
        return default_value
    end
    local ok, value = pcall(function()
        return config:get_bool(key)
    end)
    if not ok or value == nil then
        return default_value
    end
    return value
end

local function config_get_int(config, key, default_value)
    if not config then
        return default_value
    end
    local ok, value = pcall(function()
        return config:get_int(key)
    end)
    if not ok or value == nil then
        return default_value
    end
    return value
end

local function config_get_string(config, key, default_value)
    if not config then
        return default_value
    end
    local ok, value = pcall(function()
        return config:get_string(key)
    end)
    if not ok or value == nil then
        return default_value
    end
    return value
end

-- ===============================================
-- 生命周期
-- ===============================================
local function normalize_input(input)
    if input == nil then
        return ""
    end
    if type(input) == "string" then
        return input
    end
    return tostring(input)
end

local function apply_input_telemetry(payload, input, telemetry)
    if not payload then
        return
    end

    local normalized_input = normalize_input(input)
    if telemetry and telemetry.log_raw_input == true then
        payload.input = normalized_input
    else
        payload.input_len = #normalized_input
    end
end

local function init(env)
    local engine = env and env.engine
    local schema = engine and engine.schema
    local config = schema and schema.config

    local sm_enabled = config_get_bool(config, "moran_ja/state_machine/enabled", true)
    local telemetry_enabled = config_get_bool(config, "moran_ja/telemetry/enabled", false)

    env.state = {
        current = STATE_NEUTRAL,
        commit_history = {},  -- 滑动窗口：记录 "ja" 或 "zh"
        last_event_ts = 0,
        last_decay_ts = os.time(),
    }

    env.config = {
        state_machine = {
            enabled = sm_enabled,
            window_size = config_get_int(config, "moran_ja/state_machine/window_size", 8),
            decay_seconds = config_get_int(config, "moran_ja/state_machine/decay_seconds", 45),
            ja_threshold = config_get_int(config, "moran_ja/state_machine/ja_threshold", 3),
            zh_threshold = config_get_int(config, "moran_ja/state_machine/zh_threshold", 2),
        },
        telemetry = {
            enabled = telemetry_enabled,
            log_file = config_get_string(config, "moran_ja/telemetry/log_file", ""),
            sample_rate = tonumber(config_get_string(config, "moran_ja/telemetry/sample_rate", "1.0")) or 1.0,
            log_raw_input = config_get_bool(config, "moran_ja/telemetry/log_raw_input", false),
        },
    }

    -- ===============================================
    -- 挂载 commit_notifier：追踪用户实际选择行为
    -- ===============================================
    if sm_enabled then
        env.commit_conn = engine.context.commit_notifier:connect(function(ctx)
            local cfg = env.config.state_machine
            if not cfg or not cfg.enabled then
                return
            end

            local now = os.time()

            -- 获取 commit 文本与已选候选身份
            local ok, commit_text = pcall(function()
                return ctx:get_commit_text()
            end)
            if not ok or not commit_text or #commit_text == 0 then
                return
            end

            local committed_lang = selected_language(ctx)
            if not committed_lang then
                return
            end

            -- 推入滑动窗口
            push_commit_lang(env.state, committed_lang, cfg.window_size)
            env.state.last_decay_ts = now

            -- 统计窗口内 ja/zh 计数，决定状态迁移
            local ja_count, zh_count = count_langs(env.state)
            local next_state = resolve_commit_state(committed_lang, ja_count, zh_count, cfg)
            transition_state(env, next_state, now)
            publish_state(env)

            -- 遥测
            emit_event(env.config.telemetry, {
                event = "commit",
                committed_lang = committed_lang,
                state = env.state.current,
            })
        end)
    end

    publish_state(env)
    local init_payload = {
        event = "state",
        state = env.state.current,
    }
    apply_input_telemetry(init_payload, "", env.config and env.config.telemetry)
    emit_event(env.config.telemetry, init_payload)
end

local function fini(env)
    if env and env.state then
        emit_event(env.config and env.config.telemetry, {
            event = "state",
            state = env.state.current,
        })
        env.state.current = STATE_NEUTRAL
        publish_state(env)
    end

    -- 断开 commit_notifier
    if env and env.commit_conn then
        env.commit_conn:disconnect()
        env.commit_conn = nil
    end

end

-- ===============================================
-- telemetry 辅助
-- ===============================================
local function safe_key_repr(key_event)
    if not key_event then
        return ""
    end
    local ok, value = pcall(function()
        return key_event:repr()
    end)
    if not ok or not value then
        return ""
    end
    return tostring(value)
end

local function detect_telemetry_event(key_event, input)
    local key_repr = safe_key_repr(key_event)
    local normalized_input = normalize_input(input)

    local is_digit_select = string.match(key_repr, "^[1-9]$") ~= nil
    local is_commit_key = key_repr == "space" or key_repr == "Return" or key_repr == "KP_Enter"

    if is_commit_key and #normalized_input > 0 then
        return "commit"
    end

    if is_digit_select and #normalized_input > 0 then
        return "select"
    end

    if #normalized_input > 0 then
        return "filter"
    end

    return nil
end

-- ===============================================
-- 核心 processor：仅衰减 + telemetry，打分已移至 commit_notifier
-- ===============================================
local function processor(key_event, env)
    if key_event:release() then
        return kNoop
    end

    local cfg = env and env.config and env.config.state_machine
    local state = env and env.state
    if not cfg or not state or not cfg.enabled then
        return kNoop
    end

    local now = os.time()
    local elapsed = now - (state.last_decay_ts or now)

    -- ===============================================
    -- 衰减路径：超时清空窗口，回落 neutral
    -- ===============================================
    if cfg.decay_seconds > 0 and elapsed >= cfg.decay_seconds then
        state.commit_history = {}
        transition_state(env, STATE_NEUTRAL, now)
    end

    -- ===============================================
    -- 遥测事件
    -- ===============================================
    local context = env and env.engine and env.engine.context
    local input = normalize_input(context and context.input or "")

    local event_type = detect_telemetry_event(key_event, input)
    if event_type ~= nil then
        local payload = {
            event = event_type,
            state = state.current,
        }
        apply_input_telemetry(payload, input, env and env.config and env.config.telemetry)
        emit_event(env.config.telemetry, payload)
    end

    state.last_event_ts = now
    return kNoop
end

return {
    init = init,
    func = processor,
    fini = fini,

    -- 供后续调试/测试直接读取常量
    neutral = STATE_NEUTRAL,
    ja_bias = STATE_JA_BIAS,
    zh_bias = STATE_ZH_BIAS,
}

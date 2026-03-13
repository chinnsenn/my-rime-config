-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (KeyEvent, Context, SchemaConfig, env)
-- [OUTPUT]: 对外提供 moran_ja_processor (lua_processor, 软状态机骨架)
-- [POS]:    lua/ 目录的日语混输状态处理器，被 moran_ja_hybrid 方案与过滤器协作读取
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local kNoop = 2

local active_telemetry = nil

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

local function emit_event(event_table)
    local telemetry = active_telemetry
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

local function init(env)
    local engine = env and env.engine
    local schema = engine and engine.schema
    local config = schema and schema.config

    local sm_enabled = config_get_bool(config, "moran_ja/state_machine/enabled", true)
    local telemetry_enabled = config_get_bool(config, "moran_ja/telemetry/enabled", false)

    env.state = {
        current = STATE_NEUTRAL,
        ja_score = 0,
        zh_score = 0,
        last_event_ts = 0,
        last_decay_ts = os.time(),
    }

    env.config = {
        state_machine = {
            enabled = sm_enabled,
            window_size = config_get_int(config, "moran_ja/state_machine/window_size", 6),
            decay_seconds = config_get_int(config, "moran_ja/state_machine/decay_seconds", 25),
            ja_threshold = config_get_int(config, "moran_ja/state_machine/ja_threshold", 2),
            zh_threshold = config_get_int(config, "moran_ja/state_machine/zh_threshold", 2),
        },
        telemetry = {
            enabled = telemetry_enabled,
            log_file = config_get_string(config, "moran_ja/telemetry/log_file", ""),
            sample_rate = tonumber(config_get_string(config, "moran_ja/telemetry/sample_rate", "1.0")) or 1.0,
        },
    }

    active_telemetry = env.config.telemetry

    publish_state(env)
    emit_event({
        event = "state",
        input = "",
        state = env.state.current,
    })
end

local function fini(env)
    if env and env.state then
        emit_event({
            event = "state",
            state = env.state.current,
        })
        env.state.current = STATE_NEUTRAL
        publish_state(env)
    end
    active_telemetry = nil
end

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
    -- 衰减路径：超时回落 neutral
    -- ===============================================
    if cfg.decay_seconds > 0 and elapsed >= cfg.decay_seconds then
        state.ja_score = 0
        state.zh_score = 0
        transition_state(env, STATE_NEUTRAL, now)
    end

    -- ===============================================
    -- 轻量启发式：基于当前输入更新 ja/zh 分数
    -- ===============================================
    local context = env and env.engine and env.engine.context
    local input = context and context.input or ""

    local has_ascii_letter = false
    local has_digit = false
    for i = 1, #input do
        local c = string.sub(input, i, i)
        if string.match(c, "%a") then
            has_ascii_letter = true
        elseif string.match(c, "%d") then
            has_digit = true
        end
    end

    if #input > 0 then
        if has_ascii_letter and not has_digit then
            state.ja_score = state.ja_score + 1
            if state.zh_score > 0 then
                state.zh_score = state.zh_score - 1
            end
        elseif has_digit and not has_ascii_letter then
            state.zh_score = state.zh_score + 1
            if state.ja_score > 0 then
                state.ja_score = state.ja_score - 1
            end
        else
            if state.ja_score > 0 then
                state.ja_score = state.ja_score - 1
            end
            if state.zh_score > 0 then
                state.zh_score = state.zh_score - 1
            end
        end

        local window = cfg.window_size or 6
        if window > 0 then
            if state.ja_score > window then
                state.ja_score = window
            end
            if state.zh_score > window then
                state.zh_score = window
            end
        end
    end

    -- ===============================================
    -- 最小状态迁移：达到阈值时进入偏置态
    -- ===============================================
    if state.ja_score >= (cfg.ja_threshold or 2) then
        transition_state(env, STATE_JA_BIAS, now)
    elseif state.zh_score >= (cfg.zh_threshold or 2) then
        transition_state(env, STATE_ZH_BIAS, now)
    elseif state.ja_score == 0 and state.zh_score == 0 then
        transition_state(env, STATE_NEUTRAL, now)
    end

    emit_event({
        event = "heartbeat",
        input = input,
        state = state.current,
    })

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

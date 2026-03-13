-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (KeyEvent, Context, SchemaConfig, env)
-- [OUTPUT]: 对外提供 moran_ja_processor (lua_processor, 软状态机骨架)
-- [POS]:    lua/ 目录的日语混输状态处理器，被 moran_ja_hybrid 方案与过滤器协作读取
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local kNoop = 2

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

    publish_state(env)
end

local function fini(env)
    if env and env.state then
        env.state.current = STATE_NEUTRAL
        publish_state(env)
    end
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

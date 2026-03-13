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

local function init(env)
    local config = env.engine.schema.config

    local sm_enabled = config:get_bool("moran_ja/state_machine/enabled")
    if sm_enabled == nil then
        sm_enabled = true
    end

    local telemetry_enabled = config:get_bool("moran_ja/telemetry/enabled")
    if telemetry_enabled == nil then
        telemetry_enabled = false
    end

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
            window_size = config:get_int("moran_ja/state_machine/window_size") or 6,
            decay_seconds = config:get_int("moran_ja/state_machine/decay_seconds") or 25,
            ja_threshold = config:get_int("moran_ja/state_machine/ja_threshold") or 2,
            zh_threshold = config:get_int("moran_ja/state_machine/zh_threshold") or 2,
        },
        telemetry = {
            enabled = telemetry_enabled,
            log_file = config:get_string("moran_ja/telemetry/log_file") or "",
            sample_rate = tonumber(config:get_string("moran_ja/telemetry/sample_rate") or "") or 1.0,
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
    -- 衰减骨架：当前仅在窗口超时后回落 neutral
    -- ===============================================
    if cfg.decay_seconds > 0 and elapsed >= cfg.decay_seconds then
        state.current = STATE_NEUTRAL
        state.ja_score = 0
        state.zh_score = 0
        state.last_decay_ts = now
        publish_state(env)
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

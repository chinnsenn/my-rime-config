-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (Candidate, yield, env)
-- [OUTPUT]: 对外提供按当前输入意图裁决的 moran_ja_filter
-- [POS]:    lua/ 目录的日语混合过滤器，与翻译器、处理器共享语言判定
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local language = require("moran_ja_language")

-- ===============================================
-- 性能优化：缓存全局函数引用
-- ===============================================
local string_match = string.match
local string_sub = string.sub
local ipairs = ipairs

-- ===============================================
-- 更新缓存
-- ===============================================
local function update_cache(cache, input)
    if input ~= cache.input then
        cache.kana_preview = language.to_kana(input)
        cache.input = input
    end
end

-- ===============================================
-- 状态机读取
-- ===============================================
local JA_STATE_PROPERTY = "moran_ja/state"
local JA_STATE_NEUTRAL = "neutral"
local JA_STATE_JA_BIAS = "ja_bias"
local JA_STATE_ZH_BIAS = "zh_bias"

local function resolve_ja_state(context)
    local ok, state = pcall(function()
        return context:get_property(JA_STATE_PROPERTY)
    end)
    if not ok then
        return JA_STATE_NEUTRAL
    end
    if state == JA_STATE_JA_BIAS or state == JA_STATE_ZH_BIAS or state == JA_STATE_NEUTRAL then
        return state
    end
    return JA_STATE_NEUTRAL
end

-- ===============================================
-- 模糊输入由提交状态决定候选分组
-- ===============================================
local function prefer_zh_first(ja_state)
    return ja_state ~= JA_STATE_JA_BIAS
end

-- ===============================================
-- Filter 生命周期
-- ===============================================
local function append_prefix(prefixes, prefix, force_identity)
    if prefix and prefix ~= "" then
        prefixes[#prefixes + 1] = { value = prefix, force_identity = force_identity }
    end
end

local function init(env)
    env.default_position = 2
    env.japanese_prefixes = {}
    env.cache = {
        input = "",
        kana_preview = "",
    }
    env.candidate_scan_limit = math.max(1, tonumber(env.engine.schema.page_size) or 10)

    local config = env.engine.schema.config
    if config then
        local pos = config:get_int("moran_ja/default_position")
        if pos and pos > 0 then
            env.default_position = pos
        end
        append_prefix(env.japanese_prefixes, config:get_string("kagiroi/prefix"), false)
        append_prefix(env.japanese_prefixes, config:get_string("japanese_only/prefix"), true)
    end
end

local function fini(env)
    env.cache = nil
end

-- ===============================================
-- 候选包装与流式排序
-- ===============================================
local function append_preview(comment, preview)
    local original = comment or ""
    if original == "" then
        return "[" .. preview .. "]"
    end
    return original .. " [" .. preview .. "]"
end

local function preview_candidate(candidate, kana_preview)
    local candidate_language = language.candidate_language(candidate)
    if candidate_language ~= "ja" then
        return candidate, candidate_language
    end

    local comment = candidate.comment or ""
    if kana_preview ~= "" and kana_preview ~= candidate.text then
        comment = append_preview(comment, kana_preview)
    end
    local shadow = ShadowCandidate(candidate, candidate.type or "jaroomaji", candidate.text, comment)
    shadow.preedit = candidate.preedit
    return shadow, "ja"
end

local function yield_buffer(buffer)
    for _, candidate in ipairs(buffer) do
        yield(candidate)
    end
end

local function filter_language(input, kana_preview, target_language)
    for candidate in input:iter() do
        local decorated, candidate_language = preview_candidate(candidate, kana_preview)
        if candidate_language == target_language then
            yield(decorated)
        end
    end
end

local function filter_explicit_japanese(input, kana_preview)
    for candidate in input:iter() do
        local decorated, candidate_language = preview_candidate(candidate, kana_preview)
        if candidate_language == "ja" then
            yield(decorated)
        else
            local shadow = ShadowCandidate(candidate, "moran_ja", candidate.text, candidate.comment or "")
            shadow.preedit = candidate.preedit
            shadow.quality = candidate.quality
            yield(shadow)
        end
    end
end

local function matched_prefix(input, prefixes)
    local matched
    for _, entry in ipairs(prefixes) do
        if (not matched or #entry.value > #matched.value)
           and string_sub(input, 1, #entry.value) == entry.value then
            matched = entry
        end
    end
    return matched
end

-- 两个拉丁字母仍处于中日短码重叠区：保留中文首选，
-- 将假名作为第 2 个候选，便于继续输入或直接选字。
local function is_two_letter_input(input)
    return string_match(input, "^[A-Za-z][A-Za-z]$") ~= nil
end

local function candidate_stream(input, kana_preview, scan_limit)
    local next_source_candidate, source_state = input:iter()
    local function source()
        return next_source_candidate(source_state)
    end
    local buffered_candidates = {}
    local buffered_languages = {}
    local has_chinese = false
    local has_japanese = false
    local exhausted = false
    local limit = math.max(1, tonumber(scan_limit) or 10)

    for _ = 1, limit do
        local candidate = source()
        if not candidate then
            exhausted = true
            break
        end
        local decorated, candidate_language = preview_candidate(candidate, kana_preview)
        buffered_candidates[#buffered_candidates + 1] = decorated
        buffered_languages[#buffered_languages + 1] = candidate_language or "neutral"
        has_chinese = has_chinese or candidate_language == "zh"
        has_japanese = has_japanese or candidate_language == "ja"
    end

    local index = 0
    local function next_buffered()
        index = index + 1
        if index <= #buffered_candidates then
            return buffered_candidates[index], buffered_languages[index]
        end
        return nil
    end

    local function next_remaining()
        if exhausted then
            return nil
        end
        local candidate = source()
        if not candidate then
            exhausted = true
            return nil
        end
        return preview_candidate(candidate, kana_preview)
    end

    return next_buffered, next_remaining, has_chinese, has_japanese
end

local function yield_stream(next_candidate)
    while true do
        local candidate = next_candidate()
        if not candidate then
            return
        end
        yield(candidate)
    end
end

local function filter_ja_first(next_candidate)
    local pending_chinese = {}
    local pending_neutral = {}

    while true do
        local decorated, candidate_language = next_candidate()
        if not decorated then
            break
        end
        if candidate_language == "ja" then
            yield(decorated)
        elseif candidate_language == "zh" then
            pending_chinese[#pending_chinese + 1] = decorated
        else
            pending_neutral[#pending_neutral + 1] = decorated
        end
    end

    yield_buffer(pending_chinese)
    yield_buffer(pending_neutral)
end

local function filter_at_position(next_candidate, default_position)
    local chinese_before_insert = math.max(0, default_position - 1)
    local pending_japanese = {}
    local pending_chinese = {}
    local pending_neutral = {}
    local chinese_count = 0
    local inserted = false

    while true do
        local decorated, candidate_language = next_candidate()
        if not decorated then
            break
        end
        if candidate_language == "ja" then
            if inserted then
                pending_japanese[#pending_japanese + 1] = decorated
            elseif chinese_count >= chinese_before_insert then
                yield(decorated)
                inserted = true
                yield_buffer(pending_chinese)
                pending_chinese = {}
            else
                pending_japanese[#pending_japanese + 1] = decorated
            end
        elseif candidate_language == "zh" then
            if inserted then
                yield(decorated)
            elseif chinese_count < chinese_before_insert then
                yield(decorated)
                chinese_count = chinese_count + 1
                if chinese_count >= chinese_before_insert and pending_japanese[1] then
                    yield(table.remove(pending_japanese, 1))
                    inserted = true
                end
            else
                pending_chinese[#pending_chinese + 1] = decorated
            end
        else
            pending_neutral[#pending_neutral + 1] = decorated
        end
    end

    yield_buffer(pending_chinese)
    yield_buffer(pending_japanese)
    yield_buffer(pending_neutral)
end

-- ===============================================
-- 核心过滤逻辑
-- ===============================================
local function filter(input, env)
    local context = env.engine.context
    local input_text = context.input or ""

    local prefix_entry = matched_prefix(input_text, env.japanese_prefixes or {})
    local prefix = prefix_entry and prefix_entry.value or ""
    local language_input = prefix == "" and input_text or string_sub(input_text, #prefix + 1)
    update_cache(env.cache, language_input)
    if prefix_entry then
        if prefix_entry.force_identity then
            filter_explicit_japanese(input, env.cache.kana_preview)
        else
            filter_language(input, env.cache.kana_preview, "ja")
        end
        return
    end
    local next_buffered, next_remaining, has_chinese, has_japanese = candidate_stream(
        input,
        env.cache.kana_preview,
        env.candidate_scan_limit
    )
    if has_chinese and has_japanese then
        local ja_state = resolve_ja_state(context)
        if is_two_letter_input(language_input) or prefer_zh_first(ja_state) then
            filter_at_position(next_buffered, env.default_position or 2)
        else
            filter_ja_first(next_buffered)
        end
    else
        yield_stream(next_buffered)
    end
    yield_stream(next_remaining)
end

return { init = init, func = filter, fini = fini }

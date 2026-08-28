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
local utf8_codes = utf8.codes
local string_sub = string.sub
local string_lower = string.lower
local string_upper = string.upper
local string_match = string.match
local table_concat = table.concat
local ipairs = ipairs

-- ===============================================
-- 罗马字 → 假名 映射表
-- ===============================================
local romaji_to_kana = {
    ["a"] = "あ",
    ["i"] = "い",
    ["u"] = "う",
    ["e"] = "え",
    ["o"] = "お",
    ["ka"] = "か",
    ["ki"] = "き",
    ["ku"] = "く",
    ["ke"] = "け",
    ["ko"] = "こ",
    ["sa"] = "さ",
    ["shi"] = "し",
    ["si"] = "し",
    ["su"] = "す",
    ["se"] = "せ",
    ["so"] = "そ",
    ["ta"] = "た",
    ["chi"] = "ち",
    ["ti"] = "ち",
    ["tsu"] = "つ",
    ["tu"] = "つ",
    ["te"] = "て",
    ["to"] = "と",
    ["na"] = "な",
    ["ni"] = "に",
    ["nu"] = "ぬ",
    ["ne"] = "ね",
    ["no"] = "の",
    ["ha"] = "は",
    ["hi"] = "ひ",
    ["fu"] = "ふ",
    ["hu"] = "ふ",
    ["he"] = "へ",
    ["ho"] = "ほ",
    ["ma"] = "ま",
    ["mi"] = "み",
    ["mu"] = "む",
    ["me"] = "め",
    ["mo"] = "も",
    ["ya"] = "や",
    ["yu"] = "ゆ",
    ["yo"] = "よ",
    ["ra"] = "ら",
    ["ri"] = "り",
    ["ru"] = "る",
    ["re"] = "れ",
    ["ro"] = "ろ",
    ["wa"] = "わ",
    ["wo"] = "を",
    ["n"] = "ん",
    ["nn"] = "ん",
    ["ga"] = "が",
    ["gi"] = "ぎ",
    ["gu"] = "ぐ",
    ["ge"] = "げ",
    ["go"] = "ご",
    ["za"] = "ざ",
    ["ji"] = "じ",
    ["zi"] = "じ",
    ["zu"] = "ず",
    ["ze"] = "ぜ",
    ["zo"] = "ぞ",
    ["da"] = "だ",
    ["di"] = "ぢ",
    ["du"] = "づ",
    ["de"] = "で",
    ["do"] = "ど",
    ["ba"] = "ば",
    ["bi"] = "び",
    ["bu"] = "ぶ",
    ["be"] = "べ",
    ["bo"] = "ぼ",
    ["pa"] = "ぱ",
    ["pi"] = "ぴ",
    ["pu"] = "ぷ",
    ["pe"] = "ぺ",
    ["po"] = "ぽ",
    ["kya"] = "きゃ",
    ["kyu"] = "きゅ",
    ["kyo"] = "きょ",
    ["sha"] = "しゃ",
    ["shu"] = "しゅ",
    ["sho"] = "しょ",
    ["sya"] = "しゃ",
    ["syu"] = "しゅ",
    ["syo"] = "しょ",
    ["cha"] = "ちゃ",
    ["chu"] = "ちゅ",
    ["cho"] = "ちょ",
    ["tya"] = "ちゃ",
    ["tyu"] = "ちゅ",
    ["tyo"] = "ちょ",
    ["nya"] = "にゃ",
    ["nyu"] = "にゅ",
    ["nyo"] = "にょ",
    ["hya"] = "ひゃ",
    ["hyu"] = "ひゅ",
    ["hyo"] = "ひょ",
    ["mya"] = "みゃ",
    ["myu"] = "みゅ",
    ["myo"] = "みょ",
    ["rya"] = "りゃ",
    ["ryu"] = "りゅ",
    ["ryo"] = "りょ",
    ["gya"] = "ぎゃ",
    ["gyu"] = "ぎゅ",
    ["gyo"] = "ぎょ",
    ["ja"] = "じゃ",
    ["ju"] = "じゅ",
    ["jo"] = "じょ",
    ["jya"] = "じゃ",
    ["jyu"] = "じゅ",
    ["jyo"] = "じょ",
    ["zya"] = "じゃ",
    ["zyu"] = "じゅ",
    ["zyo"] = "じょ",
    ["bya"] = "びゃ",
    ["byu"] = "びゅ",
    ["byo"] = "びょ",
    ["pya"] = "ぴゃ",
    ["pyu"] = "ぴゅ",
    ["pyo"] = "ぴょ",
    ["xtu"] = "っ",
    ["xtsu"] = "っ",
    ["ltu"] = "っ",
    ["-"] = "ー",
    ["fa"] = "ふぁ",
    ["fi"] = "ふぃ",
    ["fe"] = "ふぇ",
    ["fo"] = "ふぉ",
}

-- ===============================================
-- 候选语言判定
-- ===============================================
local function is_japanese_candidate(candidate)
    return language.candidate_language(candidate) == "ja"
end

-- ===============================================
-- 罗马字 → 假名预览（O(n) 字符串拼接）
-- ===============================================
local SOKUON_PATTERN = "[kstcgzjdbp]"

local function hiragana_to_katakana(text)
    local parts = {}
    for _, codepoint in utf8_codes(text) do
        if codepoint >= 0x3041 and codepoint <= 0x3096 then
            codepoint = codepoint + 0x60
        end
        parts[#parts + 1] = utf8.char(codepoint)
    end
    return table_concat(parts)
end

local function romaji_to_kana_preview(input)
    if not input or #input == 0 then return "" end

    local parts = {}
    local n = 0
    local i = 1
    local len = #input
    local lower = string_lower(input)

    while i <= len do
        local matched = false
        for l = 4, 1, -1 do
            if i + l - 1 <= len then
                local substr = string_sub(lower, i, i + l - 1)
                local kana = romaji_to_kana[substr]
                if kana then
                    n = n + 1
                    parts[n] = kana
                    i = i + l
                    matched = true
                    break
                end
            end
        end
        if not matched then
            local char = string_sub(lower, i, i)
            local next_char = string_sub(lower, i + 1, i + 1)
            -- 促音检测：连续相同辅音
            if i < len and string_match(char, SOKUON_PATTERN) and next_char == char then
                n = n + 1
                parts[n] = "っ"
            else
                n = n + 1
                parts[n] = char
            end
            i = i + 1
        end
    end

    local kana = table_concat(parts)
    local has_uppercase = input ~= string_lower(input)
    if has_uppercase and input == string_upper(input) then
        kana = hiragana_to_katakana(kana)
    end
    return kana
end

-- ===============================================
-- 更新缓存
-- ===============================================
local function update_cache(cache, input)
    if input ~= cache.input then
        cache.intent = language.classify_input(input)
        cache.kana_preview = romaji_to_kana_preview(input)
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
local function init(env)
    env.default_position = 2
    env.kagiroi_prefix = ""
    env.cache = {
        input = "",
        intent = "ambiguous",
        kana_preview = "",
    }

    local config = env.engine.schema.config
    if config then
        local pos = config:get_int("moran_ja/default_position")
        if pos and pos > 0 then
            env.default_position = pos
        end
        env.kagiroi_prefix = config:get_string("kagiroi/prefix") or ""
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
    if not is_japanese_candidate(candidate) then
        return candidate, false
    end

    local comment = candidate.comment or ""
    if kana_preview ~= "" and kana_preview ~= candidate.text then
        comment = append_preview(comment, kana_preview)
    end
    local shadow = ShadowCandidate(candidate, candidate.type or "jaroomaji", candidate.text, comment)
    shadow.preedit = candidate.preedit
    return shadow, true
end

local function yield_buffer(buffer)
    for _, candidate in ipairs(buffer) do
        yield(candidate)
    end
end

local function filter_language(input, kana_preview, target_language)
    for candidate in input:iter() do
        local decorated, is_japanese = preview_candidate(candidate, kana_preview)
        local candidate_language = is_japanese and "ja" or "zh"
        if candidate_language == target_language then
            yield(decorated)
        end
    end
end

local function filter_ja_first(input, kana_preview)
    local pending_japanese = {}
    local pending_chinese = {}
    local yielded_head = false

    for candidate in input:iter() do
        local decorated, is_japanese = preview_candidate(candidate, kana_preview)
        if is_japanese then
            if yielded_head then
                yield(decorated)
            else
                pending_japanese[#pending_japanese + 1] = decorated
            end
        elseif not yielded_head then
            yield(decorated)
            yielded_head = true
            yield_buffer(pending_japanese)
            pending_japanese = {}
        else
            pending_chinese[#pending_chinese + 1] = decorated
        end
    end

    yield_buffer(pending_japanese)
    yield_buffer(pending_chinese)
end

local function filter_at_position(input, kana_preview, default_position)
    local chinese_before_insert = math.max(0, default_position - 1)
    local pending_japanese = {}
    local pending_chinese = {}
    local chinese_count = 0
    local inserted = false

    for candidate in input:iter() do
        local decorated, is_japanese = preview_candidate(candidate, kana_preview)
        if inserted and is_japanese then
            pending_japanese[#pending_japanese + 1] = decorated
        elseif inserted then
            yield(decorated)
        elseif is_japanese and chinese_count >= chinese_before_insert then
            yield(decorated)
            inserted = true
            yield_buffer(pending_chinese)
            pending_chinese = {}
        elseif is_japanese then
            pending_japanese[#pending_japanese + 1] = decorated
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
    end

    yield_buffer(pending_chinese)
    yield_buffer(pending_japanese)
end

-- ===============================================
-- 核心过滤逻辑
-- ===============================================
local function filter(input, env)
    local context = env.engine.context
    local input_text = context.input or ""
    if #input_text < 2 then
        for candidate in input:iter() do
            yield(candidate)
        end
        return
    end

    update_cache(env.cache, input_text)
    local intent = env.cache.intent
    local prefix = env.kagiroi_prefix or ""
    if prefix ~= "" and string_sub(input_text, 1, #prefix) == prefix then
        intent = "ja"
    end
    if intent == "ja" or intent == "zh" then
        filter_language(input, env.cache.kana_preview, intent)
        return
    end

    local ja_state = resolve_ja_state(context)
    local use_default_position = prefer_zh_first(ja_state)
    if use_default_position then
        filter_at_position(input, env.cache.kana_preview, env.default_position or 2)
        return
    end
    filter_ja_first(input, env.cache.kana_preview)
end

return { init = init, func = filter, fini = fini }

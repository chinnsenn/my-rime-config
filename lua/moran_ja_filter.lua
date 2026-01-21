-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (Candidate, yield, env)
-- [OUTPUT]: 对外提供 moran_ja_filter (lua_filter)
-- [POS]:    lua/ 目录的日语混合过滤器，被 moran_ja_hybrid 方案调用
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

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
-- 缓存结构：避免相同输入重复计算
-- ===============================================
local cache = {
    input = "",
    is_romaji = false,
    kana_preview = "",
}

-- ===============================================
-- 日语模式检测：合并 pattern 减少循环
-- ===============================================
local JA_PATTERN = "shi|chi|tsu|fu|[kstnhmyrwgzjdbp]y[auo]|nn|xtsu|xtu|ltu"

-- ===============================================
-- 日语候选判定：优先检测来源，其次检测假名
-- ===============================================
local function has_kana(text)
    if not text or #text == 0 then return false end
    for _, codepoint in utf8.codes(text) do
        -- 平假名 (U+3040-U+309F) 或 片假名 (U+30A0-U+30FF)
        if (codepoint >= 0x3040 and codepoint <= 0x30FF) then
            return true
        end
    end
    return false
end

local function is_from_jaroomaji(cand)
    if cand.type == "jaroomaji" then
        return true
    end
    local genuine = cand:get_genuine()
    return genuine and genuine.type == "jaroomaji"
end

local function is_japanese_candidate(cand)
    -- 1. 来源检测：来自 jaroomaji 翻译器
    if is_from_jaroomaji(cand) then
        return true
    end
    -- 2. 内容检测：包含假名字符
    return has_kana(cand.text)
end

local function is_romaji_pattern(input)
    if not input or #input < 3 then return false end
    if input == cache.input then return cache.is_romaji end

    local lower = input:lower()

    for pattern in JA_PATTERN:gmatch("[^|]+") do
        if lower:find(pattern, 1, true) then
            return true
        end
    end

    local cv_count = 0
    for _ in lower:gmatch("[kstcnhmyrwgzjdbp][aiueo]") do
        cv_count = cv_count + 1
    end

    return cv_count >= 3
end

-- ===============================================
-- 罗马字 → 假名预览（带缓存）
-- ===============================================
local function romaji_to_kana_preview(input)
    if not input or #input == 0 then return "" end
    if input == cache.input then return cache.kana_preview end

    local result = ""
    local i = 1
    local len = #input
    local lower = input:lower()

    while i <= len do
        local matched = false
        for l = 4, 1, -1 do
            if i + l - 1 <= len then
                local substr = lower:sub(i, i + l - 1)
                if romaji_to_kana[substr] then
                    result = result .. romaji_to_kana[substr]
                    i = i + l
                    matched = true
                    break
                end
            end
        end
        if not matched then
            local char = lower:sub(i, i)
            local next_char = lower:sub(i + 1, i + 1)
            if i < len and char:match("[kstcgzjdbp]") and next_char == char then
                result = result .. "っ"
            else
                result = result .. char
            end
            i = i + 1
        end
    end

    return result
end

-- ===============================================
-- 更新缓存
-- ===============================================
local function update_cache(input)
    if input ~= cache.input then
        cache.input = input
        cache.is_romaji = is_romaji_pattern(input)
        cache.kana_preview = romaji_to_kana_preview(input)
    end
end

-- ===============================================
-- Filter 生命周期
-- ===============================================
local function init(env)
    env.default_position = 2
    env.ja_only_suffix = "//"
    local config = env.engine.schema.config
    if config then
        local pos = config:get_int("moran_ja/default_position")
        if pos and pos > 0 then
            env.default_position = pos
        end
        local suffix = config:get_string("moran_ja/ja_only_suffix")
        if suffix and #suffix > 0 then
            env.ja_only_suffix = suffix
        end
    end
end

local function fini(env)
    cache.input = ""
    cache.is_romaji = false
    cache.kana_preview = ""
end

-- ===============================================
-- 核心过滤逻辑
-- ===============================================
local function filter(input, env)
    local context = env.engine.context
    local input_text = context.input or ""

    if #input_text < 2 then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    local ja_only_suffix = env.ja_only_suffix
    local ja_only_mode = false
    local real_input = input_text

    if #input_text > #ja_only_suffix and input_text:sub(- #ja_only_suffix) == ja_only_suffix then
        ja_only_mode = true
        real_input = input_text:sub(1, - #ja_only_suffix - 1)
    end

    update_cache(real_input)

    local is_romaji = cache.is_romaji
    local kana_preview = cache.kana_preview

    local chinese_candidates = {}
    local japanese_candidates = {}
    local has_japanese = false

    for cand in input:iter() do
        local is_ja = is_japanese_candidate(cand)

        if is_ja then
            has_japanese = true
            local new_comment = cand.comment or ""
            if kana_preview ~= "" and kana_preview ~= cand.text then
                new_comment = "[" .. kana_preview .. "]"
            end

            local new_cand = Candidate(cand.type, cand.start, cand._end, cand.text, new_comment)
            new_cand.quality = cand.quality
            table.insert(japanese_candidates, new_cand)
        else
            table.insert(chinese_candidates, cand)
        end
    end

    if ja_only_mode then
        local suffix_len = #ja_only_suffix
        for _, cand in ipairs(japanese_candidates) do
            local extended_cand = Candidate(cand.type, cand.start, cand._end + suffix_len, cand.text, cand.comment)
            extended_cand.quality = cand.quality
            yield(extended_cand)
        end
        return
    end

    if not has_japanese then
        for _, cand in ipairs(chinese_candidates) do
            yield(cand)
        end
        return
    end

    if is_romaji then
        if chinese_candidates[1] then
            yield(chinese_candidates[1])
        end

        for _, cand in ipairs(japanese_candidates) do
            yield(cand)
        end

        for i = 2, #chinese_candidates do
            yield(chinese_candidates[i])
        end
    else
        local ja_idx = 1
        local cn_idx = 1
        local output_idx = 1
        local default_pos = env.default_position or 2

        while cn_idx <= #chinese_candidates or ja_idx <= #japanese_candidates do
            if output_idx == default_pos and ja_idx <= #japanese_candidates then
                yield(japanese_candidates[ja_idx])
                ja_idx = ja_idx + 1
            elseif cn_idx <= #chinese_candidates then
                yield(chinese_candidates[cn_idx])
                cn_idx = cn_idx + 1
            elseif ja_idx <= #japanese_candidates then
                yield(japanese_candidates[ja_idx])
                ja_idx = ja_idx + 1
            end
            output_idx = output_idx + 1
        end
    end
end

return { init = init, func = filter, fini = fini }

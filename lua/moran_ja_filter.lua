-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (Candidate, yield, env)
-- [OUTPUT]: 对外提供 moran_ja_filter (lua_filter)
-- [POS]:    lua/ 目录的日语混合过滤器，被 moran_ja_hybrid 方案调用
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local romaji_to_kana = {
    ["a"] = "あ", ["i"] = "い", ["u"] = "う", ["e"] = "え", ["o"] = "お",
    ["ka"] = "か", ["ki"] = "き", ["ku"] = "く", ["ke"] = "け", ["ko"] = "こ",
    ["sa"] = "さ", ["shi"] = "し", ["si"] = "し", ["su"] = "す", ["se"] = "せ", ["so"] = "そ",
    ["ta"] = "た", ["chi"] = "ち", ["ti"] = "ち", ["tsu"] = "つ", ["tu"] = "つ", ["te"] = "て", ["to"] = "と",
    ["na"] = "な", ["ni"] = "に", ["nu"] = "ぬ", ["ne"] = "ね", ["no"] = "の",
    ["ha"] = "は", ["hi"] = "ひ", ["fu"] = "ふ", ["hu"] = "ふ", ["he"] = "へ", ["ho"] = "ほ",
    ["ma"] = "ま", ["mi"] = "み", ["mu"] = "む", ["me"] = "め", ["mo"] = "も",
    ["ya"] = "や", ["yu"] = "ゆ", ["yo"] = "よ",
    ["ra"] = "ら", ["ri"] = "り", ["ru"] = "る", ["re"] = "れ", ["ro"] = "ろ",
    ["wa"] = "わ", ["wo"] = "を", ["n"] = "ん", ["nn"] = "ん",
    ["ga"] = "が", ["gi"] = "ぎ", ["gu"] = "ぐ", ["ge"] = "げ", ["go"] = "ご",
    ["za"] = "ざ", ["ji"] = "じ", ["zi"] = "じ", ["zu"] = "ず", ["ze"] = "ぜ", ["zo"] = "ぞ",
    ["da"] = "だ", ["di"] = "ぢ", ["du"] = "づ", ["de"] = "で", ["do"] = "ど",
    ["ba"] = "ば", ["bi"] = "び", ["bu"] = "ぶ", ["be"] = "べ", ["bo"] = "ぼ",
    ["pa"] = "ぱ", ["pi"] = "ぴ", ["pu"] = "ぷ", ["pe"] = "ぺ", ["po"] = "ぽ",
    ["kya"] = "きゃ", ["kyu"] = "きゅ", ["kyo"] = "きょ",
    ["sha"] = "しゃ", ["shu"] = "しゅ", ["sho"] = "しょ",
    ["sya"] = "しゃ", ["syu"] = "しゅ", ["syo"] = "しょ",
    ["cha"] = "ちゃ", ["chu"] = "ちゅ", ["cho"] = "ちょ",
    ["tya"] = "ちゃ", ["tyu"] = "ちゅ", ["tyo"] = "ちょ",
    ["nya"] = "にゃ", ["nyu"] = "にゅ", ["nyo"] = "にょ",
    ["hya"] = "ひゃ", ["hyu"] = "ひゅ", ["hyo"] = "ひょ",
    ["mya"] = "みゃ", ["myu"] = "みゅ", ["myo"] = "みょ",
    ["rya"] = "りゃ", ["ryu"] = "りゅ", ["ryo"] = "りょ",
    ["gya"] = "ぎゃ", ["gyu"] = "ぎゅ", ["gyo"] = "ぎょ",
    ["ja"] = "じゃ", ["ju"] = "じゅ", ["jo"] = "じょ",
    ["jya"] = "じゃ", ["jyu"] = "じゅ", ["jyo"] = "じょ",
    ["zya"] = "じゃ", ["zyu"] = "じゅ", ["zyo"] = "じょ",
    ["bya"] = "びゃ", ["byu"] = "びゅ", ["byo"] = "びょ",
    ["pya"] = "ぴゃ", ["pyu"] = "ぴゅ", ["pyo"] = "ぴょ",
    ["xtu"] = "っ", ["xtsu"] = "っ", ["ltu"] = "っ",
    ["-"] = "ー",
    ["fa"] = "ふぁ", ["fi"] = "ふぃ", ["fe"] = "ふぇ", ["fo"] = "ふぉ",
}

local ja_patterns = {
    "shi", "chi", "tsu", "fu",
    "kya", "kyu", "kyo", "sha", "shu", "sho",
    "cha", "chu", "cho", "nya", "nyu", "nyo",
    "hya", "hyu", "hyo", "mya", "myu", "myo",
    "rya", "ryu", "ryo", "gya", "gyu", "gyo",
    "jya", "jyu", "jyo", "bya", "byu", "byo",
    "pya", "pyu", "pyo",
    "nn", "xtsu", "xtu",
}

local function is_japanese_text(text)
    if not text or #text == 0 then return false end
    for _, codepoint in utf8.codes(text) do
        if (codepoint >= 0x3040 and codepoint <= 0x30FF) then
            return true
        end
    end
    return false
end

local function romaji_to_kana_preview(input)
    if not input or #input == 0 then return "" end
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

local function is_romaji_pattern(input)
    if not input or #input < 3 then return false end
    local lower = input:lower()

    for _, p in ipairs(ja_patterns) do
        if lower:find(p, 1, true) then
            return true
        end
    end

    local cv_count = 0
    for _ in lower:gmatch("[kstcnhmyrwgzjdbp][aiueo]") do
        cv_count = cv_count + 1
    end

    return cv_count >= 3
end

local function init(env)
    env.default_position = 2
    local config = env.engine.schema.config
    if config then
        local pos = config:get_int("moran_ja/default_position")
        if pos and pos > 0 then
            env.default_position = pos
        end
    end
end

local function fini(env)
end

local function filter(input, env)
    local context = env.engine.context
    local input_text = context.input or ""
    local is_romaji = is_romaji_pattern(input_text)
    local kana_preview = romaji_to_kana_preview(input_text)

    local chinese_candidates = {}
    local japanese_candidates = {}

    for cand in input:iter() do
        local dominated_by_ja = is_japanese_text(cand.text)

        if dominated_by_ja then
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

-- ===================================================================
-- [INPUT]:  罗马字输入与 Rime Candidate
-- [OUTPUT]: 对外提供罗马字结构校验与候选语言识别
-- [POS]:    日语混输的统一语义模块；翻译器校验输入，过滤器与处理器识别候选来源
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local M = {}

local string_find = string.find
local string_lower = string.lower
local string_sub = string.sub
local utf8_codes = utf8.codes
local utf8_len = utf8.len

-- -------------------------------------------------------------------
-- 罗马字语法
-- canonical 来自 jaroomaji.kana_kigou；aliases 来自 jaroomaji speller algebra。
-- 单辅音派生只用于促音上下文，不进入普通音节集合。
-- -------------------------------------------------------------------

local CANONICAL_MORAE = [[
- a e i o u ba be bi bo bu da de di do du ga ge gi go gu ha he hi ho hu
ka ke ki ko ku ma me mi mo mu na ne ni nn no nu pa pe pi po pu ra re ri ro ru
sa se si so su ta te ti to tu va ve vi vo vu wa wo xa xe xi xo xu ya ye yo yu
za ze zi zo zu bya bye byi byo byu dha dhe dhi dho dhu dwa dwe dwi dwo dwu
dya dye dyi dyo dyu fwa fwe fwi fwo fwu fya fyo fyu gwa gwe gwi gwo gwu
gya gye gyi gyo gyu hya hye hyi hyo hyu kya kye kyi kyo kyu mya mye myi
myo myu nya nye nyi nyo nyu pya pye pyi pyo pyu qwa qwe qwi qwo qwu qya
qyo qyu rya rye ryi ryo ryu swa swe swi swo swu sya sye syi syo syu tha
the thi tho thu tsa tse tsi tso twa twe twi two twu tya tye tyi tyo tyu vya
vyo vyu wha whe whi who wye wyi xka xke xtu xwa xya xyo xyu zya zye zyi
zyo zyu
]]

local ALIAS_MORAE = [[
l n yi wu whu wi we xyi xye ca cu qu co qa kwa qi qyi qe qye qo ci shi ce
sha shu she sho ji ja jya jyi ju jyu je jye jo jyo chi tsu cha cya cyi chu
cyu che cye cho cyo xtsu ltu fu fa fi fyi fe fye fo vyi vye
]]

local morae = {}
local max_mora_length = 0

local function add_morae(source)
    for token in string.gmatch(source, "%S+") do
        morae[token] = true
        if #token > max_mora_length then
            max_mora_length = #token
        end
    end
end

add_morae(CANONICAL_MORAE)
add_morae(ALIAS_MORAE)

local SOKUON_PREFIXES = {
    k = { "k" },
    c = { "c", "ch" },
    q = { "q" },
    g = { "g" },
    s = { "s", "sh" },
    z = { "z" },
    j = { "j" },
    t = { "t", "ch", "ts" },
    d = { "d" },
    h = { "h" },
    f = { "f" },
    b = { "b" },
    v = { "v" },
    p = { "p" },
    m = { "m" },
    y = { "y" },
    r = { "r" },
    w = { "w" },
}

local function token_has_prefix(token, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string_sub(token, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function record_transition(states, next_index)
    states[next_index] = true
end

local function parse_segment(text)
    local text_length = #text
    local end_index = text_length + 1
    local states = { [1] = true }

    for index = 1, text_length do
        if states[index] then
            local remaining = text_length - index + 1
            local longest = math.min(max_mora_length, remaining)
            for length = longest, 1, -1 do
                local token = string_sub(text, index, index + length - 1)
                if morae[token] then
                    record_transition(states, index + length)
                end
            end

            local consonant = string_sub(text, index, index)
            local prefixes = SOKUON_PREFIXES[consonant]
            if prefixes then
                local next_index = index + 1
                local next_remaining = text_length - next_index + 1
                local next_longest = math.min(max_mora_length, next_remaining)
                for length = next_longest, 1, -1 do
                    local token = string_sub(text, next_index, next_index + length - 1)
                    if morae[token] and token_has_prefix(token, prefixes) then
                        record_transition(states, next_index + length)
                    end
                end
            end
        end
    end

    return states[end_index] == true
end

local function parse_input(input)
    if type(input) ~= "string" then
        return false
    end

    local normalized = string_lower(input)
    local has_segment = false
    for segment in string.gmatch(normalized, "[^%s']+") do
        has_segment = true
        if not parse_segment(segment) then
            return false
        end
    end
    return has_segment
end

function M.is_valid_romaji(input)
    return parse_input(input)
end


-- -------------------------------------------------------------------
-- 候选语言识别
-- -------------------------------------------------------------------

local JAPANESE_CANDIDATE_TYPES = {
    jaroomaji = true,
    moran_ja = true,
    kagiroi = true,
}

local CHINESE_CANDIDATE_TYPES = {
    table = true,
    phrase = true,
    user_phrase = true,
    sentence = true,
    fixed = true,
    pinned = true,
    simplified = true,
}

local function safe_candidate_type(candidate)
    if not candidate then
        return nil
    end
    local ok, candidate_type = pcall(function()
        return candidate.type
    end)
    return ok and candidate_type or nil
end

local function safe_genuine(candidate)
    if not candidate then
        return nil
    end
    local ok, genuine = pcall(function()
        return candidate:get_genuine()
    end)
    return ok and genuine or nil
end

local function has_kana(text)
    if type(text) ~= "string" or text == "" or utf8_len(text) == nil then
        return false
    end
    for _, codepoint in utf8_codes(text) do
        if codepoint >= 0x3040 and codepoint <= 0x30FF then
            return true
        end
    end
    return false
end

function M.candidate_language(candidate)
    local candidate_type = safe_candidate_type(candidate)
    local genuine_type = safe_candidate_type(safe_genuine(candidate))
    if JAPANESE_CANDIDATE_TYPES[candidate_type]
       or JAPANESE_CANDIDATE_TYPES[genuine_type]
       or has_kana(candidate and candidate.text) then
        return "ja"
    end
    if CHINESE_CANDIDATE_TYPES[candidate_type]
       or CHINESE_CANDIDATE_TYPES[genuine_type] then
        return "zh"
    end
    return nil
end

return M

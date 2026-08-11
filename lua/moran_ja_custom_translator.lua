-- ===================================================================
-- [INPUT]:  依赖 Rime Component API 与 custom_phrase_ja 表翻译器
-- [OUTPUT]: 对外提供 moran_ja_custom_translator，将候选标记为稳定 moran_ja 类型
-- [POS]:    lua/ 的日语自定义短语边界适配器，为纯汉字候选保留日语来源身份
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local JAPANESE_CANDIDATE_TYPE = "moran_ja"

local function init(env)
    env.custom_ja_translator = Component.Translator(env.engine, "", "table_translator@custom_phrase_ja")
end

local function fini(env)
    env.custom_ja_translator = nil
end

local function func(input, segment, env)
    local translation = env.custom_ja_translator:query(input, segment)
    if not translation then
        return
    end

    for candidate in translation:iter() do
        local wrapped = ShadowCandidate(candidate, JAPANESE_CANDIDATE_TYPE, candidate.text, candidate.comment, true)
        wrapped.quality = candidate.quality
        yield(wrapped)
    end
end

return { init = init, func = func, fini = fini }

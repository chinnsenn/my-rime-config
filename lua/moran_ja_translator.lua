-- ===================================================================
-- [INPUT]:  依赖 Rime Component API, jaroomaji 词典配置
-- [OUTPUT]: 对外提供带罗马字结构校验的 moran_ja_translator
-- [POS]:    lua/ 目录的日语翻译器包装，替代 script_translator@jaroomaji_translator
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local language = require("moran_ja_language")

local function init(env)
    env.translator = Component.Translator(env.engine, "", "script_translator@jaroomaji_translator")
end

local function fini(env)
    env.translator = nil
end

local function func(input, seg, env)
    if not language.is_valid_romaji(input) then
        return
    end
    local translation = env.translator:query(input, seg)
    if translation == nil then
        return
    end

    for cand in translation:iter() do
        local wrapped = ShadowCandidate(cand, "jaroomaji", cand.text, cand.comment, true)
        wrapped.quality = cand.quality
        -- wrapped.preedit = cand.preedit  -- 继承假名 preedit
        yield(wrapped)
    end
end

return { init = init, func = func, fini = fini }

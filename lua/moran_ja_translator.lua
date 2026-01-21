-- ===================================================================
-- [INPUT]:  依赖 Rime Component API, jaroomaji 词典配置
-- [OUTPUT]: 对外提供 moran_ja_translator (lua_translator)
-- [POS]:    lua/ 目录的日语翻译器包装，替代 script_translator@jaroomaji_translator
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local function init(env)
    env.translator = Component.Translator(env.engine, "", "script_translator@jaroomaji_translator")
end

local function fini(env)
    env.translator = nil
end

local function func(input, seg, env)
    local translation = env.translator:query(input, seg)
    if translation == nil then
        return
    end

    for cand in translation:iter() do
        local wrapped = ShadowCandidate(cand, "jaroomaji", cand.text, cand.comment, true)
        wrapped.quality = cand.quality
        yield(wrapped)
    end
end

return { init = init, func = func, fini = fini }

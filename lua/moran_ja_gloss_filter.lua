-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API、moran 工具模块与 zh_ja_wiki.txt
-- [OUTPUT]: 对中文候选追加离线日语释义 comment
-- [POS]:    lua/ 目录的中日释义过滤器，在文字转换完成后、去重前运行
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local moran = require("moran")

local Module = {}
local dictionaries = {}
local DEFAULT_DICTIONARY = "lua/zh_ja_wiki.txt"
local COMMENT_SEPARATOR = " ¦ "
local COMMENT_PREFIX = "〔日："
local COMMENT_SUFFIX = "〕"

local japanese_types = {
    jaroomaji = true,
    kagiroi = true,
    moran_ja = true,
}

local function open_dictionary(rel_path)
    local pathsep = (package.config or "/"):sub(1, 1)
    local normalized = rel_path:gsub("[/\\]", pathsep)
    return moran.open_rime_file(normalized, pathsep)
end

local function load_dictionary(rel_path)
    if dictionaries[rel_path] then
        return dictionaries[rel_path]
    end

    local entries = {}
    local file = open_dictionary(rel_path)
    if file then
        for line in file:lines() do
            if line:sub(1, 1) ~= "#" then
                local source, target = line:match("^([^\t]+)\t(.+)$")
                if source and target then
                    entries[source] = target
                end
            end
        end
        file:close()
    end

    dictionaries[rel_path] = entries
    return entries
end

local function is_japanese_candidate(candidate)
    if japanese_types[candidate.type] then
        return true
    end

    local genuine = candidate:get_genuine()
    return genuine and japanese_types[genuine.type] or false
end

local function lookup_gloss(candidate, entries)
    local gloss = entries[candidate.text]
    if gloss then
        return gloss
    end

    local genuine = candidate:get_genuine()
    if genuine and genuine.text ~= candidate.text then
        return entries[genuine.text]
    end
    return nil
end

local function append_gloss(comment, gloss)
    local annotation = COMMENT_PREFIX .. gloss .. COMMENT_SUFFIX
    if comment == nil or comment == "" then
        return annotation
    end
    if comment:find(annotation, 1, true) then
        return comment
    end
    return comment .. COMMENT_SEPARATOR .. annotation
end

function Module.init(env)
    local config = env.engine.schema.config
    local dictionary = config and config:get_string("moran_ja_gloss/dictionary")
    env.gloss_entries = load_dictionary(dictionary or DEFAULT_DICTIONARY)
end

function Module.fini(env)
    env.gloss_entries = nil
end

function Module.func(input, env)
    local enabled = env.engine.context:get_option("ja_gloss")
    for candidate in input:iter() do
        local text = candidate.text or ""
        if enabled and text ~= "" and not is_japanese_candidate(candidate)
           and moran.str_is_chinese(text) then
            local gloss = lookup_gloss(candidate, env.gloss_entries)
            if gloss then
                local comment = append_gloss(candidate.comment, gloss)
                yield(ShadowCandidate(candidate, candidate.type, candidate.text, comment))
                goto continue
            end
        end
        yield(candidate)
        ::continue::
    end
end

return Module

-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API、moran 工具模块与有序中日 TSV 词库
-- [OUTPUT]: 按配置优先级合并词库，并为中文候选追加离线日语释义 comment
-- [POS]:    lua/ 目录的多源中日释义过滤器，在文字转换完成后、去重前运行
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local moran = require("moran")
local language = require("moran_ja_language")

local Module = {}
local dictionaries = {}
local merged_dictionaries = {}
local DEFAULT_DICTIONARIES = {
    "lua/zh_ja_custom.txt",
    "lua/zh_ja_learner.txt",
    "lua/zh_ja_wiki.txt",
}
local COMMENT_SEPARATOR = " ¦ "
local COMMENT_PREFIX = "〔"
local COMMENT_SUFFIX = "〕"

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

local function config_value_string(value)
    if not value then
        return nil
    end
    if value.value then
        return value.value
    end
    if value.get_string then
        return value:get_string()
    end
    return nil
end

local function configured_dictionaries(config)
    local list = config and config:get_list("moran_ja_gloss/dictionaries")
    if list and list.size > 0 then
        local paths = {}
        for index = 0, list.size - 1 do
            local path = config_value_string(list:get_value_at(index))
            if path and path ~= "" then
                paths[#paths + 1] = path
            end
        end
        if paths[1] then
            return paths
        end
    end

    local legacy = config and config:get_string("moran_ja_gloss/dictionary")
    if legacy and legacy ~= "" then
        return { legacy }
    end
    return DEFAULT_DICTIONARIES
end

local function merge_dictionary_entries(paths)
    local cache_key = table.concat(paths, "\0")
    if merged_dictionaries[cache_key] then
        return merged_dictionaries[cache_key]
    end

    local entries = {}
    for _, path in ipairs(paths) do
        for source, target in pairs(load_dictionary(path)) do
            if entries[source] == nil then
                entries[source] = target
            end
        end
    end
    merged_dictionaries[cache_key] = entries
    return entries
end

local function is_japanese_candidate(candidate)
    return language.candidate_language(candidate) == "ja"
end

local function safe_genuine_text(candidate)
    local ok, genuine = pcall(function()
        return candidate:get_genuine()
    end)
    if not ok or not genuine then
        return nil
    end

    local text_ok, text = pcall(function()
        return genuine.text
    end)
    if not text_ok or type(text) ~= "string" then
        return nil
    end
    return text
end

local function lookup_gloss(candidate, entries)
    local candidate_text = candidate.text
    local gloss = entries[candidate_text]
    if gloss then
        return gloss
    end

    local genuine_text = safe_genuine_text(candidate)
    if genuine_text and genuine_text ~= candidate_text then
        return entries[genuine_text]
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
    env.gloss_entries = merge_dictionary_entries(configured_dictionaries(config))
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

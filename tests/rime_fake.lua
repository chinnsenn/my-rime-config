-- ===================================================================
-- [INPUT]:  依赖 Lua 标准库，读取受测 schema 文件
-- [OUTPUT]: 对外提供 Rime Context/Candidate/Translation fake 与 xform 执行器
-- [POS]:    tests/ 的系统边界适配层，使生产模块可经公开接口在 Lua 5.5 运行
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local M = {}

local function fail(message, level)
    error(message, (level or 1) + 1)
end

function M.equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s\nexpected: %s\nactual:   %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

function M.truthy(value, message)
    if not value then
        fail(message or "expected a truthy value", 2)
    end
end

function M.contains(text, fragment, message)
    if not string.find(text or "", fragment, 1, true) then
        fail(string.format("%s\nexpected fragment: %s\nactual text:       %s", message or "text lacks fragment", fragment, tostring(text)), 2)
    end
end

function M.not_contains(text, fragment, message)
    if string.find(text or "", fragment, 1, true) then
        fail(string.format("%s\nunexpected fragment: %s\nactual text:         %s", message or "text contains fragment", fragment, tostring(text)), 2)
    end
end

function M.sequence_text(candidates)
    local values = {}
    for i, candidate in ipairs(candidates) do
        values[i] = candidate.text
    end
    return table.concat(values, "|")
end

local function new_notifier()
    local notifier = { callbacks = {} }

    function notifier:connect(callback)
        self.callbacks[#self.callbacks + 1] = callback
        local connected = true
        return {
            disconnect = function()
                connected = false
            end,
            is_connected = function()
                return connected
            end,
        }
    end

    function notifier:emit(context)
        for _, callback in ipairs(self.callbacks) do
            callback(context)
        end
    end

    return notifier
end

function M.candidate(candidate_type, text, comment, genuine)
    local candidate = {
        type = candidate_type,
        text = text,
        comment = comment or "",
        preedit = "",
        quality = 0,
    }

    function candidate:get_genuine()
        return genuine or self
    end

    return candidate
end

function M.shadow_candidate(candidate_type, text, comment, genuine_type)
    local genuine = M.candidate(genuine_type, text, comment)
    return M.candidate(candidate_type, text, comment, genuine)
end

function M.environment(config_values)
    local properties = {}
    local notifier = new_notifier()
    local context = {
        input = "",
        commit_notifier = notifier,
        commit_text = "",
        selected_candidate = nil,
    }

    function context:set_property(key, value)
        properties[key] = value
    end

    function context:get_property(key)
        return properties[key]
    end

    function context:set_option(key, value)
        properties["option:" .. key] = value
    end

    function context:get_option(key)
        return properties["option:" .. key] or false
    end

    function context:get_commit_text()
        return self.commit_text
    end

    function context:get_selected_candidate()
        return self.selected_candidate
    end

    local config = {}
    function config:get_bool(key)
        if config_values == nil then return nil end
        return config_values[key]
    end
    function config:get_int(key)
        if config_values == nil then return nil end
        return config_values[key]
    end
    function config:get_string(key)
        if config_values == nil then return nil end
        return config_values[key]
    end
    function config:get_list(key)
        if config_values == nil then return nil end
        local values = config_values[key]
        if type(values) ~= "table" then return nil end
        return {
            size = #values,
            get_value_at = function(_, index)
                local value = values[index + 1]
                if value == nil then return nil end
                return {
                    value = value,
                    get_string = function(self) return self.value end,
                }
            end,
        }
    end

    local env = {
        engine = {
            context = context,
            schema = { config = config },
            component_translation = nil,
        },
    }

    function env:commit(candidate, text)
        context.selected_candidate = candidate
        context.commit_text = text == nil and (candidate and candidate.text or "") or text
        notifier:emit(context)
    end

    function env:set_component_candidates(candidates)
        self.engine.component_translation = M.input(candidates)
    end

    return env
end

function M.key(representation)
    return {
        release = function() return false end,
        repr = function() return representation or "a" end,
    }
end

function M.input(candidates)
    local source = { consumed = 0, candidates = candidates }
    function source:iter()
        local index = 0
        return function()
            index = index + 1
            local candidate = self.candidates[index]
            if candidate then
                self.consumed = self.consumed + 1
            end
            return candidate
        end
    end
    return source
end

function M.install_rime_globals()
    local old_yield = _G.yield
    local old_shadow = _G.ShadowCandidate
    local old_component = _G.Component
    local old_rime_api = _G.rime_api
    local old_log = _G.log

    _G.ShadowCandidate = function(candidate, candidate_type, text, comment)
        local shadow = M.candidate(candidate_type, text, comment, candidate:get_genuine())
        shadow.preedit = candidate.preedit
        shadow.quality = candidate.quality
        return shadow
    end

    _G.Component = {
        Translator = function(engine)
            return {
                query = function()
                    return engine.component_translation
                end,
            }
        end,
    }
    _G.rime_api = {
        get_user_data_dir = function() return "." end,
    }
    _G.log = {
        error = function() end,
    }

    return function()
        _G.yield = old_yield
        _G.ShadowCandidate = old_shadow
        _G.Component = old_component
        _G.rime_api = old_rime_api
        _G.log = old_log
    end
end

function M.collect_yields(body)
    local output = {}
    local old_yield = _G.yield
    _G.yield = function(candidate)
        output[#output + 1] = candidate
    end
    local ok, err = xpcall(body, debug.traceback)
    _G.yield = old_yield
    if not ok then error(err, 0) end
    return output
end

function M.collect_filter(filter_module, input, env)
    local output = {}
    local old_yield = _G.yield
    _G.yield = function(candidate)
        output[#output + 1] = candidate
    end
    local ok, err = xpcall(function()
        filter_module.func(input, env)
    end, debug.traceback)
    _G.yield = old_yield
    if not ok then
        error(err, 0)
    end
    return output
end

local function read_lines(path)
    local file = assert(io.open(path, "r"))
    local lines = {}
    for line in file:lines() do
        lines[#lines + 1] = line
    end
    file:close()
    return lines
end

local function indent_of(line)
    return #(string.match(line, "^(%s*)") or "")
end

local function find_mapping(lines, key, start_at, parent_indent)
    for i = start_at or 1, #lines do
        local indent = indent_of(lines[i])
        if parent_indent and indent <= parent_indent and string.match(lines[i], "%S") then
            return nil
        end
        if string.match(lines[i], "^%s*" .. key .. ":%s*$") then
            return i, indent
        end
    end
    return nil
end

function M.schema_scalar(path, parents, key)
    local lines = read_lines(path)
    local index = 1
    local parent_indent = -1
    for _, parent in ipairs(parents) do
        local found, indent = find_mapping(lines, parent, index, parent_indent)
        if not found then
            fail("schema mapping missing: " .. parent, 2)
        end
        index = found + 1
        parent_indent = indent
    end
    for i = index, #lines do
        local indent = indent_of(lines[i])
        if indent <= parent_indent and string.match(lines[i], "%S") then
            break
        end
        local value = string.match(lines[i], "^%s*" .. key .. ":%s*['\"]?(.-)['\"]?%s*$")
        if value then
            return value
        end
    end
    fail("schema scalar missing: " .. key, 2)
end

local function extract_xforms(path, mapping_name)
    local lines = read_lines(path)
    local mapping_index, mapping_indent = find_mapping(lines, mapping_name, 1, nil)
    if not mapping_index then
        fail("schema mapping missing: " .. mapping_name, 3)
    end
    local preedit_index, preedit_indent = find_mapping(lines, "preedit_format", mapping_index + 1, mapping_indent)
    if not preedit_index then
        local include
        local patches = {}
        for i = mapping_index + 1, #lines do
            local indent = indent_of(lines[i])
            if indent <= mapping_indent and string.match(lines[i], "%S") then break end
            include = include or string.match(lines[i], "^%s*__include:%s*([^%s]+)%s*$")
            local index, rule = string.match(lines[i], '^%s*["\']preedit_format/@(%d+)["\']:%s*["\'](xform/.-/)["\']%s*$')
            if index and rule then patches[tonumber(index) + 1] = rule end
            local before, inserted = string.match(lines[i], '^%s*["\']preedit_format/@before%s+(%d+)["\']:%s*["\'](xform/.-/)["\']%s*$')
            if before and inserted then patches["before:" .. before] = inserted end
        end
        if not include then
            fail("preedit_format missing under: " .. mapping_name, 3)
        end

        local include_schema, include_mapping = string.match(include, "^([^:]+):/([^/]+)$")
        local include_path = string.match(include_schema or "", "%.schema$")
            and include_schema .. ".yaml"
            or (include_schema or "") .. ".schema.yaml"
        local rules = extract_xforms(include_path, include_mapping)
        for index, rule in pairs(patches) do
            local before = type(index) == "string" and string.match(index, "^before:(%d+)$")
            if before then
                table.insert(rules, tonumber(before) + 1, rule)
            else
                rules[index] = rule
            end
        end
        return rules
    end

    local rules = {}
    local includes = {}
    for i = preedit_index + 1, #lines do
        local line = lines[i]
        local indent = indent_of(line)
        if indent <= preedit_indent and string.match(line, "%S") then
            break
        end
        local rule = string.match(line, '^%s*%-%s*["\']?(xform/.-/)["\']?%s*$')
        if rule then
            rules[#rules + 1] = rule
        end
        local include = string.match(line, "^%s*__include:%s*([^%s]+)%s*$")
        if include then
            includes[#includes + 1] = include
        end
    end

    for _, include in ipairs(includes) do
        local include_schema, include_mapping = string.match(include, "^([^:]+):/([^/]+)/preedit_format$")
        if include_schema and include_mapping then
            local include_path = string.match(include_schema, "%.schema$")
                and include_schema .. ".yaml"
                or include_schema .. ".schema.yaml"
            local included = extract_xforms(include_path, include_mapping)
            for _, rule in ipairs(included) do
                rules[#rules + 1] = rule
            end
        end
    end
    return rules
end

function M.apply_preedit(path, mapping_name, input)
    local output = input
    for _, rule in ipairs(extract_xforms(path, mapping_name)) do
        local pattern, replacement = string.match(rule, "^xform/(.-)/(.-)/$")
        if pattern then
            output = string.gsub(output, pattern, replacement)
        end
    end
    return output
end

return M

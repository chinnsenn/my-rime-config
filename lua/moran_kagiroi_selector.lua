-- ===================================================================
-- [INPUT]:  Rime Lua API、Kagiroi 前缀分段
-- [OUTPUT]: 在 Kagiroi 段用 1–0 直接选择当前页候选
-- [POS]:    补足 Kagiroi 罗马字转写与 Rime 数字选择器之间的按键边界
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local kAccepted = 1
local kNoop = 2

local function func(key_event, env)
    if key_event:release() or key_event:ctrl() or key_event:alt() or key_event:super() then
        return kNoop
    end
    local keycode = key_event.keycode
    if keycode < string.byte("0") or keycode > string.byte("9") then
        return kNoop
    end

    local context = env.engine.context
    local composition = context.composition
    if composition:empty() then
        return kNoop
    end
    local segment = composition:back()
    if not segment:has_tag("kagiroi") then
        return kNoop
    end

    local index = keycode == string.byte("0") and 9 or keycode - string.byte("1")
    local count = segment.menu:prepare(env.engine.schema.page_size)
    if index >= count then
        return kNoop
    end
    local page_size = env.engine.schema.page_size
    local page_start = math.floor(segment.selected_index / page_size) * page_size
    context:select(page_start + index)
    return kAccepted
end

return { func = func }

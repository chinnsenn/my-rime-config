-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (KeyEvent, Context, env)
-- [OUTPUT]: 对外提供 moran_ja_processor (lua_processor)
-- [POS]:    lua/ 目录的日语模式按键处理器，被 moran_ja_hybrid 方案调用
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local kRejected = 0
local kAccepted = 1
local kNoop = 2

local function init(env)
    env.ja_only_suffix = "//"
    env.was_ja_only_mode = false
    local config = env.engine.schema.config
    if config then
        local suffix = config:get_string("moran_ja/ja_only_suffix")
        if suffix and #suffix > 0 then
            env.ja_only_suffix = suffix
        end
    end

    -- 选词后恢复筛选模式后缀
    env.select_notifier = env.engine.context.select_notifier:connect(function(ctx)
        if not env.was_ja_only_mode then return end
        env.was_ja_only_mode = false
        
        local remaining = ctx.input or ""
        if #remaining == 0 then return end
        
        -- 移除可能残留的后缀，然后重新追加
        remaining = remaining:gsub("/+$", "")
        if #remaining > 0 then
            ctx.input = remaining .. env.ja_only_suffix
        else
            ctx.input = ""
        end
    end)
end

local function fini(env)
    if env.select_notifier then
        env.select_notifier:disconnect()
    end
end

local function processor(key_event, env)
    if key_event:release() then
        return kNoop
    end

    local context = env.engine.context
    local input = context.input or ""
    local suffix = env.ja_only_suffix
    local suffix_len = #suffix

    if #input < suffix_len then
        env.was_ja_only_mode = false  -- 输入太短，清除状态
        return kNoop
    end

    local suffix_pos = #input - suffix_len + 1
    local has_suffix = input:sub(suffix_pos) == suffix

    -- 状态同步：只有当前确实有后缀时才标记
    env.was_ja_only_mode = has_suffix

    if not has_suffix then
        return kNoop
    end

    local keycode = key_event.keycode

    -- Backspace: 整体删除后缀，退出筛选模式
    if keycode == 0xff08 then
        context.input = input:sub(1, suffix_pos - 1)
        return kAccepted
    end

    -- 字母键: 在后缀前插入，保持筛选模式
    local is_letter = (keycode >= 0x61 and keycode <= 0x7a)
                   or (keycode >= 0x41 and keycode <= 0x5a)

    if is_letter then
        context.input = input:sub(1, suffix_pos - 1) .. string.char(keycode) .. suffix
        return kAccepted
    end

    return kNoop
end

return { init = init, func = processor, fini = fini }

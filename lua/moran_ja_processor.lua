-- ===================================================================
-- [INPUT]:  依赖 Rime Lua API (KeyEvent, Context, env)
-- [OUTPUT]: 对外提供 moran_ja_processor (lua_processor)
-- [POS]:    lua/ 目录的日语模式按键处理器，被 moran_ja_hybrid 方案调用
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

local kNoop = 2

local function init(env) end
local function fini(env) end

local function processor(key_event, env)
    return kNoop
end

return { init = init, func = processor, fini = fini }

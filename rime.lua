-- ===================================================================
-- [INPUT]:  依赖 lua/ 目录下的各 Lua 模块
-- [OUTPUT]: 对外提供 Rime Lua 组件注册表 (lua_filter, lua_translator 等)
-- [POS]:    Rime 用户目录的 Lua 入口，被 librime-lua 插件加载
-- [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
-- ===================================================================

moran_ja_filter = require("moran_ja_filter")
moran_ja_processor = require("moran_ja_processor")

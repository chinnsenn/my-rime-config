# lua/
> L2 | 父级: /Users/chinnsenn/Library/Rime/CLAUDE.md

Lua 扩展脚本目录，为 Rime 提供过滤器、翻译器、处理器。

## 成员清单

moran.lua: 公共模块，提供 query_translation、unicode 检测等工具函数
moran_aux_translator.lua: 辅助码翻译器，实现直接辅助码筛选
moran_charset_comment_filter.lua: 字符集注释过滤器，添加 Unicode 等信息
moran_charset_filter.lua: 字符集过滤器，按 GBK/通用筛选候选
moran_disable_phrase_memory.lua: 禁用词组记忆过滤器
moran_english_filter.lua: 英文候选过滤器
moran_express_translator.lua: 快速翻译器，整合 fixed+smart 双词库
moran_fix_filter.lua: 固顶码过滤器，处理简快码优先级
moran_hint_filter.lua: 提示过滤器，显示编码提示
moran_ijrq_filter.lua: 出简让全过滤器
moran_ja_custom_translator.lua: 日语自定义短语边界适配器，包装 custom_phrase_ja 并标记稳定 moran_ja 候选类型
moran_ja_gloss_filter.lua: 多源中日释义过滤器，通过统一候选语言身份仅为中文候选追加离线日语释义
moran_ja_language.lua: 日语混输统一语义模块，校验完整罗马字音节并统一识别候选语言身份
moran_ja_filter.lua: 日语混合过滤器，在当前候选页内探测真实中日来源，决定单语言直出或偏置混排，并追加假名预览
moran_ja_processor.lua: 提交行为状态机，通过统一候选语言身份追踪中日提交，维护滑动窗口、阈值夺权与活动衰减
moran_ja_translator.lua: jaroomaji 包装翻译器，仅让结构完整的日语罗马字进入候选流并标记稳定来源类型
moran_kagiroi_selector.lua: Kagiroi 前缀段数字选词处理器，按当前页选择 1–0 对应候选
moran_number.lua: 数字翻译器，大写数字转换
moran_pin.lua: 固顶词处理器/过滤器
moran_processor.lua: 按键处理器
moran_reorder_filter.lua: 候选重排过滤器
moran_shijian.lua: 时间日期翻译器
moran_unicode.lua: Unicode 输入翻译器
moran_unicode_display_filter.lua: Unicode 码点显示过滤器

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

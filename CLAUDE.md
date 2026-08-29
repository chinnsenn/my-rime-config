# Rime Config - 个人 Rime 输入法配置
Rime + YAML + Lua

<directory>
build/ - Rime 构建产物 (二进制文件)
docs/ - 设计与实施文档 (方案设计、执行计划)
lua/ - Lua 扩展脚本 (过滤器/处理器)
opencc/ - OpenCC 简繁转换配置
skins_and_layouts/ - 键盘皮肤与布局配置 (2子目录: fcitx5, hamster)
tests/ - Lua 行为回归测试 (Rime API 边界 fake、schema 规则执行器)
./ - 核心方案配置文件 (*.schema.yaml) 及词库 (*.dict.yaml)
</directory>

<config>
default.custom.yaml - 全局快捷键与方案列表
trime.custom.yaml - 同文输入法（Trime）键盘配置加载器
moran.schema.yaml - 魔然主方案配置
moran_kagiroi_hybrid.schema.yaml - 魔然中文主输入与 Kagiroi 分号前缀日文长文转换方案（依赖 rime-kagiroi）
moran_kagiroi_hybrid.trime.yaml - 魔然·篝火日混的 Trime 虚拟键盘布局
moran_kagiroi_symbols.trime.yaml - Trime 液态符号目录的数据层，完整映射 Rime 官方符号组并提供紧凑滚动网格。
lua/moran_ja_gloss_filter.lua - 按配置顺序合并多源中日词库，并将最高优先级释义追加到中文候选 comment。
lua/moran_ja_language.lua - 日语混输统一语义模块，集中维护罗马字有效性与候选语言身份。
lua/zh_ja_custom.txt - 用户可直接维护的高优先级中日人工修订词表。
lua/zh_ja_learner.txt - 基于 Unlicense 日中学习词库反向构建的日常词汇映射。
lua/zh_ja_wiki.txt - 基于 CC0 Wikidict、与内置魔然词典取交集的中文到日语长尾映射。
installation.yaml - Rime 安装标识
</config>

<changes>
2026-08-29 - 默认中日混输为合法日语罗马字新增纯假名候选；直接复用 jaroomaji 的 preedit_format，保持中文首选与原有日语转换候选顺序。
2026-08-28 - moran_kagiroi_hybrid 接入 CC0 中日离线词表与可切换候选释义过滤器。
2026-08-28 - 日语释义扩展为人工修订、学习词库、Wikidict 三级有序合并，并保留单词库旧配置读取能力。
2026-08-28 - 日语混输建立统一罗马字语法与候选来源裁决，单语言候选保持原序，中日共存时使用偏置混排。
2026-08-29 - 普通混输改为当前候选页内的有界候选探测，词典与用户学习产生的新重叠编码自动进入中日混排。
</changes>

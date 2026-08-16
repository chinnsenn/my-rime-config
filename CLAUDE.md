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
installation.yaml - Rime 安装标识
</config>

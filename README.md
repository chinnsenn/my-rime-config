# Rime 精简配置 - 魔然智能整句 + 日文罗马字输入 | 中日文混合输入解决方案

> 基于 Rime 输入法引擎的精简配置，聚焦中日文智能输入场景

## 🎯 特性概览

### 三大核心方案
- **[魔然](moran.schema.yaml)** - 基于自然码的智能整句输入，含固顶简快码
- **[魔然·日混](moran_ja_hybrid.schema.yaml)** - 中日文混合输入，智能候选排序
- **[日文罗马字](jaroomaji.schema.yaml)** - 日本语罗马字输入，支持长音和强制片假名

## 🚀 快速安装

### 前置要求
- [Rime 输入法引擎](https://rime.im/) 已安装
- 支持 Squirrel(macOS)、Weasel(Windows)、ibus-rime(Linux)，理论上还支持其他 Rime 引擎的输入法，请自行测试。

### 安装步骤

1. **克隆配置仓库**
   ```bash
   git clone https://github.com/chinnsenn/my-rime-config.git
   cd my-rime-config
   ```

2. **复制到 Rime 用户目录**
   
   **macOS:**
   ```bash
   cp -r ./* ~/Library/Rime/
   ```
   
   **Windows:**
   ```cmd
   xcopy /E /I * %APPDATA%\Rime\
   ```
   
   **Linux:**
   ```bash
   cp -r ./* ~/.config/rime/
   ```

3. **重新部署**
   - 点击输入法菜单 → 重新部署
   - 或重启输入法引擎

## 📝 配置说明

### 全局配置
- **[default.custom.yaml](default.custom.yaml)** - 全局按键绑定和方案列表
  - F4: 方案切换菜单
  - Control+`/Control+Shift+`: 快速切换方案
  - Shift+Space: 全角/半角切换

### 方案特色

#### 魔然整句模式
- 智能整句输入，基于自然码编码
- 支持固顶词模式（4码优先输出词组）
- 集成多种输入方式：拼音、笔画、仓颉、英文
- 繁简转换

#### 魔然·日混模式
- 中日文候选同时显示，智能排序
- 日语候选显示假名预览 [にほん]
- 智能检测日语模式，自动调整优先级
- 无需切换即可输入中日文混合内容

#### 日文罗马字输入
- 标准罗马字入力
- L 键也可作为长音（除 - 键外）
- Shift+字母强制片假名输入
- 默认日文模式启动

## 🎮 使用技巧

### 快捷键
| 快捷键 | 功能 |
|--------|------|
| F4 | 方案切换菜单 |
| Control+` | 下一个方案 |
| Control+Shift+` | 上一个方案 |
| Shift+Space | 全角/半角切换 |
| Control+Shift+4 | 繁简转换 |

### 魔然方案特色
- **4码固顶**: 输入4码时优先输出词组（带⚡️标记）
- **智能纠错**: 支持拼音容错和笔画提示
- **中英混输**: 无需切换直接输入英文
- **符号输入**: 支持多种符号输入方式

### 日文输入特色
- **长音输入**: `ka-` 或 `kaL` 都可输入「カー」
- **片假名**: Shift+字母强制片假名
- **模式切换**: `あ/A` 切换日文/英文模式

## 🔧 自定义配置

### 添加自定义词库
1. 编辑 `jaroomaji.user.dict.yaml` 或 `moran.user.dict.yaml`
2. 重新部署输入法

### 修改按键绑定
编辑 `default.custom.yaml` 中的 `key_binder` 部分

### 调整方案顺序
修改 `default.custom.yaml` 中的 `schema_list`

## 📁 文件结构

```
Rime/
├── 📋 配置文件
│   ├── default.custom.yaml        # 全局配置
│   ├── installation.yaml          # 安装信息
│   └── .gitignore                # Git 忽略规则
├── 🎯 核心输入方案
│   ├── moran.schema.yaml         # 魔然整句
│   ├── moran_ja_hybrid.schema.yaml  # 魔然·日混
│   └── jaroomaji.schema.yaml     # 日文罗马字
├── 📚 词库文件
│   ├── moran.*.dict.yaml         # 魔然词库
│   ├── jaroomaji.*.dict.yaml     # 日文词库
│   └── *.user.dict.yaml          # 用户词库
├── 🔧 运行时数据
│   ├── *.userdb/                 # 编译后的二进制数据
│   └── build/                    # 构建缓存
├── 🧩 辅助模块
│   ├── lua/                      # Lua 脚本扩展
│   └── opencc/                   # 简繁转换配置
└── 📖 文档
    └── README.md                 # 本文档
```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交规范
- 问题描述清晰，包含复现步骤
- 代码修改保持风格一致
- 更新相关文档说明

## 📄 许可证

本项目采用 [Apache License 2.0](LICENSE) 许可证。

## 🙏 致谢

- [Rime 输入法引擎](https://rime.im/) - 核心引擎
- [魔然输入法](https://github.com/ksqsf/moran) - 智能整句方案
- [日文罗马字方案](https://github.com/lazy-fox-chan/jaroomaji) - 日文输入支持
- [iamcheyan/rime](https://github.com/iamcheyan/rime) - 思路

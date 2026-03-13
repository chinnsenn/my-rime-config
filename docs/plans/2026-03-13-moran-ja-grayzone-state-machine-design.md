# moran_ja_hybrid 灰区外置 + 状态机 + 埋点设计

日期：2026-03-13
范围：`moran_ja_hybrid.schema.yaml`、`lua/moran_ja_filter.lua`、`lua/moran_ja_processor.lua`

## 背景
当前混输已完成判定地基修复与降噪，但灰区编码仍依赖 `moran_ja_filter.lua` 内硬编码词表，扩展成本高；同时缺少可用于自动筛选灰区的行为日志。

目标是在不破坏既有排序职责边界的前提下：
- 将灰区词表从代码迁移到配置；
- 引入轻量软模式状态机，减少中日判定抖动；
- 增加最小可用埋点，形成可迭代的数据闭环。

## 设计原则
1. 单一职责：`moran_reorder_filter` 继续只做中文体系重排；`moran_ja_filter` 只做中日分流与插位；`moran_ja_processor` 负责状态与埋点。
2. 低风险：先加配置与开关，再启用行为逻辑；所有新能力可逐级关闭回滚。
3. 数据驱动：灰区扩展由日志统计驱动，不靠拍脑袋扩表。

## 方案对比
### A. 仅外置灰区词表
- 优点：改动最小。
- 缺点：无法自动扩表，长期维护仍偏手工。

### B. 仅埋点，不加状态机
- 优点：先拿数据。
- 缺点：短期误判收益有限。

### C. 外置词表 + 软状态机 + 埋点（采用）
- 优点：短期稳定性与长期可迭代性兼得。
- 缺点：改动面比 A/B 大，需要严格开关与回归。

## 架构设计
### 1) schema 层（配置）
在 `moran_ja_hybrid.schema.yaml` 的 `moran_ja` 段新增：
- `gray_zone_inputs`: 灰区输入数组（如 `koko`, `nori`）
- `state_machine.enabled`: 状态机开关
- `state_machine.window_size`: 窗口大小
- `state_machine.decay_seconds`: 衰减时长
- `state_machine.ja_threshold` / `zh_threshold`: 转态阈值
- `telemetry.enabled`: 埋点开关
- `telemetry.log_file`: JSONL 路径
- `telemetry.sample_rate`: 采样率

并在 `engine/processors` 挂回 `lua_processor@moran_ja_processor`。

### 2) processor 层（状态机 + 埋点）
`lua/moran_ja_processor.lua` 从 no-op 升级为轻量处理器：
- 维护状态：`neutral` / `ja_bias` / `zh_bias`
- 监听选择与提交，更新窗口计数并做衰减
- 将当前状态写入 context 可读位置，供 filter 读取
- 在开关开启时落盘 JSONL 事件

### 3) filter 层（分流）
`lua/moran_ja_filter.lua`：
- 删除硬编码 `GRAY_ZONE_SHUANGPIN_INPUTS`
- 从 schema 读取 `gray_zone_inputs` 并缓存
- 在不改变中文内部重排的前提下，按状态机软偏置调整中日插位策略

## 数据流
1. filter 阶段：记录 `input/top1_lang/gray_zone_hit/state_before`
2. select 阶段：记录 `selection_index/selected_lang/state_before`
3. commit 阶段：记录 `committed_lang/state_after`

示例（JSONL）：
```json
{"ts":1710000000,"event":"filter","input":"koko","top1_lang":"ja","gray_zone_hit":true,"state":"neutral"}
{"ts":1710000001,"event":"select","input":"koko","selection_index":2,"selected_lang":"zh","state":"neutral"}
{"ts":1710000001,"event":"commit","input":"koko","committed_lang":"zh","state":"zh_bias"}
```

## 验证指标
- 中文 Top1 稳定率（不下降）
- 灰区输入纠错率（上升）
- 候选抖动次数（下降）
- 日文预览正确率（保持）

## 回滚策略
按开关逐级回退：
1. 关闭 telemetry
2. 关闭 state_machine
3. 清空 gray_zone_inputs（回到基础规则）

## 最小实施顺序
1. 加 schema 默认配置（行为不变）
2. 实现 processor 状态机（默认可关）
3. filter 改为读外置灰区词表
4. 开启 telemetry，跑一轮回归并统计

## 风险与缓解
- 状态共享一致性风险：统一通过 context 单点读写
- 写日志性能风险：采样率 + 可关闭 + 追加写
- 阈值过敏风险：默认保守阈值，先小流量观察

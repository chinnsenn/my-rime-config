# moran_ja_hybrid 灰区外置 + 状态机 + 埋点 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 `moran_ja_hybrid` 中实现“灰区词表外置 + 轻量中日软模式状态机 + 可开关埋点”，并保持现有中日分流与中文重排职责边界稳定。

**Architecture:** 将配置入口集中在 `moran_ja_hybrid.schema.yaml` 的 `moran_ja` 段；`moran_ja_processor.lua` 负责状态机与事件埋点；`moran_ja_filter.lua` 仅消费“灰区配置 + 状态偏置”进行插位决策，不承担中文内部排序。

**Tech Stack:** Rime Schema YAML + Lua（Rime Lua API：Context/Engine/Candidate）

---

### Task 1: 在 schema 增加灰区、状态机、埋点配置并挂回 processor

**Files:**
- Modify: `moran_ja_hybrid.schema.yaml`（`engine/processors`，`moran_ja` 配置段）
- Test: `moran_ja_hybrid.schema.yaml`（语法/结构检查）

**Step 1: 写“配置存在性”检查脚本（先失败）**

```bash
python3 - <<'PY'
from pathlib import Path
import re
p = Path('moran_ja_hybrid.schema.yaml').read_text(encoding='utf-8')
required = [
    'lua_processor@moran_ja_processor',
    'gray_zone_inputs:',
    'state_machine:',
    'telemetry:',
]
missing = [x for x in required if x not in p]
if missing:
    raise SystemExit('MISSING: ' + ', '.join(missing))
print('OK')
PY
```

**Step 2: 运行检查，确认当前失败**

Run: 上述命令
Expected: FAIL，提示缺少新配置字段

**Step 3: 最小实现 schema 修改**

在 `moran_ja_hybrid.schema.yaml`：
- `engine/processors` 挂回 `lua_processor@moran_ja_processor`
- 在 `moran_ja:` 下新增（示例）

```yaml
moran_ja:
  default_position: 2
  indicator: "🇯🇵"
  gray_zone_inputs: [koko, nori]
  state_machine:
    enabled: true
    window_size: 6
    decay_seconds: 25
    ja_threshold: 2
    zh_threshold: 2
  telemetry:
    enabled: false
    log_file: "moran_ja_hybrid.telemetry.jsonl"
    sample_rate: 1.0
```

**Step 4: 运行检查，确认通过**

Run: Task 1 Step 1 同命令
Expected: PASS（输出 `OK`）

**Step 5: 提交**

```bash
git add moran_ja_hybrid.schema.yaml
git commit -m "feat(moran_ja): add state-machine and telemetry schema config"
```

---

### Task 2: 将 moran_ja_processor 从 no-op 实现为轻量状态机骨架

**Files:**
- Modify: `lua/moran_ja_processor.lua`
- Test: `lua/moran_ja_processor.lua`（Lua 语法检查）

**Step 1: 写失败检查（状态机导出能力）**

```bash
python3 - <<'PY'
from pathlib import Path
s = Path('lua/moran_ja_processor.lua').read_text(encoding='utf-8')
required = ['neutral', 'ja_bias', 'zh_bias', 'init', 'func', 'fini']
missing = [x for x in required if x not in s]
if missing:
    raise SystemExit('MISSING: ' + ', '.join(missing))
print('OK')
PY
```

**Step 2: 运行检查，确认当前失败**

Run: 上述命令
Expected: FAIL（no-op 不含状态定义）

**Step 3: 最小实现状态机骨架**

在 `lua/moran_ja_processor.lua` 实现：
- 状态常量：`neutral/ja_bias/zh_bias`
- `init` 读取 schema：`state_machine.*` 与 `telemetry.*`
- `func` 中维护窗口计数与衰减（按时间戳）
- 将当前状态写入 `context` 可读位置（例如 property 或特定 tag）
- 保持无侵入：未命中事件时返回 `kNoop`

**Step 4: 语法验证**

Run: `luac -p lua/moran_ja_processor.lua`
Expected: PASS

**Step 5: 提交**

```bash
git add lua/moran_ja_processor.lua
git commit -m "feat(moran_ja): implement lightweight zh/ja soft-state machine"
```

---

### Task 3: 在 processor 增加可开关 JSONL 埋点

**Files:**
- Modify: `lua/moran_ja_processor.lua`
- Test: `lua/moran_ja_processor.lua`（语法检查）

**Step 1: 写失败检查（埋点关键字）**

```bash
python3 - <<'PY'
from pathlib import Path
s = Path('lua/moran_ja_processor.lua').read_text(encoding='utf-8')
required = ['telemetry', 'log_file', 'sample_rate', 'event']
missing = [x for x in required if x not in s]
if missing:
    raise SystemExit('MISSING: ' + ', '.join(missing))
print('OK')
PY
```

**Step 2: 运行检查，确认失败或部分失败**

Run: 上述命令
Expected: FAIL 或缺字段

**Step 3: 最小实现 JSONL 事件写出**

新增：
- `emit_event(event_table)`（受 `telemetry.enabled` 控制）
- 事件类型：`filter/select/commit`
- 字段最小集：`ts,event,input,top1_lang,selection_index,committed_lang,state`
- 采样：`sample_rate`（0~1）

**Step 4: 语法验证**

Run: `luac -p lua/moran_ja_processor.lua`
Expected: PASS

**Step 5: 提交**

```bash
git add lua/moran_ja_processor.lua
git commit -m "feat(moran_ja): add configurable jsonl telemetry events"
```

---

### Task 4: moran_ja_filter 读取外置灰区词表替代硬编码

**Files:**
- Modify: `lua/moran_ja_filter.lua`
- Test: `lua/moran_ja_filter.lua`（语法检查）

**Step 1: 写失败检查（硬编码仍存在）**

```bash
python3 - <<'PY'
from pathlib import Path
s = Path('lua/moran_ja_filter.lua').read_text(encoding='utf-8')
if 'GRAY_ZONE_SHUANGPIN_INPUTS' in s:
    raise SystemExit('FAIL: hardcoded gray-zone table still exists')
print('OK')
PY
```

**Step 2: 运行检查，确认失败**

Run: 上述命令
Expected: FAIL

**Step 3: 最小实现外置读取**

在 `lua/moran_ja_filter.lua`：
- `init(env)` 读取 `moran_ja/gray_zone_inputs` 到本地缓存集合
- `has_shuangpin_negative_feature(input)` 改为查缓存集合
- 保留现有“仅灰区路径触发负特征”的保守策略

**Step 4: 语法验证**

Run: `luac -p lua/moran_ja_filter.lua`
Expected: PASS

**Step 5: 提交**

```bash
git add lua/moran_ja_filter.lua
git commit -m "refactor(moran_ja): externalize gray-zone inputs to schema"
```

---

### Task 5: filter 消费状态机软偏置（不改中文内部重排）

**Files:**
- Modify: `lua/moran_ja_filter.lua`
- Test: `lua/moran_ja_filter.lua`, `lua/moran_reorder_filter.lua`

**Step 1: 写失败检查（缺状态偏置分支）**

```bash
python3 - <<'PY'
from pathlib import Path
s = Path('lua/moran_ja_filter.lua').read_text(encoding='utf-8')
required = ['ja_bias', 'zh_bias']
missing = [x for x in required if x not in s]
if missing:
    raise SystemExit('MISSING: ' + ', '.join(missing))
print('OK')
PY
```

**Step 2: 运行检查，确认失败**

Run: 上述命令
Expected: FAIL

**Step 3: 最小实现软偏置消费**

在 `filter(input, env)`：
- 读取 processor 暴露状态
- `ja_bias`：保持“中文首项后插日文”策略
- `zh_bias`：日文回落到 `default_position` 后插
- `neutral`：保持当前逻辑
- 明确不改 `moran_reorder_filter` 与中文内部顺序

**Step 4: 语法验证（双文件）**

Run:
- `luac -p lua/moran_ja_filter.lua`
- `luac -p lua/moran_reorder_filter.lua`

Expected: 两者 PASS

**Step 5: 提交**

```bash
git add lua/moran_ja_filter.lua
git commit -m "feat(moran_ja): apply processor soft-bias in zh/ja insertion"
```

---

### Task 6: 端到端回归与指标基线

**Files:**
- Modify: （无代码必须修改；如需记录结果可更新 `docs/plans/2026-03-13-moran-ja-grayzone-state-machine-design.md` 附录）
- Test: runtime manual test + Lua 语法

**Step 1: 运行语法回归**

Run:
- `luac -p lua/moran_ja_filter.lua`
- `luac -p lua/moran_ja_processor.lua`
- `luac -p lua/moran_reorder_filter.lua`

Expected: 全 PASS

**Step 2: 执行手工输入回归**

测试集：
- 中文：常见 2~4 码、整句
- 日文：`nihon`, `konnichiha`, `gakkou`, `nn`
- 灰区：`koko`, `nori`, `ka`

Expected:
- 中文 Top1 不回退
- 日文预览正确
- 灰区误判下降，不引入明显新误伤

**Step 3: 开启 telemetry 小流量（可选）**

在 schema 中临时开启：
- `moran_ja/telemetry/enabled: true`

观察 JSONL 是否产出且字段完整。

**Step 4: 记录结论并回到默认安全开关**

- 若性能无异常，可保持开启；否则关闭 telemetry。

**Step 5: 最终提交（若有文档更新）**

```bash
git add docs/plans/2026-03-13-moran-ja-grayzone-state-machine-design.md
# 若无文档变更可跳过 commit
```

---

### Task 7: 文档同构校验（GEB 回环）

**Files:**
- Modify: `lua/CLAUDE.md`（如新增/变更职责描述）
- Modify: `CLAUDE.md`（仅当目录结构再变化）

**Step 1: 检查 L2 文档是否反映 processor 职责变化**

`lua/CLAUDE.md` 中 `moran_ja_processor.lua` 描述应从“占位/no-op”更新为“软状态机 + 埋点”。

**Step 2: 必要时更新文档**

仅改受影响条目，保持一行一文件。

**Step 3: 验证文档协议字段**

确认包含：
`[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md`

**Step 4: 提交文档同步**

```bash
git add lua/CLAUDE.md CLAUDE.md
git commit -m "docs(lua): sync moran_ja_processor role with implementation"
```

---

## 执行注意事项
- 每个 Task 完成后立即运行对应验证，不跨任务累计风险。
- 任何一步回归失败，先停止并定位，不继续叠加改动。
- 避免新建无必要抽象；以可回滚开关优先。

## 完成标准
- 灰区词表不再硬编码在 `moran_ja_filter.lua`
- `moran_ja_processor.lua` 提供可控软状态机与可开关埋点
- `moran_ja_hybrid.schema.yaml` 提供完整配置入口
- 语法检查全通过，手工回归无明显退化
- 文档与代码职责保持同构

# tests/
> L2 | 父级: /Users/chinnsenn/Library/Rime/CLAUDE.md

无需第三方依赖的 Lua 行为测试，通过公开生命周期接口验证 Rime 扩展。

## 成员清单

run.lua: 测试入口与极简断言运行器，聚合执行全部测试并以退出码报告结果
rime_fake.lua: Rime 系统边界 fake，提供 Context、Notifier、Candidate、Translation 与 schema xform 执行能力
test_moran_ja.lua: 日语混输状态机、过滤器与 japanese_only schema 的行为回归测试
test_moran_kagiroi.lua: Kagiroi 前缀段、罗马字布局与拨音映射的独立方案契约

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

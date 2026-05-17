---
session_id: SPEC-ui-unification-2026-05-17
phase: 4
document: adr
adr_id: ADR-002
title: 渐进式模块迁移策略
status: accepted
---

# ADR-002: 渐进式模块迁移策略

## Context
529 处硬编码样式分布在 55 个文件中。需要选择迁移策略：全量一次性迁移 vs 渐进式分批迁移。

## Decision
采用**7 波次渐进式迁移**，按风险从低到高排列：

| Wave | Module | Files | Rationale |
|------|--------|-------|-----------|
| Wave 1 | 令牌基础设施 | 3 new + app.dart | 零风险，无用户影响 |
| Wave 2 | 核心自定义组件 | 8 | 跨切面组件修复后效果倍增 |
| Wave 3 | mine/settings | 12 | 设置页自身先遵守设置（信任锚点） |
| Wave 4 | notifications/chat | 4 | 较低视觉复杂度，验证模式 |
| Wave 5 | search | 2 | 中等复杂度 |
| Wave 6 | posts（topic feed + detail） | 9 | 最高复杂度 + 最核心路径，最后迁移 |
| Wave 7 | compose/editor | 3 | 编辑器最后迁移，最小化创作者中断风险 |

## 每波次验证门禁
1. 该波次所有文件在亮/暗模式下手动 QA 通过
2. 无视觉回归（与迁移前截图对比）
3. 该波次无新增 lint 警告

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A: 全量一次性迁移** | 速度快 | 高风险、难以 review、回滚困难 | Rejected |
| **B: 渐进式（选定）** | 低风险、每波独立验证、可随时暂停 | 总时间较长 | **Accepted** |

## Consequences
- 每个 Wave 是一个独立的 git commit
- CI/CD 中的 lint 门禁仅在 Wave 7 完成后启用（避免迁移期间产生海量警告）
- 波次间可并行 review，但执行必须顺序（前一波建立模式，后一波使用模式）

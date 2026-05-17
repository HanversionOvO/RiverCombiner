---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: requirement
req_id: REQ-004
priority: should
status: complete
---

# REQ-004: 布局一致性

## User Story
As a **用户**，I want **所有页面的间距、留白和信息层级保持一致**，so that **我在不同模块之间切换时，视觉节奏感自然流畅，不需要重新适应布局**。

## Description

统一全 App 的布局模式：

1. **页面级 padding**: 所有页面水平 padding 统一（标准 16px），通过 RiverSpacing.lg 令牌引用
2. **卡片内边距**: 统一卡片内部 content padding
3. **列表项间距**: 同类列表项之间的垂直间距一致
4. **Section 间距**: 页面内不同 Section 之间的分隔间距形成 1x/2x/3x 比例关系
5. **信息层级**: 同一语义级别（页面标题、段落标题、正文、辅助文字）在所有页面使用一致的 TextTheme 层级 + 间距搭配

## Acceptance Criteria

- [ ] 所有页面的水平 padding 使用共同的间距令牌
- [ ] 卡片内 content padding 在所有特征模块中一致
- [ ] Section 间距比例为 1:2:3（列表项间 : 卡片间 : Section 间）
- [ ] 信息层级：标题→正文→辅助文字的垂直间距节奏在所有页面一致
- [ ] 布局变更不引起任何 widget 溢出或布局异常

## Traceability
- Product Brief Goal: 布局一致性
- Epic: EPIC-004 布局与无障碍审计

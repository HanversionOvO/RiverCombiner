---
session_id: SPEC-ui-unification-2026-05-17
phase: 4
document: adr
adr_id: ADR-001
title: 混合令牌架构（静态常量 + ThemeExtension）
status: accepted
---

# ADR-001: 混合令牌架构

## Context
river 需要建立统一的设计令牌系统来替代 529 处硬编码样式。需要选择令牌的架构形式。

## Decision
采用**混合架构**：静态常量类定义设计尺度 + ThemeExtension 存储运行时解析值。

```
静态常量 (river_design_tokens.dart)
  RiverRadius.none/xs/sm/md/lg/xl/full
  RiverSpacing.xs/sm/md/lg/xl/xxl
  → 用途: lint 规则验证 + 代码审查参考

ThemeExtension (river_custom_component_theme.dart)
  RiverCustomComponentTheme
  → 用途: 运行时通过 Theme.of(context) 解析，保留暗黑模式上下文
```

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A: 纯静态类** | 简单直接 | 绕过 Theme.of(context)、暗黑模式失效、需手动传递 | Rejected |
| **B: 纯 ThemeExtension** | 完整 Flutter 主题集成 | 无静态尺度参考、lint 难以验证、样板代码多 | Rejected |
| **C: 混合（选定）** | 静态尺可验证 + 动态值可运行时解析 | 两个文件需要协同维护 | **Accepted** |

## Consequences
- 新增 `lib/core/theme/` 目录，不影响现有结构
- 所有 ThemeExtension 必须实现 `lerp()` 以支持主题切换动画
- 未来新增设计尺度（如 typographyScale）在静态常量中扩展

---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: requirement
req_id: REQ-001
priority: must
status: complete
---

# REQ-001: 设计令牌系统

## User Story
As a **开发者**，I want **一套统一的设计令牌（颜色、字体、圆角、间距）作为所有 UI 代码的唯一引用源**，so that **新代码自动保持一致性，不再引入硬编码样式**。

## Description

定义一套完整的设计令牌系统，替代代码库中 529 处硬编码 BorderRadius、48 处硬编码 fontSize、128+ 处硬编码颜色。令牌系统包含：

1. **圆角尺度**（`RiverRadius`）：基于 6 级阶梯（none=0, xs=4, sm=8, md=12, lg=16, xl=24, full=999），覆盖当前 17 种不一致的圆角值
2. **间距栅格**（`RiverSpacing`）：基于 4px 基准（xs=4, sm=8, md=12, lg=16, xl=24, xxl=32），统一页面 padding、卡片间距、列表项间隔
3. **语义色彩扩展**（`RiverSemanticColors`）：在 ColorScheme 基础上增加 success/onSuccess/successContainer/overlayBackground 等语义 token
4. **排版层级映射**：确保所有文字使用 TextTheme 层级（displayLarge→labelSmall），无直接 fontSize 硬编码

架构原则：静态常量定义尺度（可被 lint 规则验证）+ ThemeExtension 存储运行时解析值（保留主题上下文和暗黑模式兼容）。

## Acceptance Criteria

- [ ] `lib/core/theme/river_design_tokens.dart` 存在，包含 RiverRadius 和 RiverSpacing 常量类
- [ ] `lib/core/theme/river_semantic_colors.dart` 存在，作为 ThemeExtension 子类
- [ ] `lib/core/theme/river_custom_component_theme.dart` 存在，覆盖自定义组件的 ThemeExtension
- [ ] `_buildTheme()` 注册所有 ThemeExtension
- [ ] 所有新增设计令牌文件有完整的单元测试覆盖

## Traceability
- Product Brief Goal: 设计令牌系统
- Epic: EPIC-001 设计令牌基础设施

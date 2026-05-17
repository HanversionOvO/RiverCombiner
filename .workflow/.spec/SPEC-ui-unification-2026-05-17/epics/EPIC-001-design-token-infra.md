---
session_id: SPEC-ui-unification-2026-05-17
phase: 5
document: epic
epic_id: EPIC-001
title: 设计令牌基础设施
mapped_requirements: [REQ-001, REQ-004]
mapped_adrs: [ADR-001]
priority: P0
mvp: true
---

# EPIC-001: 设计令牌基础设施

## Goal
建立设计令牌系统和主题扩展基础设施，为所有后续迁移提供引用源。

## Stories

### Story 1.1: 创建圆角尺度常量
**As a** 开发者 | **I want** `RiverRadius` 静态常量类 | **So that** 全 App 使用统一的 6 级圆角阶梯
- **Acceptance**: `lib/core/theme/river_design_tokens.dart` 包含 RiverRadius（none/xs/sm/md/lg/xl/full）
- **Size**: S

### Story 1.2: 创建间距栅格常量
**As a** 开发者 | **I want** `RiverSpacing` 静态常量类 | **So that** 全 App 使用 4px 基准间距系统
- **Acceptance**: `lib/core/theme/river_design_tokens.dart` 包含 RiverSpacing（xs/sm/md/lg/xl/xxl）
- **Size**: S

### Story 1.3: 创建语义色彩 ThemeExtension
**As a** 用户 | **I want** 语义色彩（success/error/overlay）在亮暗模式下自动切换 | **So that** SnackBar 和各弹窗的颜色与主题协调
- **Acceptance**: `river_semantic_colors.dart` 实现 ThemeExtension<RiverSemanticColors>（含 success/onSuccess/successContainer/overlayBackground），lerp() 已实现
- **Size**: M

### Story 1.4: 注册 ThemeExtension 到 _buildTheme()
**As a** 开发者 | **I want** 新 ThemeExtension 在主题系统中可用 | **So that** `Theme.of(context).extension<RiverSemanticColors>()` 返回正确实例
- **Acceptance**: `_buildTheme()` 通过 `extensions:` 注册 RiverSemanticColors 和 RiverCustomComponentTheme，亮/暗模式返回正确变体
- **Size**: M

### Story 1.5: 创建自定义组件主题扩展
**As a** 开发者 | **I want** 自定义组件的 style 通过 ThemeExtension 解析 | **So that** 组件可根据用户设置动态调整
- **Acceptance**: `river_custom_component_theme.dart` 包含 snackBarRadius/confirmDialogRadius/markdownEditorToolbarRadius 等属性，lerp() 已实现
- **Size**: M

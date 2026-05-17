---
session_id: SPEC-ui-unification-2026-05-17
phase: 5
document: epic
epic_id: EPIC-002
title: 核心自定义组件迁移
mapped_requirements: [REQ-002]
mapped_adrs: [ADR-002]
priority: P0
mvp: true
---

# EPIC-002: 核心自定义组件迁移

## Goal
将 7 个核心自定义组件从硬编码样式迁移到令牌 + 主题系统，建立迁移参考模式。

## Stories

### Story 2.1: RiverConfirmDialog 模板迁移
**As a** 开发者 | **I want** RiverConfirmDialog 成为首个迁移模板 | **So that** 建立迁移模式供后续组件参考
- **Acceptance**: 2 处硬编码 BR 替换为 RiverRadius.xl；硬编码 EdgeInsets 替换为 RiverSpacing；亮/暗模式验证通过
- **Size**: S (1 file, ~151 lines)

### Story 2.2: RiverSnackBar 语义色彩迁移
**As a** 用户 | **I want** SnackBar 的 success/error 色在暗黑模式下和谐显示 | **So that** 通知信息在所有主题下都可辨识
- **Acceptance**: 4 处硬编码 Color(0xFF...) 替换为 RiverSemanticColors.success/error 引用；亮/暗模式对比度达标
- **Size**: M (1 file, ~353 lines)

### Story 2.3: RiverImageViewer 叠加层迁移
**As a** 用户 | **I want** 图片查看器的背景遮罩和操作按钮在暗黑模式下正确显示 | **So that** 全屏看图时视觉体验一致
- **Acceptance**: 硬编码 Colors.white/black 替换为 colorScheme.surface/onSurface；叠加层迁移到 RiverSemanticColors.overlayBackground
- **Size**: M (2 files)

### Story 2.4: 选择器和按钮组件迁移
**As a** 用户 | **I want** 表情选择器、分类选择器、AI 按钮跟随用户圆角预设 | **So that** 外观设置真正全局生效
- **Acceptance**: RiverEmojiPicker、RiverCategoryPickerSheet、RiverPublishCategoryPickerSheet、RiverAIActionButton 的 BR 和颜色迁移完成
- **Size**: M (4 files)

### Story 2.5: RiverMarkdownEditor 令牌对齐
**As a** 用户 | **I want** 编辑器工具栏、预览卡、草稿弹窗跟随主题 | **So that** 编辑器与帖子详情页的视觉语言一致
- **Acceptance**: 36 处硬编码 BR + 多处硬编码 Colors 迁移到令牌和主题引用；编辑/预览/工具栏三种模式在亮/暗下验证
- **Size**: XL (1 file, ~2000 lines)

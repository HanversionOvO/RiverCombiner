---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: requirement
req_id: REQ-002
priority: must
status: complete
---

# REQ-002: 组件样式标准化

## User Story
As a **用户**，I want **所有页面和组件的视觉风格统一**，so that **我在不同模块之间切换时不会感到违和，设置中的外观偏好能全局生效**。

## Description

将 9 个特征模块和 7 个核心自定义组件中的硬编码样式迁移到主题系统：

**核心自定义组件**（`lib/core/widgets/`）：
- RiverConfirmDialog → 模板迁移（2 处 BorderRadius，作为后续参考模式）
- RiverSnackBar → 硬编码 success/error 颜色迁移到 RiverSemanticColors
- RiverImageViewer → 硬编码黑白叠加背景迁移
- RiverMarkdownEditor → 36 处 BorderRadius + 多处硬编码颜色（最复杂组件）
- RiverEmojiPicker、RiverCategoryPickerSheet、RiverAIActionButton → 少量修正

**特征模块**（按风险从低到高）：
- Wave 2: mine/settings（12 文件，设置页自身先遵守设置）
- Wave 3: notifications/chat（4 文件）
- Wave 4: search（2 文件）
- Wave 5: posts（9 文件，最复杂模块）
- Wave 6: compose/editor（最后迁移）

## Acceptance Criteria

- [ ] `lib/features/` 中零处 `Color(0xFF...)`（启动屏除外）
- [ ] `lib/features/` 中零处直接 `fontSize:` 字面量（不从 TextTheme 衍生的）
- [ ] `lib/features/` 中 BorderRadius 值均来自 RiverRadius 或 ThemeData
- [ ] `lib/core/widgets/` 中 7 个自定义组件均通过 Theme.of(context) 获取样式
- [ ] 所有迁移页面在亮/暗模式下验证通过
- [ ] 用户调整圆角预设后，所有迁移组件响应变化

## Traceability
- Product Brief Goal: 组件样式标准化
- Epic: EPIC-002 组件与特征模块迁移

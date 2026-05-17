---
session_id: SPEC-ui-unification-2026-05-17
phase: 5
document: epic
epic_id: EPIC-005
title: 主题增强与质量门禁
mapped_requirements: [REQ-003, NFR-usability-001, NFR-performance-001, NFR-maintainability-001]
mapped_adrs: [ADR-003]
priority: P2
mvp: false
---

# EPIC-005: 主题增强与质量门禁

## Goal
完成暗黑模式审计、补全组件主题覆盖、添加 lint/CI 门禁防止样式回归。

## Stories

### Story 5.1: 暗黑模式 WCAG AA 审计
**As a** 用户 | **I want** 暗黑模式下所有文字清晰可读 | **So that** 夜间刷帖不伤眼
- **Acceptance**: 5 页面 × 2 模式对比度检测；onSurfaceVariant 等低对比度问题修复；0 WCAG violations
- **Size**: M

### Story 5.2: 组件主题补全
**As a** 用户 | **I want** TabBar/Slider/Checkbox/Switch 也跟随主题 | **So that** 设置页和其他页面的内置组件不在"主题外"
- **Acceptance**: `_buildTheme()` 增加 tabBarTheme/sliderTheme/checkboxTheme/switchTheme 配置
- **Size**: S

### Story 5.3: custom_lint 规则与 CI 门禁
**As a** 团队 | **I want** 自动化手段防止硬编码样式回归 | **So that** 未来新增代码自动保持一致性
- **Acceptance**: `analysis_options.yaml` 增加 3 条 custom_lint 规则；`codemagic.yaml` CI 增加 lint 步骤；`flutter analyze` 在 CI 中失败时阻止合并
- **Size**: M

### Story 5.4: ReduceMotion 动画覆盖
**As a** 用户 | **I want** 开启减少动效后所有动画都被抑制 | **So that** 我对动效敏感的视觉需求被尊重
- **Acceptance**: 通知 banner 弹出/收起、聊天气泡 AnimatedSwitcher、浮动面板扇形展开 均检查 reduceMotion；reduceMotion=true 时直接跳到目标状态
- **Size**: M

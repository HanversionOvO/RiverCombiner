---
session_id: SPEC-ui-unification-2026-05-17
phase: 5
document: epic
epic_id: EPIC-003
title: 特征模块迁移 (Wave 1-3)
mapped_requirements: [REQ-002]
mapped_adrs: [ADR-002]
priority: P1
mvp: true
---

# EPIC-003: 特征模块迁移 (Wave 1-3)

## Goal
将 mine/settings、notifications/chat、search 模块从硬编码样式迁移到令牌系统，使 MVP 范围（80% 交互表面）完成统一。

## Stories

### Story 3.1: Mine/Settings 模块迁移
**As a** 用户 | **I want** 设置页自身遵守我的外观设置 | **So that** 我调整圆角和主题后，设置页也能立即反映变化
- **Acceptance**: 12 个文件迁移完成；设置页的 _SettingsCard/_SettingsSection 使用 RiverRadius token；亮/暗模式验证；圆角预设切换后设置页响应
- **Size**: L (12 files)

### Story 3.2: Notifications/Chat 模块迁移
**As a** 用户 | **I want** 通知和聊天页面的视觉密度与帖子页一致 | **So that** 我在阅读通知和回复私信时视觉节奏不变
- **Acceptance**: 4 个文件迁移完成；通知条目卡片圆角使用 RiverRadius.md；聊天气泡颜色使用 colorScheme.surface；padding 标准化
- **Size**: L (4 files)

### Story 3.3: Search 模块迁移
**As a** 用户 | **I want** 搜索页的卡片和筛选 Chip 跟随主题 | **So that** 搜索结果与帖子列表的视觉风格一致
- **Acceptance**: 2 个文件迁移完成；结果卡片 BR 使用 RiverRadius.md；Chip 使用 ChipTheme；高亮文字颜色使用 colorScheme.primary
- **Size**: M (2 files)

### Story 3.4: MVP 集成验证
**As a** 用户 | **I want** MVP 范围内的所有界面在亮/暗模式下无视觉问题 | **So that** 我可以放心升级
- **Acceptance**: 5 个关键页面（home、topic feed、notifications、chat、settings）在亮/暗模式下手动 QA；0 白屏闪现页面；圆角/字体预设切换验证
- **Size**: M

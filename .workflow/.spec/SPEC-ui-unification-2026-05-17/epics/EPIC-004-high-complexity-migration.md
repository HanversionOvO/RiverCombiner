---
session_id: SPEC-ui-unification-2026-05-17
phase: 5
document: epic
epic_id: EPIC-004
title: 高复杂度模块迁移 (Posts + Compose)
mapped_requirements: [REQ-002]
mapped_adrs: [ADR-002]
priority: P1
mvp: false
---

# EPIC-004: 高复杂度模块迁移 (Posts + Compose)

## Goal
将最复杂的 posts 和 compose 模块从硬编码样式迁移到令牌系统，完成全 App 统一。

## Stories

### Story 4.1: Posts Feed 页面迁移
**As a** 用户 | **I want** 帖子列表的卡片、标签、图片网格使用统一圆角和间距 | **So that** 滑浏览体验流畅一致
- **Acceptance**: `posts_page.dart` + `posts_page_widgets.dart` 的 34 处 BR + 3 处 fontSize + 硬编码 Colors 迁移完成
- **Size**: L (2 files)

### Story 4.2: Topic Detail 核心组件迁移
**As a** 用户 | **I want** 帖子正文、引用块、代码块使用统一的文本层级和圆角 | **So that** 深度阅读时不被打断
- **Acceptance**: `topic_detail_widgets_content.dart` + `topic_detail_widgets_meta.dart` + `topic_detail_widgets_images.dart` 迁移完成
- **Size**: L (3 files)

### Story 4.3: Topic Detail 交互组件迁移
**As a** 用户 | **I want** 反应选择器、操作栏、评论卡片使用统一样式 | **So that** 互动体验精致流畅
- **Acceptance**: `topic_detail_widgets_cards.dart` + `topic_detail_page_reactions.dart` + `topic_detail_page_actions.dart` 迁移完成
- **Size**: L (3 files)

### Story 4.4: Compose 编辑器迁移
**As a** 用户 | **I want** 编辑器与帖子详情页共享视觉语言 | **So that** 写帖和看帖之间自然过渡
- **Acceptance**: `compose_topic_page.dart` + `view.dart` + `actions.dart` 的 21+ 处硬编码迁移完成；标题输入框 fontSize 对齐 TextTheme.headlineSmall；渐变背景使用 ColorScheme token；亮/暗/compact/relaxed 四种组合验证
- **Size**: XL (3 files)

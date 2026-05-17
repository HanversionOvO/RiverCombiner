# Roadmap: river UI 统一

## Overview

将 river（清水河畔）从"10 个不同风格的屏幕合集"转变为"具有统一视觉语言的应用"。分 2 个阶段：Phase 1 交付 MVP（设计令牌 + 核心组件 + 中低风险模块迁移），Phase 2 完成高复杂度模块迁移和质量门禁。总规模 5 Epics / 22 Stories，预估 5-6 周。

## Phases

- [ ] **Phase 1: MVP — 基础设施 + 核心迁移** — 设计令牌系统、核心组件迁移、settings/notifications/search 模块统一
- [ ] **Phase 2: Complete — 高复杂度迁移 + 质量门禁** — posts/compose 迁移、暗黑模式审计、lint/CI 门禁

## Phase Details

### Phase 1: MVP — 基础设施 + 核心迁移
**Goal**: 建立设计令牌基础设施，迁移核心自定义组件和中低风险特征模块，使 80% 用户交互表面完成 UI 统一
**Depends on**: Nothing
**Requirements**: REQ-001, REQ-002, REQ-004
**Success Criteria** (what must be TRUE):
  1. 用户调整圆角预设后，主页/通知/聊天/设置页的卡片和组件均响应变化
  2. 暗黑模式下，home/topic feed/notifications/chat/settings 5 个关键页面 0 硬编码亮色背景
  3. 核心自定义组件（RiverConfirmDialog/RiverSnackBar/RiverEmojiPicker 等）在亮/暗模式下视觉一致
  4. 圆角值统一收敛到 6 级尺度（none/xs/sm/md/lg/xl），跨模块无 17 种不同值的现象

**Epics**:
| Epic | Title | Stories | Est. Days |
|------|-------|---------|-----------|
| EPIC-001 | 设计令牌基础设施 | 5 | 2 |
| EPIC-002 | 核心自定义组件迁移 | 5 | 4 |
| EPIC-003 | 特征模块迁移 (Wave 1-3) | 4 | 7 |
| **Total** | | **14** | **13** |

### Phase 2: Complete — 高复杂度迁移 + 质量门禁
**Goal**: 完成最复杂的 posts 和 compose 模块迁移，暗黑模式 WCAG AA 审计，添加 lint/CI 门禁防止样式回归
**Depends on**: Phase 1 (令牌和迁移模式已在实际模块中验证)
**Requirements**: REQ-002, REQ-003, NFR-usability-001, NFR-performance-001, NFR-maintainability-001
**Success Criteria** (what must be TRUE):
  1. 帖子详情页和编辑器的正文/引用/标题使用统一 TextTheme 层级
  2. 亮/暗模式下 5 个代表页面均通过 WCAG AA 对比度检测（0 violations）
  3. CI lint 门禁阻止 PR 引入新的 `Color(0xFF...)` 或硬编码 `fontSize:`
  4. 主题切换动画 220ms、无丢帧，reduceMotion 下所有动画被抑制
  5. `lib/features/` 中零处裸 `BorderRadius.circular(N)`（N 为字面量）

**Epics**:
| Epic | Title | Stories | Est. Days |
|------|-------|---------|-----------|
| EPIC-004 | 高复杂度模块迁移 | 4 | 8 |
| EPIC-005 | 主题增强与质量门禁 | 4 | 4 |
| **Total** | | **8** | **12** |

## Scope Decisions

- **In scope**: 设计令牌定义、7 核心组件迁移、9 特征模块迁移、暗黑模式修复、WCAG AA、lint/CI 门禁、布局间距标准化
- **Deferred**: 小程序 WebView 内部 UI 统一（Web 内容由第三方提供，暂不纳入）
- **Out of scope**: 全新视觉重设计、新组件开发、后端 API 变更、启动屏调色板变更

## Progress

| Phase | Status | Completed |
|-------|--------|-----------|
| 1. MVP — 基础设施 + 核心迁移 | Not started | — |
| 2. Complete — 高复杂度迁移 + 质量门禁 | Not started | — |

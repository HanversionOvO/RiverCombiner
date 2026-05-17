# Project: river（清水河畔）

## What This Is

面向高校学生的 Flutter 跨平台社区应用。用户可以发布 Markdown 话题、参与讨论、使用表情反应和投票互动，同时支持小程序生态扩展。覆盖 iOS 和 Android 双平台。

## Core Value

**内容质量** — 如果所有功能都失败，高效地发布和消费高质量内容这件事必须成功。所有优先级围绕创作者体验和内容消费体验展开。

## Requirements

### Validated

<!-- Shipped and confirmed valuable. 从现有代码库推断。 -->

- [x] 双通道登录（RiverSide 密码 + 清水河畔 OAuth/WebView）
- [x] 话题浏览/发布/回复/引用
- [x] Markdown 内容编辑器（含 AI 辅助写作）
- [x] 图片上传与管理（PicUI 图床集成）
- [x] 表情反应系统 + 投票
- [x] 实时通知推送 + 私信聊天
- [x] 小程序平台（安装/悬浮/权限管理/Codec）
- [x] 用户个人主页、徽章、活动记录
- [x] 综合设置（AI 提供商、外观字体、存储、服务器）
- [x] 搜索（帖子/用户/小程序）

### Active

<!-- Current scope being built toward. These are hypotheses until shipped. -->

- [ ] 内容创作体验增强 — 编辑器改进、图片管理流程、草稿同步、AI 辅助深化
- [ ] 体验与性能优化 — UI 升级（暗黑模式等）、字体系统完善、启动速度、内存优化、设置体验
- [ ] 小程序生态完善 — SDK 能力扩展、权限控制细化、安装流程优化、悬浮体验改进

### Out of Scope

<!-- Explicit boundaries. Include reasoning to prevent re-adding. -->

- 第三方社交平台深度集成（微信/QQ 登录）— 当前聚焦自有账号体系

## Context

项目已迭代至 v1.1.5，拥有 10 个功能模块、130 个 Dart 文件。采用 `lib/app/`（应用壳）、`lib/core/`（共享基础设施）、`lib/features/`（功能页面）三层架构。使用 ChangeNotifier 做状态管理，API 客户端通过扩展方法组织端点。CI/CD 已通过 Codemagic 配置。

## Constraints

- **API 兼容**: 必须保持与现有 RiverSide 服务器 API 的兼容性 — 核心后端接口不可变更
- **跨平台同步**: iOS 和 Android 必须同步发布 — 不可单平台先行

## Tech Stack

- **Language**: Dart (SDK ^3.10.8)
- **Framework**: Flutter
- **State Management**: ChangeNotifier (built-in)
- **HTTP Client**: http ^1.6.0
- **Local Storage**: shared_preferences ^2.5.4
- **Key Libraries**: webview_flutter, markdown, cached_network_image, qr_flutter, image_picker, wechat_assets_picker
- **CI/CD**: Codemagic

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 三层架构（app/core/features） | 核心层无 UI 依赖，功能层仅依赖核心层，清晰分层 | — Active |
| 扩展方法组织 API 端点 | 单 API Client + 按领域拆分的扩展方法，避免上帝类 | — Active |
| ChangeNotifier 状态管理 | 保持轻量，无第三方状态管理依赖 | — Active |

## Stakeholders

- 高校学生用户（清水河畔社区成员）

---
*Last updated: 2026-05-17 after initialization*

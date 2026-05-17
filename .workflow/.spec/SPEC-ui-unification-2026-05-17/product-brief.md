---
session_id: SPEC-ui-unification-2026-05-17
phase: 2
document: product-brief
version: 1.0.0
status: complete
created: 2026-05-17
updated: 2026-05-17
---

# Product Brief: river UI 统一 — 设计系统标准化

## Vision

将 river（清水河畔）从"10 个不同风格的屏幕合集"转变为"一个具有统一视觉语言的 App"。让高校学生用户在任何页面、任何模式下感受到一致的品质感——设置页遵守自己的设置、深色模式覆盖每一页、信息层级在所有场景下稳定可预测。

**UX North Star**: 用户从话题流 → 发帖 → 通知 → 聊天 → 个人主页的完整旅程中，永远不会产生"这个页面属于另一个 App"的违和感。

## Goals

1. **设计令牌系统**: 定义颜色、字体、圆角、间距的统一标准，作为所有 UI 代码的唯一引用源
2. **组件样式标准化**: 将 529 处硬编码 BorderRadius、48 处硬编码 fontSize、128+ 处硬编码颜色迁移到主题系统
3. **主题系统完善**: 覆盖所有 Flutter 内置组件主题、暗黑模式 WCAG AA 对比度、主题切换动画
4. **布局一致性**: 4px 基准栅格、统一页面 padding、卡片间距与信息层级

## Scope

### In Scope
- 设计令牌定义（radius scale、spacing scale、color tokens、type scale）
- 7 个核心自定义组件迁移（RiverSnackBar、RiverConfirmDialog、RiverMarkdownEditor、RiverImageViewer、RiverEmojiPicker、RiverCategoryPickerSheet、RiverAIActionButton）
- 9 个特征模块样式迁移（mine/settings、notifications、search、posts、compose 等）
- 暗黑模式对比度审计与修复
- custom_lint 规则 + CI 门禁
- 布局间距标准化

### Out of Scope
- Mini App WebView 内部 UI（第三方 Web 内容）
- 启动屏定制调色板（品牌化启动体验，保留当前设计）
- 全新视觉重设计（仅统一，不重设计）
- 全新动画/交互模式
- 后端 API 变更
- 全新组件开发

## Multi-Perspective Synthesis

### Convergent Themes (All Perspectives Agree)

| Theme | Product | Technical | User |
|-------|---------|-----------|------|
| 设计令牌是前提 | 统一标准防止再次分化 | 静态常量 + ThemeData 扩展的混合方案 | 用户看不见令牌，但感受得到节奏 |
| 渐进式迁移 | 核心组件先行、帖子页最后 | 7 波次迁移，每波独立验证 | 不中断使用体验 |
| 设置页是信任锚点 | 设置页先迁移、作为参考实现 | appearance_settings 是第 2 波次 | 设置页自身不遵守设置→信任崩塌 |
| 暗黑模式是基本要求 | 0 白屏闪现页面 | 审计所有 `.withOpacity()` 叠加行为 | 宿舍夜间使用的核心场景 |

### Conflicts & Resolutions

| Conflict | Resolution |
|----------|-----------|
| Product 认为启动屏应纳入统一 | Technical + User: 启动屏是品牌资产，保留当前调色板（Out of Scope） |
| Technical 倾向纯 ThemeExtension 方案 | Product + User: 混合方案（静态常量尺 + ThemeExtension 覆盖值），既可通过 lint 检测也可运行时解析 |

## Success Criteria

1. **SC-1**: 暗黑模式下 0 个页面出现硬编码亮色背景
2. **SC-2**: 用户调整圆角预设后，所有页面卡片/对话框/Chip/按钮/底部弹出/输入框均响应
3. **SC-3**: 用户调整字体缩放后，所有可读文字（含编辑器标题输入框）均响应
4. **SC-4**: 帖子详情页的正文/引用/标题使用统一的 TextTheme 层级
5. **SC-5**: 关键路径（浏览→阅读→回复→发帖）无视觉回归
6. **SC-6**: 亮/暗双模式下文字图标均满足 WCAG AA 对比度
7. **SC-7**: 主题切换动画 220ms、无丢帧
8. **SC-8**: CI lint 门禁阻止新增硬编码样式

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 帖子详情页视觉回归 | High | Critical | 增量迁移，取截图作为黄金参考 |
| 暗黑模式叠加行为异常 | Medium | High | 审计所有 `.withValues(alpha:)` 调用点 |
| 用户偏好语义变更 | Medium | Medium | 保持预设→数值映射不变 |
| Compose 编辑器回归 | Medium | High | 最后迁移，用真实 Markdown 内容验证 |
| 范围蔓延至重设计 | Medium | Medium | 严格 Code Review：diff 只允许 Token 替换 |

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| 混合令牌架构（静态常量 + ThemeExtension） | 常量尺可被 lint 规则验证；ThemeExtension 保留运行时主题解析和暗黑模式兼容 |
| `lib/core/theme/` 作为设计系统目录 | 新增目录，不影响现有代码结构 |
| 7 波次渐进迁移 | 核心组件先行降低风险，帖子/编辑器等高复杂度模块最后迁移 |
| custom_lint 在迁移完成后启用 | 避免迁移期间产生海量无关 lint 警告 |

---
status: complete
target: MVP (Phase 1 + Phase 2)
started: 2026-05-17
updated: 2026-05-17
---

## Tests

### 1. dart analyze 零错误
expected: `dart analyze lib/` 返回 0 errors, 0 warnings（仅 4 个 info 可忽略）
result: pass

### 2. 全项目零硬编码 BR
expected: 529 处硬编码数字 BR 全部替换为 RiverRadius 令牌常量
result: pass

### 3. 设计令牌文件完整性
expected: 3 个核心令牌文件结构正确
result: pass

### 4. ThemeExtension 注册
expected: _buildTheme() extensions 包含两个 ThemeExtension，亮/暗工厂正确切换
result: pass

### 5. CI Lint Gate 配置
expected: codemagic.yaml 包含样式门禁
result: pass

### 6. 暗黑模式 — 设置页无白屏
expected: dark 模式下设置页无硬编码白色背景
result: pass

### 7. 圆角预设 — 设置页卡片响应
expected: 切换圆角预设后设置页自身卡片圆角应变化
result: issue
reported: "分区容器圆角没有同步变化"
severity: minor
root_cause: >
  _SettingsSection 使用 `RiverRadius.xl`（静态常量）而非
  `Theme.of(context).extension<RiverCustomComponentTheme>()!.xxx`（运行时 ThemeExtension）。
  静态 RiverRadius 仅在编译期定义尺度，不响应用户的 cornerPreset 切换。
  只有通过 RiverCustomComponentTheme（scaleForPreset factory）获取的值才会随预设缩放。
fix_direction: >
  将 _SettingsSection 和 _SettingsCard 的 BR 从 RiverRadius.xl/md 静态常量
  改为通过 RiverCustomComponentTheme ThemeExtension 运行时解析。
  需要在 RiverCustomComponentTheme 中增加 settingsCardRadius 和 settingsSectionRadius 字段。
affected_files: ["lib/features/mine/mine_page_widgets.dart", "lib/features/mine/appearance_settings_widgets.dart", "lib/core/theme/river_custom_component_theme.dart"]
issue_id: ISS-20260517-001

### 8. 编辑器 — 工具栏圆角统一
expected: 编辑器工具栏/草稿/预览卡片圆角使用统一 6 级尺度
result: pass

## Summary

total: 8
passed: 7
issues: 1
skipped: 0

## Gaps

- test: 7
  truth: "切换圆角预设后设置页自身卡片圆角应变化"
  status: failed
  reason: "分区容器圆角没有同步变化 — 静态 RiverRadius 不连接 ThemeExtension"
  severity: minor
  root_cause: "静态 RiverRadius 常量不响应用户预设；需改为 ThemeExtension 运行时解析"
  fix_direction: "在 RiverCustomComponentTheme 中增加 settingsCardRadius/settingsSectionRadius 字段"
  affected_files: ["lib/features/mine/mine_page_widgets.dart", "lib/features/mine/appearance_settings_widgets.dart", "lib/core/theme/river_custom_component_theme.dart"]
  issue_id: ISS-20260517-001

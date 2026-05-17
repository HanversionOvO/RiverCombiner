---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: requirement
req_id: REQ-003
priority: should
status: complete
---

# REQ-003: 主题系统完善

## User Story
As a **用户**，I want **深色模式完全覆盖、主题切换流畅、所有组件主题可定制**，so that **我在夜间使用时眼睛舒适，整体体验精致无瑕**。

## Description

在令牌系统和组件迁移的基础上，增强主题系统：

1. **暗黑模式对比度**: 审计所有表面的文字/图标对比度，确保达到 WCAG AA（正文 4.5:1，大文字 3:1）
2. **组件主题覆盖**: 补全 _buildTheme() 中缺失的组件主题（tabBarTheme、sliderTheme、checkboxTheme、switchTheme）
3. **主题切换动画**: 确保 ThemeData 切换使用 220ms `themeAnimationDuration`、无丢帧
4. **reduceMotion 覆盖**: 通知 banner、聊天气泡、浮动面板的动画在 reduceMotion 下直接跳到目标状态
5. **字体粗细预设验证**: 确保 `_applyFontWeightPreset` 在迁移后的 TextTheme 体系下正确工作

## Acceptance Criteria

- [ ] 亮/暗模式 5 个代表页面均通过 WCAG AA 对比度检测
- [ ] `tabBarTheme`、`sliderTheme`、`checkboxTheme`、`switchTheme` 在 _buildTheme() 中配置
- [ ] 主题切换时 GPU 帧时间 < 16ms（5 次切换测试）
- [ ] reduceMotion 开启时：通知 banner 直接出现/消失、聊天气泡无动画、浮动面板无动画
- [ ] 所有字体粗细预设（regular/medium/bold）在各 TextTheme 层级上正确渲染

## Traceability
- Product Brief Goal: 主题系统完善
- Epic: EPIC-003 主题系统增强

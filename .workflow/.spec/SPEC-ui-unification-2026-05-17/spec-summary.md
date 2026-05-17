---
session_id: SPEC-ui-unification-2026-05-17
phase: 6
document: spec-summary
version: 1.0.0
status: complete
---

# Spec Summary: river UI 统一

## 一句话
统一 river App 的设计语言——将 55 个文件中 529+ 处硬编码样式迁移到统一的设计令牌和主题系统，让 10 个特征模块看起来像"同一个 App"。

## 问题
river 虽有集中式 `_buildTheme()` 主题系统（ColorScheme.fromSeed + 用户可配置圆角/字体），但各特征模块大量使用硬编码值绕过了它，导致暗黑模式半调子、圆角预设不生效、信息层级不统一。

## 方案
1. **建立设计令牌**（RiverRadius/RiverSpacing/RiverSemanticColors）
2. **渐进式迁移**（7 波次，低风险先行）
3. **完善主题**（暗黑模式 WCAG AA、组件主题补全、reduceMotion）
4. **门禁防回归**（custom_lint + CI）

## 规模
- 5 Epics / 22 Stories
- ~40 文件改动（130 总文件中）
- 预估 25 开发天 / 5-6 周
- MVP（Epic 001-003）：12 天，覆盖 80% 用户交互表面

## 关键决策
- **混合令牌架构**: 静态常量尺 + ThemeExtension 运行时解析
- **渐进式迁移**: 7 波次，核心组件先行，posts/compose 最后
- **语义色彩扩展**: success/error/overlay 等语义 token，非直接使用 ColorScheme.error

## 质量
- 准备度得分: **87.5% (PASS)**
- 4 项功能需求 + 3 项非功能需求
- 3 个 ADR（含替代方案对比）
- 完整可追踪矩阵（Goal→REQ→ADR→Epic）

## 下一步
运行 `maestro-plan 1` 开始规划第一阶段的执行。

---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: nfr
nfr_id: NFR-usability-001
type: usability
priority: must
status: complete
---

# NFR-usability-001: WCAG AA 对比度标准

## Requirement
亮色和暗色模式下，所有文字和图标 MUST 满足 WCAG AA 对比度标准：
- 正文文字（< 18pt）：对比度 >= 4.5:1
- 大文字（>= 18pt 或 >= 14pt bold）：对比度 >= 3:1

## Rationale
当前暗色模式存在硬编码 Colors.white/black 绕过 ColorScheme 的情况，以及部分 seed color 生成的暗色方案中 onSurfaceVariant 对比度可能低于阈值。

## Verification
- 工具：Flutter Accessibility Inspector 或手动计算
- 范围：topic feed、topic detail、compose editor、notifications、settings（5 页面 × 2 模式 = 10 组合）
- Gate: 0 violations

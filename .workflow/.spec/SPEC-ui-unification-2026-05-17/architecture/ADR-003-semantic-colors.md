---
session_id: SPEC-ui-unification-2026-05-17
phase: 4
document: adr
adr_id: ADR-003
title: 语义色彩 Token 扩展
status: accepted
---

# ADR-003: 语义色彩 Token 扩展

## Context
当前 ColorScheme 不包含 success/overlayBackground 等语义 token。RiverSnackBar 硬编码 `Color(0xFFDC2626)`（红）和 `Color(0xFF16A34A)`（绿），编辑器和其他弹窗硬编码 `Colors.black.withValues(alpha: 0.5)` 做遮罩。

## Decision
扩展 `ColorScheme` 语义色彩，创建 `RiverSemanticColors` ThemeExtension：

```dart
class RiverSemanticColors extends ThemeExtension<RiverSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color overlayBackground;    // 替代 Colors.black.withOpacity(0.5)
  final Color overlayOnBackground;
}
```

亮/暗变体从 seedColor 推导，确保与 ColorScheme 保持色调协调。

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A: 直接使用 ColorScheme.error/tertiary 等现有角色** | 无需新代码 | 语义不匹配（红色≠成功，绿色≠错误） | Rejected |
| **B: 保持硬编码** | 无变更 | 暗黑模式不可用 | Rejected |
| **C: ThemeExtension 扩展（选定）** | 语义正确、暗黑模式兼容、类型安全 | 需要额外样板代码 | **Accepted** |

## Consequences
- 4-6 个新色彩 token
- RiverSnackBar 的 success/error 色迁移到 RiverSemanticColors
- 弹窗遮罩统一使用 overlayBackground

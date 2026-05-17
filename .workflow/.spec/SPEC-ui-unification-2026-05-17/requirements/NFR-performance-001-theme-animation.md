---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: nfr
nfr_id: NFR-performance-001
type: performance
priority: should
status: complete
---

# NFR-performance-001: 主题切换动画性能

## Requirement
主题切换和相关 UI 变更 MUST NOT 引入额外丢帧：
- 主题切换动画 220ms 期间，所有帧 GPU 时间 < 16ms
- AnimatedTheme 过渡不应触发不必要的 rebuild

## Rationale
_applyFontWeightPreset 和 _applyFontVariationPreset 在 _buildTheme() 中操作 TextTheme。如果这些计算过于昂贵或迁移后主题解析链路变长，可能导致主题切换卡顿。

## Verification
- 工具：Flutter DevTools frame timeline
- 测试：5 次 light/dark 切换，记录 GPU 帧时间
- Gate: 0 帧超过 16ms

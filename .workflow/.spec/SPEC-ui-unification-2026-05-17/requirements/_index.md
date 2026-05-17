---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: requirements-index
version: 1.0.0
status: complete
---

# Requirements Index — river UI 统一

## MoSCoW Priority Summary

| Priority | Count | IDs |
|----------|-------|-----|
| **Must** | 2 | REQ-001, REQ-002 |
| **Should** | 2 | REQ-003, REQ-004 |
| **Could** | 0 | — |
| **Won't** | 0 | — |

## Functional Requirements

| ID | Title | Priority | Epic |
|----|-------|----------|------|
| REQ-001 | 设计令牌系统 | Must | EPIC-001 |
| REQ-002 | 组件样式标准化 | Must | EPIC-002 |
| REQ-003 | 主题系统完善 | Should | EPIC-003 |
| REQ-004 | 布局一致性 | Should | EPIC-004 |

## Non-Functional Requirements

| ID | Type | Description |
|----|------|-------------|
| NFR-usability-001 | Usability | WCAG AA 对比度标准 |
| NFR-performance-001 | Performance | 主题切换 60fps |
| NFR-maintainability-001 | Maintainability | lint 规则防止回归 |

## Traceability Matrix

| Requirement | product-brief Goal | Architecture ADR | Epic |
|-------------|-------------------|-----------------|------|
| REQ-001 | 设计令牌系统 | ADR-001 令牌架构 | EPIC-001 |
| REQ-002 | 组件样式标准化 | ADR-002 迁移策略 | EPIC-002 |
| REQ-003 | 主题系统完善 | ADR-003 语义色彩 | EPIC-003 |
| REQ-004 | 布局一致性 | ADR-001 令牌架构 | EPIC-004 |

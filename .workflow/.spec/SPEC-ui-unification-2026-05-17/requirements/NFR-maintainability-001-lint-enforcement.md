---
session_id: SPEC-ui-unification-2026-05-17
phase: 3
document: nfr
nfr_id: NFR-maintainability-001
type: maintainability
priority: must
status: complete
---

# NFR-maintainability-001: Lint 规则防止样式回归

## Requirement
新增 UI 代码 MUST NOT 使用硬编码样式值。通过 custom_lint 规则 + CI 门禁强制执行：
- 禁止 `lib/features/` 和 `lib/core/widgets/` 中直接使用 `Color(0x...)`
- 禁止硬编码 `Colors.white`、`Colors.black`、`Colors.grey`
- 禁止 `BorderRadius.circular(N)` 的 N 为字面量（除非来自 RiverRadius 常量）
- 禁止 `fontSize: N` 的字面量赋值（除非通过 TextTheme 衍生）

## Rationale
迁移完成后，若无自动化门禁，新增代码将再次引入硬编码样式，导致问题复发。

## Implementation
- 工具：`custom_lint` Dart 插件
- 配置：`analysis_options.yaml`
- CI：`codemagic.yaml` 增加 lint 检查步骤
- 启用时机：迁移 Phase 3（lint + CI setup）完成后启用

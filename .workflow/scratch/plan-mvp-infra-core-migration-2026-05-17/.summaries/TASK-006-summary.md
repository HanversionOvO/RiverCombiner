# TASK-006 Summary
**Status**: completed
**Commit**: pending

## What was done
Migrated RiverImageViewer components to design tokens:
- `river_image_viewer_components.dart`: BR(14)→RiverRadius.md, BR(10)→RiverRadius.sm, BR(16)→RiverRadius.lg, BR(8)→RiverRadius.sm
- `river_image_viewer.dart`: Added `import river_design_tokens.dart`

Note: Image viewer canvas colors (Colors.black for background) intentionally preserved — these are the viewing surface, not UI chrome themeable elements.

## Verification
- `dart analyze lib/core/widgets/` — No issues found

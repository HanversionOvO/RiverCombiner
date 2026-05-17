# TASK-003 Summary
**Status**: completed
**Commit**: pending

## What was done
Modified `lib/app/app.dart` _buildTheme() to register two ThemeExtension instances:
- Added imports for `river_semantic_colors.dart` and `river_custom_component_theme.dart`
- Added `extensions:` parameter in `base.copyWith()` with `RiverSemanticColors.light()/.dark()` (brightness-aware) and `RiverCustomComponentTheme.scaleForPreset()` (corner-preset-aware)

## Verification
- `dart analyze lib/app/app.dart` — No issues found
- Theme.of(context).extension<T>() now resolvable for both extension types

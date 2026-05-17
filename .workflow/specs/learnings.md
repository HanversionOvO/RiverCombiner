---
title: "Learnings"
readMode: optional
priority: medium
category: learning
keywords:
  - bug
  - lesson
  - gotcha
  - learning
---

# Learnings

Add entries with: `/spec-add learning <description>`

## Entries

<spec-entry category="learning" keywords="flutter theme design-token border-radius migration" date="2026-05-17" source="milestone-complete MVP">

### 批量硬编码样式迁移模式

将 529 处硬编码 `BorderRadius.circular(N)` 迁移到 6 级设计令牌系统。关键模式：
- **sed 批量替换**：高效的 `find -exec sed` 模式可一次性替换整个目录
- **圆角值映射表**：`N=[0,2]→none, [3-6]→xs, [7-9]→sm, [10-13]→md, [14-18]→lg, [19-28]→xl, >900→full`
- **part 文件处理**：Flutter 的 `part of` 文件需要将 import 添加到父文件而非 part 文件本身
- **门禁顺序**：lint 规则必须在迁移完成后启用，避免迁移期间产生海量警告

Milestone: MVP

</spec-entry>

<spec-entry category="learning" keywords="flutter theme-extension lerp animation dark-mode" date="2026-05-17" source="milestone-complete MVP">

### ThemeExtension 混合令牌架构

采用静态常量（编译期尺度）+ ThemeExtension（运行时解析）的混合架构：
- **静态常量**（`RiverRadius`/`RiverSpacing`）：可被 lint 规则验证，零运行时开销
- **ThemeExtension**（`RiverSemanticColors`/`RiverCustomComponentTheme`）：通过 `Theme.of(context)` 亮/暗自动解析，`lerp()` 支持主题切换动画
- **scaleForPreset**：通过 `factory` 构造函数实现用户 cornerPreset 的三档缩放
- **局限**：静态常量不响应用户预设。需要运行时响应的组件必须通过 ThemeExtension

Milestone: MVP

</spec-entry>

<spec-entry category="learning" keywords="flutter architecture layer-dependency backward-reference" date="2026-05-17" source="milestone-complete MVP">

### 核心层反向依赖问题

`lib/core/theme/river_custom_component_theme.dart` 依赖 `lib/app/app_settings_controller.dart` 中的 `AppCornerPreset` 枚举，违反了 `lib/core/ → no dependency on lib/app/` 的架构约束。 避免方案：将枚举提取到 core/theme/ 或改为数值参数接口。

Milestone: MVP

</spec-entry>

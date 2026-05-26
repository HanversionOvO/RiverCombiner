# River UI 设计规范

基于项目现有 UI 实践提炼的规范。所有新 UI 开发必须遵循本规范。

---

## 1. 颜色系统

**三层架构，优先级从高到低：**

| 层级 | 来源 | 适用范围 | 获取方式 |
|------|------|----------|----------|
| L1 | Material 3 ColorScheme | 通用 UI 色（primary/secondary/surface/error 等） | `Theme.of(context).colorScheme.*` |
| L2 | RiverSemanticColors | 功能语义色（success/error/overlay） | `Theme.of(context).extension<RiverSemanticColors>()!` |
| L3 | 特定场景色 | 启动屏、AI 渐变等固定装饰色 | `static const` 在使用类内定义 |

**禁止项：**
- `lib/features/` 和 `lib/core/widgets/` 中禁止 `Color(0xFF...)` 硬编码
- 禁止 `Colors.grey`、`Colors.redAccent` 等直接使用 — 使用对应 `colorScheme` slot
- `Colors.white` / `Colors.black` 仅允许用于图片覆盖层半透明渐变（如 `.withValues(alpha: 0.5)`）

**Seed 色系统：**
- 默认种子色 `0xFF12457A`，用户可选 8 种预设
- 全部 M3 色板由 `ColorScheme.fromSeed(seedColor: ...)` 自动生成
- 不手动定义 primary/secondary 等色值

---

## 2. 字体排版

**规范用法：**
- 使用 `Theme.of(context).textTheme.*` 的语义 slot
- 常用 slot 映射：

| TextTheme Slot | 典型用途 | M3 默认大小 |
|----------------|----------|-------------|
| `headlineSmall` | 页面主标题、启动屏标题 | 24dp |
| `titleLarge` | 大号标题 | 22dp |
| `titleMedium` | 区段标题、卡片标题 | 16dp |
| `titleSmall` | 小号标题 | 14dp |
| `bodyLarge` | 正文大号 | 16dp |
| `bodyMedium` | 通用正文 | 14dp |
| `bodySmall` | 辅助文本 | 12dp |
| `labelLarge` | 按钮/芯片标签 | 14dp |
| `labelMedium` | 中号标签 | 12dp |
| `labelSmall` | 极小标签、徽章 | 11dp |

- 用 `.copyWith()` 修改个别属性（如 fontWeight、color），不替换 fontSize
- 字号缩放通过 `TextScaler.linear(settings.fontScale)` 全局生效

**禁止项：**
- `lib/features/` 和 `lib/core/widgets/` 中禁止 `fontSize: N` 硬编码
- 如需偏离 TextTheme 默认值，用 `.copyWith(fontSize: ...)` 并注明原因

**字族与字重：**
- 默认字族 `HarmonyOS Sans`，用户可切换系统字体
- 字重缩放通过 `fontWeightScale` (-3 到 +3) 和 `FontVariation('wght', ...)` 双通道生效

---

## 3. 间距与圆角

**圆角 — 三级体系：**

| 级别 | 获取方式 | 适用场景 |
|------|----------|----------|
| 静态常量 | `RiverRadius.*` | 通用圆角（xs=4, sm=8, md=12, lg=16, xl=24, full=999） |
| 组件插槽 | `RiverCustomComponentTheme.*` | 11 个特定组件圆角（snackBar/confirmDialog/markdownEditor*/imageViewer/categoryPicker/emojiPicker/aiActionButton/settingsSection/settingsCard） |
| 内联特殊值 | `BorderRadius.circular(N)` 仅允许在 `lib/app/` 和非 UI 模块 | 特殊需求值如 28、30 |

**选择原则：**
- 有组件插槽 → 用组件插槽（会随 corner preset 缩放）
- 无组件插槽但有匹配常量 → 用 `RiverRadius.*`
- 两者皆无 → 评估是否需要添加新插槽或常量

**间距：**
- 定义：`RiverSpacing.*`（xs=4, sm=8, md=12, lg=16, xl=24, xxl=32）
- 当前实践主要使用 `SizedBox(height/width: N)` 和 `EdgeInsets.*` 内联数值
- **新代码应优先使用 `RiverSpacing.*`**，逐步替换现有内联数值

**禁止项：**
- `lib/features/` 和 `lib/core/widgets/` 中禁止 `BorderRadius.circular(N)` 硬编码数值

---

## 4. 共享组件 API 规范

**命名：** `River` 前缀 + PascalCase

**对话框模式：**
```dart
// 顶层异步函数，返回 Future<T?>
Future<bool?> showRiverConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  // 可选参数用合理默认值
});
```

**SnackBar 模式：**
```dart
// Extension on ScaffoldMessengerState
extension RiverSnackBarMessenger on ScaffoldMessengerState {
  void showRiverSnackBar(String text, {RiverSnackBarTone? tone});
}
```

**全屏查看器模式：**
```dart
// 静态方法打开，传入数据模型列表
static Future<void> open(
  BuildContext context,
  {required List<RiverImageViewerItem> items, int initialIndex = 0}
);
```

**数据模型：**
- `River*Item`、`River*Payload`、`River*Action` 前缀
- `@immutable` + `const` 构造函数 + `copyWith()`

---

## 5. 页面布局

**Scaffold 规范：**
- 主页面：`Scaffold(extendBody: true)` + 透明 NavigationBar
- 设置页面：使用 `MineSettingsPageScaffold`（iOS 用 AdaptiveScaffold）
- 详情页面：`Scaffold` + `CustomScrollView` + `SliverAppBar`
- 全屏查看器：`Scaffold(backgroundColor: Colors.black)` + `SystemUiOverlayStyle.light`

**Bottom Sheet 规范：**
- `showModalBottomSheet(backgroundColor: Colors.transparent)`
- 内容包裹：`SafeArea(top: false)` + `Material` + `RiverRadius.xl` 圆角 + `Clip.antiAlias`
- Drag Handle：`Container(width: 44, height: 4)` 药丸形

---

## 6. 图标

- **首选 `Icons.*_rounded`**（712 次使用 vs CupertinoIcons 2 次）
- iOS 26+ 原生 tab bar 使用 SF Symbols（通过 adaptive_platform_ui）
- 不引入新图标库，不使用 `IconData(0x...)` 硬编码

---

## 7. 动画

**曲线：**
- `Curves.easeOutCubic` — 出场/前进
- `Curves.easeInCubic` — 入场/后退
- `Curves.easeOutBack` — 缩放入场（微 overshoot）
- `Curves.easeInOutCubic` — 对称过渡

**时长：**
- 快速：180-220ms
- 标准：260ms
- 较大：360-520ms

**Reduce Motion：**
- 根层级已通过 `settings.reduceMotion` 处理
- **新代码必须检查 reduceMotion**：使用 `Duration.zero` 和跳过动画控制器

---

## 8. 深色模式

- 全局通过 `ColorScheme.fromSeed(seedColor, brightness)` 生成
- `RiverSemanticColors.light()` / `.dark()` 工厂提供语义色
- **禁止在 feature 代码中使用 `theme.brightness == Brightness.dark` 分支** — 应将颜色定义在 Theme 或 ThemeExtension 中
- 图片覆盖层渐变中 `Colors.white.withValues(alpha:...)` 在两种模式下均可使用

---

## 9. 边到边 & 系统栏

- `SystemUiMode.edgeToEdge` + 透明 status/navigation bar
- Android 使用 `AnnotatedRegion<SystemUiOverlayStyle>` 覆盖整个 app
- `contrastEnforced: false` 在两种栏上
- 全屏查看器切换为 `SystemUiOverlayStyle.light`

---

## 10. 响应式 & 密度

- 紧凑密度：`VisualDensity.compact` 影响 AppBar/NavBar/ListTile/Input
- 字号缩放：`TextScaler.linear(settings.fontScale)` (0.85-1.4)
- 圆角预设：compact(0.71x) / standard(1.0x) / relaxed(1.43x) 通过 `RiverCustomComponentTheme.scaleForPreset()` 缩放
- 所有设置通过 `AnimatedBuilder(animation: settingsController)` 在 MaterialApp 层全局重建
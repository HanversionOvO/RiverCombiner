# River 代码编写规范

基于项目现有代码实践提炼的规范。所有新代码必须遵循本规范。

---

## 1. 状态管理

**Store 规范：**
- 所有 Store 继承 `ChangeNotifier`
- 异步初始化：`Future<void> initialize({required Future<SharedPreferences> sharedPreferencesFuture})`
- State mutation 后调用 `notifyListeners()`
- 持久化：`unawaited(_saveX())` fire-and-forget（UI 先更新，磁盘 I/O 后台）
- Getter 返回 `List.unmodifiable()` 防止外部修改

**Dispose 规范：**
- 每个 `addListener` 必须在 `dispose()` 中有对应 `removeListener`
- 使用 `_disposed` 标志防止异步操作完成后误操作
- Controller 按 `initState` 创建的反序 dispose

**UI 绑定规范：**
- 使用 `AnimatedBuilder(animation: store, builder: (context, _) { ... })`
- 第二参数用 `_` 表示不使用 child
- 仅包裹需要响应 store 变化的子树，不包裹整个页面

**setState 安全：**
- async gap 后的 `setState` 前必须检查 `if (!mounted) return;`
- 使用 `_mutateState(VoidCallback action)` 包装（含 mounted 检查）
- 不使用无 mounted 检查的 `_setState` 别名

---

## 2. 依赖注入

**AppDependencies 规范：**
- 单一手动 DI 容器，通过 `required` 构造参数传入所有页面
- Constructor 注入的 Store 用 `required`；late 创建的 Store 用 `late final`
- 无 InheritedWidget / Provider / get_it

**新增 Store 步骤：**
1. 在 `AppDependencies` 中添加字段（required 或 late）
2. 在 `_RiverAppState.initState()` 中创建并传入
3. 在 `_RiverAppState.dispose()` 中添加 dispose 调用
4. 所有需要该 Store 的页面添加 `required this.dependencies` 构造参数

---

## 3. 页面结构

**文件组织：**

| 文件类型 | 命名 | 职责 |
|----------|------|------|
| 主文件 | `feature_name_page.dart` | StatefulWidget + State class + `build()` 委托 |
| Actions part | `feature_name_page_actions.dart` | 业务逻辑方法（网络请求、状态变更） |
| View part | `feature_name_page_view.dart` | `_buildPage()` / `_buildXxx()` widget 构建方法 |
| UI part | `feature_name_page_ui.dart` | 辅助子 widget（可选，复杂页面使用） |
| Widgets part | `feature_name_page_widgets.dart` | 私有子 widget class（可选） |

**Part 文件规范：**
- 主文件声明 `part 'xxx.dart';`
- Part 文件首行 `part of 'main_file.dart';`
- Part 文件使用 `extension _XxxPageActions on _XxxPageState { ... }` 定义方法
- Part 文件**不包含任何 import**（继承主文件的 imports）

**build() 委托：**
```dart
@override
Widget build(BuildContext context) {
  return _buildPage(context); // 在 _View extension 中定义
}
```

---

## 4. API Client

**结构规范：**
- `RiverSideApiClient` 为单类，所有域方法通过 `part` 文件中的 `extension` 添加
- 每个 domain 一个 part 文件：`riverside_api_client_xxx.dart`

**方法命名：**

| 操作类型 | 前缀 | 示例 |
|----------|------|------|
| GET/读取 | `fetch` | `fetchTopicSummaries`, `fetchUserProfile` |
| POST/创建 | `create` | `createTopic` |
| PUT/状态变更 | `mark` | `markNotificationsAsRead` |
| DELETE | `delete` | `deleteComposerDraft` |

**解析辅助函数：**
- `_toStringMap(dynamic)` → `Map<String, dynamic>`
- `_asInt(dynamic)` → `int?`
- `_asBool(dynamic)` → `bool`
- 这些函数容忍 API 格式不一致（int-as-string, bool-as-string）

**错误处理：**
- 非 200 状态码抛出 `RiverSideApiException(message)`
- 403 → session expired 专用消息
- 422 → 解析 validation error message

---

## 5. Widget 构建

**原则：**
- 每个 `build` 方法开头：`final theme = Theme.of(context);` + `final colorScheme = theme.colorScheme;`
- 需要语义色时：`final semantic = theme.extension<RiverSemanticColors>()!;`
- 需要组件主题时：`final compTheme = theme.extension<RiverCustomComponentTheme>()!;`

**const 优先：**
- `const SizedBox.shrink()` / `const EdgeInsets.all(N)` / `const Duration(milliseconds: N)`
- 能 const 就 const，不能 const（依赖 Theme）就不加

**提取 vs 内联：**
- 可复用子 widget → 提取为私有 `StatelessWidget`（如 `_SkeletonBox`）
- 一次性局部 widget → 用 `_buildXxx()` 方法内联
- 不过度提取 — 三行以内不值得独立 class

---

## 6. 异步与错误处理

**Mounted 检查规范：**
```dart
final result = await someAsyncOperation();
if (!mounted) return;
setState(() { ... });
```

**请求取消（requestSerial 模式）：**
```dart
final serial = ++_requestSerial;
// ... async work ...
if (!mounted || serial != _requestSerial) return;
setState(() { ... });
```

**错误展示：**
- 使用 `ScaffoldMessenger.of(context).showRiverSnackBar(message)`
- 自动推断 tone（'失败'/'错误'/'error' → error tone）
- 明确指定：`tone: RiverSnackBarTone.error`

**catch 规范：**
- 明确捕获 `RiverSideApiException` 处理业务错误
- `catch (_)` 仅用于"不应阻断启动/恢复"的场景，**必须注释原因**
- 不允许空 catch body 无注释

---

## 7. 导航

**路由选择：**

| 场景 | 路由类型 |
|------|----------|
| 普通页面 push | `riverPageRoute<T>(builder: ...)` → CupertinoPageRoute |
| 全屏对话框 | `riverPageRoute<T>(builder: ..., fullscreenDialog: true)` → MaterialPageRoute |
| 可拖拽关闭的详情页 | `DraggableRoute<void>(builder: ...)` |
| 不可 swipe-back 的页面 | `riverPageRoute<T>(builder: ..., enableFullScreenSwipeBack: false)` |

**RouteAware（仅用于需要导航生命周期感知的页面）：**
- `didPush()` / `didPopNext()` / `didPushNext()` / `didPop()`
- 在 `didChangeDependencies()` 中订阅 `RiverRouteObserver.instance`
- 在 `dispose()` 中取消订阅

---

## 8. 命名约定

**文件：** snake_case — `compose_topic_page.dart`, `river_mini_app_floating_store.dart`

**类：**
| 类型 | 前缀/后缀 | 示例 |
|------|-----------|------|
| 页面 Widget | PascalCase | `ComposeTopicPage` |
| 页面 State | `_` + PascalCase | `_ComposeTopicPageState` |
| Store | `*Store` | `AccountStore`, `TopicFootprintStore` |
| Service | `*Service` | `RiverSideRealtimeInboxService` |
| Controller | `*Controller` | `AppSettingsController` |
| Bridge | `*Bridge` | `RiverSideCookieBridge` |
| 数据模型 | `River*` 或直接 | `RiverSideTopicSummary`, `UserAccount` |
| Extension（私有） | `_` + PascalCase | `_ComposeTopicPageActions` |
| Extension（公开） | `River*Methods` | `RiverSideApiClientTopicMethods` |

**私有成员：** `_` prefix — `_loading`, `_fetchTopicSummaries()`, `_storageKeyAccounts`

**常量：**
- 私有 static const: `_storageKeyAccounts`, `_chatGlobalRealtimeChannel`
- 公开 static const: `defaultSeedColor`, `defaultFontFamilyName`

---

## 9. Import 排序

```
1. dart:* (SDK)
2. package:flutter/* (框架)
3. package:* (第三方)
4. package:river/* (项目)
5. part directives
```

- 项目内部一律使用 `package:river/...` 绝对路径，不使用相对路径
- Part 文件无 import（继承主文件）

---

## 10. 数据模型

**规范模式：**
```dart
@immutable
class RiverSideTopicSummary {
  const RiverSideTopicSummary({
    required this.id,
    required this.title,
    this.categoryId,
  });

  final int id;
  final String title;
  final int? categoryId;

  RiverSideTopicSummary copyWith({int? id, String? title, int? categoryId}) {
    return RiverSideTopicSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
    );
  }
}
```

- `@immutable` 注解 + `const` 构造函数 + `final` 字段
- `copyWith()` 用于不可变更新
- 不使用 json_serializable / freezed — 手写 fromJson/toJson
- `fromJson` 返回 `T?`（容错），不 throw

**Enum：**
- 简单 enum 无关联数据
- 显示标签通过 extension 提供
- 私有 enum 可在 State 类内定义

---

## 11. SharedPreferences 设置

**AppSettingsController 模式：**
```dart
// Getter — 直接返回字段
ThemeMode get themeMode => _themeMode;

// Setter — update 前缀 + equality early return + notify + unawaited save
void updateThemeMode(ThemeMode value) {
  if (_themeMode == value) return;
  _themeMode = value;
  notifyListeners();
  unawaited(_saveThemeMode());
}

// Key — 私有 static const, 'app.' 前缀
static const String _themeModeKey = 'app.theme_mode';

// Default — 字段初始化
ThemeMode _themeMode = ThemeMode.system;
```

**版本化 Key：** 复杂数据用 `.v1` 后缀 — `'river.accounts.v1'`
**迁移 Key：** 旧 Key 用 `_legacy` 前缀标记

---

## 12. Platform Bridge

**新增 Bridge 步骤：**
1. 在 `lib/core/platform/` 创建新文件
2. 定义类（有状态用实例构造函数，纯静态用私有构造函数 `ClassName._()`）
3. `static const MethodChannel _channel = MethodChannel('river/your_feature');`
4. 异步方法：`try { return await _channel.invokeMethod<T>(...); } catch (_) { return fallback; }`
5. 平台检查：`if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)`
6. Channel 命名：`river/` 前缀 — `river/webview_cookies`, `river/app_icon`

---

## 13. 代码质量底线

**必须：**
- `flutter analyze lib/` 零 error 零 warning（`unused_element` 可用 `// ignore` 注释保留有意保留的代码）
- async gap 后必须有 mounted 检查
- 所有 ChangeNotifier listener 必须在 dispose 中 remove
- 不允许无注释的空 catch body

**禁止：**
- `lib/features/` 和 `lib/core/widgets/` 中禁止硬编码 `BorderRadius.circular(N)`、`Color(0xFF...)`、`fontSize: N`
- 禁止 `// ignore_for_file: use_build_context_synchronously` 文件级抑制
- 禁止引入新的状态管理框架（Riverpod/Provider/BLoC）
- 禁止引入 json_serializable / freezed 代码生成（保持手动解析）
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
flutter pub get                    # Install dependencies
flutter run                        # Run on connected device
flutter analyze                    # Static analysis (lint + custom_lint)
flutter test                       # Run tests (currently minimal)
```

No Makefile or shell scripts exist. CI runs via CodeMagic (`codemagic.yaml`).

## Architecture Overview

**State Management**: `ChangeNotifier` + `ListenableBuilder`/`AnimatedBuilder`. No Riverpod/Provider/BLoC. All stores extend `ChangeNotifier`; UI rebuilds via `AnimatedBuilder(animation: store, builder: ...)`.

**Dependency Injection**: Manual constructor-passing through `AppDependencies` (`lib/app/app_dependencies.dart`). Created once in `_RiverAppState.initState()` and threaded as a required parameter to every page widget. No service locator or context-based DI.

**Routing**: Imperative `Navigator.push` with `riverPageRoute<T>()` helper (`lib/core/navigation/river_page_route.dart`). Returns `CupertinoPageRoute` (iOS swipe-back) or `MaterialPageRoute`. `DraggableRoute` from vendored `third_party/draggable_route/` for hero-style transitions. `RiverRouteObserver` singleton registered as navigator observer. No GoRouter/auto_route.

**API Client**: Single `RiverSideApiClient` class with 14 `part` files — each domain (profile, topics, posts, reactions, chat, search, etc.) is a Dart `extension` on the main class. All HTTP calls use the `http` package directly with cookie-based and user-api-key-based auth.

**Page Pattern**: Feature pages use `part` files to separate concerns. A page's `State` class lives in the main file; action methods go in `*_actions.dart` part files; UI building goes in `*_view.dart` or `*_ui.dart` part files. Part files use `_setState` alias.

## Design Token System (Mandatory)

**Never hardcode** `BorderRadius.circular(N)`, `Color(0xFF...)`, or `fontSize: N` in `lib/features/` or `lib/core/widgets/` — CI rejects these.

Three layers of tokens:

1. **Static constants** (`lib/core/theme/river_design_tokens.dart`):
   - `RiverRadius`: none=0, xs=4, sm=8, md=12, lg=16, xl=24, full=999
   - `RiverSpacing`: xs=4, sm=8, md=12, lg=16, xl=24, xxl=32

2. **RiverSemanticColors** ThemeExtension (`lib/core/theme/river_semantic_colors.dart`):
   - Access via `Theme.of(context).extension<RiverSemanticColors>()!`
   - Provides: success/onSuccess/successContainer, error/onError/errorContainer, overlayBackground/overlayOnBackground

3. **RiverCustomComponentTheme** ThemeExtension (`lib/core/theme/river_custom_component_theme.dart`):
   - Access via `Theme.of(context).extension<RiverCustomComponentTheme>()!`
   - 11 per-component BorderRadius slots (snackBar, confirmDialog, markdownEditor*, imageViewer, categoryPicker, emojiPicker, aiActionButton, settingsSection, settingsCard)
   - Scales with `AppCornerPreset` (compact/standard/relaxed)

For colors, always use `Theme.of(context).colorScheme.*` or `RiverSemanticColors`. For font sizes, use `Theme.of(context).textTheme.*`. For radii, use `RiverRadius.*` constants or `RiverCustomComponentTheme` slots.

## Key Source Layout

```
lib/
  main.dart                          # Entry point, edge-to-edge, ToastificationWrapper
  app/
    app.dart                         # RiverApp widget, theme building, root MaterialApp
    app_dependencies.dart            # Manual DI container + PostsStartupPreloadStore
    app_settings_controller.dart     # 30+ settings persisted via SharedPreferences
  core/
    account/                         # UserAccount models, AccountStore (multi-account, multi-provider)
    config/server_config.dart        # RiverServerConfig singleton (base URLs)
    mini_apps/                       # Mini app models, stores (floating/host/install/permission), platform client
    network/                         # RiverSideApiClient + 14 extension part files + model files
    navigation/                      # riverPageRoute helper, RiverRouteObserver
    realtime/                        # Message bus poller, real-time inbox service
    theme/                           # Design tokens, semantic colors, component theme
    widgets/                         # Shared widgets (image viewer, markdown editor, snack bar, dialogs, pickers)
  features/
    compose/                         # Topic composition
    home/                            # Home shell + tab navigation
    login/                           # Login flow (WebView, session, multi-mode)
    mine/                            # Settings, profile, QR, storage, about
    mini_apps/                       # Mini app permissions, webview pages
    notifications/                   # Notifications list, chat detail
    posts/                           # Topic detail, comment detail, posts page
    search/                          # Search page
```

## Local Package Overrides

- `packages/flutter_dynamic_icon/` — Dynamic app icon switching (Android + iOS native)
- `packages/adaptive_platform_ui/` — Platform-adaptive UI (iOS Liquid Glass, Cupertino, Android Material)
- `third_party/draggable_route/` — Hero-style draggable route transition (vendored)

## Multi-Provider Accounts

The app supports two forum providers with different auth mechanisms:
- **Riverside**: Cookie-based authentication
- **QingShuiHePan (清水河畔)**: Token+secret API key authentication

`AccountStore` manages both, with `riverSideCookieHeaderFor(username)` and `qingShuiHePanAuthFor(username)` accessors. `RiverServerConfig` provides base URLs for each provider.

## CI Style Gates

`codemagic.yaml` enforces these grep-based rules on `lib/features/` and `lib/core/widgets/`:
- No `BorderRadius.circular(N)` — use `RiverRadius` constants or `RiverCustomComponentTheme`
- No `Color(0xFF...)` — use `ColorScheme` or `RiverSemanticColors`
- No `fontSize: N` — use `TextTheme` styles

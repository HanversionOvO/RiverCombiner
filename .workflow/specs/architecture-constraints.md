---
title: "Architecture Constraints"
readMode: required
priority: high
category: arch
keywords:
  - architecture
  - module
  - layer
  - boundary
  - dependency
  - structure
---

# Architecture Constraints

Auto-generated from project structure. Update manually as architecture evolves.

## Module Structure
- Type: single-package Flutter app with local package overrides
- Key modules:
  - `lib/app/` — App shell, dependency injection, settings controller
  - `lib/core/` — Shared infrastructure (network, storage, widgets, models)
  - `lib/features/` — Feature pages (compose, home, login, mine, notifications, posts, search)
  - `packages/` — Local package overrides (flutter_dynamic_icon, adaptive_platform_ui)
  - `third_party/` — Vendored third-party packages (draggable_route)

## Layer Boundaries
- `lib/features/` → depends on `lib/core/` and `lib/app/`
- `lib/app/` → depends on `lib/core/`
- `lib/core/` → no dependencies on `lib/features/` or `lib/app/`
- `lib/core/network/` — API client layer, no UI dependencies
- `lib/core/widgets/` — Shared UI components, may depend on core services/models

## Dependency Rules
- Feature pages import from core modules via `package:river/core/` paths
- API client uses extension methods for endpoint organization
- Stores use `ChangeNotifier` pattern, consumed via `ListenableBuilder` or `context.watch`
- Platform-specific code abstracted behind bridges in `lib/core/platform/`

## Technology Constraints
- Runtime: Dart SDK ^3.10.8, Flutter
- Module system: Dart package imports
- Strict mode: Dart sound null safety
- Package manager: flutter pub
- CI/CD: codemagic.yaml configured

## Key Packages
- State management: ChangeNotifier (built-in Flutter)
- HTTP client: `http` ^1.6.0
- Local storage: `shared_preferences` ^2.5.4
- Image handling: `cached_network_image`, `image_picker`, `wechat_assets_picker`
- Markdown: `markdown`, `flutter_markdown_plus`
- WebView: `webview_flutter` ^4.13.1
- QR/Barcode: `qr_flutter`, `google_mlkit_barcode_scanning`, `mobile_scanner`

## Entries

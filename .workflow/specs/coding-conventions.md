---
title: "Coding Conventions"
readMode: required
priority: high
category: coding
keywords:
  - style
  - naming
  - import
  - pattern
  - convention
  - formatting
---

# Coding Conventions

Auto-generated from project analysis. Update manually as patterns evolve.

## Formatting
- Indentation: 2 spaces
- Line length: not configured (Dart default 80)
- Trailing commas: yes (multi-line parameter lists)
- Semicolons: required (Dart)
- Quotes: single quotes preferred for strings

## Naming
- Variables/functions: camelCase
- Classes/types: PascalCase
- Enums: PascalCase
- Constants: camelCase
- Files: snake_case (e.g., `account_models.dart`, `river_ai_service.dart`)
- Private members: underscore prefix `_PrivateClass`

## Imports
- Style: named imports (`import 'package:flutter/foundation.dart'`)
- Path aliases: `package:river/` for internal imports
- Order: dart: → package:flutter/ → package: → relative

## Patterns
- `@immutable` annotation on data classes
- `copyWith` method for immutable state updates
- `toJson()` / `fromJson()` for serialization
- `const` constructors where applicable
- `ChangeNotifier` + `ListenableBuilder` for reactive state stores
- Extension methods for API client endpoint grouping (`extension X on RiverSideApiClient`)
- Extension methods for view/actions separation (`extension _PageView on _PageState`)

## Linting
- Framework: `flutter_lints` ^6.0.0
- Config: `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`

## Entries

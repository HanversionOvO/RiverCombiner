---
title: "Test Conventions"
readMode: required
priority: high
category: test
keywords:
  - test
  - coverage
  - mock
  - fixture
  - assertion
  - framework
---

# Test Conventions

Auto-generated from project analysis. Update manually as patterns evolve.

## Framework
- Framework: `flutter_test` (built-in Flutter test SDK)
- Run command: `flutter test`

## Directory Structure
- Pattern: `test/` directory at project root
- File location: co-located by feature (currently single `widget_test.dart`)

## Naming Conventions
- Test files: `*_test.dart`
- Test functions: `testWidgets('descriptive name', ...)` for widget tests

## Patterns
- `SharedPreferences.setMockInitialValues()` for mocking shared preferences
- `tester.pumpWidget()` + `tester.pumpAndSettle()` for widget rendering
- `find.text()` + `expect()` for widget assertions

## Entries

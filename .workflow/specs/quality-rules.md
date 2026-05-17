---
title: "Quality Rules"
readMode: required
priority: medium
category: quality
keywords:
  - quality
  - lint
  - rule
  - enforcement
---

# Quality Rules

## Linting
- Framework: `flutter_lints` ^6.0.0
- Config: `analysis_options.yaml` (extends `package:flutter_lints/flutter.yaml`)
- Exclusions: `_ref/**`, `_ref_*/**`, `packages/adaptive_platform_ui/example/**`

## CI/CD
- Platform: codemagic.yaml (Codemagic CI/CD for Flutter)
- Build triggers configured via codemagic.yaml

## Code Review
- No automated PR checks detected — manual review

## Entries

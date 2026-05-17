/// River design tokens — canonical scale constants for all UI dimensions.
///
/// These are the single source of truth for spacing and corner radius values
/// across the app. Feature code references these constants instead of raw
/// numeric literals, so the entire visual scale stays consistent.
///
/// For runtime theme-dependent values (colors, component radii when the user
/// changes corner presets), use the ThemeExtension classes:
///   - [RiverSemanticColors] for semantic color tokens
///   - [RiverCustomComponentTheme] for custom component border radii
library;

// ignore_for_file: avoid_classes_with_only_static_members

abstract final class RiverRadius {
  const RiverRadius._();

  /// No rounding — edges, dividers, or full-width containers
  static const double none = 0;

  /// Extra small — badges, small chips, inline indicator dots (4px)
  static const double xs = 4;

  /// Small — standard chips, compact inputs, small buttons (8px)
  static const double sm = 8;

  /// Medium — cards, list tiles, standard inputs (12px)
  static const double md = 12;

  /// Large — dialogs, bottom sheets, modal containers (16px)
  static const double lg = 16;

  /// Extra large — large containers, hero sections (24px)
  static const double xl = 24;

  /// Pill / capsule shape — for fully rounded elements like avatars (999px)
  static const double full = 999;
}

abstract final class RiverSpacing {
  const RiverSpacing._();

  /// Extra small — tight inline gaps, icon-text spacing (4px)
  static const double xs = 4;

  /// Small — compact gaps within components, chip spacing (8px)
  static const double sm = 8;

  /// Medium — standard gaps, content-to-edge padding for compact layouts (12px)
  static const double md = 12;

  /// Large — default horizontal page padding, card-content padding (16px)
  static const double lg = 16;

  /// Extra large — section separations, large card padding (24px)
  static const double xl = 24;

  /// Double extra large — page-level vertical spacers, hero padding (32px)
  static const double xxl = 32;
}

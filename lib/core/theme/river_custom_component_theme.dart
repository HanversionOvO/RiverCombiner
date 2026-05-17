import 'package:flutter/material.dart';

import '../../app/app_settings_controller.dart';
import 'river_design_tokens.dart';

/// Theme extension for River's custom-built components that Flutter's stock
/// [ThemeData] component themes don't cover.
///
/// Values stored here are **base** values (standard corner preset). The
/// [scaleForCornerPreset] factory applies the user's chosen corner preset to
/// produce the final resolved instance registered in [_buildTheme].
///
/// Usage:
/// ```dart
/// final compTheme = Theme.of(context).extension<RiverCustomComponentTheme>()!;
/// Container(borderRadius: compTheme.snackBarRadius)
/// ```
@immutable
class RiverCustomComponentTheme
    extends ThemeExtension<RiverCustomComponentTheme> {
  const RiverCustomComponentTheme({
    required this.snackBarRadius,
    required this.confirmDialogRadius,
    required this.markdownEditorToolbarRadius,
    required this.markdownEditorSheetRadius,
    required this.markdownEditorCardRadius,
    required this.imageViewerOverlayRadius,
    required this.categoryPickerRadius,
    required this.emojiPickerRadius,
    required this.aiActionButtonRadius,
  });

  // -- base values (standard preset) -----------------------------------------

  static const _baseSnackBarRadius = BorderRadius.all(Radius.circular(RiverRadius.lg));
  static const _baseConfirmDialogRadius = BorderRadius.all(Radius.circular(RiverRadius.xl));
  static const _baseMarkdownEditorToolbarRadius = BorderRadius.all(Radius.circular(RiverRadius.md));
  static const _baseMarkdownEditorSheetRadius = BorderRadius.all(Radius.circular(RiverRadius.xl));
  static const _baseMarkdownEditorCardRadius = BorderRadius.all(Radius.circular(RiverRadius.md));
  static const _baseImageViewerOverlayRadius = BorderRadius.zero;
  static const _baseCategoryPickerRadius = BorderRadius.all(Radius.circular(RiverRadius.lg));
  static const _baseEmojiPickerRadius = BorderRadius.all(Radius.circular(RiverRadius.lg));
  static const _baseAiActionButtonRadius = BorderRadius.all(Radius.circular(RiverRadius.md));

  /// Creates a [RiverCustomComponentTheme] scaled for the given corner preset.
  ///
  /// Each preset applies a multiplier to a single base corner radius value.
  /// The multiplier is derived from the relationship between the preset's
  /// underlying numeric radius (compact=10, standard=14, relaxed=20) and the
  /// standard preset (14).
  factory RiverCustomComponentTheme.scaleForPreset(
    AppCornerPreset preset,
  ) {
    final baseRadius = _presetRadius(preset);
    final scale = baseRadius / 14.0; // standard = 1.0× multiplier

    BorderRadius scaleRadius(BorderRadius source) {
      if (source == BorderRadius.zero) return BorderRadius.zero;
      return BorderRadius.only(
        topLeft: source.topLeft * scale,
        topRight: source.topRight * scale,
        bottomLeft: source.bottomLeft * scale,
        bottomRight: source.bottomRight * scale,
      );
    }

    return RiverCustomComponentTheme(
      snackBarRadius: scaleRadius(_baseSnackBarRadius),
      confirmDialogRadius: scaleRadius(_baseConfirmDialogRadius),
      markdownEditorToolbarRadius: scaleRadius(_baseMarkdownEditorToolbarRadius),
      markdownEditorSheetRadius: scaleRadius(_baseMarkdownEditorSheetRadius),
      markdownEditorCardRadius: scaleRadius(_baseMarkdownEditorCardRadius),
      imageViewerOverlayRadius: _baseImageViewerOverlayRadius, // never scales
      categoryPickerRadius: scaleRadius(_baseCategoryPickerRadius),
      emojiPickerRadius: scaleRadius(_baseEmojiPickerRadius),
      aiActionButtonRadius: scaleRadius(_baseAiActionButtonRadius),
    );
  }

  static double _presetRadius(AppCornerPreset preset) {
    switch (preset) {
      case AppCornerPreset.compact:
        return 10;
      case AppCornerPreset.standard:
        return 14;
      case AppCornerPreset.relaxed:
        return 20;
    }
  }

  // -- per-component base BorderRadius slots --------------------------------

  final BorderRadius snackBarRadius;
  final BorderRadius confirmDialogRadius;
  final BorderRadius markdownEditorToolbarRadius;
  final BorderRadius markdownEditorSheetRadius;
  final BorderRadius markdownEditorCardRadius;
  final BorderRadius imageViewerOverlayRadius;
  final BorderRadius categoryPickerRadius;
  final BorderRadius emojiPickerRadius;
  final BorderRadius aiActionButtonRadius;

  // -- ThemeExtension contract -----------------------------------------------

  @override
  RiverCustomComponentTheme copyWith({
    BorderRadius? snackBarRadius,
    BorderRadius? confirmDialogRadius,
    BorderRadius? markdownEditorToolbarRadius,
    BorderRadius? markdownEditorSheetRadius,
    BorderRadius? markdownEditorCardRadius,
    BorderRadius? imageViewerOverlayRadius,
    BorderRadius? categoryPickerRadius,
    BorderRadius? emojiPickerRadius,
    BorderRadius? aiActionButtonRadius,
  }) {
    return RiverCustomComponentTheme(
      snackBarRadius: snackBarRadius ?? this.snackBarRadius,
      confirmDialogRadius: confirmDialogRadius ?? this.confirmDialogRadius,
      markdownEditorToolbarRadius:
          markdownEditorToolbarRadius ?? this.markdownEditorToolbarRadius,
      markdownEditorSheetRadius:
          markdownEditorSheetRadius ?? this.markdownEditorSheetRadius,
      markdownEditorCardRadius:
          markdownEditorCardRadius ?? this.markdownEditorCardRadius,
      imageViewerOverlayRadius:
          imageViewerOverlayRadius ?? this.imageViewerOverlayRadius,
      categoryPickerRadius:
          categoryPickerRadius ?? this.categoryPickerRadius,
      emojiPickerRadius: emojiPickerRadius ?? this.emojiPickerRadius,
      aiActionButtonRadius:
          aiActionButtonRadius ?? this.aiActionButtonRadius,
    );
  }

  @override
  RiverCustomComponentTheme lerp(
    covariant RiverCustomComponentTheme? other,
    double t,
  ) {
    if (other == null) return this;
    return RiverCustomComponentTheme(
      snackBarRadius: BorderRadius.lerp(snackBarRadius, other.snackBarRadius, t)!,
      confirmDialogRadius: BorderRadius.lerp(confirmDialogRadius, other.confirmDialogRadius, t)!,
      markdownEditorToolbarRadius: BorderRadius.lerp(markdownEditorToolbarRadius, other.markdownEditorToolbarRadius, t)!,
      markdownEditorSheetRadius: BorderRadius.lerp(markdownEditorSheetRadius, other.markdownEditorSheetRadius, t)!,
      markdownEditorCardRadius: BorderRadius.lerp(markdownEditorCardRadius, other.markdownEditorCardRadius, t)!,
      imageViewerOverlayRadius: BorderRadius.lerp(imageViewerOverlayRadius, other.imageViewerOverlayRadius, t)!,
      categoryPickerRadius: BorderRadius.lerp(categoryPickerRadius, other.categoryPickerRadius, t)!,
      emojiPickerRadius: BorderRadius.lerp(emojiPickerRadius, other.emojiPickerRadius, t)!,
      aiActionButtonRadius: BorderRadius.lerp(aiActionButtonRadius, other.aiActionButtonRadius, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiverCustomComponentTheme &&
          runtimeType == other.runtimeType &&
          snackBarRadius == other.snackBarRadius &&
          confirmDialogRadius == other.confirmDialogRadius &&
          markdownEditorToolbarRadius == other.markdownEditorToolbarRadius &&
          markdownEditorSheetRadius == other.markdownEditorSheetRadius &&
          markdownEditorCardRadius == other.markdownEditorCardRadius &&
          imageViewerOverlayRadius == other.imageViewerOverlayRadius &&
          categoryPickerRadius == other.categoryPickerRadius &&
          emojiPickerRadius == other.emojiPickerRadius &&
          aiActionButtonRadius == other.aiActionButtonRadius;

  @override
  int get hashCode => Object.hash(
        snackBarRadius,
        confirmDialogRadius,
        markdownEditorToolbarRadius,
        markdownEditorSheetRadius,
        markdownEditorCardRadius,
        imageViewerOverlayRadius,
        categoryPickerRadius,
        emojiPickerRadius,
        aiActionButtonRadius,
      );
}

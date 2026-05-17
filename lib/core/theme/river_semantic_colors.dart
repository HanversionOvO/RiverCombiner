import 'package:flutter/material.dart';

/// Semantic color tokens that sit above Material 3's built-in [ColorScheme].
///
/// These cover functional meanings (success, overlay backgrounds) that don't
/// have dedicated roles in the stock ColorScheme. Future-proofed for additional
/// semantic tokens like warning, info, or brand colors.
///
/// Usage:
/// ```dart
/// final semantic = Theme.of(context).extension<RiverSemanticColors>()!;
/// Container(color: semantic.successContainer)
/// ```
@immutable
class RiverSemanticColors extends ThemeExtension<RiverSemanticColors> {
  const RiverSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.overlayBackground,
    required this.overlayOnBackground,
  });

  factory RiverSemanticColors.light() {
    return const RiverSemanticColors(
      success: Color(0xFF16A34A),
      onSuccess: Color(0xFFFFFFFF),
      successContainer: Color(0xFFDCFCE7),
      error: Color(0xFFDC2626),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFEE2E2),
      overlayBackground: Color(0x80000000),
      overlayOnBackground: Color(0xFFFFFFFF),
    );
  }

  factory RiverSemanticColors.dark() {
    return const RiverSemanticColors(
      success: Color(0xFF22C55E),
      onSuccess: Color(0xFF052E16),
      successContainer: Color(0xFF052E16),
      error: Color(0xFFEF4444),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF450A0A),
      overlayBackground: Color(0xB3000000),
      overlayOnBackground: Color(0xFFE5E5E5),
    );
  }

  // -- semantic slots -------------------------------------------------------

  /// Success state color (check marks, confirmation banners).
  final Color success;

  /// Content color drawn on top of [success].
  final Color onSuccess;

  /// Muted container background for success-state surfaces.
  final Color successContainer;

  /// Error / destructive state color (alerts, delete confirmations).
  final Color error;

  /// Content color drawn on top of [error].
  final Color onError;

  /// Muted container background for error-state surfaces.
  final Color errorContainer;

  /// Semi-transparent scrim drawn over content for modals / dialogs.
  /// Replaces `Colors.black.withOpacity(0.5)` style hardcodes.
  final Color overlayBackground;

  /// Content color drawn on top of [overlayBackground] — icon / text tint.
  final Color overlayOnBackground;

  // -- ThemeExtension contract -----------------------------------------------

  @override
  RiverSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? overlayBackground,
    Color? overlayOnBackground,
  }) {
    return RiverSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      overlayBackground: overlayBackground ?? this.overlayBackground,
      overlayOnBackground: overlayOnBackground ?? this.overlayOnBackground,
    );
  }

  @override
  RiverSemanticColors lerp(
    covariant RiverSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    return RiverSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      overlayBackground: Color.lerp(overlayBackground, other.overlayBackground, t)!,
      overlayOnBackground: Color.lerp(overlayOnBackground, other.overlayOnBackground, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiverSemanticColors &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          onSuccess == other.onSuccess &&
          successContainer == other.successContainer &&
          error == other.error &&
          onError == other.onError &&
          errorContainer == other.errorContainer &&
          overlayBackground == other.overlayBackground &&
          overlayOnBackground == other.overlayOnBackground;

  @override
  int get hashCode => Object.hash(
        success,
        onSuccess,
        successContainer,
        error,
        onError,
        errorContainer,
        overlayBackground,
        overlayOnBackground,
      );
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/river_semantic_colors.dart';

enum RiverSnackBarTone { normal, error }

extension RiverSnackBarMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showRiverSnackBar(
    String text, {
    RiverSnackBarTone? tone,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    hideCurrentSnackBar();
    final resolvedTone = tone ?? _inferTone(text);
    return showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.only(bottom: 14),
        duration: duration,
        content: Align(
          alignment: Alignment.bottomCenter,
          child: _RiverSnackBarCard(
            text: text,
            tone: resolvedTone,
            duration: duration,
          ),
        ),
      ),
    );
  }

  RiverSnackBarTone _inferTone(String text) {
    final lower = text.toLowerCase();
    if (text.contains('失败') ||
        text.contains('错误') ||
        text.contains('无效') ||
        text.contains('异常') ||
        text.contains('缺少') ||
        lower.contains('error') ||
        lower.contains('failed')) {
      return RiverSnackBarTone.error;
    }
    return RiverSnackBarTone.normal;
  }
}

class _RiverSnackBarCard extends StatefulWidget {
  const _RiverSnackBarCard({
    required this.text,
    required this.tone,
    required this.duration,
  });

  final String text;
  final RiverSnackBarTone tone;
  final Duration duration;

  @override
  State<_RiverSnackBarCard> createState() => _RiverSnackBarCardState();
}

class _RiverSnackBarCardState extends State<_RiverSnackBarCard>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _countdownController;
  late final AnimationController _iconController;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _countdownController = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _countdownController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _handleCloseTap() async {
    if (_closing) {
      return;
    }
    _closing = true;
    try {
      await _countdownController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInCubic,
      );
    } finally {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticColors = theme.extension<RiverSemanticColors>()!;
    final isError = widget.tone == RiverSnackBarTone.error;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;
    final accent = isError ? semanticColors.error : semanticColors.success;
    final iconBg = isError
        ? semanticColors.errorContainer
        : semanticColors.successContainer;
    final background = theme.colorScheme.surface.withValues(alpha: 0.80);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entryController,
        _countdownController,
        _iconController,
      ]),
      builder: (context, _) {
        final entry = Curves.easeOutCubic.transform(_entryController.value);
        final progress = (1 - _countdownController.value).clamp(0.0, 1.0);
        final exitT = ((_countdownController.value - 0.86) / 0.14).clamp(
          0.0,
          1.0,
        );
        final visible = 1 - Curves.easeInCubic.transform(exitT);
        final iconMotion = _iconController.value;
        return Opacity(
          opacity: entry * visible,
          child: Transform.scale(
            scale: (0.94 + (0.06 * entry)) * (0.97 + 0.03 * visible),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.88,
              ),
              child: IntrinsicWidth(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SnackCountdownBorderPainter(
                          progress: progress,
                          color: accent,
                          trackColor: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.28),
                          headPulse: iconMotion,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(2.8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.26),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, -1.2 * iconMotion),
                                  child: Transform.scale(
                                    scale: 0.96 + (0.08 * iconMotion),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: iconBg,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        icon,
                                        size: 16,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    widget.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _SnackCloseButton(onTap: _handleCloseTap),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SnackCountdownBorderPainter extends CustomPainter {
  const _SnackCountdownBorderPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.headPulse,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double headPulse;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 16.0;
    const strokeWidth = 2.5;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2 + 0.1),
      const Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.92);

    canvas.drawPath(path, trackPaint);

    var totalLength = 0.0;
    for (final metric in path.computeMetrics()) {
      totalLength += metric.length;
    }

    var remaining = totalLength * progress;
    Tangent? headTangent;
    for (final metric in path.computeMetrics()) {
      if (remaining <= 0) {
        break;
      }
      final drawLength = remaining > metric.length ? metric.length : remaining;
      final segment = metric.extractPath(0, drawLength);
      canvas.drawPath(segment, progressPaint);
      if (drawLength > 0) {
        headTangent = metric.getTangentForOffset(drawLength);
      }
      remaining -= drawLength;
    }

    final head = headTangent;
    if (head == null) {
      return;
    }

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.26 + 0.24 * headPulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(
      head.position,
      strokeWidth * (1.8 + 0.5 * headPulse),
      glowPaint,
    );
    final headPaint = Paint()..color = color;
    canvas.drawCircle(
      head.position,
      strokeWidth * (0.68 + 0.24 * headPulse),
      headPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SnackCountdownBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.headPulse != headPulse;
  }
}

class _SnackCloseButton extends StatelessWidget {
  const _SnackCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/river_design_tokens.dart';

class RiverAiActionButton extends StatefulWidget {
  const RiverAiActionButton({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.idleText,
    required this.loadingText,
  });

  final VoidCallback onPressed;
  final bool loading;
  final String idleText;
  final String loadingText;

  @override
  State<RiverAiActionButton> createState() => _RiverAiActionButtonState();
}

class _RiverAiActionButtonState extends State<RiverAiActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : theme.colorScheme.onSurface.withValues(alpha: 0.88);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value * math.pi * 2;
        final pulse = 0.55 + 0.45 * (math.sin(phase) * 0.5 + 0.5);
        final gradientBegin = Alignment(
          math.cos(phase) * 0.45,
          math.sin(phase) * 0.45,
        );
        final gradientEnd = Alignment(
          -math.cos(phase) * 0.45,
          -math.sin(phase) * 0.45,
        );

        return ClipRRect(
          borderRadius: BorderRadius.circular(RiverRadius.full),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(RiverRadius.full),
                gradient: LinearGradient(
                  begin: gradientBegin,
                  end: gradientEnd,
                  colors: [
                    const Color(
                      0xFFAED8FF,
                    ).withValues(alpha: (isDark ? 0.30 : 0.40) * pulse),
                    const Color(
                      0xFFCDB8FF,
                    ).withValues(alpha: (isDark ? 0.28 : 0.38) * pulse),
                    const Color(
                      0xFFFFCFE1,
                    ).withValues(alpha: (isDark ? 0.26 : 0.36) * pulse),
                    const Color(
                      0xFFBDEDE3,
                    ).withValues(alpha: (isDark ? 0.24 : 0.34) * pulse),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.24 : 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF9CC8FF,
                    ).withValues(alpha: (isDark ? 0.14 : 0.12) * pulse),
                    blurRadius: 14,
                    spreadRadius: 0.3,
                  ),
                ],
              ),
              child: Material(
                color: theme.colorScheme.surface.withValues(
                  alpha: isDark ? 0.22 : 0.14,
                ),
                borderRadius: BorderRadius.circular(RiverRadius.full),
                child: InkWell(
                  borderRadius: BorderRadius.circular(RiverRadius.full),
                  onTap: widget.loading ? null : widget.onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.loading)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                foreground,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: foreground,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          widget.loading ? widget.loadingText : widget.idleText,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

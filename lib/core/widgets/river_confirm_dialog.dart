import 'package:flutter/material.dart';

import '../theme/river_design_tokens.dart';

Future<bool> showRiverConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelText = '取消',
  String confirmText = '确认',
  IconData icon = Icons.help_outline_rounded,
  bool isDestructive = false,
  bool barrierDismissible = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.95, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (dialogContext, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: _RiverConfirmDialogCard(
            title: title,
            message: message,
            cancelText: cancelText,
            confirmText: confirmText,
            icon: icon,
            isDestructive: isDestructive,
            onCancel: () => Navigator.of(ctx).pop(false),
            onConfirm: () => Navigator.of(ctx).pop(true),
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

class _RiverConfirmDialogCard extends StatelessWidget {
  const _RiverConfirmDialogCard({
    required this.title,
    required this.message,
    required this.cancelText,
    required this.confirmText,
    required this.icon,
    required this.isDestructive,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String cancelText;
  final String confirmText;
  final IconData icon;
  final bool isDestructive;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onPrimaryContainer;
    final confirmStyle = isDestructive
        ? FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          )
        : FilledButton.styleFrom();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(RiverRadius.xl)),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RiverSpacing.lg, 18, RiverSpacing.lg, RiverSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primaryContainer,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: badgeColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: onCancel, child: Text(cancelText)),
                  FilledButton(
                    onPressed: onConfirm,
                    style: confirmStyle,
                    child: Text(confirmText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

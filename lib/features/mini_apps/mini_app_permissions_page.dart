import 'package:flutter/material.dart';
import 'package:river/core/theme/river_design_tokens.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_permission_store.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:river/features/mine/widgets/mine_settings_app_bar.dart';
import 'package:skeletonizer/skeletonizer.dart';
class MiniAppPermissionsPage extends StatefulWidget {
  const MiniAppPermissionsPage({
    super.key,
    required this.miniApp,
    required this.permissionStore,
  });

  final RiverMiniAppEntry miniApp;
  final RiverMiniAppPermissionStore permissionStore;

  @override
  State<MiniAppPermissionsPage> createState() => _MiniAppPermissionsPageState();
}

class _MiniAppPermissionsPageState extends State<MiniAppPermissionsPage> {
  bool _loading = true;
  RiverMiniAppPermissionPolicy _policy = const RiverMiniAppPermissionPolicy(
    states: <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{},
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final policy = await widget.permissionStore.loadPolicy(widget.miniApp.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _policy = policy;
      _loading = false;
    });
  }

  Future<void> _update(
    RiverMiniAppNativePermission permission,
    bool granted,
  ) async {
    final policy = await widget.permissionStore.updatePermission(
      appId: widget.miniApp.id,
      permission: permission,
      granted: granted,
      prompted: true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _policy = policy;
    });
    ScaffoldMessenger.of(
      context,
    ).showRiverSnackBar('${permission.title}${granted ? '已开启' : '已关闭'}');
  }

  String _subtitleFor(RiverMiniAppNativePermission permission) {
    final prompted = _policy.isPrompted(permission);
    if (!prompted && permission != RiverMiniAppNativePermission.network) {
      return '${permission.description}（首次调用将询问）';
    }
    return permission.description;
  }

  @override
  Widget build(BuildContext context) {
    return MineSettingsPageScaffold(
      title: '小程序权限',
      subtitle: widget.miniApp.name,
      icon: Icons.admin_panel_settings_outlined,
      heroTagPrefix: 'miniapp_permission_${widget.miniApp.id}',
      body: _loading
          ? Skeletonizer(
              enabled: true,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  _PermissionSection(
                    title: '原生能力权限',
                    subtitle: '默认仅开启网络请求，其他能力首次调用会弹出授权确认。',
                    child: Column(
                      children: RiverMiniAppNativePermission.values
                          .map(
                            (permission) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _PermissionTile(
                                permission: permission,
                                granted: true,
                                subtitle: _subtitleFor(permission),
                                onChanged: (_) {},
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                _PermissionSection(
                  title: '原生能力权限',
                  subtitle: '默认仅开启网络请求，其他能力首次调用会弹出授权确认。',
                  child: Column(
                    children: RiverMiniAppNativePermission.values
                        .map((permission) {
                          final granted = _policy.isGranted(permission);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PermissionTile(
                              permission: permission,
                              granted: granted,
                              subtitle: _subtitleFor(permission),
                              onChanged: (next) => _update(permission, next),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RiverRadius.xl),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.permission,
    required this.granted,
    required this.subtitle,
    required this.onChanged,
  });

  final RiverMiniAppNativePermission permission;
  final bool granted;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: granted
            ? selectedColor.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RiverRadius.lg),
        border: Border.all(
          color: granted
              ? selectedColor.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RiverRadius.lg)),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: granted
                ? selectedColor.withValues(alpha: 0.16)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(RiverRadius.md),
          ),
          alignment: Alignment.center,
          child: Icon(
            permission.icon,
            size: 18,
            color: granted ? selectedColor : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          permission.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: granted ? selectedColor : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(value: granted, onChanged: onChanged),
      ),
    );
  }
}




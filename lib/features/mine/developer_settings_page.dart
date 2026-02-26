import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/mini_apps/river_mini_app_install_store.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_platform_client.dart';
import 'package:river/features/mine/widgets/mine_settings_app_bar.dart';

class DeveloperSettingsPage extends StatefulWidget {
  const DeveloperSettingsPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<DeveloperSettingsPage> createState() => _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends State<DeveloperSettingsPage> {
  final RiverMiniAppInstallStore _miniAppInstallStore =
      RiverMiniAppInstallStore();
  final RiverMiniAppPlatformClient _platformClient =
      RiverMiniAppPlatformClient();
  late final TextEditingController _platformUsernameController;
  late final TextEditingController _platformPasswordController;
  bool _platformBusy = false;
  bool _platformLoadingSubmissions = false;
  String? _platformUsername;
  String? _platformError;
  List<RiverMiniAppSubmissionStatusItem> _platformSubmissions =
      const <RiverMiniAppSubmissionStatusItem>[];

  @override
  void initState() {
    super.initState();
    _platformUsernameController = TextEditingController();
    _platformPasswordController = TextEditingController();
    _restorePlatformAuthState();
  }

  @override
  void dispose() {
    _platformUsernameController.dispose();
    _platformPasswordController.dispose();
    super.dispose();
  }

  Future<void> _restorePlatformAuthState() async {
    final username = await _platformClient.loadUsername();
    if (!mounted) {
      return;
    }
    setState(() {
      _platformUsername = username;
      _platformUsernameController.text = username ?? '';
    });
    if (username != null && username.trim().isNotEmpty) {
      await _reloadPlatformSubmissions();
    }
  }

  bool get _platformCatalogConfigured {
    final manifestUrl =
        widget.dependencies.settingsController.miniAppsManifestUrl;
    return _platformClient.supportsPlatformCatalog(manifestUrl);
  }

  Future<void> _loginPlatform() async {
    if (_platformBusy) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (!_platformCatalogConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在服务器设置中将小程序链接配置为平台 /api/public/catalog'),
        ),
      );
      return;
    }
    setState(() {
      _platformBusy = true;
      _platformError = null;
    });
    try {
      await _platformClient.login(
        catalogUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
        username: _platformUsernameController.text,
        password: _platformPasswordController.text,
      );
      final username = await _platformClient.loadUsername();
      if (!mounted) {
        return;
      }
      setState(() {
        _platformUsername = username;
      });
      await _reloadPlatformSubmissions();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('平台登录成功')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformError = '$error';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('平台登录失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _platformBusy = false;
        });
      }
    }
  }

  Future<void> _logoutPlatform() async {
    await _platformClient.clearAuth();
    if (!mounted) {
      return;
    }
    setState(() {
      _platformUsername = null;
      _platformPasswordController.clear();
      _platformSubmissions = const <RiverMiniAppSubmissionStatusItem>[];
      _platformError = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出小程序平台账号')));
  }

  Future<void> _reloadPlatformSubmissions() async {
    if (_platformLoadingSubmissions || !_platformCatalogConfigured) {
      return;
    }
    setState(() {
      _platformLoadingSubmissions = true;
      _platformError = null;
    });
    try {
      final list = await _platformClient.fetchMySubmissions(
        catalogUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _platformSubmissions = list;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _platformLoadingSubmissions = false;
        });
      }
    }
  }

  Future<void> _exitDeveloperMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('退出开发者模式'),
          content: const Text('退出后将隐藏开发者设置项，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认退出'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    widget.dependencies.settingsController.updateDeveloperModeEnabled(false);
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出开发者模式')));
  }

  Future<void> _openInstallLocalMiniAppSheet() async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final entryPathController = TextEditingController(text: 'index.html');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        var installing = false;
        String? selectedZipPath;
        String selectedZipLabel = '未选择安装包';

        Future<void> pickZip(StateSetter setModalState) async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const <String>['zip'],
            allowMultiple: false,
            withData: false,
          );
          if (result == null || result.files.isEmpty) {
            return;
          }
          if (!mounted || !sheetContext.mounted) {
            return;
          }

          final fileName = result.files.first.name.trim();
          final path = result.files.first.path?.trim() ?? '';
          if (path.isEmpty) {
            ScaffoldMessenger.of(
              sheetContext,
            ).showSnackBar(const SnackBar(content: Text('无法读取所选文件路径，请重新选择')));
            return;
          }
          if (!path.toLowerCase().endsWith('.zip')) {
            ScaffoldMessenger.of(
              sheetContext,
            ).showSnackBar(const SnackBar(content: Text('请选择ZIP文件')));
            return;
          }

          final file = File(path);
          if (!await file.exists()) {
            if (!mounted || !sheetContext.mounted) {
              return;
            }
            ScaffoldMessenger.of(
              sheetContext,
            ).showSnackBar(const SnackBar(content: Text('所选文件不存在')));
            return;
          }
          final bytes = await file.length();
          if (!mounted || !sheetContext.mounted) {
            return;
          }

          setModalState(() {
            selectedZipPath = path;
            selectedZipLabel =
                '$fileName · ${(bytes / 1024).toStringAsFixed(1)} KB';
          });
        }

        Future<void> handleInstall(StateSetter setModalState) async {
          final zipPath = selectedZipPath?.trim() ?? '';
          if (zipPath.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('请先选择本地ZIP包')));
            return;
          }

          final rawId = idController.text.trim();
          final rawName = nameController.text.trim();
          final fallbackName = rawName.isEmpty ? '本地小程序' : rawName;
          final generatedId = _buildMiniAppId(rawId, fallbackName);

          var entryPath = entryPathController.text.trim();
          if (entryPath.isEmpty) {
            entryPath = 'index.html';
          }
          while (entryPath.startsWith('/')) {
            entryPath = entryPath.substring(1);
          }

          final localApp = RiverMiniAppEntry(
            id: generatedId,
            name: fallbackName,
            url: 'https://local/$entryPath',
            description: '开发者本地安装',
            tags: const <String>['开发者', '本地'],
            enabled: true,
            order: DateTime.now().millisecondsSinceEpoch,
          );

          setModalState(() {
            installing = true;
          });
          try {
            final installed = await _miniAppInstallStore.installFromLocalZip(
              app: localApp,
              zipFilePath: zipPath,
            );
            if (!mounted || !sheetContext.mounted) {
              return;
            }
            Navigator.of(sheetContext).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('安装成功：${installed.name}')));
          } catch (error) {
            if (mounted && sheetContext.mounted) {
              setModalState(() {
                installing = false;
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('安装失败：$error')));
            }
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    '安装本地小程序',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '选择本地ZIP安装包，安装后会出现在“我的小程序”中。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedZipLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: installing
                              ? null
                              : () => pickZip(setModalState),
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('选择'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Field(
                    controller: nameController,
                    label: '小程序名称',
                    hint: '例如：本地调试工具',
                  ),
                  _Field(
                    controller: idController,
                    label: '小程序ID（可选）',
                    hint: '留空则自动生成',
                  ),
                  _Field(
                    controller: entryPathController,
                    label: '入口路径',
                    hint: 'index.html',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: installing
                        ? null
                        : () => handleInstall(setModalState),
                    icon: installing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_for_offline_rounded),
                    label: Text(installing ? '安装中...' : '开始安装'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _buildMiniAppId(String rawId, String fallbackName) {
    final normalizedRaw = rawId.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]+'),
      '_',
    );
    if (normalizedRaw.isNotEmpty) {
      return normalizedRaw;
    }
    final normalizedName = fallbackName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final suffix = DateTime.now().millisecondsSinceEpoch;
    if (normalizedName.isEmpty) {
      return 'local.dev_$suffix';
    }
    return 'local.${normalizedName}_$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MineSettingsAppBar(
        title: '开发者模式',
        subtitle: '调试与本地小程序安装',
        icon: Icons.developer_mode_rounded,
        heroTagPrefix: 'mine_settings_developer',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          _SettingsSection(
            title: '模式管理',
            subtitle: '管理开发者模式开关',
            child: _ActionTile(
              icon: Icons.power_settings_new_rounded,
              title: '退出开发者模式',
              subtitle: '关闭后将隐藏开发者设置板块',
              onTap: _exitDeveloperMode,
            ),
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: '小程序调试',
            subtitle: '手动安装本地小程序ZIP包',
            child: _ActionTile(
              icon: Icons.extension_rounded,
              title: '安装本地小程序',
              subtitle: '通过系统文件选择器安装本地ZIP包',
              onTap: _openInstallLocalMiniAppSheet,
            ),
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: '平台审核状态',
            subtitle: '对接线上平台账号，查看提交审核进度',
            child: _buildPlatformStatusSection(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformStatusSection(BuildContext context) {
    final theme = Theme.of(context);
    final catalogUrl =
        widget.dependencies.settingsController.miniAppsManifestUrl;
    final notConfigured = !_platformCatalogConfigured;
    final hasLoggedIn = (_platformUsername ?? '').trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            notConfigured
                ? '当前小程序链接不是平台 catalog：$catalogUrl'
                : '平台目录：$catalogUrl',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (!hasLoggedIn) ...[
          TextField(
            controller: _platformUsernameController,
            enabled: !notConfigured && !_platformBusy,
            decoration: const InputDecoration(
              labelText: '平台账号',
              hintText: 'developer01',
              isDense: true,
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _platformPasswordController,
            enabled: !notConfigured && !_platformBusy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '平台密码',
              hintText: '请输入密码',
              isDense: true,
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (notConfigured || _platformBusy) ? null : _loginPlatform,
            icon: _platformBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('登录平台并查看审核状态'),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '当前账号：$_platformUsername',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _platformLoadingSubmissions
                    ? null
                    : _reloadPlatformSubmissions,
                icon: _platformLoadingSubmissions
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('刷新'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _logoutPlatform,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('退出'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if ((_platformError ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _platformError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (_platformSubmissions.isEmpty && !_platformLoadingSubmissions)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
              child: Text(
                '暂无提交记录',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._platformSubmissions.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.25,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildStatusChip(item.status),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.projectId} · ${item.versionName}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.reviewComment.trim().isEmpty
                                ? '提交ID：${item.id}'
                                : item.reviewComment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final theme = Theme.of(context);
    final resolvedStatus = status.trim().toUpperCase();
    Color fg;
    Color bg;
    String label;
    switch (resolvedStatus) {
      case 'APPROVED':
        fg = Colors.green.shade700;
        bg = Colors.green.shade50;
        label = '已通过';
        break;
      case 'REJECTED':
        fg = Colors.red.shade700;
        bg = Colors.red.shade50;
        label = '已拒绝';
        break;
      default:
        fg = Colors.orange.shade700;
        bg = Colors.orange.shade50;
        label = '审核中';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
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
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }
}

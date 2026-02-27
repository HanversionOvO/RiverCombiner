import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/features/mine/widgets/mine_settings_app_bar.dart';
import 'package:river/features/mine/riverside_profile_sheet.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.settingsController,
    required this.dependencies,
  });

  final AppSettingsController settingsController;
  final AppDependencies dependencies;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '--';
  String _buildNumber = '--';
  String _packageName = '--';
  int _devTapCount = 0;
  DateTime? _lastDevTapAt;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version.trim().isEmpty ? '--' : info.version.trim();
        _buildNumber = info.buildNumber.trim().isEmpty
            ? '--'
            : info.buildNumber.trim();
        _packageName = info.packageName.trim().isEmpty
            ? '--'
            : info.packageName.trim();
      });
    }
  }

  void _onVersionTap() {
    final now = DateTime.now();
    final last = _lastDevTapAt;
    _lastDevTapAt = now;

    if (widget.settingsController.developerModeEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开发者模式已开启')));
      return;
    }

    if (last == null || now.difference(last).inSeconds > 2) {
      _devTapCount = 1;
    } else {
      _devTapCount += 1;
    }

    final remain = 8 - _devTapCount;
    if (remain <= 0) {
      widget.settingsController.updateDeveloperModeEnabled(true);
      _devTapCount = 0;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开发者模式已开启')));
      return;
    }

    if (remain <= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('再点击 $remain 次开启开发者模式')));
    }
  }

  Future<void> _openAuthorProfile() {
    return showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: 'MikannQAQ',
      displayName: '@MikannQAQ',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: const MineSettingsAppBar(
        title: '关于 聚河畔',
        subtitle: '应用信息与项目说明',
        icon: Icons.info_outline_rounded,
        heroTagPrefix: 'mine_settings_about',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/images/logo.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '聚河畔',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'River 社区移动客户端',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _onVersionTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '版本 $_version ($_buildNumber)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '项目简介',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '聚河畔致力于提供流畅、现代、清爽的社区浏览与互动体验，支持帖子、通知、发帖、消息与小程序能力。',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '包名：$_packageName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.person_rounded,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              title: const Text('@MikannQAQ'),
              subtitle: const Text('作者主页'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: _openAuthorProfile,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '© ${DateTime.now().year} 聚河畔',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

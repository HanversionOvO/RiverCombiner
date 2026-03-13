import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/image_host/picui_image_host_service.dart';
import 'package:river/core/widgets/river_image_viewer.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:river/features/mine/widgets/mine_settings_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ImageHostSettingsPage extends StatefulWidget {
  const ImageHostSettingsPage({super.key, required this.settingsController});

  final AppSettingsController settingsController;

  @override
  State<ImageHostSettingsPage> createState() => _ImageHostSettingsPageState();
}

class _ImageHostSettingsPageState extends State<ImageHostSettingsPage> {
  late final TextEditingController _tokenController;
  final PageController _imageSwiperController = PageController(
    viewportFraction: 0.92,
  );

  bool _enabled = false;
  bool _verifying = false;
  bool _loading = false;
  bool _obscureToken = true;
  int _imageSwiperIndex = 0;

  PicUiProfile? _profile;
  List<PicUiAlbumItem> _albums = const <PicUiAlbumItem>[];
  List<PicUiImageItem> _images = const <PicUiImageItem>[];

  int? _albumId;

  @override
  void initState() {
    super.initState();
    final settings = widget.settingsController;
    _enabled = settings.picUiEnabled;
    _albumId = settings.picUiDefaultAlbumId;
    _tokenController = TextEditingController(text: settings.picUiApiToken);
    settings.updatePicUiDefaultPermission(1);
    settings.updatePicUiDefaultStrategyId(null);
    settings.updatePicUiTempUploadToken('');
    settings.updatePicUiExpiredAt('');
    _reloadRemote();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _imageSwiperController.dispose();
    super.dispose();
  }

  String get _token => _tokenController.text.trim();

  PicUiImageHostService _service() {
    return PicUiImageHostService(
      apiBaseUrl: AppSettingsController.defaultPicUiApiBaseUrl,
    );
  }

  void _persistUploadOptionSettings() {
    final settings = widget.settingsController;
    settings.updatePicUiEnabled(_enabled);
    settings.updatePicUiApiBaseUrl(
      AppSettingsController.defaultPicUiApiBaseUrl,
    );
    settings.updatePicUiApiToken(_token);
    settings.updatePicUiDefaultPermission(1);
    settings.updatePicUiDefaultStrategyId(null);
    settings.updatePicUiDefaultAlbumId(_albumId);
    settings.updatePicUiTempUploadToken('');
    settings.updatePicUiExpiredAt('');
  }

  Future<void> _reloadRemote() async {
    if (_token.isEmpty) {
      if (mounted) {
        setState(() {
          _profile = null;
          _albums = const <PicUiAlbumItem>[];
          _images = const <PicUiImageItem>[];
          _imageSwiperIndex = 0;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final service = _service();
      final profile = await service.fetchProfile(apiToken: _token);
      final albums = await service.fetchAlbums(apiToken: _token);
      final images = await service.fetchImages(apiToken: _token);
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _albums = albums.items;
        _images = images.items;
        if (_albumId != null &&
            !albums.items.any((item) => item.id == _albumId)) {
          _albumId = null;
        }
        final maxIndex = math.max(0, _images.length - 1);
        _imageSwiperIndex = _imageSwiperIndex.clamp(0, maxIndex);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_imageSwiperController.hasClients) {
          return;
        }
        final page = _imageSwiperController.page?.round();
        if (page != _imageSwiperIndex) {
          _imageSwiperController.jumpToPage(_imageSwiperIndex);
        }
      });
    } catch (error) {
      _showMessage('加载 PicUI 数据失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _applyApiTokenFromWebLogin(String apiToken) async {
    final token = apiToken.trim();
    if (token.isEmpty) {
      return;
    }
    _tokenController.text = token;
    widget.settingsController.updatePicUiApiBaseUrl(
      AppSettingsController.defaultPicUiApiBaseUrl,
    );
    widget.settingsController.updatePicUiApiToken(token);
    if (!mounted) {
      return;
    }
    setState(() => _verifying = true);
    try {
      await _service().verifyToken(token);
      _persistUploadOptionSettings();
      await _reloadRemote();
      _showMessage('登录成功，已自动保存 Token');
    } catch (error) {
      _showMessage('Token 自动保存失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  Future<void> _openPicUiLoginWebView() async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const _PicUiAuthWebViewDialogPage(
          baseUrl: AppSettingsController.defaultPicUiApiBaseUrl,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await _applyApiTokenFromWebLogin(token);
  }

  Future<void> _deleteImage(PicUiImageItem item, {bool toast = true}) async {
    if (_token.isEmpty) {
      return;
    }
    try {
      await _service().deleteImage(apiToken: _token, imageKey: item.key);
      if (!mounted) {
        return;
      }
      setState(() {
        _images = _images
            .where((entry) => entry.key != item.key)
            .toList(growable: false);
        final maxIndex = math.max(0, _images.length - 1);
        _imageSwiperIndex = _imageSwiperIndex.clamp(0, maxIndex);
      });
      if (toast) {
        _showMessage('图片已删除');
      }
    } catch (error) {
      _showMessage('删除图片失败：$error', isError: true);
    }
  }

  Future<void> _deleteAlbum(PicUiAlbumItem item) async {
    if (_token.isEmpty) {
      return;
    }
    try {
      await _service().deleteAlbum(apiToken: _token, albumId: item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _albums = _albums
            .where((entry) => entry.id != item.id)
            .toList(growable: false);
        if (_albumId == item.id) {
          _albumId = null;
        }
      });
      _showMessage('相册已删除');
    } catch (error) {
      _showMessage('删除相册失败：$error', isError: true);
    }
  }

  Future<void> _openRemotePreview(int index) async {
    final viewerItems = _images
        .map(
          (entry) => RiverImageViewerItem(
            url: entry.links.url.isEmpty
                ? entry.links.thumbnailUrl
                : entry.links.url,
            heroTag: 'picui_remote_${entry.key}',
          ),
        )
        .toList(growable: false);
    if (viewerItems.isEmpty) {
      return;
    }
    await RiverImageViewerPage.open(
      context,
      items: viewerItems,
      initialIndex: index.clamp(0, viewerItems.length - 1),
    );
  }

  Future<void> _openAllImagesGallery() async {
    if (_images.isEmpty) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final width = MediaQuery.sizeOf(sheetContext).width;
        final crossAxisCount = width >= 780
            ? 4
            : width >= 560
            ? 3
            : 2;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final items = _images;
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          '我的图片',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${items.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.9,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final imageUrl = item.links.thumbnailUrl.isEmpty
                            ? item.links.url
                            : item.links.thumbnailUrl;
                        return Material(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              final previewIndex = _images.indexWhere(
                                (entry) => entry.key == item.key,
                              );
                              if (previewIndex >= 0) {
                                _openRemotePreview(previewIndex);
                              }
                            },
                            onLongPress: () =>
                                _copyText(item.links.url, msg: '链接已复制'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 6,
                                        top: 6,
                                        child: Material(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            onTap: () async {
                                              await _deleteImage(
                                                item,
                                                toast: false,
                                              );
                                              if (!mounted ||
                                                  !sheetContext.mounted) {
                                                return;
                                              }
                                              _showMessage('图片已删除');
                                              setSheetState(() {});
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    8,
                                  ),
                                  child: Text(
                                    item.name.isEmpty ? item.key : item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _copyText(String value, {String msg = '已复制'}) {
    final text = value.trim();
    if (text.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _showMessage(msg);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showRiverSnackBar(
      message,
      tone: isError ? RiverSnackBarTone.error : RiverSnackBarTone.normal,
    );
  }

  String _displayTokenText() {
    final token = _token;
    if (token.isEmpty) {
      return '未登录';
    }
    if (!_obscureToken) {
      return token;
    }
    if (token.length <= 12) {
      return '${token.substring(0, 4)}****';
    }
    return '${token.substring(0, 6)}****${token.substring(token.length - 6)}';
  }

  String _formatStorageValue(double value) {
    final normalized = value.isFinite && value > 0 ? value : 0.0;
    if (normalized >= 1024 * 1024) {
      return '${(normalized / (1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (normalized >= 1024) {
      return '${(normalized / 1024).toStringAsFixed(2)} GB';
    }
    if (normalized >= 1) {
      return '${normalized.toStringAsFixed(1)} MB';
    }
    return '${(normalized * 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _clearCurrentToken() async {
    if (_token.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除当前 Token'),
          content: const Text('将清空当前图床 Token 与临时 Token，确认继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _tokenController.clear();
    widget.settingsController.updatePicUiApiToken('');
    setState(() {
      _profile = null;
      _albums = const <PicUiAlbumItem>[];
      _images = const <PicUiImageItem>[];
      _imageSwiperIndex = 0;
    });
    _showMessage('已删除当前 Token');
  }

  Widget _buildMyImageSwiper(ThemeData theme) {
    if (_images.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '登录后可在这里查看你上传到 PicUI 的图片，点开即可预览与管理。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 268,
          child: PageView.builder(
            controller: _imageSwiperController,
            itemCount: _images.length,
            onPageChanged: (index) => setState(() => _imageSwiperIndex = index),
            itemBuilder: (context, index) {
              final item = _images[index];
              final displayUrl = item.links.thumbnailUrl.isEmpty
                  ? item.links.url
                  : item.links.thumbnailUrl;
              final previewUrl = item.links.url.isEmpty
                  ? item.links.thumbnailUrl
                  : item.links.url;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Material(
                  borderRadius: BorderRadius.circular(18),
                  color: theme.colorScheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _openRemotePreview(index),
                          onLongPress: () =>
                              _copyText(previewUrl, msg: '链接已复制'),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CachedNetworkImage(
                                  imageUrl: displayUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                left: 10,
                                top: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '${index + 1}/${_images.length}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.name.isEmpty ? item.key : item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.humanDate.isEmpty
                                        ? item.date
                                        : item.humanDate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '复制链接',
                              onPressed: () =>
                                  _copyText(item.links.url, msg: '链接已复制'),
                              icon: const Icon(Icons.copy_rounded),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () => _deleteImage(item),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MineSettingsPageScaffold(
      title: '图床设置',
      subtitle: '图床登录、上传与管理',
      icon: Icons.photo_library_outlined,
      heroTagPrefix: 'mine_settings_image_host',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          _ImageHostSectionCard(
            title: '登录图床',
            subtitle: '登录至 PicUI 图床',
            child: Column(
              children: [
                _ImageHostSwitchTile(
                  icon: Icons.cloud_upload_rounded,
                  title: '启用 PicUI 图床',
                  subtitle: '默认使用 PicUI 图片内容',
                  value: _enabled,
                  onChanged: (value) {
                    setState(() => _enabled = value);
                    widget.settingsController.updatePicUiEnabled(value);
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow.withValues(
                      alpha: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.26,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.vpn_key_outlined,
                          size: 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前 Token',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _displayTokenText(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '复制 Token',
                        onPressed: _token.isEmpty
                            ? null
                            : () => _copyText(_token, msg: 'Token 已复制'),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                      IconButton(
                        tooltip: _obscureToken ? '显示' : '隐藏',
                        onPressed: _token.isEmpty
                            ? null
                            : () {
                                setState(() => _obscureToken = !_obscureToken);
                              },
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: '删除 Token',
                        onPressed: _token.isEmpty ? null : _clearCurrentToken,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _verifying ? null : _openPicUiLoginWebView,
                    icon: _verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_verifying ? '登录中...' : '登录图床'),
                  ),
                ),
                if (_profile != null) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final profile = _profile!;
                      final usedStorage =
                          profile.size.isFinite && profile.size > 0
                          ? profile.size
                          : 0.0;
                      final totalStorage =
                          profile.capacity.isFinite && profile.capacity > 0
                          ? profile.capacity
                          : 0.0;
                      final usageRatio = totalStorage <= 0
                          ? 0.0
                          : (usedStorage / totalStorage).clamp(0.0, 1.0);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow
                              .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundImage: profile.avatar.isEmpty
                                      ? null
                                      : CachedNetworkImageProvider(
                                          profile.avatar,
                                        ),
                                  child: profile.avatar.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.name.isEmpty
                                            ? profile.username
                                            : profile.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        '图片 ${profile.imageNum} · 相册 ${profile.albumNum}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_loading)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  '容量使用',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  totalStorage <= 0
                                      ? '未获取'
                                      : '${(usageRatio * 100).toStringAsFixed(1)}%',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: totalStorage <= 0 ? 0 : usageRatio,
                                minHeight: 9,
                                backgroundColor: theme
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.65),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              totalStorage <= 0
                                  ? '暂未获取容量上限'
                                  : '已用 ${_formatStorageValue(usedStorage)} / 共 ${_formatStorageValue(totalStorage)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ImageHostSectionCard(
            title: '上传默认参数',
            subtitle: '默认公开上传，仅保留相册归档设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 18,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '编辑器上传默认使用公开权限，上传后可直接分享图片链接。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _albumId,
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('相册：不指定'),
                    ),
                    ..._albums.map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text('${item.name} (#${item.id})'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _albumId = value);
                    widget.settingsController.updatePicUiDefaultAlbumId(
                      _albumId,
                    );
                    _persistUploadOptionSettings();
                  },
                  decoration: const InputDecoration(
                    labelText: '默认相册',
                    hintText: '不指定时上传到默认位置',
                    helperText: '设置后，编辑器上传图片会自动归档到该相册',
                    prefixIcon: Icon(Icons.photo_album_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _loading ? null : _reloadRemote,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新相册列表'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ImageHostSectionCard(
            title: '我的图片',
            subtitle: '左右滑动浏览你上传的图片，点开可预览，支持复制与删除',
            trailing: TextButton.icon(
              onPressed: _images.isEmpty ? null : _openAllImagesGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('全部图片'),
            ),
            child: _buildMyImageSwiper(theme),
          ),
          const SizedBox(height: 14),
          _ImageHostSectionCard(
            title: '我的相册',
            subtitle: '与当前登录账号同步的 PicUI 相册',
            child: _albums.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '暂无相册或未登录',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: _albums
                        .take(10)
                        .map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.name.isEmpty ? '相册 #${item.id}' : item.name,
                            ),
                            subtitle: Text('图片数：${item.imageNum}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteAlbum(item),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ImageHostSectionCard extends StatelessWidget {
  const _ImageHostSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface.withValues(alpha: 0.86),
            theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ...?(trailing == null ? null : <Widget>[trailing!]),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ImageHostSwitchTile extends StatelessWidget {
  const _ImageHostSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: value
            ? selectedColor.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? selectedColor.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: value
                ? selectedColor.withValues(alpha: 0.16)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: value ? selectedColor : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: value ? selectedColor : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _PicUiAuthWebViewDialogPage extends StatefulWidget {
  const _PicUiAuthWebViewDialogPage({required this.baseUrl});

  final String baseUrl;

  @override
  State<_PicUiAuthWebViewDialogPage> createState() =>
      _PicUiAuthWebViewDialogPageState();
}

class _PicUiAuthWebViewDialogPageState
    extends State<_PicUiAuthWebViewDialogPage> {
  static final RegExp _apiTokenPattern = RegExp(
    r'\b\d+\|[A-Za-z0-9_-]{20,}\b',
    caseSensitive: false,
  );

  static const String _probeScript = r'''
(() => {
  const values = [];
  const push = (value) => {
    if (value === null || value === undefined) return;
    const text = String(value);
    if (text.trim().length === 0) return;
    values.push(text);
  };
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      const v = localStorage.getItem(k);
      push(k);
      push(v);
      push(k + '=' + v);
    }
  } catch (_) {}
  try {
    for (let i = 0; i < sessionStorage.length; i++) {
      const k = sessionStorage.key(i);
      const v = sessionStorage.getItem(k);
      push(k);
      push(v);
      push(k + '=' + v);
    }
  } catch (_) {}
  try { push(document.cookie || ''); } catch (_) {}
  try { push(window.location.href || ''); } catch (_) {}
  try { push(document.body ? document.body.innerText : ''); } catch (_) {}
  return JSON.stringify(values);
})();
''';

  static const String _autoCreateTokenScript = r'''
(() => {
  const normalize = (v) => String(v ?? '').trim().toLowerCase();
  const bodyText = String(document.body?.innerText || '');
  const tokenReg = /\b\d+\|[A-Za-z0-9_-]{20,}\b/;
  if (tokenReg.test(bodyText)) {
    return JSON.stringify({ existing: true, opened: false, filled: false, submitted: false });
  }
  const now = Date.now();
  if (!window.__riverTokenAutoState) {
    window.__riverTokenAutoState = { openedAt: 0, submittedAt: 0 };
  }
  const state = window.__riverTokenAutoState;
  const visible = (el) => {
    if (!el) return false;
    const style = window.getComputedStyle(el);
    if (!style) return false;
    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const textOf = (el) => normalize(el.innerText || el.textContent || el.value || '');
  const allButtons = () => [
    ...document.querySelectorAll('button'),
    ...document.querySelectorAll('[role="button"]'),
    ...document.querySelectorAll('a'),
  ];
  const clickByKeywords = (keywords) => {
    const lowered = keywords.map((k) => normalize(k));
    const candidate = allButtons().find((el) => {
      if (!visible(el) || !!el.disabled) return false;
      const text = textOf(el);
      return lowered.some((k) => text.includes(k));
    });
    if (candidate) {
      candidate.click();
      return true;
    }
    return false;
  };
  const findNameInput = () => {
    const exact = document.querySelector('input[name="name"]');
    if (exact && visible(exact) && !exact.readOnly && !exact.disabled) return exact;
    const candidates = [
      ...document.querySelectorAll('input[type="text"]'),
      ...document.querySelectorAll('input:not([type])'),
      ...document.querySelectorAll('textarea'),
    ].filter((el) => visible(el) && !el.readOnly && !el.disabled);
    const hintMatcher = /token|名称|name|标题|备注|description|描述/i;
    return candidates.find((el) => {
      const hint = [el.placeholder, el.name, el.id, el.getAttribute('aria-label')]
        .map((v) => String(v ?? ''))
        .join(' ');
      return hintMatcher.test(hint);
    }) || candidates[0];
  };
  const fillName = () => {
    const input = findNameInput();
    if (!input) return false;
    const value = 'River Auto Token ' + (new Date()).toISOString().slice(0, 16);
    input.focus();
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };

  const createKeywords = [
    '创建token',
    '创建 token',
    '新增token',
    '新增 token',
    'create token',
    'new token',
  ];
  const saveKeywords = ['保存', '创建', '确认', '提交', 'save', 'create'];
  let openResult = false;
  const fillResultDirect = fillName();
  let submitted = false;
  const submit = () => {
    if (now - Number(state.submittedAt || 0) < 2800) return false;
    const btn = document.querySelector('#token-create-btn');
    if (btn && visible(btn) && !btn.disabled) {
      btn.click();
      state.submittedAt = now;
      return true;
    }
    const fallback = clickByKeywords(saveKeywords);
    if (fallback) state.submittedAt = now;
    return fallback;
  };

  if (fillResultDirect) {
    submitted = submit();
    return JSON.stringify({ opened: false, filled: true, submitted, href: location.href });
  }
  if (!fillResultDirect) {
    if (now - Number(state.openedAt || 0) < 1800) {
      return JSON.stringify({ opened: false, filled: false, submitted: false, href: location.href });
    }
    const createBtn = document.querySelector('#token-create');
    if (createBtn && visible(createBtn) && !createBtn.disabled) {
      createBtn.click();
      openResult = true;
      state.openedAt = now;
    } else {
      openResult = clickByKeywords(createKeywords);
      if (openResult) state.openedAt = now;
    }
  }
  return JSON.stringify({ opened: openResult, filled: false, submitted: false, href: location.href });
})();
''';

  late final WebViewController _controller;
  bool _loading = true;
  bool _probing = false;
  bool _autoCreatingToken = false;
  bool _autoCreateAttempted = false;
  bool _submittedToken = false;
  DateTime? _lastTokensRedirectAt;
  String? _foundToken;

  Uri get _baseUri => Uri.parse(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = true;
            });
          },
          onPageFinished: (url) async {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
            });
            await _handlePostLoginFlow(url);
            await _tryProbeApiToken();
          },
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(_resolvePath('/login'));
  }

  Uri _resolvePath(String path) {
    return Uri(
      scheme: _baseUri.scheme,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: path,
    );
  }

  bool _isAuthPath(String path) {
    final normalized = path.toLowerCase();
    return normalized.startsWith('/login') ||
        normalized.startsWith('/register');
  }

  bool _isTokenPath(String path) {
    return path.toLowerCase().startsWith('/user/tokens');
  }

  Future<void> _handlePostLoginFlow(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return;
    }
    final path = uri.path.toLowerCase();
    if (_isTokenPath(path)) {
      await _runAutoCreateTokenFlow();
      return;
    }
    if (_isAuthPath(path)) {
      return;
    }
    if ((_foundToken ?? '').trim().isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    final lastJump = _lastTokensRedirectAt;
    if (lastJump != null &&
        now.difference(lastJump) < const Duration(seconds: 2)) {
      return;
    }
    _lastTokensRedirectAt = now;
    _openPath('/user/tokens');
  }

  Future<void> _tryProbeApiToken() async {
    if (_probing) {
      return;
    }
    _probing = true;
    try {
      final raw = await _controller.runJavaScriptReturningResult(_probeScript);
      final text = _normalizeJsPayload(raw);
      final found = _extractToken(text);
      if (!mounted || found == null || found.trim().isEmpty) {
        return;
      }
      if (_foundToken == found) {
        return;
      }
      setState(() => _foundToken = found);
      _finishWithToken(found);
    } catch (_) {
      // Keep silent; user may still manually navigate to token page.
    } finally {
      _probing = false;
    }
  }

  void _finishWithToken(String token) {
    final normalized = token.trim();
    if (_submittedToken || normalized.isEmpty || !mounted) {
      return;
    }
    _submittedToken = true;
    Navigator.of(context).pop(normalized);
  }

  Future<void> _runAutoCreateTokenFlow() async {
    if (_autoCreatingToken) {
      return;
    }
    if (_autoCreateAttempted) {
      return;
    }
    if ((_foundToken ?? '').trim().isNotEmpty) {
      return;
    }
    _autoCreateAttempted = true;
    _autoCreatingToken = true;
    try {
      for (var i = 0; i < 8; i++) {
        await _controller.runJavaScriptReturningResult(_autoCreateTokenScript);
        await Future<void>.delayed(const Duration(milliseconds: 750));
        await _tryProbeApiToken();
        if ((_foundToken ?? '').trim().isNotEmpty) {
          break;
        }
      }
    } catch (_) {
      // Ignore automation failures; user can operate manually.
    } finally {
      _autoCreatingToken = false;
    }
  }

  String _normalizeJsPayload(Object raw) {
    dynamic value = raw;
    for (var i = 0; i < 2; i++) {
      if (value is! String) {
        break;
      }
      final text = value.trim();
      if (!((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith('[') && text.endsWith(']')) ||
          (text.startsWith('{') && text.endsWith('}')))) {
        break;
      }
      try {
        value = jsonDecode(text);
      } catch (_) {
        break;
      }
    }
    if (value is List) {
      return value.map((entry) => '$entry').join('\n');
    }
    if (value is Map) {
      return value.values.map((entry) => '$entry').join('\n');
    }
    return '$value';
  }

  String? _extractToken(String source) {
    final match = _apiTokenPattern.firstMatch(source);
    return match?.group(0);
  }

  void _openPath(String path) {
    if (path == '/user/tokens') {
      _controller.loadRequest(Uri.parse('https://picui.cn/user/tokens'));
      return;
    }
    _controller.loadRequest(_resolvePath(path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2.2),
            ),
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.90),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '正在打开登录页',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildFloatingWebAction(
                        tooltip: '关闭',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      _buildFloatingWebAction(
                        tooltip: 'Token 页面',
                        icon: Icons.key_rounded,
                        onPressed: () => _openPath('/user/tokens'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_foundToken == null || _autoCreatingToken || _probing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.20,
                            ),
                          ),
                        ),
                        child: Text(
                          _foundToken == null
                              ? (_autoCreatingToken
                                    ? '正在自动创建并提取 Token...'
                                    : (_probing
                                          ? '正在检测 Token...'
                                          : '等待自动提取 Token...'))
                              : '检测到 Token，正在自动应用...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.20,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: 0.08,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFloatingWebAction(
                            tooltip: '登录页',
                            icon: Icons.login_rounded,
                            onPressed: () => _openPath('/login'),
                          ),
                          _buildFloatingWebAction(
                            tooltip: '注册页',
                            icon: Icons.person_add_alt_1_rounded,
                            onPressed: () => _openPath('/register'),
                          ),
                          _buildFloatingWebAction(
                            tooltip: '刷新',
                            icon: Icons.refresh_rounded,
                            onPressed: _loading
                                ? null
                                : () => _controller.reload(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingWebAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

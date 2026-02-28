import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:river/core/constants.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:river/core/widgets/river_snack_bar.dart';

import 'package:river/core/widgets/river_auto_animated_scroll.dart';
part 'river_image_viewer_components.dart';

class RiverImageViewerItem {
  const RiverImageViewerItem({
    required this.url,
    this.headers,
    required this.heroTag,
    this.imageProvider,
  });

  final String url;
  final Map<String, String>? headers;
  final String heroTag;
  final ImageProvider<Object>? imageProvider;
}

typedef RiverImageViewerActionHandler =
    Future<void> Function(BuildContext context, RiverImageViewerItem item);

class RiverImageViewerAction {
  const RiverImageViewerAction({
    required this.id,
    required this.label,
    this.icon,
    required this.onSelected,
  });

  final String id;
  final String label;
  final IconData? icon;
  final RiverImageViewerActionHandler onSelected;
}

class RiverImageViewerPage extends StatefulWidget {
  const RiverImageViewerPage({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.extraActions = const <RiverImageViewerAction>[],
  });

  final List<RiverImageViewerItem> items;
  final int initialIndex;
  final List<RiverImageViewerAction> extraActions;

  static Future<void> open(
    BuildContext context, {
    required List<RiverImageViewerItem> items,
    int initialIndex = 0,
    List<RiverImageViewerAction> extraActions =
        const <RiverImageViewerAction>[],
  }) async {
    if (items.isEmpty) {
      return;
    }
    final safeIndex = initialIndex.clamp(0, items.length - 1);
    await Navigator.of(context).push(
      riverPageRoute<void>(
        enableFullScreenSwipeBack: false,
        builder: (_) => RiverImageViewerPage(
          items: items,
          initialIndex: safeIndex,
          extraActions: extraActions,
        ),
      ),
    );
  }

  @override
  State<RiverImageViewerPage> createState() => _RiverImageViewerPageState();
}

class _RiverImageViewerPageState extends State<RiverImageViewerPage> {
  static const String _actionSaveOriginal = 'save_original';
  static const String _actionEditImage = 'edit_image';
  static const String _actionRecognizeQr = 'recognize_qr';
  static const String _labelActionSheetTitle = '图片操作';
  static const String _labelActionCancel = '取消';
  static const String _labelRecognizeQr = '识别该二维码';
  static const String _labelQrResultTitle = '二维码识别结果';
  static const String _labelQrResultEmpty = '未识别到二维码内容';
  static const String _labelQrCopy = '复制内容';
  static const String _labelQrOpen = '打开内容';
  static const String _labelCopied = '已复制到剪贴板';

  late final PageController _pageController;
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  final Map<String, String?> _qrDecodeCache = <String, String?>{};
  late int _currentIndex;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
  }

  Future<void> _showImageActions(RiverImageViewerItem item) async {
    final actions = <RiverImageViewerAction>[
      RiverImageViewerAction(
        id: _actionSaveOriginal,
        label: '\u4fdd\u5b58\u539f\u56fe',
        icon: Icons.download_outlined,
        onSelected: (context, selected) => _saveOriginalImage(selected),
      ),
      RiverImageViewerAction(
        id: _actionEditImage,
        label: '\u7f16\u8f91\u56fe\u7247',
        icon: Icons.tune_rounded,
        onSelected: (context, selected) => _editImage(selected),
      ),
      ...widget.extraActions,
    ];
    if (actions.isEmpty) {
      return;
    }
    final selected = await _showModernImageActionSheet(
      actions,
      asyncAction: _resolveQrCodeContent(item).then((qrContent) {
        if (qrContent == null || qrContent.trim().isEmpty) {
          return null;
        }
        return RiverImageViewerAction(
          id: _actionRecognizeQr,
          label: _labelRecognizeQr,
          icon: Icons.qr_code_2_rounded,
          onSelected: (context, selected) =>
              _showQrRecognitionResult(qrContent),
        );
      }),
      insertBeforeTailCount: widget.extraActions.length,
    );
    if (!mounted || selected == null) {
      return;
    }
    try {
      await selected.onSelected(context, item);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is StateError
          ? error.message.toString()
          : '\u64cd\u4f5c\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5';
      ScaffoldMessenger.of(context).showRiverSnackBar(message);
    }
  }

  Future<RiverImageViewerAction?> _showModernImageActionSheet(
    List<RiverImageViewerAction> initialActions, {
    Future<RiverImageViewerAction?>? asyncAction,
    int insertBeforeTailCount = 0,
  }) {
    final actions = List<RiverImageViewerAction>.from(initialActions);
    var asyncStarted = false;
    return showModalBottomSheet<RiverImageViewerAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!asyncStarted && asyncAction != null) {
              asyncStarted = true;
              unawaited(() async {
                RiverImageViewerAction? resolved;
                try {
                  resolved = await asyncAction;
                } catch (_) {
                  // Ignore async action failures.
                }
                if (!sheetContext.mounted) {
                  return;
                }
                final resolvedAction = resolved;
                setModalState(() {
                  if (resolvedAction != null &&
                      actions.every((item) => item.id != resolvedAction.id)) {
                    var insertionIndex = actions.length - insertBeforeTailCount;
                    if (insertionIndex < 0) {
                      insertionIndex = 0;
                    }
                    if (insertionIndex > actions.length) {
                      insertionIndex = actions.length;
                    }
                    actions.insert(insertionIndex, resolvedAction);
                  }
                });
              }());
            }

            final theme = Theme.of(sheetContext);
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  color: theme.colorScheme.surface.withValues(alpha: 0.96),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.36,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.72,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _labelActionSheetTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RiverAutoAnimatedListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        itemCount: actions.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final action = actions[index];
                          return _ViewerActionTile(
                            icon: action.icon,
                            label: action.label,
                            onTap: () => Navigator.of(sheetContext).pop(action),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text(_labelActionCancel),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _qrCacheKey(RiverImageViewerItem item) {
    final hasCookie = (item.headers?['Cookie'] ?? '').trim().isNotEmpty;
    return '${item.url}#${hasCookie ? 'auth' : 'anon'}';
  }

  Future<String?> _resolveQrCodeContent(RiverImageViewerItem item) async {
    if (kIsWeb) {
      return null;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    final key = _qrCacheKey(item);
    if (_qrDecodeCache.containsKey(key)) {
      return _qrDecodeCache[key];
    }
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      _qrDecodeCache[key] = null;
      return null;
    }
    try {
      final bytes = await _downloadImageBytes(
        uri,
        item.headers,
      ).timeout(const Duration(seconds: 8));
      if (bytes.isEmpty) {
        _qrDecodeCache[key] = null;
        return null;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}'
        'river_qr_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      try {
        await file.writeAsBytes(bytes, flush: true);
        final inputImage = InputImage.fromFilePath(file.path);
        final barcodes = await _barcodeScanner.processImage(inputImage);
        for (final barcode in barcodes) {
          final value = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
          if (value.isNotEmpty) {
            _qrDecodeCache[key] = value;
            return value;
          }
        }
      } finally {
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Ignore decode errors.
    }
    _qrDecodeCache[key] = null;
    return null;
  }

  Future<void> _showQrRecognitionResult(String content) async {
    final value = content.trim();
    if (value.isEmpty) {
      throw StateError(_labelQrResultEmpty);
    }
    final uri = Uri.tryParse(value);
    final openUri = (uri != null && uri.hasScheme) ? uri : null;
    final canOpen = openUri != null;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Material(
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surface.withValues(alpha: 0.96),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.36,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _labelQrResultTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                      child: SelectableText(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: value),
                              );
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(
                                context,
                              ).showRiverSnackBar(_labelCopied);
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(_labelQrCopy),
                          ),
                        ),
                        if (canOpen) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await launchUrl(
                                  openUri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text(_labelQrOpen),
                            ),
                          ),
                        ],
                      ],
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

  Future<void> _saveOriginalImage(RiverImageViewerItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      throw StateError('\u56fe\u7247\u5730\u5740\u65e0\u6548');
    }
    final granted = await _ensureStoragePermission();
    if (!mounted) {
      return;
    }
    if (!granted) {
      throw StateError(
        '\u672a\u83b7\u5f97\u76f8\u518c\u6743\u9650\uff0c\u65e0\u6cd5\u4fdd\u5b58\u56fe\u7247',
      );
    }
    ScaffoldMessenger.of(
      context,
    ).showRiverSnackBar('\u6b63\u5728\u4fdd\u5b58\u539f\u56fe...');
    final bytes = await _downloadImageBytes(uri, item.headers);
    final name = _guessImageFileName(uri);
    final result = await ImageGallerySaverPlus.saveImage(
      Uint8List.fromList(bytes),
      quality: 100,
      name: name,
    );
    final outcome = _parseSaveResult(result);
    if (!outcome.success) {
      throw StateError(
        outcome.message ?? '\u7cfb\u7edf\u76f8\u518c\u4fdd\u5b58\u5931\u8d25',
      );
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showRiverSnackBar(
      '\u539f\u56fe\u5df2\u4fdd\u5b58\u5230\u7cfb\u7edf\u76f8\u518c',
    );
  }

  Future<void> _editImage(RiverImageViewerItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      throw StateError('\u56fe\u7247\u5730\u5740\u65e0\u6548');
    }
    final bytes = await _downloadImageBytes(uri, item.headers);
    if (!mounted) {
      return;
    }
    var saved = false;
    final editorConfigs = _buildImageEditorConfigs(Theme.of(context));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProImageEditor.memory(
          Uint8List.fromList(bytes),
          configs: editorConfigs,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (editedBytes) async {
              final granted = await _ensureStoragePermission();
              if (!mounted) {
                return;
              }
              if (!granted) {
                ScaffoldMessenger.of(context).showRiverSnackBar(
                  '\u672a\u83b7\u5f97\u76f8\u518c\u6743\u9650\uff0c\u65e0\u6cd5\u4fdd\u5b58\u56fe\u7247',
                );
                return;
              }
              final result = await ImageGallerySaverPlus.saveImage(
                editedBytes,
                quality: 100,
                name: 'river_edit_${DateTime.now().millisecondsSinceEpoch}',
              );
              final outcome = _parseSaveResult(result);
              if (!outcome.success) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showRiverSnackBar(
                  outcome.message ??
                      '\u7f16\u8f91\u56fe\u7247\u4fdd\u5b58\u5931\u8d25',
                );
                return;
              }
              saved = true;
              if (!mounted) {
                return;
              }
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
    if (!mounted || !saved) {
      return;
    }
    ScaffoldMessenger.of(context).showRiverSnackBar(
      '\u7f16\u8f91\u540e\u7684\u56fe\u7247\u5df2\u4fdd\u5b58\u5230\u7cfb\u7edf\u76f8\u518c',
    );
  }

  ProImageEditorConfigs _buildImageEditorConfigs(ThemeData appTheme) {
    final colorScheme = appTheme.colorScheme;
    final useCupertino = defaultTargetPlatform == TargetPlatform.iOS;
    final canvasColor = Colors.black;
    final chromeColor = colorScheme.surface.withValues(alpha: 0.9);
    final chromeStrongColor = colorScheme.surfaceContainerHigh.withValues(
      alpha: 0.93,
    );
    final sheetColor = colorScheme.surfaceContainer.withValues(alpha: 0.96);
    final inactiveColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.82);
    final outlineColor = colorScheme.outlineVariant.withValues(alpha: 0.46);
    const uiOverlayStyle = SystemUiOverlayStyle.light;

    return ProImageEditorConfigs(
      designMode: useCupertino
          ? ImageEditorDesignMode.cupertino
          : ImageEditorDesignMode.material,
      theme: appTheme.copyWith(scaffoldBackgroundColor: canvasColor),
      mainEditor: MainEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: MainEditorStyle(
          background: canvasColor,
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          bottomBarBackground: chromeColor,
          bottomBarColor: colorScheme.onSurface,
          outsideCaptureAreaLayerOpacity: 0.26,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      paintEditor: PaintEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: PaintEditorStyle(
          background: canvasColor,
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          bottomBarBackground: chromeColor,
          bottomBarActiveItemColor: colorScheme.primary,
          bottomBarInactiveItemColor: inactiveColor,
          lineWidthBottomSheetBackground: sheetColor,
          opacityBottomSheetBackground: sheetColor,
          editSheetBackgroundColor: chromeStrongColor,
          editSheetColor: colorScheme.onSurface,
          editSheetPreviewAreaColor: colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.7),
          initialColor: colorScheme.primary,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      textEditor: TextEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: TextEditorStyle(
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          bottomBarBackground: chromeColor,
          background: canvasColor.withValues(alpha: 0.68),
          inputHintColor: inactiveColor,
          inputCursorColor: colorScheme.primary,
          fontScaleBottomSheetBackground: sheetColor,
          inputTextFieldBackground: colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.62),
          inputTextFieldBorderColor: outlineColor,
          inputTextFieldBorderRadius: BorderRadius.circular(14),
          inputTextFieldPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        initialPrimaryColor: colorScheme.onSurface,
        initialSecondaryColor: colorScheme.primary.withValues(alpha: 0.22),
        defaultTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cropRotateEditor: CropRotateEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: CropRotateEditorStyle(
          background: canvasColor,
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          bottomBarBackground: chromeColor,
          bottomBarColor: colorScheme.onSurface,
          cropCornerColor: colorScheme.primary,
          helperLineColor: colorScheme.primary.withValues(alpha: 0.75),
          cropOverlayColor: Colors.black,
          aspectRatioSheetBackgroundColor: sheetColor,
          aspectRatioSheetForegroundColor: colorScheme.onSurface,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      filterEditor: FilterEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: FilterEditorStyle(
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          background: canvasColor,
          previewTextColor: inactiveColor,
          previewSelectedTextColor: colorScheme.primary,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      tuneEditor: TuneEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: TuneEditorStyle(
          appBarBackground: chromeColor,
          appBarColor: colorScheme.onSurface,
          bottomBarBackground: chromeColor,
          bottomBarActiveItemColor: colorScheme.primary,
          bottomBarInactiveItemColor: inactiveColor,
          background: canvasColor,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      blurEditor: BlurEditorConfigs(
        safeArea: const EditorSafeArea.none(),
        style: BlurEditorStyle(
          appBarBackgroundColor: chromeColor,
          appBarForegroundColor: colorScheme.onSurface,
          background: canvasColor,
          uiOverlayStyle: uiOverlayStyle,
        ),
      ),
      emojiEditor: EmojiEditorConfigs(
        style: EmojiEditorStyle(
          backgroundColor: chromeStrongColor,
          bottomActionBarConfig: BottomActionBarConfig(
            showBackspaceButton: false,
            backgroundColor: chromeStrongColor,
            buttonColor: colorScheme.primary.withValues(alpha: 0.2),
            buttonIconColor: colorScheme.primary,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: chromeStrongColor,
            indicatorColor: colorScheme.primary,
            iconColor: inactiveColor,
            iconColorSelected: colorScheme.primary,
            backspaceColor: colorScheme.primary,
            dividerColor: outlineColor,
          ),
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: chromeStrongColor,
            noRecents: Text(
              '暂无最近表情',
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: chromeStrongColor,
            buttonIconColor: inactiveColor,
            hintText: '搜索',
            hintTextStyle: TextStyle(color: inactiveColor),
            inputTextStyle: TextStyle(color: colorScheme.onSurface),
          ),
          skinToneConfig: SkinToneConfig(
            dialogBackgroundColor: sheetColor,
            indicatorColor: colorScheme.primary,
          ),
          categoryTitleStyle: TextStyle(
            color: inactiveColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      dialogConfigs: DialogConfigs(
        style: DialogStyle(
          loadingDialog: LoadingDialogStyle(
            textColor: colorScheme.onSurface,
            cupertinoPrimaryColorLight: colorScheme.primary,
            cupertinoPrimaryColorDark: colorScheme.primary,
          ),
          adaptiveDialog: AdaptiveDialogStyle(
            cupertinoPrimaryColorLight: colorScheme.primary,
            cupertinoPrimaryColorDark: colorScheme.primary,
          ),
        ),
      ),
      i18n: _buildChineseImageEditorI18n(),
    );
  }

  I18n _buildChineseImageEditorI18n() {
    return const I18n(
      importStateHistoryMsg: '正在初始化编辑器...',
      cancel: '取消',
      undo: '撤销',
      redo: '重做',
      done: '完成',
      remove: '移除',
      doneLoadingMsg: '正在生成图片...',
      various: I18nVarious(
        loadingDialogMsg: '请稍候...',
        closeEditorWarningTitle: '退出编辑？',
        closeEditorWarningMessage: '当前修改尚未保存，确定要退出吗？',
        closeEditorWarningConfirmBtn: '退出',
        closeEditorWarningCancelBtn: '继续编辑',
      ),
      layerInteraction: I18nLayerInteraction(
        remove: '删除',
        edit: '编辑',
        rotateScale: '旋转/缩放',
      ),
      paintEditor: I18nPaintEditor(
        moveAndZoom: '移动与缩放',
        bottomNavigationBarText: '涂鸦',
        freestyle: '自由画笔',
        freestyleArrowStart: '自由线(起点箭头)',
        freestyleArrowEnd: '自由线(终点箭头)',
        freestyleArrowStartEnd: '自由线(双向箭头)',
        arrow: '箭头',
        line: '直线',
        rectangle: '矩形',
        circle: '圆形',
        dashLine: '虚线',
        dashDotLine: '点划线',
        hexagon: '六边形',
        polygon: '多边形',
        blur: '模糊',
        pixelate: '像素化',
        custom1: '自定义 1',
        custom2: '自定义 2',
        custom3: '自定义 3',
        lineWidth: '线宽',
        eraser: '橡皮擦',
        toggleFill: '填充开关',
        changeOpacity: '透明度',
        undo: '撤销',
        redo: '重做',
        done: '完成',
        back: '返回',
        smallScreenMoreTooltip: '更多',
        opacity: '透明度',
        color: '颜色',
        strokeWidth: '描边粗细',
        fill: '填充',
        cancel: '取消',
      ),
      textEditor: I18nTextEditor(
        inputHintText: '输入文字',
        bottomNavigationBarText: '文字',
        back: '返回',
        done: '完成',
        textAlign: '文字对齐',
        fontScale: '字号',
        backgroundMode: '背景模式',
        smallScreenMoreTooltip: '更多',
      ),
      cropRotateEditor: I18nCropRotateEditor(
        bottomNavigationBarText: '裁剪/旋转',
        rotate: '旋转',
        flip: '翻转',
        ratio: '比例',
        back: '返回',
        done: '完成',
        cancel: '取消',
        undo: '撤销',
        redo: '重做',
        smallScreenMoreTooltip: '更多',
        reset: '重置',
      ),
      tuneEditor: I18nTuneEditor(
        bottomNavigationBarText: '调节',
        back: '返回',
        done: '完成',
        brightness: '亮度',
        contrast: '对比度',
        saturation: '饱和度',
        exposure: '曝光',
        hue: '色相',
        temperature: '色温',
        sharpness: '锐化',
        fade: '褪色',
        luminance: '明度',
        undo: '撤销',
        redo: '重做',
      ),
      filterEditor: I18nFilterEditor(
        bottomNavigationBarText: '滤镜',
        back: '返回',
        done: '完成',
        filters: I18nFilters(
          none: '无滤镜',
          addictiveBlue: '蓝调',
          addictiveRed: '红调',
          aden: '雅登',
          amaro: '阿玛罗',
          ashby: '阿什比',
          brannan: '布兰南',
          brooklyn: '布鲁克林',
          charmes: '夏慕',
          clarendon: '克拉伦登',
          crema: '克雷玛',
          dogpatch: '道格帕奇',
          earlybird: '晨鸟',
          f1977: '1977',
          gingham: '金格姆',
          ginza: '银座',
          hefe: '海菲',
          helena: '海伦娜',
          hudson: '哈德森',
          inkwell: '墨色',
          juno: '朱诺',
          kelvin: '开尔文',
          lark: '云雀',
          loFi: '高反差',
          ludwig: '路德维希',
          maven: '梅文',
          mayfair: '梅菲尔',
          moon: '月光',
          nashville: '纳什维尔',
          perpetua: '珀佩图阿',
          reyes: '雷耶斯',
          rise: '初升',
          sierra: '内华达',
          skyline: '天际线',
          slumber: '沉眠',
          stinson: '斯廷森',
          sutro: '苏特罗',
          toaster: '烘烤',
          valencia: '瓦伦西亚',
          vesper: '维斯珀',
          walden: '瓦尔登',
          willow: '柳影',
          xProII: 'X-Pro II',
        ),
      ),
      blurEditor: I18nBlurEditor(
        bottomNavigationBarText: '模糊',
        back: '返回',
        done: '完成',
      ),
      emojiEditor: I18nEmojiEditor(
        bottomNavigationBarText: '表情',
        search: '搜索',
        categoryRecent: '最近使用',
        categorySmileys: '笑脸与人物',
        categoryAnimals: '动物与自然',
        categoryFood: '食物与饮料',
        categoryActivities: '活动',
        categoryTravel: '旅行与地点',
        categoryObjects: '物品',
        categorySymbols: '符号',
        categoryFlags: '旗帜',
      ),
      stickerEditor: I18nStickerEditor(bottomNavigationBarText: '贴纸'),
    );
  }

  Future<bool> _ensureStoragePermission() async {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final addOnlyStatus = await Permission.photosAddOnly.status;
      if (addOnlyStatus.isGranted || addOnlyStatus.isLimited) {
        return true;
      }
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }

      final addOnlyRequested = await Permission.photosAddOnly.request();
      if (addOnlyRequested.isGranted || addOnlyRequested.isLimited) {
        return true;
      }

      final photosRequested = await Permission.photos.request();
      return photosRequested.isGranted || photosRequested.isLimited;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    final photos = await Permission.photos.request();
    if (photos.isGranted || photos.isLimited) {
      return true;
    }
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  String _guessImageFileName(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final sanitized = last.split('?').first.trim();
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
    return 'river_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  Future<List<int>> _downloadImageBytes(
    Uri uri,
    Map<String, String>? sourceHeaders,
  ) async {
    final candidates = _buildDownloadHeaderCandidates(uri, sourceHeaders);
    final statuses = <int>[];
    for (final headers in candidates) {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      statuses.add(response.statusCode);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    }
    final joined = statuses.isEmpty ? 'unknown' : statuses.join('/');
    throw StateError(
      '\u56fe\u7247\u4e0b\u8f7d\u5931\u8d25\uff08HTTP $joined\uff09',
    );
  }

  List<Map<String, String>?> _buildDownloadHeaderCandidates(
    Uri uri,
    Map<String, String>? sourceHeaders,
  ) {
    final candidates = <Map<String, String>?>[];
    void add(Map<String, String>? headers) {
      final normalized = _normalizeHeaders(headers);
      final key = normalized == null
          ? '<none>'
          : normalized.entries.map((e) => '${e.key}=${e.value}').join('&');
      final exists = candidates.any((item) {
        final current = _normalizeHeaders(item);
        final currentKey = current == null
            ? '<none>'
            : current.entries.map((e) => '${e.key}=${e.value}').join('&');
        return currentKey == key;
      });
      if (!exists) {
        candidates.add(normalized);
      }
    }

    final stripped = _headersWithoutCookie(sourceHeaders);
    final browserHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': '${uri.scheme}://${uri.host}/',
    };
    add(sourceHeaders);
    add(stripped);
    add({...?stripped, ...browserHeaders});
    add(browserHeaders);
    return candidates;
  }

  Map<String, String>? _normalizeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    final normalized = <String, String>{};
    headers.forEach((key, value) {
      final k = key.trim();
      final v = value.trim();
      if (k.isEmpty || v.isEmpty) {
        return;
      }
      normalized[k] = v;
    });
    return normalized.isEmpty ? null : normalized;
  }

  ({bool success, String? message}) _parseSaveResult(dynamic result) {
    if (result is bool) {
      return (
        success: result,
        message: result
            ? null
            : '\u7cfb\u7edf\u76f8\u518c\u4fdd\u5b58\u5931\u8d25',
      );
    }
    if (result is Map) {
      final map = <String, dynamic>{};
      result.forEach((key, value) {
        map['$key'] = value;
      });
      final isSuccess =
          map['isSuccess'] == true ||
          map['success'] == true ||
          (map['filePath']?.toString().trim().isNotEmpty ?? false);
      if (isSuccess) {
        return (success: true, message: null);
      }
      final errorMessage = (map['errorMessage'] ?? map['error'] ?? '')
          .toString()
          .trim();
      return (
        success: false,
        message: errorMessage.isEmpty
            ? '\u7cfb\u7edf\u76f8\u518c\u4fdd\u5b58\u5931\u8d25'
            : errorMessage,
      );
    }
    return (
      success: false,
      message: '\u7cfb\u7edf\u76f8\u518c\u4fdd\u5b58\u5931\u8d25',
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    final current = _currentIndex + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleOverlay,
              behavior: HitTestBehavior.opaque,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return Center(
                    child: Hero(
                      tag: item.heroTag,
                      child: _ViewerZoomableImage(
                        item: item,
                        onLongPress: () => _showImageActions(item),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showOverlay ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        color: Colors.white,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          '$current / $count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showOverlay ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: _PageIndicator(
                  controller: _pageController,
                  itemCount: widget.items.length,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isRiverSideImageUrl(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').trim().toLowerCase();
  if (host.isEmpty) {
    return false;
  }
  final forumHost = Uri.parse(riverSideBaseUrl).host.toLowerCase();
  return host == forumHost || host.endsWith('.$forumHost');
}

Map<String, String>? _headersWithoutCookie(Map<String, String>? source) {
  if (source == null || source.isEmpty) {
    return source;
  }
  final next = <String, String>{};
  source.forEach((key, value) {
    if (key.toLowerCase() == 'cookie') {
      return;
    }
    next[key] = value;
  });
  return next;
}

String _buildImageCacheKey(String url, Map<String, String>? headers) {
  final cookie = (headers?['Cookie'] ?? '').trim();
  if (cookie.isEmpty) {
    return url;
  }
  return '$url#auth';
}




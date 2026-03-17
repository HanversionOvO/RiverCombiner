import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image/image.dart' as img;
import 'package:river/core/widgets/river_structured_emoji_picker.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

typedef RiverMarkdownSubmitCallback = Future<bool> Function(String markdown);
typedef RiverMarkdownImageUploadCallback =
    Future<String?> Function(String fileName, List<int> bytes);
typedef RiverMarkdownDraftLoadCurrentCallback =
    Future<RiverMarkdownDraftEntry?> Function();
typedef RiverMarkdownDraftSaveCallback =
    Future<RiverMarkdownDraftEntry?> Function(String markdown, int? sequence);
typedef RiverMarkdownDraftLoadListCallback =
    Future<List<RiverMarkdownDraftEntry>> Function();
typedef RiverMarkdownDraftDeleteCallback =
    Future<bool> Function(RiverMarkdownDraftEntry draft);
typedef RiverMarkdownAiGenerateCallback =
    Future<String?> Function(RiverMarkdownAiRequest request);
typedef RiverMarkdownAiGenerateStreamCallback =
    Stream<String> Function(RiverMarkdownAiRequest request);
typedef RiverMarkdownMentionSearchCallback =
    Future<List<RiverMarkdownMentionUser>> Function(String query);

const String _assetEmojiScheme = 'asset://';

bool _isAssetEmojiUrl(String source) =>
    source.trim().toLowerCase().startsWith(_assetEmojiScheme);

String _assetPathFromEmojiUrl(String source) =>
    source.trim().substring(_assetEmojiScheme.length);

class RiverMarkdownDraftEntry {
  const RiverMarkdownDraftEntry({
    required this.draftKey,
    required this.sequence,
    required this.markdown,
    this.title = '',
    this.subtitle = '',
    this.updatedAt,
  });

  final String draftKey;
  final int sequence;
  final String markdown;
  final String title;
  final String subtitle;
  final DateTime? updatedAt;
}

class RiverMarkdownMentionUser {
  const RiverMarkdownMentionUser({
    required this.key,
    required this.insertText,
    this.displayName = '',
    this.username = '',
    this.avatarUrl = '',
    this.subtitle = '',
  });

  final String key;
  final String insertText;
  final String displayName;
  final String username;
  final String avatarUrl;
  final String subtitle;
}

enum RiverMarkdownAiScene { generic, topicReply, topicCompose, editComment }

class RiverMarkdownAiRequest {
  const RiverMarkdownAiRequest({
    required this.scene,
    required this.instruction,
    required this.currentMarkdown,
    this.referenceMarkdown,
  });

  final RiverMarkdownAiScene scene;
  final String instruction;
  final String currentMarkdown;
  final String? referenceMarkdown;
}

enum _EditorMode { edit, preview }

enum _ImagePickSource { camera, gallery }

class _PickedImageUploadData {
  const _PickedImageUploadData({required this.fileName, required this.bytes});

  final String fileName;
  final List<int> bytes;
}

class _MentionTrigger {
  const _MentionTrigger({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class RiverMarkdownEditor extends StatefulWidget {
  const RiverMarkdownEditor({
    super.key,
    required this.onSubmit,
    this.onUploadImage,
    this.title,
    this.hintText,
    this.submitLabel,
    this.initialText = '',
    this.emojiUrls = const <String, String>{},
    this.emojiGroups = const <String, List<String>>{},
    this.closeOnSubmitSuccess = true,
    this.autofocus = true,
    this.maxHeight = 0,
    this.enablePreview = true,
    this.onLoadCurrentDraft,
    this.onSaveDraft,
    this.onLoadDrafts,
    this.onDeleteDraft,
    this.onAiGenerate,
    this.onAiGenerateStream,
    this.aiScene = RiverMarkdownAiScene.generic,
    this.aiReplyReferenceText,
    this.emojiInsertFormatter,
    this.onSearchMentionUsers,
  });

  final RiverMarkdownSubmitCallback onSubmit;
  final RiverMarkdownImageUploadCallback? onUploadImage;
  final String? title;
  final String? hintText;
  final String? submitLabel;
  final String initialText;
  final Map<String, String> emojiUrls;
  final Map<String, List<String>> emojiGroups;
  final bool closeOnSubmitSuccess;
  final bool autofocus;
  final double maxHeight;
  final bool enablePreview;
  final RiverMarkdownDraftLoadCurrentCallback? onLoadCurrentDraft;
  final RiverMarkdownDraftSaveCallback? onSaveDraft;
  final RiverMarkdownDraftLoadListCallback? onLoadDrafts;
  final RiverMarkdownDraftDeleteCallback? onDeleteDraft;
  final RiverMarkdownAiGenerateCallback? onAiGenerate;
  final RiverMarkdownAiGenerateStreamCallback? onAiGenerateStream;
  final RiverMarkdownAiScene aiScene;
  final String? aiReplyReferenceText;
  final String Function(String key)? emojiInsertFormatter;
  final RiverMarkdownMentionSearchCallback? onSearchMentionUsers;

  @override
  State<RiverMarkdownEditor> createState() => _RiverMarkdownEditorState();
}

class _RiverMarkdownEditorState extends State<RiverMarkdownEditor> {
  static const double _emojiPanelHeight = 296;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _editStackKey = GlobalKey();
  final GlobalKey _editFieldKey = GlobalKey();
  Timer? _draftSaveDebounce;
  Timer? _mentionDebounce;

  static const int _maxGalleryPickCount = 3;
  static const int _imageUploadTargetMaxBytes = 1024 * 1024;

  bool _submitting = false;
  bool _uploadingImage = false;
  bool _loadingDraft = false;
  bool _savingDraft = false;
  bool _generatingAi = false;
  bool _showAiThinkingHint = false;
  bool _emojiPanelVisible = false;
  _EditorMode _mode = _EditorMode.edit;
  int? _draftSequence;
  String _lastDraftSavedContent = '';
  DateTime? _lastDraftSavedAt;
  bool _mentionLoading = false;
  int _mentionRequestSerial = 0;
  int? _mentionStartOffset;
  String _mentionQuery = '';
  Offset? _mentionAnchorOffset;
  List<RiverMarkdownMentionUser> _mentionUsers =
      const <RiverMarkdownMentionUser>[];

  bool get _draftEnabled => widget.onSaveDraft != null;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialText;
    if (widget.initialText.isNotEmpty) {
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialText.length,
      );
      _lastDraftSavedContent = widget.initialText;
    }
    _controller.addListener(_onEditorTextChanged);
    _focusNode.addListener(_onEditorFocusChanged);
    _loadCurrentDraft();
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();
    _mentionDebounce?.cancel();
    _controller.removeListener(_onEditorTextChanged);
    _focusNode.removeListener(_onEditorFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onEditorFocusChanged() {
    if (!mounted) {
      return;
    }
    if (!_focusNode.hasFocus) {
      _hideMentionPanel();
    } else {
      _hideEmojiPicker();
      _refreshMentionSuggestions(immediate: true);
    }
    setState(() {});
  }

  void _onEditorTextChanged() {
    _refreshMentionSuggestions();
    if (!_draftEnabled) {
      return;
    }
    if (_controller.text.trim().isEmpty) {
      return;
    }
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 1300), () {
      _saveDraft(showSnack: false);
    });
  }

  Future<void> _loadCurrentDraft() async {
    final callback = widget.onLoadCurrentDraft;
    if (callback == null) {
      return;
    }

    setState(() => _loadingDraft = true);
    try {
      final draft = await callback();
      if (!mounted || draft == null) {
        return;
      }
      _draftSequence = draft.sequence;
      if (_controller.text.trim().isEmpty && draft.markdown.trim().isNotEmpty) {
        _controller.text = draft.markdown;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
      _lastDraftSavedContent = _controller.text;
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _loadingDraft = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnack('内容不能为空', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final ok = await widget.onSubmit(text);
      if (!mounted) return;
      if (ok && widget.closeOnSubmitSuccess) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack('发送失败: $error', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveDraft({required bool showSnack}) async {
    final callback = widget.onSaveDraft;
    if (callback == null || _savingDraft) {
      return;
    }

    final markdown = _controller.text;
    if (markdown.trim().isEmpty) {
      if (showSnack) {
        _showSnack('内容为空，未保存草稿', isError: true);
      }
      return;
    }
    if (!showSnack && markdown == _lastDraftSavedContent) {
      return;
    }

    setState(() => _savingDraft = true);
    try {
      final saved = await callback(markdown, _draftSequence);
      if (!mounted) {
        return;
      }
      if (saved != null) {
        _draftSequence = saved.sequence;
      }
      _lastDraftSavedContent = markdown;
      _lastDraftSavedAt = DateTime.now();
      if (showSnack) {
        _showSnack('草稿已保存');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (showSnack) {
        _showSnack('草稿保存失败: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _savingDraft = false);
      }
    }
  }

  Future<void> _openDraftBox() async {
    final callback = widget.onLoadDrafts;
    if (callback == null) {
      _showSnack('当前页面未启用草稿箱');
      return;
    }

    List<RiverMarkdownDraftEntry> drafts = const <RiverMarkdownDraftEntry>[];
    try {
      drafts = await callback();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('草稿箱加载失败: $error', isError: true);
      return;
    }
    if (!mounted) {
      return;
    }

    final selected = await showModalBottomSheet<RiverMarkdownDraftEntry>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        if (drafts.isEmpty) {
          return _EditorActionSheetShell(
            title: '草稿箱',
            subtitle: '选择要恢复的草稿',
            icon: Icons.inventory_2_rounded,
            maxHeight: 280,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.28,
                        ),
                      ),
                    ),
                    child: Text(
                      '暂无草稿',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return _EditorActionSheetShell(
          title: '草稿箱',
          subtitle: '选择要恢复的草稿',
          icon: Icons.inventory_2_rounded,
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            itemCount: drafts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final draft = drafts[index];
              final title = draft.title.trim().isEmpty
                  ? draft.draftKey
                  : draft.title.trim();
              final subtitle = draft.subtitle.trim().isEmpty
                  ? draft.markdown.trim()
                  : draft.subtitle.trim();
              final updated = draft.updatedAt;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(sheetContext).pop(draft),
                  child: Ink(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: colorScheme.surface.withValues(alpha: 0.72),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.30,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.82,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.description_outlined,
                            size: 18,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle.isEmpty ? '无内容' : subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (updated != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${updated.month}-${updated.day} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.onDeleteDraft != null)
                          IconButton.filledTonal(
                            tooltip: '删除草稿',
                            onPressed: () async {
                              final ok = await widget.onDeleteDraft!(draft);
                              if (!context.mounted) {
                                return;
                              }
                              if (ok) {
                                Navigator.of(context).pop();
                              }
                            },
                            style: IconButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              backgroundColor: colorScheme.errorContainer
                                  .withValues(alpha: 0.7),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                          )
                        else
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }
    _controller.text = selected.markdown;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _draftSequence = selected.sequence;
    _lastDraftSavedContent = selected.markdown;
    _showSnack('已加载草稿');
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    final callback = widget.onUploadImage;
    if (callback == null) {
      _showSnack('当前不支持上传图片', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();

    final source = await _showImageSourceMenu();
    if (!mounted || source == null) {
      _focusNode.requestFocus();
      return;
    }

    List<_PickedImageUploadData> pickedImages;
    try {
      pickedImages = await _pickImagesBySource(source);
      if (pickedImages.isEmpty) return;
    } catch (error) {
      if (mounted) {
        _showSnack('选择图片失败: $error', isError: true);
      }
      return;
    }

    try {
      setState(() => _uploadingImage = true);

      var successCount = 0;
      var failedCount = 0;
      final insertedSegments = <String>[];

      for (final image in pickedImages) {
        final prepared = await _prepareImageForUpload(image);
        final inserted = await callback(prepared.fileName, prepared.bytes);
        if (inserted != null && inserted.trim().isNotEmpty) {
          successCount++;
          insertedSegments.add(inserted.trim());
        } else {
          failedCount++;
        }
      }
      if (!mounted) return;

      if (insertedSegments.isNotEmpty) {
        final merged = insertedSegments.map((segment) => '\n$segment\n').join();
        _insertText(merged);
        if (failedCount > 0) {
          _showSnack('已添加 $successCount 张图片，$failedCount 张上传失败');
        } else {
          _showSnack('已添加 $successCount 张图片');
        }
      } else {
        _showSnack('图片上传失败', isError: true);
      }
    } catch (error) {
      if (mounted) {
        _showSnack('插入图片失败: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
        _focusNode.requestFocus();
      }
    }
  }

  Future<_ImagePickSource?> _showImageSourceMenu() {
    return showModalBottomSheet<_ImagePickSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImageSourceSheet(),
    );
  }

  Future<List<_PickedImageUploadData>> _pickImagesBySource(
    _ImagePickSource source,
  ) async {
    if (source == _ImagePickSource.gallery) {
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: _maxGalleryPickCount,
          requestType: RequestType.image,
        ),
      );
      if (assets == null || assets.isEmpty) {
        return const <_PickedImageUploadData>[];
      }
      final images = <_PickedImageUploadData>[];
      final limit = assets.length > _maxGalleryPickCount
          ? _maxGalleryPickCount
          : assets.length;
      for (var i = 0; i < limit; i++) {
        final data = await _buildUploadDataFromAsset(
          assets[i],
          fallbackPrefix: 'gallery_${i + 1}',
        );
        if (data != null) {
          images.add(data);
        }
      }
      return images;
    }
    final entity = await CameraPicker.pickFromCamera(
      context,
      pickerConfig: const CameraPickerConfig(
        enableRecording: false,
        onlyEnableRecording: false,
      ),
    );
    if (entity == null) {
      return const <_PickedImageUploadData>[];
    }
    final image = await _buildUploadDataFromAsset(
      entity,
      fallbackPrefix: 'camera_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (image == null) {
      throw StateError('拍摄结果读取失败');
    }
    return <_PickedImageUploadData>[image];
  }

  Future<_PickedImageUploadData?> _buildUploadDataFromAsset(
    AssetEntity entity, {
    required String fallbackPrefix,
  }) async {
    final title = (entity.title ?? '').trim();
    final bytes = await entity.originBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return _PickedImageUploadData(
        fileName: title.isEmpty ? '$fallbackPrefix.jpg' : title,
        bytes: bytes,
      );
    }
    final file = await entity.file;
    if (file == null) {
      return null;
    }
    final fileBytes = await file.readAsBytes();
    if (fileBytes.isEmpty) {
      return null;
    }
    final fileNameFromPath = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.trim()
        : '';
    final resolvedName = title.isNotEmpty
        ? title
        : (fileNameFromPath.isNotEmpty
              ? fileNameFromPath
              : '$fallbackPrefix.jpg');
    return _PickedImageUploadData(fileName: resolvedName, bytes: fileBytes);
  }

  Future<_PickedImageUploadData> _prepareImageForUpload(
    _PickedImageUploadData source,
  ) async {
    final compressed = await _compressImageToTargetSize(
      source.bytes,
      maxBytes: _imageUploadTargetMaxBytes,
    );
    if (compressed == null || compressed.isEmpty) {
      return source;
    }
    return _PickedImageUploadData(
      fileName: _replaceFileExtension(source.fileName, 'jpg'),
      bytes: compressed,
    );
  }

  Future<List<int>?> _compressImageToTargetSize(
    List<int> sourceBytes, {
    required int maxBytes,
  }) async {
    final rawBytes = Uint8List.fromList(sourceBytes);
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return null;
    }

    List<int>? bestBytes;
    void rememberBest(List<int> candidateBytes) {
      if (candidateBytes.isEmpty) {
        return;
      }
      if (bestBytes == null || candidateBytes.length < bestBytes!.length) {
        bestBytes = candidateBytes;
      }
    }

    const qualitySteps = <int>[96, 90, 84, 78, 72, 66, 60, 54, 48, 42, 36, 30];
    const scaleSteps = <double>[1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.25];

    for (final scale in scaleSteps) {
      final minWidth = math.max(320, (decoded.width * scale).round());
      final minHeight = math.max(320, (decoded.height * scale).round());
      for (final quality in qualitySteps) {
        final compressed = await FlutterImageCompress.compressWithList(
          rawBytes,
          minWidth: minWidth,
          minHeight: minHeight,
          quality: quality,
          format: CompressFormat.jpeg,
          autoCorrectionAngle: true,
          keepExif: false,
        );
        if (compressed.isEmpty) {
          continue;
        }
        final candidate = compressed.toList(growable: false);
        rememberBest(candidate);
        if (candidate.length <= maxBytes) {
          return candidate;
        }
      }
    }

    return bestBytes;
  }

  String _replaceFileExtension(String fileName, String newExtension) {
    final cleanExtension = newExtension.toLowerCase().replaceFirst('.', '');
    final normalized = fileName.trim();
    if (normalized.isEmpty) {
      return 'upload_${DateTime.now().millisecondsSinceEpoch}.$cleanExtension';
    }
    final dotIndex = normalized.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == normalized.length - 1) {
      return '$normalized.$cleanExtension';
    }
    return '${normalized.substring(0, dotIndex)}.$cleanExtension';
  }

  void _showEmojiPicker() {
    HapticFeedback.selectionClick();
    if (_emojiPanelVisible) {
      _hideEmojiPicker();
      _focusNode.requestFocus();
      return;
    }
    _dismissKeyboard();
    if (!mounted) {
      return;
    }
    setState(() {
      _emojiPanelVisible = true;
    });
  }

  void _hideEmojiPicker() {
    if (!_emojiPanelVisible || !mounted) {
      return;
    }
    setState(() {
      _emojiPanelVisible = false;
    });
  }

  void _dismissKeyboard() {
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  List<_AiToolAction> _buildAiToolActions() {
    final actions = <_AiToolAction>[
      const _AiToolAction(
        title: '润色表达',
        subtitle: '保持原意，提升语气和可读性',
        instruction: '请润色这段内容，让表达更自然流畅。',
        icon: Icons.auto_fix_high_rounded,
      ),
      const _AiToolAction(
        title: '扩写内容',
        subtitle: '补充细节与上下文',
        instruction: '请扩写这段内容，补充必要细节，但不要偏题。',
        icon: Icons.unfold_more_double_rounded,
      ),
      const _AiToolAction(
        title: '精简内容',
        subtitle: '保留重点并更简洁',
        instruction: '请精简这段内容，保留核心信息。',
        icon: Icons.short_text_rounded,
      ),
      const _AiToolAction(
        title: '纠错优化',
        subtitle: '修正语病和错别字',
        instruction: '请修正错别字、语病，并保持原始语气。',
        icon: Icons.spellcheck_rounded,
      ),
      const _AiToolAction(
        title: '结构化排版',
        subtitle: '优化成清晰的 Markdown 结构',
        instruction: '请将内容改写为结构清晰的 Markdown 格式。',
        icon: Icons.view_list_rounded,
      ),
    ];
    final reference = (widget.aiReplyReferenceText ?? '').trim();
    if (widget.aiScene == RiverMarkdownAiScene.topicReply &&
        reference.isNotEmpty) {
      actions.insert(
        0,
        const _AiToolAction(
          title: '高情商回复',
          subtitle: '基于被回复内容生成更得体的回复',
          instruction: '请基于被回复内容，生成一段高情商且真诚的回复。',
          icon: Icons.favorite_border_rounded,
          needsReference: true,
        ),
      );
    }
    return actions;
  }

  Future<void> _openAiTools() async {
    final hasAi =
        widget.onAiGenerateStream != null || widget.onAiGenerate != null;
    if (!hasAi) {
      _showSnack('当前页面未接入 AI 能力', isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final actions = _buildAiToolActions();
    final selected = await showModalBottomSheet<_AiToolAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiToolsSheet(actions: actions),
    );
    if (!mounted || selected == null) {
      return;
    }
    await _generateAiText(selected);
  }

  Future<void> _generateAiText(_AiToolAction action) async {
    if (_generatingAi) {
      return;
    }
    final originalText = _controller.text;
    final originalSelection = _controller.selection;
    setState(() {
      _generatingAi = true;
      _showAiThinkingHint = true;
    });
    try {
      final request = RiverMarkdownAiRequest(
        scene: widget.aiScene,
        instruction: action.instruction,
        currentMarkdown: _controller.text,
        referenceMarkdown: action.needsReference
            ? widget.aiReplyReferenceText
            : null,
      );
      final stream = widget.onAiGenerateStream != null
          ? widget.onAiGenerateStream!(request)
          : _fallbackStreamFromFuture(request);
      final anchor = _createAiInsertAnchor();
      final buffer = StringBuffer();
      var hasChunk = false;

      await for (final chunk in stream) {
        if (!mounted) {
          return;
        }
        final value = chunk;
        if (value.isEmpty) {
          continue;
        }
        if (!hasChunk && _showAiThinkingHint) {
          setState(() => _showAiThinkingHint = false);
        }
        hasChunk = true;
        buffer.write(value);
        _replaceAiInsertedContent(anchor, buffer.toString());
      }

      if (!mounted) {
        return;
      }
      if (!hasChunk || buffer.toString().trim().isEmpty) {
        _restoreEditorValue(originalText, originalSelection);
        _showSnack('AI 未返回有效内容', isError: true);
        return;
      }
      _showSnack('AI 生成完成');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _restoreEditorValue(originalText, originalSelection);
      _showSnack('AI 生成失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _generatingAi = false;
          _showAiThinkingHint = false;
        });
      }
    }
  }

  Stream<String> _fallbackStreamFromFuture(
    RiverMarkdownAiRequest request,
  ) async* {
    final callback = widget.onAiGenerate;
    if (callback == null) {
      return;
    }
    final generated = await callback(request);
    final text = (generated ?? '').trim();
    if (text.isEmpty) {
      return;
    }
    const int step = 8;
    for (var i = 0; i < text.length; i += step) {
      final end = (i + step > text.length) ? text.length : i + step;
      yield text.substring(i, end);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  _AiInsertAnchor _createAiInsertAnchor() {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    final next = '${text.substring(0, safeStart)}${text.substring(safeEnd)}';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeStart),
    );
    _focusNode.requestFocus();
    return _AiInsertAnchor(start: safeStart, end: safeStart);
  }

  void _replaceAiInsertedContent(_AiInsertAnchor anchor, String content) {
    final text = _controller.text;
    final safeStart = anchor.start.clamp(0, text.length);
    final safeEnd = anchor.end.clamp(safeStart, text.length);
    final next =
        '${text.substring(0, safeStart)}$content${text.substring(safeEnd)}';
    anchor.end = safeStart + content.length;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: anchor.end),
    );
    _focusNode.requestFocus();
  }

  void _restoreEditorValue(String text, TextSelection selection) {
    final safeSelection = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    _controller.value = TextEditingValue(text: text, selection: safeSelection);
    if (_mode == _EditorMode.edit) {
      _focusNode.requestFocus();
    }
  }

  void _applyFormat(String prefix, String suffix, String placeholder) {
    HapticFeedback.selectionClick();
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid) {
      final newText = '$text$prefix$placeholder$suffix';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: newText.length - suffix.length,
        ),
      );
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final selectedText = text.substring(start, end);
    final content = selectedText.isEmpty ? placeholder : selectedText;

    final newText = text.replaceRange(start, end, '$prefix$content$suffix');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset:
            start +
            prefix.length +
            content.length +
            (selectedText.isEmpty ? 0 : suffix.length),
      ),
    );
    _focusNode.requestFocus();
  }

  void _insertText(String content) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    final newText = text.replaceRange(start, end, content);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + content.length),
    );
    if (!_emojiPanelVisible) {
      _focusNode.requestFocus();
    }
  }

  bool get _showMentionPanel =>
      _mentionStartOffset != null &&
      _focusNode.hasFocus &&
      (_mentionLoading || _mentionUsers.isNotEmpty || _mentionQuery.isNotEmpty);

  void _refreshMentionSuggestions({bool immediate = false}) {
    final callback = widget.onSearchMentionUsers;
    if (callback == null || !_focusNode.hasFocus) {
      _hideMentionPanel();
      return;
    }
    final trigger = _currentMentionTrigger();
    if (trigger == null) {
      _hideMentionPanel();
      return;
    }

    final anchor = _computeMentionAnchor();
    final nextQuery = trigger.query.trim();
    final shouldFetch =
        _mentionStartOffset != trigger.start || _mentionQuery != nextQuery;

    if (!shouldFetch) {
      if (anchor != null &&
          (_mentionAnchorOffset == null ||
              (_mentionAnchorOffset! - anchor).distance > 0.5)) {
        if (mounted) {
          setState(() {
            _mentionAnchorOffset = anchor;
          });
        }
      }
      return;
    }

    _mentionDebounce?.cancel();
    final delay = immediate || nextQuery.isEmpty
        ? Duration.zero
        : const Duration(milliseconds: 220);
    _mentionDebounce = Timer(delay, () {
      unawaited(_fetchMentionUsers(trigger));
    });
  }

  Future<void> _fetchMentionUsers(_MentionTrigger trigger) async {
    final callback = widget.onSearchMentionUsers;
    if (callback == null) {
      return;
    }
    final serial = ++_mentionRequestSerial;
    final anchor = _computeMentionAnchor();
    if (mounted) {
      setState(() {
        _mentionLoading = true;
        _mentionStartOffset = trigger.start;
        _mentionQuery = trigger.query.trim();
        _mentionAnchorOffset = anchor;
      });
    }

    try {
      final users = await callback(trigger.query.trim());
      if (!mounted || serial != _mentionRequestSerial) {
        return;
      }
      final latest = _currentMentionTrigger();
      if (latest == null || latest.start != trigger.start) {
        _hideMentionPanel();
        return;
      }
      final deduped = _dedupeMentionUsers(users);
      setState(() {
        _mentionLoading = false;
        _mentionUsers = deduped;
        _mentionQuery = latest.query.trim();
        _mentionStartOffset = latest.start;
        _mentionAnchorOffset = _computeMentionAnchor();
      });
    } catch (_) {
      if (!mounted || serial != _mentionRequestSerial) {
        return;
      }
      setState(() {
        _mentionLoading = false;
        _mentionUsers = const <RiverMarkdownMentionUser>[];
      });
    }
  }

  List<RiverMarkdownMentionUser> _dedupeMentionUsers(
    List<RiverMarkdownMentionUser> source,
  ) {
    if (source.isEmpty) {
      return const <RiverMarkdownMentionUser>[];
    }
    final seen = <String>{};
    final result = <RiverMarkdownMentionUser>[];
    for (final item in source) {
      final key = item.key.trim().isEmpty
          ? item.insertText.trim().toLowerCase()
          : item.key.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      result.add(item);
      if (result.length >= 20) {
        break;
      }
    }
    return result;
  }

  _MentionTrigger? _currentMentionTrigger() {
    final selection = _controller.selection;
    final text = _controller.text;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final caret = selection.extentOffset;
    if (caret <= 0 || caret > text.length) {
      return null;
    }

    var atIndex = -1;
    for (var i = caret - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '@') {
        atIndex = i;
        break;
      }
      if (_isMentionBreakChar(char)) {
        return null;
      }
    }
    if (atIndex < 0) {
      return null;
    }
    if (atIndex > 0) {
      final prev = text[atIndex - 1];
      if (_isMentionBodyChar(prev)) {
        return null;
      }
    }
    final query = text.substring(atIndex + 1, caret);
    if (query.length > 32 || query.contains('@')) {
      return null;
    }
    return _MentionTrigger(start: atIndex, end: caret, query: query);
  }

  bool _isMentionBreakChar(String char) {
    const breaks = <String>{
      ' ',
      '\n',
      '\r',
      '\t',
      ',',
      '.',
      ';',
      ':',
      '!',
      '?',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '<',
      '>',
      '"',
      '\'',
      '\\',
      '/',
      '|',
      '`',
      '~',
    };
    return breaks.contains(char);
  }

  bool _isMentionBodyChar(String char) {
    final rune = char.runes.isEmpty ? 0 : char.runes.first;
    final isDigit = rune >= 48 && rune <= 57;
    final isUpper = rune >= 65 && rune <= 90;
    final isLower = rune >= 97 && rune <= 122;
    return isDigit || isUpper || isLower || char == '_' || char == '.';
  }

  Offset? _computeMentionAnchor() {
    final stackContext = _editStackKey.currentContext;
    final fieldContext = _editFieldKey.currentContext;
    if (stackContext == null || fieldContext == null) {
      return null;
    }
    final stackRender = stackContext.findRenderObject();
    final fieldRender = fieldContext.findRenderObject();
    if (stackRender is! RenderBox || fieldRender == null) {
      return null;
    }
    final editable = _findRenderEditable(fieldRender);
    if (editable == null) {
      return null;
    }
    final selection = _controller.selection;
    final offset = selection.isValid ? selection.extentOffset : -1;
    if (offset < 0 || offset > _controller.text.length) {
      return null;
    }
    final caretRect = editable.getLocalRectForCaret(
      TextPosition(offset: offset),
    );
    final caretGlobal = editable.localToGlobal(caretRect.bottomLeft);
    return stackRender.globalToLocal(caretGlobal);
  }

  RenderEditable? _findRenderEditable(RenderObject root) {
    if (root is RenderEditable) {
      return root;
    }
    RenderEditable? found;
    root.visitChildren((child) {
      found ??= _findRenderEditable(child);
    });
    return found;
  }

  void _hideMentionPanel() {
    _mentionDebounce?.cancel();
    _mentionRequestSerial++;
    if (!mounted) {
      _mentionLoading = false;
      _mentionUsers = const <RiverMarkdownMentionUser>[];
      _mentionStartOffset = null;
      _mentionQuery = '';
      _mentionAnchorOffset = null;
      return;
    }
    setState(() {
      _mentionLoading = false;
      _mentionUsers = const <RiverMarkdownMentionUser>[];
      _mentionStartOffset = null;
      _mentionQuery = '';
      _mentionAnchorOffset = null;
    });
  }

  void _selectMentionUser(RiverMarkdownMentionUser user) {
    final trigger = _currentMentionTrigger();
    if (trigger == null) {
      final fallback = _normalizeMentionInsertText(user);
      if (fallback.isNotEmpty) {
        _insertText('@$fallback ');
      }
      _hideMentionPanel();
      return;
    }
    final insertText = _normalizeMentionInsertText(user);
    if (insertText.isEmpty) {
      _hideMentionPanel();
      return;
    }
    final fullText = _controller.text;
    final replacement = '@$insertText ';
    final next = fullText.replaceRange(trigger.start, trigger.end, replacement);
    final nextOffset = trigger.start + replacement.length;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _focusNode.requestFocus();
    _hideMentionPanel();
  }

  String _normalizeMentionInsertText(RiverMarkdownMentionUser user) {
    var text = user.insertText.trim();
    if (text.startsWith('@')) {
      text = text.substring(1).trim();
    }
    if (text.isNotEmpty) {
      return text;
    }
    final username = user.username.trim();
    if (username.isNotEmpty) {
      return username.startsWith('@') ? username.substring(1) : username;
    }
    final displayName = user.displayName.trim();
    if (displayName.isEmpty) {
      return '';
    }
    return displayName.startsWith('@') ? displayName.substring(1) : displayName;
  }

  String _previewMarkdown(String raw) {
    if (raw.trim().isEmpty || widget.emojiUrls.isEmpty) {
      return raw;
    }
    final normalized = raw.replaceAllMapped(
      RegExp(r'\[([as])\s*:\s*(\d+)\]', caseSensitive: false),
      (match) {
        final prefix = (match.group(1) ?? '').toLowerCase();
        final id = (match.group(2) ?? '').trim();
        if ((prefix != 'a' && prefix != 's') || id.isEmpty) {
          return match.group(0) ?? '';
        }
        return ':${prefix}_$id:';
      },
    );
    final regex = RegExp(r':([a-zA-Z0-9_+\-.]+):');
    return normalized.replaceAllMapped(regex, (match) {
      final key = (match.group(1) ?? '').trim();
      final emojiUrl = widget.emojiUrls[key];
      if (emojiUrl == null || emojiUrl.isEmpty) {
        return match.group(0) ?? '';
      }
      return '![:$key:]($emojiUrl)';
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showRiverSnackBar(
      msg,
      tone: isError ? RiverSnackBarTone.error : RiverSnackBarTone.normal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emojiPanelVisible = _emojiPanelVisible;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible =
        !emojiPanelVisible && (bottomInset > 0 || _focusNode.hasFocus);
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final maxAvailableHeight = screenHeight - media.padding.top - 8;
    final requestedHeight = widget.maxHeight > 0
        ? widget.maxHeight
        : screenHeight * 0.88;
    final editorHeight = requestedHeight.clamp(420.0, maxAvailableHeight);
    final statusText = _loadingDraft
        ? '正在同步草稿...'
        : (_lastDraftSavedAt != null
              ? '草稿更新于 ${_lastDraftSavedAt!.hour.toString().padLeft(2, '0')}:${_lastDraftSavedAt!.minute.toString().padLeft(2, '0')}'
              : (_mode == _EditorMode.edit ? 'Markdown 编辑' : '预览内容'));

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: editorHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.surfaceContainerLow,
                            colorScheme.surface,
                          ],
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: '关闭',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  style: IconButton.styleFrom(
                                    foregroundColor:
                                        colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.title ?? '发布内容',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        statusText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onLoadDrafts != null)
                                  IconButton(
                                    tooltip: '草稿箱',
                                    onPressed: _openDraftBox,
                                    icon: const Icon(
                                      Icons.inventory_2_outlined,
                                    ),
                                  ),
                                if (_draftEnabled)
                                  IconButton(
                                    tooltip: '保存草稿',
                                    onPressed: _savingDraft
                                        ? null
                                        : () => _saveDraft(showSnack: true),
                                    icon: _savingDraft
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colorScheme.primary,
                                            ),
                                          )
                                        : const Icon(Icons.save_outlined),
                                  ),
                                FilledButton.tonal(
                                  onPressed: _submitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: _submitting
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: colorScheme.primary,
                                          ),
                                        )
                                      : Text(widget.submitLabel ?? '发送'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (widget.enablePreview)
                                  _EditorModeSwitch(
                                    mode: _mode,
                                    onChanged: (next) {
                                      if (next == _mode) return;
                                      setState(() => _mode = next);
                                    },
                                  ),
                                if (widget.enablePreview)
                                  const SizedBox(width: 10),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: _loadingDraft
                                        ? LinearProgressIndicator(
                                            key: const ValueKey<String>(
                                              'draft_loading_indicator',
                                            ),
                                            minHeight: 3,
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.24,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: _mode == _EditorMode.edit
                                      ? KeyedSubtree(
                                          key: const ValueKey<String>(
                                            'editor_mode_edit',
                                          ),
                                          child: Stack(
                                            key: _editStackKey,
                                            clipBehavior: Clip.none,
                                            children: [
                                              TextField(
                                                key: _editFieldKey,
                                                controller: _controller,
                                                focusNode: _focusNode,
                                                autofocus: widget.autofocus,
                                                expands: true,
                                                textAlignVertical:
                                                    TextAlignVertical.top,
                                                maxLines: null,
                                                minLines: null,
                                                keyboardType:
                                                    TextInputType.multiline,
                                                style: theme.textTheme.bodyLarge
                                                    ?.copyWith(height: 1.52),
                                                decoration: InputDecoration(
                                                  hintText:
                                                      widget.hintText ??
                                                      '分享你的想法...',
                                                  hintStyle: theme
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.62,
                                                            ),
                                                      ),
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  disabledBorder:
                                                      InputBorder.none,
                                                  errorBorder: InputBorder.none,
                                                  focusedErrorBorder:
                                                      InputBorder.none,
                                                  border: InputBorder.none,
                                                  contentPadding:
                                                      const EdgeInsets.fromLTRB(
                                                        18,
                                                        14,
                                                        18,
                                                        18,
                                                      ),
                                                ),
                                              ),
                                              AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 220,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                opacity: _showAiThinkingHint
                                                    ? 1
                                                    : 0,
                                                child: IgnorePointer(
                                                  ignoring: true,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          18,
                                                          10,
                                                          18,
                                                          0,
                                                        ),
                                                    child: Align(
                                                      alignment:
                                                          Alignment.topLeft,
                                                      child: _AiThinkingHintChip(
                                                        visible:
                                                            _showAiThinkingHint,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (_showMentionPanel)
                                                _MentionSuggestionPanel(
                                                  key: ValueKey<String>(
                                                    'mention_panel_${_mentionQuery}_${_mentionUsers.length}_${_mentionLoading ? 1 : 0}',
                                                  ),
                                                  users: _mentionUsers,
                                                  loading: _mentionLoading,
                                                  query: _mentionQuery,
                                                  anchorOffset:
                                                      _mentionAnchorOffset ??
                                                      const Offset(28, 28),
                                                  onSelect: _selectMentionUser,
                                                ),
                                            ],
                                          ),
                                        )
                                      : Container(
                                          key: const ValueKey<String>(
                                            'editor_mode_preview',
                                          ),
                                          color: colorScheme
                                              .surfaceContainerLowest,
                                          child: _controller.text.trim().isEmpty
                                              ? Center(
                                                  child: Text(
                                                    '暂无预览内容',
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                )
                                              : Markdown(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        16,
                                                        12,
                                                        16,
                                                        24,
                                                      ),
                                                  data: _previewMarkdown(
                                                    _controller.text,
                                                  ),
                                                  selectable: true,
                                                  physics:
                                                      const ClampingScrollPhysics(),
                                                  styleSheet:
                                                      MarkdownStyleSheet.fromTheme(
                                                        theme,
                                                      ).copyWith(
                                                        p: theme
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.copyWith(
                                                              height: 1.6,
                                                            ),
                                                      ),
                                                  imageBuilder: (uri, title, alt) {
                                                    final source = uri
                                                        .toString();
                                                    if (_isAssetEmojiUrl(
                                                      source,
                                                    )) {
                                                      final assetPath =
                                                          _assetPathFromEmojiUrl(
                                                            source,
                                                          );
                                                      return ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        child: Image.asset(
                                                          assetPath,
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => const Icon(
                                                                Icons
                                                                    .broken_image_outlined,
                                                              ),
                                                        ),
                                                      );
                                                    }
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      child: CachedNetworkImage(
                                                        imageUrl: source,
                                                        fit: BoxFit.contain,
                                                        placeholder:
                                                            (
                                                              context,
                                                              imageUrl,
                                                            ) => const Padding(
                                                              padding:
                                                                  EdgeInsets.symmetric(
                                                                    vertical:
                                                                        20,
                                                                  ),
                                                              child: Center(
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              ),
                                                            ),
                                                        errorWidget:
                                                            (
                                                              context,
                                                              imageUrl,
                                                              error,
                                                            ) => const Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: emojiPanelVisible
                                ? SizedBox(
                                    key: const ValueKey<String>(
                                      'editor_emoji_panel_visible',
                                    ),
                                    height: _emojiPanelHeight,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        10,
                                        10,
                                        8,
                                      ),
                                      child: RiverEmojiPicker(
                                        emojiUrls: widget.emojiUrls,
                                        emojiGroups: widget.emojiGroups,
                                        embedded: true,
                                        onSelected: (key) {
                                          final formatter =
                                              widget.emojiInsertFormatter;
                                          final token = formatter == null
                                              ? ':$key:'
                                              : formatter(key);
                                          _insertText(token);
                                        },
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          _EditorToolbar(
                            uploadingImage: _uploadingImage,
                            generatingAi: _generatingAi,
                            enableAi:
                                widget.onAiGenerateStream != null ||
                                widget.onAiGenerate != null,
                            showKeyboardDismiss: keyboardVisible,
                            emojiPanelVisible: emojiPanelVisible,
                            onImageTap: _pickAndUploadImage,
                            onEmojiTap: _showEmojiPicker,
                            onKeyboardDismissTap: _dismissKeyboard,
                            onAiTap: _openAiTools,
                            onBoldTap: () => _applyFormat('**', '**', 'bold'),
                            onItalicTap: () => _applyFormat('*', '*', 'italic'),
                            onQuoteTap: () => _applyFormat('> ', '', 'quote'),
                            onCodeTap: () =>
                                _applyFormat('```\n', '\n```', 'code'),
                            onLinkTap: () =>
                                _applyFormat('[', '](url)', 'link'),
                          ),
                        ],
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
  }
}

class _EditorModeSwitch extends StatelessWidget {
  const _EditorModeSwitch({required this.mode, required this.onChanged});

  final _EditorMode mode;
  final ValueChanged<_EditorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 74,
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: mode == _EditorMode.edit
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: 34,
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: IconButton(
                  tooltip: 'Markdown 编辑',
                  onPressed: () => onChanged(_EditorMode.edit),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.code_rounded,
                    color: mode == _EditorMode.edit
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: IconButton(
                  tooltip: '预览',
                  onPressed: () => onChanged(_EditorMode.preview),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.visibility_rounded,
                    color: mode == _EditorMode.preview
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MentionSuggestionPanel extends StatelessWidget {
  const _MentionSuggestionPanel({
    super.key,
    required this.users,
    required this.loading,
    required this.query,
    required this.anchorOffset,
    required this.onSelect,
  });

  final List<RiverMarkdownMentionUser> users;
  final bool loading;
  final String query;
  final Offset anchorOffset;
  final ValueChanged<RiverMarkdownMentionUser> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? MediaQuery.sizeOf(context).width;
    final height = box?.size.height ?? 320;
    const panelWidth = 280.0;
    const panelHeight = 220.0;
    final left = (anchorOffset.dx - 18)
        .clamp(10.0, math.max(10.0, width - panelWidth - 10))
        .toDouble();
    final preferredTop = anchorOffset.dy + 8;
    final top = (preferredTop + panelHeight > height)
        ? (anchorOffset.dy - panelHeight - 12)
        : preferredTop;
    final resolvedTop = top.clamp(6.0, math.max(6.0, height - 56)).toDouble();

    return Positioned(
      left: left,
      top: resolvedTop,
      width: panelWidth,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(maxHeight: panelHeight),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              if (users.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.alternate_email_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          query.trim().isEmpty ? '继续输入以搜索可@用户' : '未找到可@用户',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                    ),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final displayName = user.displayName.trim().isEmpty
                          ? (user.username.trim().isEmpty
                                ? user.insertText
                                : user.username.trim())
                          : user.displayName.trim();
                      final username = user.username.trim();
                      final subtitle = user.subtitle.trim();
                      final resolvedSubtitle = subtitle.isNotEmpty
                          ? subtitle
                          : (username.isEmpty ? '' : '@$username');
                      return InkWell(
                        onTap: () => onSelect(user),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Row(
                            children: [
                              _MentionAvatar(url: user.avatarUrl),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (resolvedSubtitle.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        resolvedSubtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
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
          ),
        ),
      ),
    );
  }
}

class _MentionAvatar extends StatelessWidget {
  const _MentionAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = url.trim();
    if (avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_outline_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorWidget: (context, imageUrl, error) => CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outline_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.uploadingImage,
    required this.generatingAi,
    required this.enableAi,
    required this.showKeyboardDismiss,
    required this.emojiPanelVisible,
    required this.onImageTap,
    required this.onEmojiTap,
    required this.onKeyboardDismissTap,
    required this.onAiTap,
    required this.onBoldTap,
    required this.onItalicTap,
    required this.onQuoteTap,
    required this.onCodeTap,
    required this.onLinkTap,
  });

  final bool uploadingImage;
  final bool generatingAi;
  final bool enableAi;
  final bool showKeyboardDismiss;
  final bool emojiPanelVisible;
  final VoidCallback onImageTap;
  final VoidCallback onEmojiTap;
  final VoidCallback onKeyboardDismissTap;
  final VoidCallback onAiTap;
  final VoidCallback onBoldTap;
  final VoidCallback onItalicTap;
  final VoidCallback onQuoteTap;
  final VoidCallback onCodeTap;
  final VoidCallback onLinkTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              _ToolbarAction(
                icon: Icons.image_outlined,
                busy: uploadingImage,
                onTap: onImageTap,
              ),
              const SizedBox(width: 6),
              _ToolbarAction(
                icon: emojiPanelVisible
                    ? Icons.keyboard_rounded
                    : Icons.sentiment_satisfied_alt_outlined,
                active: emojiPanelVisible,
                onTap: onEmojiTap,
              ),
              if (showKeyboardDismiss) ...[
                const SizedBox(width: 6),
                _ToolbarAction(
                  icon: Icons.keyboard_hide_rounded,
                  onTap: onKeyboardDismissTap,
                ),
              ],
              if (enableAi) ...[
                const SizedBox(width: 6),
                _ToolbarAiAction(busy: generatingAi, onTap: onAiTap),
              ],
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 24,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              _ToolbarAction(icon: Icons.format_bold_rounded, onTap: onBoldTap),
              _ToolbarAction(
                icon: Icons.format_italic_rounded,
                onTap: onItalicTap,
              ),
              _ToolbarAction(
                icon: Icons.format_quote_rounded,
                onTap: onQuoteTap,
              ),
              _ToolbarAction(icon: Icons.code_rounded, onTap: onCodeTap),
              _ToolbarAction(icon: Icons.link_rounded, onTap: onLinkTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarAiAction extends StatelessWidget {
  const _ToolbarAiAction({required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: busy ? null : onTap,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.7,
        ),
        foregroundColor: colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : const _AiGlowLabel(),
    );
  }
}

class _AiGlowLabel extends StatelessWidget {
  const _AiGlowLabel();

  @override
  Widget build(BuildContext context) {
    return const _AiFlowingText(
      text: 'AI',
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
      glow: true,
    );
  }
}

class _AiFlowingText extends StatefulWidget {
  const _AiFlowingText({
    required this.text,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.letterSpacing = 0,
    this.glow = false,
  });

  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final bool glow;

  @override
  State<_AiFlowingText> createState() => _AiFlowingTextState();
}

class _AiFlowingTextState extends State<_AiFlowingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final width = bounds.width <= 0 ? 1.0 : bounds.width;
            final shifted = Rect.fromLTWH(
              -width + 2 * width * t,
              0,
              width * 2,
              bounds.height <= 0 ? 1.0 : bounds.height,
            );
            return const LinearGradient(
              colors: <Color>[
                Color(0xFF67D2FF),
                Color(0xFF87A8FF),
                Color(0xFFFF95D2),
                Color(0xFF78E7D5),
                Color(0xFF67D2FF),
              ],
              stops: <double>[0.0, 0.25, 0.5, 0.75, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(shifted);
          },
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: widget.fontWeight,
              letterSpacing: widget.letterSpacing,
              shadows: widget.glow
                  ? const <Shadow>[
                      Shadow(color: Color(0x663AA8FF), blurRadius: 8),
                      Shadow(color: Color(0x55FF89CB), blurRadius: 10),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _AiThinkingHintChip extends StatelessWidget {
  const _AiThinkingHintChip({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      scale: visible ? 1 : 0.92,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.auto_awesome_rounded, size: 14),
            SizedBox(width: 6),
            _AiFlowingText(
              text: 'AI思考中...',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              glow: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: busy ? null : onTap,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: active
            ? colorScheme.primaryContainer.withValues(alpha: 0.92)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        foregroundColor: active
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : Icon(icon),
    );
  }
}

class _AiToolAction {
  const _AiToolAction({
    required this.title,
    required this.subtitle,
    required this.instruction,
    required this.icon,
    this.needsReference = false,
  });

  final String title;
  final String subtitle;
  final String instruction;
  final IconData icon;
  final bool needsReference;
}

class _AiInsertAnchor {
  _AiInsertAnchor({required this.start, required this.end});

  final int start;
  int end;
}

class _EditorActionSheetShell extends StatelessWidget {
  const _EditorActionSheetShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.maxHeight,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedMaxHeight =
        maxHeight ?? MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: resolvedMaxHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
              theme.colorScheme.surface,
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primaryContainer,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    return _EditorActionSheetShell(
      title: '插入图片',
      subtitle: '选择图片来源',
      icon: Icons.add_photo_alternate_rounded,
      maxHeight: 280,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ImageSourceActionTile(
              icon: Icons.camera_alt_rounded,
              title: '拍摄照片',
              subtitle: '调用相机拍摄后插入编辑器',
              onTap: () => Navigator.of(context).pop(_ImagePickSource.camera),
            ),
            const SizedBox(height: 8),
            _ImageSourceActionTile(
              icon: Icons.image_outlined,
              title: '选择图片',
              subtitle: '从相册中选择图片并上传（最多 3 张）',
              onTap: () => Navigator.of(context).pop(_ImagePickSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSourceActionTile extends StatelessWidget {
  const _ImageSourceActionTile({
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
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiToolsSheet extends StatelessWidget {
  const _AiToolsSheet({required this.actions});

  final List<_AiToolAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.52;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return _EditorActionSheetShell(
      title: 'AI 工具箱',
      subtitle: '选择要执行的写作辅助操作',
      icon: Icons.auto_awesome_rounded,
      maxHeight: height,
      child: ClipRect(
        child: ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
          child: ListView.separated(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(14, 0, 14, 16 + bottomSafe),
            itemCount: actions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = actions[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).pop(item),
                  child: Ink(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.30,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.82,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            item.icon,
                            size: 17,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmojiCategoryItem {
  const _EmojiCategoryItem({
    required this.name,
    required this.keys,
    required this.coverKey,
  });

  final String name;
  final List<String> keys;
  final String coverKey;
}

class RiverStructuredEmojiPicker extends StatefulWidget {
  const RiverStructuredEmojiPicker({
    super.key,
    required this.emojiUrls,
    required this.emojiGroups,
    required this.onSelected,
    this.title = '选择表情',
    this.embedded = false,
    this.resolveUrl,
    this.headersForUrl,
  });

  final Map<String, String> emojiUrls;
  final Map<String, List<String>> emojiGroups;
  final ValueChanged<String> onSelected;
  final String title;
  final bool embedded;
  final String Function(String raw)? resolveUrl;
  final Map<String, String>? Function(String resolvedUrl)? headersForUrl;

  @override
  State<RiverStructuredEmojiPicker> createState() =>
      _RiverStructuredEmojiPickerState();
}

class _RiverStructuredEmojiPickerState
    extends State<RiverStructuredEmojiPicker> {
  late final List<_EmojiCategoryItem> _categories;
  final List<GlobalKey> _sectionKeys = <GlobalKey>[];
  final ScrollController _emojiScrollController = ScrollController();
  final ScrollController _tabScrollController = ScrollController();
  int _selectedIndex = 0;
  int _loopCount = 3;

  @override
  void initState() {
    super.initState();
    _categories = _buildCategories();
    _emojiScrollController.addListener(_handleEmojiScroll);
  }

  @override
  void dispose() {
    _emojiScrollController.removeListener(_handleEmojiScroll);
    _emojiScrollController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  List<_EmojiCategoryItem> _buildCategories() {
    final categories = <_EmojiCategoryItem>[];

    widget.emojiGroups.forEach((name, keys) {
      final valid = keys.where(widget.emojiUrls.containsKey).toList();
      if (valid.isEmpty) {
        return;
      }
      categories.add(
        _EmojiCategoryItem(name: name, keys: valid, coverKey: valid.first),
      );
    });

    if (categories.isEmpty && widget.emojiUrls.isNotEmpty) {
      final keys = widget.emojiUrls.keys.toList()..sort();
      categories.add(
        _EmojiCategoryItem(name: '全部', keys: keys, coverKey: keys.first),
      );
    }
    return categories;
  }

  String _resolveUrl(String raw) {
    final resolver = widget.resolveUrl;
    return resolver == null ? raw : resolver(raw);
  }

  List<int> get _orderedCategoryIndices => <int>[
    for (var loop = 0; loop < _loopCount; loop++)
      for (var index = 0; index < _categories.length; index++) index,
  ];

  GlobalKey _sectionKeyFor(int index) {
    while (_sectionKeys.length <= index) {
      _sectionKeys.add(GlobalKey());
    }
    return _sectionKeys[index];
  }

  void _handleEmojiScroll() {
    if (!_emojiScrollController.hasClients || _categories.isEmpty) {
      return;
    }
    final position = _emojiScrollController.position;
    final preloadThreshold = math.max(220.0, position.viewportDimension * 0.75);
    if (position.pixels >= position.maxScrollExtent - preloadThreshold &&
        _loopCount < 12) {
      setState(() {
        _loopCount += 1;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSelectedTabFromScroll();
    });
  }

  void _syncSelectedTabFromScroll() {
    if (!mounted || _categories.isEmpty) {
      return;
    }
    final panelBox = context.findRenderObject();
    if (panelBox is! RenderBox) {
      return;
    }
    final threshold =
        panelBox.localToGlobal(Offset.zero).dy + (widget.embedded ? 76 : 120);
    final ordered = _orderedCategoryIndices;
    int? active;
    for (var index = 0; index < ordered.length; index++) {
      final keyContext = _sectionKeys.length > index
          ? _sectionKeys[index].currentContext
          : null;
      if (keyContext == null) {
        continue;
      }
      final render = keyContext.findRenderObject();
      if (render is! RenderBox) {
        continue;
      }
      final dy = render.localToGlobal(Offset.zero).dy;
      if (dy <= threshold) {
        active = ordered[index];
      } else {
        break;
      }
    }
    if (active != null && active != _selectedIndex) {
      setState(() {
        _selectedIndex = active!;
      });
      _scrollTabIntoView(active);
    }
  }

  void _scrollToCategory(int categoryIndex) {
    if (_categories.isEmpty) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = categoryIndex;
    });
    _scrollTabIntoView(categoryIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ordered = _orderedCategoryIndices;
      final preferredSectionIndex = _preferredSectionIndexFor(categoryIndex);
      if (preferredSectionIndex != null) {
        final targetContext = _sectionKeyFor(
          preferredSectionIndex,
        ).currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: 0.0,
          );
          return;
        }
      }
      for (var index = 0; index < ordered.length; index++) {
        if (ordered[index] == categoryIndex) {
          final targetContext = _sectionKeyFor(index).currentContext;
          if (targetContext == null) {
            continue;
          }
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: 0.0,
          );
          return;
        }
      }
    });
  }

  int? _preferredSectionIndexFor(int categoryIndex) {
    if (!_emojiScrollController.hasClients || _categories.isEmpty) {
      return null;
    }
    final panelBox = context.findRenderObject();
    if (panelBox is! RenderBox) {
      return null;
    }
    final anchorDy =
        panelBox.localToGlobal(Offset.zero).dy + (widget.embedded ? 88 : 132);
    int? nearestForward;
    double nearestForwardDistance = double.infinity;
    int? nearestAny;
    double nearestAnyDistance = double.infinity;
    for (var index = 0; index < _orderedCategoryIndices.length; index++) {
      if (_orderedCategoryIndices[index] != categoryIndex) {
        continue;
      }
      final keyContext = _sectionKeyFor(index).currentContext;
      if (keyContext == null) {
        continue;
      }
      final render = keyContext.findRenderObject();
      if (render is! RenderBox) {
        continue;
      }
      final dy = render.localToGlobal(Offset.zero).dy;
      final distance = (dy - anchorDy).abs();
      if (distance < nearestAnyDistance) {
        nearestAnyDistance = distance;
        nearestAny = index;
      }
      if (dy >= anchorDy - 24) {
        final forwardDistance = dy - anchorDy;
        if (forwardDistance < nearestForwardDistance) {
          nearestForwardDistance = forwardDistance;
          nearestForward = index;
        }
      }
    }
    return nearestForward ?? nearestAny;
  }

  void _scrollTabIntoView(int index) {
    if (!_tabScrollController.hasClients) {
      return;
    }
    final targetOffset = math.max(0.0, index * 52.0 - 32.0);
    _tabScrollController.animateTo(
      targetOffset.clamp(0.0, _tabScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildEmojiThumb({
    required String source,
    required double size,
    required Widget fallback,
  }) {
    if (source.trim().isEmpty) {
      return fallback;
    }
    if (_isAssetEmojiUrl(source)) {
      final assetPath = _assetPathFromEmojiUrl(source);
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    final resolved = _resolveUrl(source);
    return CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: widget.headersForUrl?.call(resolved),
      width: size,
      height: size,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, imageUrl) => fallback,
      errorWidget: (context, imageUrl, error) => fallback,
    );
  }

  Widget _buildCategoryStrip(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.16),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: ListView.separated(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = _categories[index];
          final selected = index == _selectedIndex;
          final source = widget.emojiUrls[item.coverKey] ?? '';
          return Tooltip(
            message: item.name,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _scrollToCategory(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 42,
                decoration: BoxDecoration(
                  color: selected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildEmojiThumb(
                      source: source,
                      size: 22,
                      fallback: Icon(
                        Icons.tag_faces_rounded,
                        size: 18,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: selected ? 20 : 8,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: selected
                              ? <Color>[
                                  colorScheme.primary,
                                  colorScheme.primary.withValues(alpha: 0.72),
                                ]
                              : <Color>[
                                  colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                  colorScheme.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiCell(BuildContext context, String key, double size) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = widget.emojiUrls[key] ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onSelected(key);
      },
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.16),
          ),
        ),
        child: Center(
          child: _buildEmojiThumb(
            source: source,
            size: size * 0.62,
            fallback: Icon(
              Icons.broken_image_rounded,
              size: 18,
              color: colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiSectionList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          '暂无表情',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final ordered = _orderedCategoryIndices;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemSize = ((width - 7 * 8) / 8).clamp(34.0, 52.0);
        return SingleChildScrollView(
          controller: _emojiScrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var sectionIndex = 0;
                sectionIndex < ordered.length;
                sectionIndex++
              )
                Container(
                  key: _sectionKeyFor(sectionIndex),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: _buildEmojiThumb(
                                source:
                                    widget
                                        .emojiUrls[_categories[ordered[sectionIndex]]
                                        .coverKey] ??
                                    '',
                                size: 12,
                                fallback: Icon(
                                  Icons.tag_faces_rounded,
                                  size: 12,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _categories[ordered[sectionIndex]].name,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final key
                              in _categories[ordered[sectionIndex]].keys)
                            SizedBox(
                              width: itemSize,
                              height: itemSize,
                              child: _buildEmojiCell(context, key, itemSize),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
            colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(widget.embedded ? 24 : 30),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: widget.embedded ? 0.08 : 0.12,
            ),
            blurRadius: widget.embedded ? 20 : 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (!widget.embedded) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(12, widget.embedded ? 12 : 4, 12, 8),
            child: _buildCategoryStrip(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow.withValues(
                    alpha: 0.48,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.16),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildEmojiSectionList(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.58;
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

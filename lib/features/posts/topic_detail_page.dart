// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:draggable_route/draggable_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/ai/river_ai_service.dart';
import 'package:river/core/categories/riverside_category_store.dart';
import 'package:river/core/categories/riverside_category_utils.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/constants.dart';
import 'package:river/core/image_host/picui_image_host_service.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_message_bus_models.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/posts/topic_footprint_store.dart';
import 'package:river/core/qing/qing_emoji_catalog.dart';
import 'package:river/core/realtime/riverside_message_bus_poller.dart';
import 'package:river/core/widgets/river_confirm_dialog.dart';
import 'package:river/core/widgets/river_ai_action_button.dart';
import 'package:river/core/widgets/river_image_viewer.dart';
import 'package:river/core/widgets/river_markdown_editor.dart';
import 'package:river/core/widgets/river_publish_category_picker_sheet.dart';
import 'package:river/features/compose/compose_topic_page.dart';
import 'package:river/features/mine/riverside_profile_sheet.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:screenshot_callback/screenshot_callback.dart';
import 'package:share_plus/share_plus.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
part 'topic_detail_comment_detail_page.dart';
part 'topic_detail_comment_detail_actions.dart';
part 'topic_detail_comment_detail_ui.dart';
part 'topic_detail_widgets_cards.dart';
part 'topic_detail_widgets_content.dart';
part 'topic_detail_widgets_images.dart';
part 'topic_detail_widgets_meta.dart';
part 'topic_detail_content_utils.dart';
part 'topic_detail_page_actions.dart';
part 'topic_detail_page_reactions.dart';
part 'topic_detail_page_loading.dart';

// -----------------------------------------------------------------------------
// 閻㈩垱鎮傞崳娲嚋閸パ傜矗闁稿繐鍢查崵閬嶅极?
// -----------------------------------------------------------------------------

class _ReactionOption {
  const _ReactionOption({
    required this.id,
    required this.emoji,
    this.label = '',
  });

  final String id;
  final String emoji;
  final String label;
}

const List<_ReactionOption> _defaultReactionOptions = <_ReactionOption>[
  _ReactionOption(id: '+1', emoji: '\u{1F44D}', label: '+1'),
  _ReactionOption(id: 'laughing', emoji: '\u{1F606}', label: 'laughing'),
  _ReactionOption(id: 'heart', emoji: '❤️', label: 'heart'),
  _ReactionOption(id: 'open_mouth', emoji: '\u{1F62E}', label: 'open_mouth'),
  _ReactionOption(id: 'thinking', emoji: '\u{1F914}', label: 'thinking'),
  _ReactionOption(
    id: 'anxious_face_with_sweat',
    emoji: '\u{1F605}',
    label: 'anxious_face_with_sweat',
  ),
  _ReactionOption(
    id: 'distorted_face',
    emoji: '\u{1F635}',
    label: 'distorted_face',
  ),
  _ReactionOption(
    id: 'saluting_face',
    emoji: '\u{1FAE1}',
    label: 'saluting_face',
  ),
  _ReactionOption(id: 'sob', emoji: '\u{1F62D}', label: 'sob'),
  _ReactionOption(id: '-1', emoji: '\u{1F44E}', label: '-1'),
];

final Map<String, _ReactionOption> _reactionOptionById =
    <String, _ReactionOption>{
      for (final option in _defaultReactionOptions) option.id: option,
    };

List<_ReactionOption> _reactionOptionsFromIds(Iterable<String> reactionIds) {
  final result = <_ReactionOption>[];
  final seen = <String>{};
  for (final rawId in reactionIds) {
    final id = rawId.trim();
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    result.add(
      _reactionOptionById[id] ??
          _ReactionOption(id: id, emoji: '❓', label: id),
    );
  }
  return result.isEmpty ? _defaultReactionOptions : result;
}

String _reactionEmoji(String reactionId) {
  return _reactionOptionById[reactionId]?.emoji ?? '❓';
}

String _commentHeroTag(int postId) => 'comment-card-$postId';

String _topicPostAuthorAvatarHeroTag(RiverSideTopicPostDetail post) {
  return 'author_avatar_${post.topicId}_${post.id}_${post.authorUsername}';
}

String _topicPostAuthorNameHeroTag(RiverSideTopicPostDetail post) {
  return 'author_name_${post.topicId}_${post.id}_${post.authorUsername}';
}

String _reactionHeroTag({required int postId, required String reactionId}) {
  return 'post_reaction_${postId}_$reactionId';
}

Widget _commentCardHeroShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final fromHero = fromHeroContext.widget as Hero;
  final toHero = toHeroContext.widget as Hero;
  final heroChild = flightDirection == HeroFlightDirection.push
      ? fromHero.child
      : toHero.child;

  return Material(
    type: MaterialType.transparency,
    child: LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: heroChild,
            ),
          ),
        );
      },
    ),
  );
}

// -----------------------------------------------------------------------------
// 濞戞挸顭烽悥婊堟?
// -----------------------------------------------------------------------------

class TopicDetailPreview {
  const TopicDetailPreview({
    required this.title,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.titleHeroTag,
    required this.authorAvatarHeroTag,
    required this.authorNameHeroTag,
  });

  final String title;
  final String authorDisplayName;
  final String authorUsername;
  final String authorAvatarUrl;
  final String titleHeroTag;
  final String authorAvatarHeroTag;
  final String authorNameHeroTag;
}

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.dependencies,
    required this.topicId,
    this.preview,
    this.provider = AccountProvider.riverSide,
    this.qingBoardId,
    this.scrollToRepliesOnOpen = false,
    this.initialPostNumberOnOpen,
  });

  final AppDependencies dependencies;
  final int topicId;
  final TopicDetailPreview? preview;
  final AccountProvider provider;
  final int? qingBoardId;
  final bool scrollToRepliesOnOpen;
  final int? initialPostNumberOnOpen;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage>
    with TickerProviderStateMixin {
  static const int _loadMoreBatchSize = 20;
  static const double _loadMoreTriggerOffset = 280;
  static const double _showBackToTopOffset = 420;

  static const String _labelTopicDetail = '帖子详情';
  static const String _labelReplies = '评论';
  static const String _labelRetry = '重试';
  static const String _labelNoComments = '暂无评论，快来抢沙发~';
  static const String _labelNoMoreReplies = '没有更多评论了';
  static const String _labelReply = '回复';
  static const String _labelReplyEditorTitle = '编写回复';
  static const String _labelReplySuccess = '回复发布成功';
  static const String _labelReplyNeedLogin = '请先登录账号';
  static const String _labelEditCommentTitle = '编辑评论';
  static const String _labelEditCommentSuccess = '评论已更新';
  static const String _labelDeleteCommentTitle = '删除评论';
  static const String _labelDeleteCommentHint = '确定要删除这条评论吗？';
  static const String _labelDeleteCommentSuccess = '评论已删除';
  static const String _labelActionCopyContent = '复制内容';
  static const String _labelActionEditComment = '编辑评论';
  static const String _labelActionDeleteComment = '删除评论';
  static const String _labelActionEditMainPost = '编辑主贴';
  static const String _labelActionDeleteMainPost = '删除帖子';
  static const String _labelDeleteMainPostTitle = '删除帖子';
  static const String _labelDeleteMainPostHint = '确定要删除该帖子吗？';
  static const String _labelDeleteMainPostSuccess = '帖子已删除';
  static const String _labelSave = '保存';
  static const String _labelCancel = '取消';
  static const String _labelDelete = '删除';
  static const String _labelTargetFloorMissing = '目标楼层尚未加载';
  static const String _labelQuoteLoading = '正在加载被回复内容...';
  static const String _labelQuoteLoadFailed = '被回复内容加载失败，已展示引用片段';
  static const String _labelReplyContent = '回复内容';
  static const String _labelJumpToFloor = '跳转至被回复楼层';
  static const String _labelInvalidQuoteFloor = '无法识别被回复楼层';
  static const String _labelCrossTopicQuote = '跨帖引用暂不支持跳转';
  static const String _labelUnknownUser = '未知用户';
  static const String _labelEmpty = '暂无内容';
  static const String _labelReact = '点赞';
  static const String _labelReactionNotReady = '请先登录账号';
  static const String _labelReactionUsersEmpty = '暂无用户';
  static const String _labelAiSummaryTitle = 'AI总结';
  static const String _labelAiSummaryLoadFailed = 'AI总结加载失败，请稍后重试';
  static const String _labelSharePoster = '分享';
  static const String _labelMoreActions = '更多';
  static const String _labelReport = '举报';
  static const String _labelFavorite = '收藏';
  static const String _labelUnfavorite = '取消收藏';
  static const String _labelSharePosterTitle = '分享帖子海报';
  static const String _labelSharePosterButton = '分享海报';
  static const String _labelCopyTopicLinkButton = '复制帖子链接';
  static const String _labelTopicLinkCopied = '帖子链接已复制';
  static const String _labelSharePosterFailed = '海报生成失败，请重试';

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _postItemKeys = <int, GlobalKey>{};
  final GlobalKey _screenshotCaptureBoundaryKey = GlobalKey();
  final GlobalKey _repliesSectionAnchorKey = GlobalKey();
  final GlobalKey _repliesHeaderKey = GlobalKey();

  RiverSideTopicDetail? _detail;
  List<RiverSideTopicPostDetail> _comments = const <RiverSideTopicPostDetail>[];
  final Set<int> _loadedPostIds = <int>{};
  final Set<int> _reactingPostIds = <int>{};
  final Set<String> _submittingPollKeys = <String>{};
  final Map<int, String> _pendingReactionHeroByPostId = <int, String>{};
  final Map<int, int> _reactionPulseTokenByPostId = <int, int>{};
  final Set<int> _qingLikedPostIds = <int>{};
  final Set<int> _qingDislikedPostIds = <int>{};
  final Map<int, int> _qingDislikeCountByPostId = <int, int>{};
  final Map<int, int> _qingReplyIdByPostNumber = <int, int>{};
  final Map<int, int> _qingPostNumberByReplyId = <int, int>{};
  final Map<String, _QingReplyUploadImage> _qingUploadedImagesByUrl =
      <String, _QingReplyUploadImage>{};
  Map<String, String> _emojiUrls = const <String, String>{};
  Map<String, List<String>> _emojiGroups = const <String, List<String>>{};

  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasRealtimeCommentUpdate = false;
  bool _loadingAiSummary = false;
  bool _showAiSummaryMarquee = false;
  bool _showRepliesFloorSlider = false;
  int _currentVisibleReplyFloor = 1;
  static const double _repliesFloorJumpBarBaseHeight = 52;
  int _qingCurrentPage = 1;
  bool _qingHasMoreComments = false;
  int? _qingBoardId;
  int? _jumpHighlightPostNumber;
  int _jumpHighlightToken = 0;
  Timer? _jumpHighlightClearTimer;
  Timer? _aiSummaryMarqueeStopTimer;
  bool _skipNextEntranceAnimation = false;
  RiverSideMessageBusPoller? _messageBusPoller;
  int _pollingBootstrapSerial = 0;
  final ValueNotifier<bool> _showBackToTopButtonNotifier = ValueNotifier<bool>(
    false,
  );
  String? _error;
  bool _presenceReady = false;
  bool _didInitialRepliesScroll = false;
  bool _didInitialPostNumberJump = false;
  final Set<int> _onlineUserIds = <int>{};
  final Set<String> _onlineUsernames = <String>{};
  final Map<int, String> _knownOnlineUsernameById = <int, String>{};
  String _watermarkAppName = 'River';
  String _watermarkVersion = '';
  ScreenshotCallback? _screenshotCallback;
  bool _handlingScreenshotEvent = false;
  bool _sharePosterSheetVisible = false;
  bool _topicFavoriteResolved = false;
  bool _topicFavorited = false;
  bool _topicFavoriteBusy = false;
  bool _topicReportBusy = false;
  ScaffoldMessengerState? _scaffoldMessenger;
  final DateTime _visibleWatermarkTime = DateTime.now();

  bool get _isQingShuiHePanTopic =>
      widget.provider == AccountProvider.qingShuiHePan;

  String get _loginRequiredLabel =>
      _isQingShuiHePanTopic ? '请先登录清水河畔账号' : '请先登录 RiverSide 账号';

  // 闁稿繈鍎遍悧顒勫礋閺囩姵娈柟璨夊啫鐓戦柛?
  late AnimationController _entranceController;
  late AnimationController _contentRevealController;
  late AnimationController _repliesFloorSliderVisibilityController;

  @override
  void initState() {
    super.initState();
    // 闁告帗绻傞～鎰板礌閺嵮冪彋闁伙綆鍋呯敮鍫曞礆鐠虹儤鐝?
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _contentRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _repliesFloorSliderVisibilityController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
          value: 0,
        )..addListener(() {
          if (!mounted) {
            return;
          }
          setState(() {});
        });

    widget.dependencies.settingsController.addListener(
      _onRefreshBannerSettingsChanged,
    );
    widget.dependencies.accountStore.addListener(_onWatermarkAccountChanged);
    _scrollController.addListener(_onScroll);
    _initWatermarkMetadata();
    _initScreenshotCallback();
    _restartRealtimePolling();
    _loadInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _jumpHighlightClearTimer?.cancel();
    _aiSummaryMarqueeStopTimer?.cancel();
    _entranceController.dispose();
    _contentRevealController.dispose();
    _repliesFloorSliderVisibilityController.dispose();
    _messageBusPoller?.stop();
    widget.dependencies.settingsController.removeListener(
      _onRefreshBannerSettingsChanged,
    );
    widget.dependencies.accountStore.removeListener(_onWatermarkAccountChanged);
    _disposeScreenshotCallback();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showBackToTopButtonNotifier.dispose();
    super.dispose();
  }

  bool get _showTopicCommentsRealtimeRefreshBanner {
    return widget
        .dependencies
        .settingsController
        .showTopicCommentsRealtimeRefreshBanner;
  }

  String get _topicDetailVisibleWatermarkText {
    final account = _isQingShuiHePanTopic
        ? widget.dependencies.accountStore.activeQingShuiHePanAccount
        : widget.dependencies.accountStore.activeRiverSideAccount;
    final userId = account?.userId;
    final uid = userId == null || userId <= 0 ? 'guest' : '$userId';
    final nickname = (account?.displayName ?? account?.username ?? 'guest')
        .trim();
    final nick = nickname.isEmpty ? 'guest' : nickname;
    final now = _visibleWatermarkTime;
    final time =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    return 'ID:$uid  $nick  $time';
  }

  Future<void> _initWatermarkMetadata() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _watermarkAppName = info.appName.trim().isEmpty
            ? _watermarkAppName
            : info.appName.trim();
        _watermarkVersion = info.version.trim();
      });
    } catch (_) {
      // Keep silent fallback values.
    }
  }

  void _onWatermarkAccountChanged() {
    if (!mounted) {
      return;
    }
    _mutateState(() {});
  }

  Future<void> _initScreenshotCallback() async {
    try {
      final callback = ScreenshotCallback();
      callback.addListener(_onScreenshotDetected);
      await callback.initialize();
      if (!mounted) {
        await callback.dispose();
        return;
      }
      _screenshotCallback = callback;
    } catch (_) {
      // Keep silent on unsupported platforms.
    }
  }

  Future<void> _disposeScreenshotCallback() async {
    final callback = _screenshotCallback;
    _screenshotCallback = null;
    if (callback == null) {
      return;
    }
    try {
      await callback.dispose();
    } catch (_) {
      // Ignore dispose failures.
    }
  }

  Future<void> _onScreenshotDetected() async {
    if (!mounted || _handlingScreenshotEvent || _sharePosterSheetVisible) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      return;
    }
    _handlingScreenshotEvent = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await _openSharePosterSheet(triggeredByScreenshot: true);
    } finally {
      _handlingScreenshotEvent = false;
    }
  }

  String _topicShareLink(int topicId) {
    if (_isQingShuiHePanTopic) {
      return '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/forum.php?mod=viewthread&tid=$topicId';
    }
    return '$riverSideBaseUrl/t/topic/$topicId';
  }

  Future<void> _openSharePosterSheet({
    bool triggeredByScreenshot = false,
  }) async {
    final detail = _detail;
    if (detail == null || _sharePosterSheetVisible || !mounted) {
      return;
    }
    _sharePosterSheetVisible = true;
    final posterKey = GlobalKey();
    final link = _topicShareLink(detail.topicId);
    final mainContentMarkdown = detail.mainPost.contentMarkdown.trim();
    final account = _isQingShuiHePanTopic
        ? widget.dependencies.accountStore.activeQingShuiHePanAccount
        : widget.dependencies.accountStore.activeRiverSideAccount;
    final hostContext = context;

    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          var sharing = false;
          Future<void> onSharePressed(StateSetter setModalState) async {
            if (sharing) {
              return;
            }
            setModalState(() => sharing = true);
            try {
              final posterBytes = await _capturePngFromBoundary(
                posterKey,
                pixelRatio: 2.8,
              );
              if (posterBytes == null || posterBytes.isEmpty) {
                throw StateError(_labelSharePosterFailed);
              }
              final shareBytes = posterBytes;
              final fileName = 'river_topic_${detail.topicId}.png';
              await SharePlus.instance.share(
                ShareParams(
                  files: <XFile>[
                    XFile.fromData(
                      shareBytes,
                      mimeType: 'image/png',
                      name: fileName,
                    ),
                  ],
                  text: link,
                  subject: detail.title,
                ),
              );
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.maybeOf(
                  hostContext,
                )?.showRiverSnackBar(_labelSharePosterFailed);
              }
            } finally {
              try {
                setModalState(() => sharing = false);
              } catch (_) {
                // Sheet may already be disposed.
              }
            }
          }

          return StatefulBuilder(
            builder: (context, setModalState) {
              final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.96),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.32),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.share_rounded,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _labelSharePosterTitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              if (triggeredByScreenshot)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '截图触发',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: RepaintBoundary(
                              key: posterKey,
                              child: _TopicSharePosterCard(
                                detail: detail,
                                mainContentMarkdown: mainContentMarkdown,
                                topicLink: link,
                                accountDisplayName: (account?.displayName ?? '')
                                    .trim(),
                                accountUsername: (account?.username ?? '')
                                    .trim(),
                                accountAvatarUrl: (account?.avatarUrl ?? '')
                                    .trim(),
                                appName: _watermarkAppName,
                                appVersion: _watermarkVersion.trim().isNotEmpty
                                    ? _watermarkVersion.trim()
                                    : widget
                                          .dependencies
                                          .updateChecker
                                          .currentVersion
                                          .trim(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: sharing
                                      ? null
                                      : () => onSharePressed(setModalState),
                                  icon: sharing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.ios_share_rounded),
                                  label: Text(_labelSharePosterButton),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: link),
                                    );
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.maybeOf(
                                      hostContext,
                                    )?.showRiverSnackBar(_labelTopicLinkCopied);
                                  },
                                  icon: const Icon(Icons.link_rounded),
                                  label: Text(_labelCopyTopicLinkButton),
                                ),
                              ),
                            ],
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
    } finally {
      _sharePosterSheetVisible = false;
    }
  }

  Future<Uint8List?> _capturePngFromBoundary(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.5,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    final captureContext = boundaryKey.currentContext;
    if (captureContext == null) {
      return null;
    }
    final renderObject = captureContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }
    final captured = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await captured.toByteData(format: ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      captured.dispose();
    }
  }

  void _onRefreshBannerSettingsChanged() {
    if (!mounted) {
      return;
    }
    if (!_showTopicCommentsRealtimeRefreshBanner && _hasRealtimeCommentUpdate) {
      _mutateState(() {
        _hasRealtimeCommentUpdate = false;
      });
      return;
    }
    _mutateState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final offset = position.pixels;
    if (offset >= position.maxScrollExtent - _loadMoreTriggerOffset) {
      _loadMoreComments();
    }

    final nextShow = offset >= _showBackToTopOffset;
    if (_showBackToTopButtonNotifier.value != nextShow) {
      _showBackToTopButtonNotifier.value = nextShow;
    }
    _updateRepliesFloorSliderVisibility();
    _syncCurrentReplyFloorWithViewport();
  }

  void _updateRepliesFloorSliderVisibility() {
    final headerContext = _repliesHeaderKey.currentContext;
    var nextVisible = false;
    if (headerContext != null) {
      final renderObject = headerContext.findRenderObject();
      if (renderObject is RenderBox && renderObject.attached) {
        final media = MediaQuery.maybeOf(context);
        final statusBarTop = media?.padding.top ?? 0;
        final pinnedTop = statusBarTop + kToolbarHeight;
        final headerTop = renderObject.localToGlobal(Offset.zero).dy;
        nextVisible = headerTop <= pinnedTop + 1 && _comments.isNotEmpty;
      }
    }
    if (_showRepliesFloorSlider == nextVisible) {
      return;
    }
    _mutateState(() {
      _showRepliesFloorSlider = nextVisible;
    });
    if (nextVisible) {
      _repliesFloorSliderVisibilityController.forward();
    } else {
      _repliesFloorSliderVisibilityController.reverse();
    }
  }

  void _syncCurrentReplyFloorWithViewport() {
    if (_repliesFloorSliderVisibilityController.value <= 0.01) {
      return;
    }
    if (_comments.isEmpty) {
      return;
    }
    final currentPostNumber = _findTopVisibleCommentPostNumber();
    if (currentPostNumber == null) {
      return;
    }
    if (_currentVisibleReplyFloor == currentPostNumber) {
      return;
    }
    _mutateState(() {
      _currentVisibleReplyFloor = currentPostNumber;
    });
  }

  int? _findTopVisibleCommentPostNumber() {
    final media = MediaQuery.maybeOf(context);
    if (media == null) {
      return null;
    }
    final sliderHeight =
        _repliesFloorJumpBarBaseHeight *
        _repliesFloorSliderVisibilityController.value;
    final viewportTop = media.padding.top + kToolbarHeight + 48 + sliderHeight;
    final viewportBottom = media.size.height;
    var targetPostNumber = 0;
    var targetTop = double.infinity;

    for (final post in _comments) {
      final key = _postItemKeys[post.postNumber];
      final itemContext = key?.currentContext;
      if (itemContext == null) {
        continue;
      }
      final renderObject = itemContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final itemTop = renderObject.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + renderObject.size.height;
      final isVisible =
          itemBottom > viewportTop + 1 && itemTop < viewportBottom;
      if (!isVisible) {
        continue;
      }
      if (itemTop < targetTop) {
        targetTop = itemTop;
        targetPostNumber = post.postNumber;
      }
    }

    if (targetPostNumber <= 0) {
      return null;
    }
    return targetPostNumber;
  }

  Future<void> _showReplyFloorJumpDialog({
    required int topicId,
    required int currentFloor,
  }) async {
    final maxLoadedFloor = math.max(1, _comments.length + 1);
    final targetFloor = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReplyFloorJumpSheet(
        maxLoadedFloor: maxLoadedFloor,
        initialFloor: currentFloor.clamp(1, maxLoadedFloor),
      ),
    );
    if (!mounted || targetFloor == null) {
      return;
    }
    _mutateState(() {
      _currentVisibleReplyFloor = targetFloor;
    });
    await _jumpToPostNumber(postNumber: targetFloor, topicId: topicId);
  }

  String? _activeCookieHeader() {
    if (_isQingShuiHePanTopic) {
      final auth = _activeQingAuth();
      final cookie = auth?.cookieHeader.trim();
      if (cookie == null || cookie.isEmpty) {
        return null;
      }
      return cookie;
    }
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) return null;
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(username);
  }

  QingShuiHePanAuth? _activeQingAuth() {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (username == null || username.trim().isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.qingShuiHePanAuthFor(username);
  }

  Future<Map<String, dynamic>> _callQingApi({
    required QingShuiHePanAuth auth,
    required Map<String, String> body,
  }) async {
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final requestBody = <String, String>{
      ...body,
      'accessToken': auth.token,
      'accessSecret': auth.secret,
    };
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: const <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: _qingFormEncode(requestBody),
        )
        .timeout(const Duration(seconds: 16));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final errCode = '${map['errcode'] ?? ''}'.trim();
      final head = map['head'] is Map
          ? (map['head'] as Map)
          : const <dynamic, dynamic>{};
      final errInfo = '${head['errInfo'] ?? ''}'.trim();
      final message = errCode.isNotEmpty
          ? errCode
          : (errInfo.isNotEmpty ? errInfo : '清水河畔请求失败');
      throw RiverSideApiException(message);
    }
    return map;
  }

  String _qingFormEncode(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }

  List<Map<String, dynamic>> _asStringDynamicMapList(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      final map = _asStringDynamicMap(item);
      if (map.isNotEmpty) {
        result.add(map);
      }
    }
    return result;
  }

  int? _asInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return int.tryParse('${raw ?? ''}'.trim());
  }

  bool _asBool(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    final source = '${raw ?? ''}'.trim().toLowerCase();
    return source == '1' ||
        source == 'true' ||
        source == 'yes' ||
        source == 'y';
  }

  String _pickString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = '${source[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  int? _pickInt(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = _asInt(source[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  DateTime? _epochToDate(int? epoch) {
    if (epoch == null || epoch <= 0) {
      return null;
    }
    final millis = epoch > 1000000000000 ? epoch : epoch * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _cleanQingHtmlText(String source) {
    final text = _decodeQingHtmlEntities(source);
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _resolveQingUrl(String source) {
    final raw = source.trim();
    if (raw.isEmpty) {
      return '';
    }
    if (raw.startsWith('data:')) {
      return raw;
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      return raw;
    }

    // Guard: avoid treating arbitrary text as URL; this prevents
    // FormatException when parsing plain content such as "100% ...".
    final looksRelativeUrl =
        raw.startsWith('/') ||
        raw.startsWith('./') ||
        raw.startsWith('../') ||
        raw.startsWith('?') ||
        raw.contains('.php') ||
        raw.contains('/mobcent/') ||
        raw.contains('/forum.php') ||
        RegExp(r'^[a-zA-Z0-9_\-./]+(?:\?.*)?$').hasMatch(raw);
    if (!looksRelativeUrl) {
      return '';
    }

    try {
      final base = Uri.parse(RiverServerConfig.instance.qingShuiHePanBaseUrl);
      final relative = Uri.parse(raw);
      return base.resolveUri(relative).toString();
    } catch (_) {
      return '';
    }
  }

  String _decodeQingHtmlEntities(String source) {
    return source
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  bool _looksLikeImageUrl(String source) {
    final value = source.trim().toLowerCase();
    return RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|svg|heic|heif)(\?.*)?$',
    ).hasMatch(value);
  }

  int? _extractUidFromAvatarUrl(String source) {
    final value = source.trim();
    if (value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final queryUid = int.tryParse((uri.queryParameters['uid'] ?? '').trim());
      if (queryUid != null && queryUid > 0) {
        return queryUid;
      }
    }
    final match = RegExp(r'uid=(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    final uid = int.tryParse(match.group(1) ?? '');
    if (uid == null || uid <= 0) {
      return null;
    }
    return uid;
  }

  bool _looksLikeQingInlineEmojiUrl(String source) {
    final value = source.trim().toLowerCase();
    if (value.isEmpty) {
      return false;
    }
    if (value.contains('/smiley/') ||
        value.contains('/mobcent/app/data/phiz/')) {
      return true;
    }
    return RegExp(r'/emoji/|/emoticon/|/emotion/').hasMatch(value);
  }

  String _registerQingInlineEmojiFromUrl(String sourceUrl) {
    final resolved = _resolveQingUrl(sourceUrl);
    if (resolved.isEmpty) {
      return '';
    }
    final seed = resolved.toLowerCase();
    final token = 'qing_inline_${seed.hashCode.abs()}';

    final urls = Map<String, String>.from(_emojiUrls);
    if (urls[token] != resolved) {
      urls[token] = resolved;
      _emojiUrls = urls;
    }

    final groups = <String, List<String>>{};
    for (final entry in _emojiGroups.entries) {
      groups[entry.key] = List<String>.from(entry.value);
    }
    final groupName = '清水河畔';
    final group = groups.putIfAbsent(groupName, () => <String>[]);
    if (!group.contains(token)) {
      group.add(token);
      _emojiGroups = groups;
    }
    return token;
  }

  bool _isLikelyQingUserProfileUrl(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) {
      return false;
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return false;
    }
    final forumHost = Uri.parse(
      RiverServerConfig.instance.qingShuiHePanBaseUrl,
    ).host.toLowerCase();
    if (forumHost.isEmpty) {
      return false;
    }
    final hostMatched = host == forumHost || host.endsWith('.$forumHost');
    if (!hostMatched) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.contains('home.php')) {
      final mod = (uri.queryParameters['mod'] ?? '').toLowerCase();
      return mod == 'space';
    }
    return path.contains('space-uid-');
  }

  String _convertQingBbCodeToMarkdown(String source) {
    var text = _decodeQingHtmlEntities(source).replaceAll('\r\n', '\n');
    if (text.trim().isEmpty) {
      return '';
    }
    text = QingEmojiCatalog.replaceBracketTagsWithColonKey(text);

    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAllMapped(
      RegExp(r'<img[^>]*src="([^"]+)"[^>]*>', caseSensitive: false),
      (match) {
        final tag = (match.group(0) ?? '').toLowerCase();
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return '';
        }
        if (tag.contains('smiley') || _looksLikeQingInlineEmojiUrl(url)) {
          final token = _registerQingInlineEmojiFromUrl(url);
          if (token.isNotEmpty) {
            return ':$token:';
          }
        }
        return '![]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      ),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        final label = _cleanQingHtmlText(match.group(2) ?? '');
        return '[${label.isEmpty ? url : label}]($url)';
      },
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    text = text.replaceAllMapped(
      RegExp(r'\[mobcent_phiz=([^\]]+)\]', caseSensitive: false),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return '';
        }
        final token = _registerQingInlineEmojiFromUrl(url);
        if (token.isNotEmpty) {
          return ':$token:';
        }
        return '![]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\[img(?:=[^\]]*)?\]([\s\S]*?)\[/img\]', caseSensitive: false),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return '';
        }
        return '![]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'\[(?:attach|attachimg)(?:=[^\]]*)?\]([\s\S]*?)\[/\s*(?:attach|attachimg)\]',
        caseSensitive: false,
      ),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return '';
        }
        if (_looksLikeImageUrl(url)) {
          return '![]($url)';
        }
        return '[附件]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\[url=([^\]]+)\]([\s\S]*?)\[/url\]', caseSensitive: false),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return match.group(2) ?? '';
        }
        final label = _cleanQingHtmlText(match.group(2) ?? '');
        final labelAsUrl = _resolveQingUrl(label.trim());
        if (labelAsUrl.isNotEmpty && _looksLikeImageUrl(labelAsUrl)) {
          return '![]($labelAsUrl)';
        }
        final imageInLabelMatch = RegExp(
          r'!\[[^\]]*\]\(([^)]+)\)',
          caseSensitive: false,
        ).firstMatch(label);
        if (imageInLabelMatch != null) {
          final imageUrl = _resolveQingUrl(
            (imageInLabelMatch.group(1) ?? '').trim(),
          );
          if (imageUrl.isNotEmpty) {
            return '![]($imageUrl)';
          }
        }
        final normalizedMentionLabel = _normalizeMentionUsernameToken(label);
        final normalizedLabel = label.isEmpty
            ? url
            : (_isLikelyQingUserProfileUrl(url) &&
                      normalizedMentionLabel.isNotEmpty
                  ? '@$normalizedMentionLabel'
                  : label);
        return '[$normalizedLabel]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\[url\]([\s\S]*?)\[/url\]', caseSensitive: false),
      (match) {
        final url = _resolveQingUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) {
          return '';
        }
        if (_looksLikeImageUrl(url)) {
          return '![]($url)';
        }
        return '[$url]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'\[quote(?:=[^\]]*)?\]([\s\S]*?)\[/quote\]',
        caseSensitive: false,
      ),
      (match) {
        final quote = _cleanQingHtmlText(match.group(1) ?? '');
        if (quote.isEmpty) {
          return '';
        }
        return quote.split('\n').map((line) => '> ${line.trim()}').join('\n');
      },
    );

    text = text
        .replaceAllMapped(
          RegExp(r'\[b\]([\s\S]*?)\[/b\]', caseSensitive: false),
          (match) => '**${match.group(1) ?? ''}**',
        )
        .replaceAllMapped(
          RegExp(r'\[i\]([\s\S]*?)\[/i\]', caseSensitive: false),
          (match) => '_${match.group(1) ?? ''}_',
        )
        .replaceAllMapped(
          RegExp(r'\[u\]([\s\S]*?)\[/u\]', caseSensitive: false),
          (match) => '<u>${match.group(1) ?? ''}</u>',
        )
        .replaceAllMapped(
          RegExp(r'\[s\]([\s\S]*?)\[/s\]', caseSensitive: false),
          (match) => '~~${match.group(1) ?? ''}~~',
        )
        .replaceAllMapped(
          RegExp(
            r'\[(?:size|color|font|align|backcolor)(?:=[^\]]*)?\]([\s\S]*?)\[/\s*(?:size|color|font|align|backcolor)\]',
            caseSensitive: false,
          ),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\[/?(?:list|\*)\]', caseSensitive: false), '');

    text = text.replaceAll(
      RegExp(r'\[/?[a-z][^\]]*\]', caseSensitive: false),
      '',
    );
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Map<String, dynamic> _extractQingQuoteMeta(Map<String, dynamic> raw) {
    var quoteReplyId = _pickInt(raw, const <String>[
      'quote_pid',
      'quote_id',
      'reply_to_post_id',
    ]);
    dynamic contentOverride;
    var legacyMode = 0;

    final replyContent = raw['reply_content'];
    if ((quoteReplyId == null || quoteReplyId <= 0) && replyContent is List) {
      final list = List<dynamic>.from(replyContent);
      if (list.length > 1) {
        final first = _asStringDynamicMap(list[0]);
        final second = _asStringDynamicMap(list[1]);
        final firstType = _asInt(first['type']) ?? 0;
        final secondType = _asInt(second['type']) ?? 0;
        final firstUrl = '${first['url'] ?? ''}'.trim();
        final secondUrl = '${second['url'] ?? ''}'.trim();

        if (firstType == 4 &&
            firstUrl.contains('mod=redirect&goto=findpost&pid=')) {
          final pidMatch = RegExp(r'pid=(\d+)').firstMatch(firstUrl);
          quoteReplyId = int.tryParse(pidMatch?.group(1) ?? '');
          legacyMode = 1;
          list.removeAt(0);
        } else if (secondType == 4 && secondUrl.contains('/goto/')) {
          final pidMatch = RegExp(r'/goto/(\d+)').firstMatch(secondUrl);
          quoteReplyId = int.tryParse(pidMatch?.group(1) ?? '');
          legacyMode = 2;
          if (list.length >= 2) {
            list.removeRange(0, 2);
          }
          if (list.isNotEmpty) {
            final firstText = _asStringDynamicMap(list.first);
            if ((_asInt(firstText['type']) ?? 0) == 0) {
              var infor = '${firstText['infor'] ?? ''}';
              if (infor.contains('\r\n\r\n')) {
                infor = infor.substring(infor.indexOf('\r\n\r\n') + 4);
              } else if (infor.startsWith('>') && !infor.contains('\n')) {
                infor = '';
              }
              firstText['infor'] = infor;
              list[0] = firstText;
            }
          }
        }
      }
      contentOverride = list;
    }

    return <String, dynamic>{
      'quoteReplyId': quoteReplyId,
      'legacyMode': legacyMode,
      'contentOverride': contentOverride,
    };
  }

  String _qingContentToMarkdown(dynamic raw) {
    if (raw is String) {
      return _convertQingBbCodeToMarkdown(raw);
    }
    if (raw is Map) {
      final map = _asStringDynamicMap(raw);
      if (map.isEmpty) {
        return '';
      }
      return _qingContentToMarkdown(
        map['content'] ?? map['infor'] ?? map['text'] ?? map['subject'],
      );
    }
    if (raw is! List) {
      return '';
    }
    final lines = <String>[];
    for (final item in raw) {
      final map = _asStringDynamicMap(item);
      if (map.isEmpty) {
        continue;
      }
      final type = _asInt(map['type']) ?? 0;
      final info = _convertQingBbCodeToMarkdown(
        '${map['infor'] ?? map['text'] ?? ''}',
      );
      final rawUrl = type == 1
          ? _pickString(map, const <String>['originalInfo', 'infor', 'url'])
          : _pickString(map, const <String>['url', 'originalInfo', 'infor']);
      var url = _resolveQingUrl(rawUrl);
      if (type == 1 &&
          (url.isEmpty || !_looksLikeImageUrl(url)) &&
          map.containsKey('url')) {
        final fallbackUrl = _resolveQingUrl('${map['url'] ?? ''}');
        if (fallbackUrl.isNotEmpty && _looksLikeImageUrl(fallbackUrl)) {
          url = fallbackUrl;
        }
      }
      if (type == 1 && url.isNotEmpty) {
        lines.add('![]($url)');
        continue;
      }
      if (type == 3 && url.isNotEmpty) {
        lines.add('[音频]($url)');
        continue;
      }
      if ((type == 2 || type == 5) && url.isNotEmpty) {
        final label = info.isEmpty ? '附件' : info;
        if (_looksLikeImageUrl(url)) {
          lines.add('![]($url)');
        } else {
          lines.add('[$label]($url)');
        }
        continue;
      }
      if (type == 4 && url.isNotEmpty) {
        if (info.trim().isNotEmpty) {
          final infoAsUrl = _resolveQingUrl(info.trim());
          if (_looksLikeImageUrl(infoAsUrl)) {
            lines.add('![]($infoAsUrl)');
            continue;
          }
        }
        final label = info.isEmpty ? url : info;
        lines.add('[$label]($url)');
        continue;
      }
      if (url.isNotEmpty &&
          RegExp(
            r'\.(png|jpe?g|gif|webp|bmp|svg)(\?.*)?$',
            caseSensitive: false,
          ).hasMatch(url)) {
        lines.add('![]($url)');
        continue;
      }
      if (info.isNotEmpty) {
        final pureInfo = info.trim();
        final infoUrl = _resolveQingUrl(pureInfo);
        if (RegExp(r'^https?://', caseSensitive: false).hasMatch(infoUrl) &&
            _looksLikeImageUrl(infoUrl)) {
          lines.add('![]($infoUrl)');
        } else {
          lines.add(info);
        }
      } else if (url.isNotEmpty) {
        lines.add(url);
      }
    }
    return lines.join('\n\n').trim();
  }

  _QingStructuredQuote _buildQingStructuredQuote({
    required dynamic rawQuote,
    required int topicId,
    required int? replyToPostNumber,
    String fallbackUsername = '',
  }) {
    final fallbackToken = _normalizeMentionUsernameToken(fallbackUsername);
    final markdown = _qingContentToMarkdown(rawQuote).trim();
    if (markdown.isEmpty) {
      return _QingStructuredQuote(
        username: fallbackToken,
        bodyMarkdown: '',
        blockMarkdown: '',
      );
    }

    var username = fallbackToken;
    var bodyMarkdown = markdown;
    final lines = markdown.split('\n');
    if (lines.isNotEmpty) {
      final firstLine = lines.first.trim();
      final headerMatch = RegExp(
        r'^(.+?)\s+发表于\s+.+$',
      ).firstMatch(firstLine);
      if (headerMatch != null) {
        final parsedUsername = _normalizeMentionUsernameToken(
          (headerMatch.group(1) ?? '').trim(),
        );
        if (parsedUsername.isNotEmpty) {
          username = parsedUsername;
        }
        bodyMarkdown = lines.skip(1).join('\n').trim();
      }
    }

    if (bodyMarkdown.isEmpty) {
      return _QingStructuredQuote(
        username: username,
        bodyMarkdown: '',
        blockMarkdown: '',
      );
    }

    final headerParts = <String>[
      if (username.isNotEmpty) username.replaceAll('"', ''),
      if ((replyToPostNumber ?? 0) > 0) 'post: $replyToPostNumber',
      'topic: $topicId',
    ];
    final blockMarkdown =
        '[quote="${headerParts.join(', ')}"]$bodyMarkdown[/quote]';
    return _QingStructuredQuote(
      username: username,
      bodyMarkdown: bodyMarkdown,
      blockMarkdown: blockMarkdown,
    );
  }

  List<RiverSidePostReaction> _buildQingReactionList({
    required int likeCount,
    required int dislikeCount,
  }) {
    final list = <RiverSidePostReaction>[];
    if (likeCount > 0) {
      list.add(
        RiverSidePostReaction(id: '+1', type: 'likes', count: likeCount),
      );
    }
    if (dislikeCount > 0) {
      list.add(
        RiverSidePostReaction(id: '-1', type: 'dislikes', count: dislikeCount),
      );
    }
    return list;
  }

  int _extractQingLikeCount(Map<String, dynamic> source) {
    final direct = _pickInt(source, const <String>[
      'recommendAdd',
      'support',
      'support_num',
      'up_num',
      'likes',
    ]);
    if (direct != null && direct >= 0) {
      return direct;
    }
    final extraPanels = source['extraPanel'];
    if (extraPanels is List) {
      for (final panel in extraPanels) {
        final panelMap = _asStringDynamicMap(panel);
        if (panelMap.isEmpty) {
          continue;
        }
        final ext = _asStringDynamicMap(panelMap['extParams']);
        final count = _pickInt(ext, const <String>[
          'recommendAdd',
          'support',
          'up',
        ]);
        if (count != null && count >= 0) {
          return count;
        }
      }
    }
    return 0;
  }

  int _extractQingDislikeCount(Map<String, dynamic> source) {
    final direct = _pickInt(source, const <String>[
      'recommendSub',
      'recommendv_sub_digg',
      'against',
      'down_num',
      'dislikes',
    ]);
    if (direct != null && direct >= 0) {
      return direct;
    }
    final extraPanels = source['extraPanel'];
    if (extraPanels is List) {
      for (final panel in extraPanels) {
        final panelMap = _asStringDynamicMap(panel);
        if (panelMap.isEmpty) {
          continue;
        }
        final ext = _asStringDynamicMap(panelMap['extParams']);
        final count = _pickInt(ext, const <String>[
          'recommendSub',
          'recommendv_sub_digg',
          'against',
          'down',
        ]);
        if (count != null && count >= 0) {
          return count;
        }
      }
    }
    return 0;
  }

  bool _extractQingLiked(Map<String, dynamic> source) {
    for (final key in const <String>[
      'isSupport',
      'is_support',
      'has_support',
      'isHasRecommendAdd',
      'is_recommend_add',
      'isLike',
      'hasLiked',
    ]) {
      final value = source[key];
      if (value == null) {
        continue;
      }
      return _asBool(value);
    }
    return false;
  }

  bool _extractQingDisliked(Map<String, dynamic> source) {
    for (final key in const <String>[
      'isAgainst',
      'is_against',
      'has_against',
      'isHasRecommendSub',
      'is_recommend_sub',
      'isDislike',
      'hasDisliked',
    ]) {
      final value = source[key];
      if (value == null) {
        continue;
      }
      return _asBool(value);
    }
    return false;
  }

  bool _extractQingFavorited(Map<String, dynamic> source) {
    for (final key in const <String>[
      'is_favor',
      'isFavor',
      'is_favorite',
      'isFavorite',
      'favorite',
      'favorited',
      'hasFavor',
      'hasFavorite',
    ]) {
      final value = source[key];
      if (value == null) {
        continue;
      }
      return _asBool(value);
    }
    return false;
  }

  void _mutateState(VoidCallback action) {
    if (!mounted) return;
    setState(action);
  }

  bool get _hasMoreComments {
    if (_isQingShuiHePanTopic) {
      return _qingHasMoreComments;
    }
    final detail = _detail;
    if (detail == null) return false;
    for (final postId in detail.streamPostIds) {
      if (!_loadedPostIds.contains(postId)) return true;
    }
    return false;
  }

  bool _hasLoadedPostNumber(int postNumber) {
    if (postNumber == 1 && _detail != null) return true;
    return _comments.any((post) => post.postNumber == postNumber);
  }

  GlobalKey _keyForPostNumber(int postNumber) {
    return _postItemKeys.putIfAbsent(postNumber, GlobalKey.new);
  }

  List<int> _nextPostIdsToLoad() {
    if (_isQingShuiHePanTopic) {
      return const <int>[];
    }
    final detail = _detail;
    if (detail == null) return const <int>[];

    final next = <int>[];
    for (final postId in detail.streamPostIds) {
      if (_loadedPostIds.contains(postId)) continue;
      next.add(postId);
      if (next.length >= _loadMoreBatchSize) break;
    }
    return next;
  }

  Future<void> _showQuoteBottomSheet(_QuoteBlock quote) async {
    final cookieHeader = _activeCookieHeader();
    final hasFloorRef = quote.ref.postNumber > 0;
    final Future<RiverSideTopicPostDetail>? quotedPostFuture =
        !_isQingShuiHePanTopic && hasFloorRef
        ? widget.dependencies.accountStore.riverSideApiClient
              .fetchTopicPostByNumber(
                topicId: quote.ref.topicId,
                postNumber: quote.ref.postNumber,
                cookieHeader: cookieHeader,
              )
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.76;
        return SafeArea(
          top: false,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.97, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 20),
                  child: child,
                ),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.surfaceContainerLow.withValues(
                        alpha: 0.92,
                      ),
                      theme.colorScheme.surface,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
                        padding: const EdgeInsets.fromLTRB(4, 14, 0, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primaryContainer,
                              ),
                              child: Icon(
                                Icons.format_quote_rounded,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hasFloorRef
                                        ? '回复 @${quote.ref.username} 的 #${quote.ref.postNumber}'
                                        : '引用内容',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    hasFloorRef ? '查看完整被回复内容' : '查看完整引用内容',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: theme
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: '关闭',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow
                                .withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.30,
                              ),
                            ),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              child: quotedPostFuture == null
                                  ? SingleChildScrollView(
                                      child: _MarkdownContent(
                                        markdown: quote.contentMarkdown,
                                        cookieHeader: cookieHeader,
                                        emojiUrls: _emojiUrls,
                                      ),
                                    )
                                  : FutureBuilder<RiverSideTopicPostDetail>(
                                      future: quotedPostFuture,
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 20,
                                            ),
                                            child: Center(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(_labelQuoteLoading),
                                                ],
                                              ),
                                            ),
                                          );
                                        }

                                        if (snapshot.hasError) {
                                          return SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _labelQuoteLoadFailed,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                ),
                                                const SizedBox(height: 8),
                                                _MarkdownContent(
                                                  markdown:
                                                      quote.contentMarkdown,
                                                  cookieHeader: cookieHeader,
                                                  emojiUrls: _emojiUrls,
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        final markdown =
                                            snapshot.data?.contentMarkdown ??
                                            quote.contentMarkdown;
                                        return SingleChildScrollView(
                                          child: _MarkdownContent(
                                            markdown: markdown,
                                            cookieHeader: cookieHeader,
                                            emojiUrls: _emojiUrls,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (hasFloorRef) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  Navigator.of(sheetContext).pop();
                                  await _jumpToPostNumber(
                                    postNumber: quote.ref.postNumber,
                                    topicId: quote.ref.topicId,
                                  );
                                },
                                icon: const Icon(
                                  Icons.numbers_rounded,
                                  size: 18,
                                ),
                                label: const Text(_labelJumpToFloor),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  Navigator.of(sheetContext).pop();
                                  final detailTopicId = _detail?.topicId;
                                  if (detailTopicId == null ||
                                      quote.ref.topicId != detailTopicId) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showRiverSnackBar(_labelCrossTopicQuote);
                                    return;
                                  }
                                  await _openReplyComposer(
                                    topicId: quote.ref.topicId,
                                    replyToPostNumber: quote.ref.postNumber,
                                    quoteUsername: quote.ref.username,
                                    quoteTopicId: quote.ref.topicId,
                                    quoteContent: _stripQuotedMarkdown(
                                      quote.contentMarkdown,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.reply_rounded, size: 18),
                                label: const Text(_labelReplyContent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onRefresh() async {
    _entranceController.reset();
    _contentRevealController.value = 1;
    await _loadInitial();
    if (mounted && _detail != null) {
      _entranceController.forward();
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _dismissRealtimeCommentHint() {
    if (!_hasRealtimeCommentUpdate) return;
    _mutateState(() {
      _hasRealtimeCommentUpdate = false;
    });
  }

  Future<void> _openMentionProfileFromContent(String username) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_isQingShuiHePanTopic) {
      await _openQingUserProfileSheetByMentionToken(normalized);
      return;
    }
    await showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: normalized,
    );
  }

  Future<void> _openTopicFromContent(int topicId) async {
    if (topicId <= 0 || topicId == widget.topicId) {
      return;
    }
    await Navigator.of(context).push(
      DraggableRoute<void>(
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: topicId,
          provider: widget.provider,
          qingBoardId: _qingBoardId,
        ),
      ),
    );
  }

  void _triggerJumpHighlight(int postNumber) {
    _jumpHighlightClearTimer?.cancel();
    _mutateState(() {
      _jumpHighlightPostNumber = postNumber;
      _jumpHighlightToken++;
    });
    _jumpHighlightClearTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted || _jumpHighlightPostNumber != postNumber) {
        return;
      }
      _mutateState(() {
        _jumpHighlightPostNumber = null;
      });
    });
  }

  Future<void> _onRealtimeCommentHintTap() async {
    await _consumeRealtimeCommentUpdate();
  }

  Future<void> _onAiSummaryPressed() async {
    if (_isQingShuiHePanTopic) {
      return;
    }
    if (_loadingAiSummary) {
      return;
    }
    _aiSummaryMarqueeStopTimer?.cancel();
    _mutateState(() {
      _loadingAiSummary = true;
      _showAiSummaryMarquee = true;
    });

    try {
      final summary = await widget.dependencies.accountStore.riverSideApiClient
          .fetchTopicAiSummary(
            topicId: widget.topicId,
            cookieHeader: _activeCookieHeader(),
          );
      if (!mounted) {
        return;
      }
      await _showAiSummarySheet(summary);
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_labelAiSummaryLoadFailed);
    } finally {
      if (mounted) {
        _mutateState(() {
          _loadingAiSummary = false;
        });
        _aiSummaryMarqueeStopTimer = Timer(
          const Duration(milliseconds: 650),
          () {
            if (!mounted) {
              return;
            }
            _mutateState(() {
              _showAiSummaryMarquee = false;
            });
          },
        );
      }
    }
  }

  Future<void> _showAiSummarySheet(RiverSideAiTopicSummary summary) async {
    final theme = Theme.of(context);
    final updatedAtText = summary.updatedAt == null
        ? ''
        : _formatDateTime(summary.updatedAt);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.82;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: 0.98),
            elevation: 12,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
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
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withValues(
                                  alpha: 0.9,
                                ),
                                theme.colorScheme.tertiary.withValues(
                                  alpha: 0.9,
                                ),
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _labelAiSummaryTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (summary.algorithm.isNotEmpty ||
                      updatedAtText.isNotEmpty ||
                      summary.outdated) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (summary.algorithm.isNotEmpty)
                            _TopicMetaPill(
                              icon: Icons.memory_rounded,
                              text: summary.algorithm,
                            ),
                          if (updatedAtText.isNotEmpty)
                            _TopicMetaPill(
                              icon: Icons.schedule_rounded,
                              text: updatedAtText,
                            ),
                          if (summary.outdated)
                            _TopicMetaPill(
                              icon: Icons.warning_amber_rounded,
                              text: '总结可能已过期',
                            ),
                        ],
                      ),
                    ),
                  ],
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.34,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: MarkdownBody(
                            data: summary.summarizedText,
                            selectable: false,
                            styleSheet: MarkdownStyleSheet(
                              p: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                              strong: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
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
  }

  Animation<double> _mainContentRevealAnimation() {
    return CurvedAnimation(
      parent: _contentRevealController,
      curve: Curves.easeOutCubic,
    );
  }

  Animation<double> _commentRevealAnimation(int index) {
    final start = (0.08 + index * 0.03).clamp(0.0, 0.82).toDouble();
    final end = (start + 0.24).clamp(start + 0.08, 1.0).toDouble();
    return CurvedAnimation(
      parent: _contentRevealController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _openCommentDetail(RiverSideTopicPostDetail post) async {
    if (_isQingShuiHePanTopic) {
      return;
    }
    final hasMutations = await Navigator.of(context).push<bool>(
      riverPageRoute<bool>(
        builder: (_) => CommentDetailPage(
          dependencies: widget.dependencies,
          rootPost: post,
          heroTag: _commentHeroTag(post.id),
          initialValidReactions: _detail?.validReactions ?? const <String>[],
          initialEmojiUrls: _emojiUrls,
          initialEmojiGroups: _emojiGroups,
        ),
      ),
    );
    if (!mounted) return;
    if (hasMutations == true) {
      await _loadInitial();
      if (mounted) {
        _entranceController.forward(from: 1.0);
      }
    }
  }

  String get _titleHeroTag =>
      widget.preview?.titleHeroTag ?? 'title_${widget.topicId}';

  String? _mainAuthorAvatarHeroTag(RiverSideTopicDetail? detail) {
    final preview = widget.preview;
    if (preview != null) {
      return preview.authorAvatarHeroTag;
    }
    if (detail != null) {
      return _topicPostAuthorAvatarHeroTag(detail.mainPost);
    }
    return null;
  }

  String? _mainAuthorNameHeroTag(RiverSideTopicDetail? detail) {
    final preview = widget.preview;
    if (preview != null) {
      return preview.authorNameHeroTag;
    }
    if (detail != null) {
      return _topicPostAuthorNameHeroTag(detail.mainPost);
    }
    return null;
  }

  Widget _buildInitialLoadingView(ThemeData theme) {
    final preview = widget.preview;
    final title = preview?.title ?? _labelTopicDetail;
    final avatarHeroTag = preview?.authorAvatarHeroTag;
    final nameHeroTag = preview?.authorNameHeroTag;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Skeletonizer(
        enabled: true,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 126,
              pinned: true,
              stretch: true,
              scrolledUnderElevation: 4,
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surfaceTint,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface.withValues(
                    alpha: 0.88,
                  ),
                  foregroundColor: theme.colorScheme.onSurface,
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: _labelMoreActions,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: _openTopicMoreActionSheet,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface.withValues(
                        alpha: 0.88,
                      ),
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 0,
                  bottom: 14,
                  end: 12,
                ),
                title: Hero(
                  tag: _titleHeroTag,
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ),
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                        theme.colorScheme.surface,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (preview != null &&
                              avatarHeroTag != null &&
                              avatarHeroTag.isNotEmpty)
                            Hero(
                              tag: avatarHeroTag,
                              child: CircleAvatar(
                                radius: 20,
                                backgroundImage: preview.authorAvatarUrl.isEmpty
                                    ? null
                                    : NetworkImage(preview.authorAvatarUrl),
                                child: preview.authorAvatarUrl.isEmpty
                                    ? const Icon(Icons.person_outline)
                                    : null,
                              ),
                            )
                          else
                            const CircleAvatar(
                              radius: 20,
                              child: Icon(Icons.person_outline),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (preview != null &&
                                    nameHeroTag != null &&
                                    nameHeroTag.isNotEmpty)
                                  Hero(
                                    tag: nameHeroTag,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Text(
                                        riverSidePrimaryLabel(
                                          username: preview.authorUsername,
                                          displayName:
                                              preview.authorDisplayName,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  )
                                else
                                  _SkeletonBox(
                                    width: 120,
                                    height: 14,
                                    radius: 7,
                                  ),
                                const SizedBox(height: 6),
                                _SkeletonBox(width: 96, height: 11, radius: 6),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SkeletonBox(
                        width: double.infinity,
                        height: 13,
                        radius: 6,
                      ),
                      const SizedBox(height: 8),
                      _SkeletonBox(
                        width: double.infinity,
                        height: 13,
                        radius: 6,
                      ),
                      const SizedBox(height: 8),
                      _SkeletonBox(width: 220, height: 13, radius: 6),
                      const SizedBox(height: 14),
                      Row(
                        children: const [
                          _SkeletonBox(width: 76, height: 30, radius: 15),
                          SizedBox(width: 8),
                          _SkeletonBox(width: 76, height: 30, radius: 15),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _SkeletonBox(width: 40, height: 40, radius: 20),
                            SizedBox(width: 10),
                            _SkeletonBox(width: 90, height: 12, radius: 6),
                          ],
                        ),
                        SizedBox(height: 12),
                        _SkeletonBox(
                          width: double.infinity,
                          height: 12,
                          radius: 6,
                        ),
                        SizedBox(height: 8),
                        _SkeletonBox(width: 240, height: 12, radius: 6),
                      ],
                    ),
                  ),
                );
              }, childCount: 3),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 闂佸鍨甸鍐惞閺囩姵鍊?
    if (_error != null && _detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(_labelTopicDetail)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadInitial,
                  child: const Text(_labelRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading 闁绘瑢鍋撻柟?
    if (_loadingInitial && _detail == null) {
      return _buildInitialLoadingView(theme);
    }

    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();

    // 閻熸瑥鎽滃▍锕傚礂閵夈儳澹冮柛鏇熸礈閺?
    if (!_loadingInitial &&
        _entranceController.status == AnimationStatus.dismissed) {
      if (_skipNextEntranceAnimation) {
        _skipNextEntranceAnimation = false;
        _entranceController.value = 1;
      } else {
        _entranceController.forward();
      }
    }

    final cookieHeader = _activeCookieHeader();
    final titleHeroTag = _titleHeroTag;
    final mainAuthorAvatarHeroTag = _mainAuthorAvatarHeroTag(detail);
    final mainAuthorNameHeroTag = _mainAuthorNameHeroTag(detail);
    final maxLoadedFloor = math.max(1, _comments.length + 1);
    final currentVisibleFloor = _currentVisibleReplyFloor.clamp(
      1,
      maxLoadedFloor,
    );
    final jumpBarVisibility = _repliesFloorSliderVisibilityController.value
        .clamp(0.0, 1.0);

    return RepaintBoundary(
      key: _screenshotCaptureBoundaryKey,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              edgeOffset: 140,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 126,
                    pinned: true,
                    stretch: true,
                    scrolledUnderElevation: 4,
                    elevation: 0,
                    backgroundColor: theme.colorScheme.surface,
                    surfaceTintColor: theme.colorScheme.surfaceTint,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface.withValues(
                          alpha: 0.88,
                        ),
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          tooltip: _labelMoreActions,
                          icon: const Icon(Icons.more_horiz_rounded),
                          onPressed: _openTopicMoreActionSheet,
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.surface
                                .withValues(alpha: 0.88),
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      stretchModes: const [
                        StretchMode.zoomBackground,
                        StretchMode.blurBackground,
                      ],
                      centerTitle: false,
                      titlePadding: const EdgeInsetsDirectional.only(
                        start: 0,
                        bottom: 14,
                        end: 12,
                      ),
                      title: AnimatedBuilder(
                        animation: _scrollController,
                        child: Hero(
                          tag: titleHeroTag,
                          flightShuttleBuilder:
                              (
                                flightContext,
                                animation,
                                flightDirection,
                                fromHeroContext,
                                toHeroContext,
                              ) {
                                return DefaultTextStyle.merge(
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ) ??
                                      const TextStyle(),
                                  child: (toHeroContext.widget as Hero).child,
                                );
                              },
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              detail.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ),
                        builder: (context, child) {
                          final offset = _scrollController.hasClients
                              ? _scrollController.offset
                              : 0.0;
                          final t = (offset / 84).clamp(0.0, 1.0);
                          final left = 8.0 + 48.0 * t;
                          return Padding(
                            padding: EdgeInsets.only(left: left),
                            child: child,
                          );
                        },
                      ),
                      background: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.10),
                              theme.colorScheme.surface,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 72, 0),
                              child: _TopicStatsCapsule(
                                replyCount: detail.replyCount,
                                viewCount: detail.viewCount,
                                likeCount: detail.likeCount,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Main post section.
                  SliverToBoxAdapter(
                    child: _SlideFadeTransition(
                      animation: _entranceController,
                      delay: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _showBackToTopButtonNotifier,
                          builder: (context, showFloatingReply, _) {
                            final ownMainPost = _isOwnComment(detail.mainPost);
                            return _MainPostCard(
                              key: _keyForPostNumber(1),
                              detail: detail,
                              cookieHeader: cookieHeader,
                              emojiUrls: _emojiUrls,
                              onQuoteTap: _showQuoteBottomSheet,
                              onMentionTap: _openMentionProfileFromContent,
                              onTopicLinkTap: _openTopicFromContent,
                              isReacting: _reactingPostIds.contains(
                                detail.mainPost.id,
                              ),
                              onReactPressed: _onReactPressed,
                              onReplyPressed: (post) => _openReplyComposer(
                                topicId: post.topicId,
                                aiReferenceText: _stripQuotedMarkdown(
                                  post.contentMarkdown,
                                ),
                              ),
                              onReactionStatusPressed: (post, reactionId) =>
                                  _onReactionStatusPressed(
                                    post: post,
                                    reactionId: reactionId,
                                  ),
                              onAuthorTap: _openAuthorProfileSheetForPost,
                              showOwnerActions:
                                  !_isQingShuiHePanTopic && ownMainPost,
                              showTransferAction: ownMainPost,
                              onTransferPressed: ownMainPost
                                  ? _openCrossPostTransferSheet
                                  : null,
                              transferTargetProvider: _isQingShuiHePanTopic
                                  ? AccountProvider.riverSide
                                  : AccountProvider.qingShuiHePan,
                              onEditPressed:
                                  !_isQingShuiHePanTopic && ownMainPost
                                  ? () => _openEditCommentComposer(
                                      detail.mainPost,
                                    )
                                  : null,
                              onDeletePressed:
                                  !_isQingShuiHePanTopic && ownMainPost
                                  ? () => _deleteMainPost(detail.mainPost)
                                  : null,
                              authorAvatarHeroTag: mainAuthorAvatarHeroTag,
                              authorNameHeroTag: mainAuthorNameHeroTag,
                              bodyRevealAnimation:
                                  _mainContentRevealAnimation(),
                              pendingHeroReactionId:
                                  _pendingReactionHeroByPostId[detail
                                      .mainPost
                                      .id],
                              reactionPulseToken:
                                  _reactionPulseTokenByPostId[detail
                                      .mainPost
                                      .id] ??
                                  0,
                              submittingPollKeys: _submittingPollKeys,
                              onPollVote: (poll, optionIds) => _submitPollVote(
                                postId: detail.mainPost.id,
                                poll: poll,
                                optionIds: optionIds,
                              ),
                              onPollClear: (poll) => _clearPollVote(
                                postId: detail.mainPost.id,
                                poll: poll,
                              ),
                              onAiSummaryPressed: _onAiSummaryPressed,
                              aiSummaryLoading: _loadingAiSummary,
                              showAiSummaryMarquee: _showAiSummaryMarquee,
                              showAiSummaryAction: !_isQingShuiHePanTopic,
                              showReplyAction: !showFloatingReply,
                              showAliasFirst: _isQingShuiHePanTopic,
                              autoCollapseBody: widget
                                  .dependencies
                                  .settingsController
                                  .autoCollapseTopicBody,
                              isJumpHighlighted: _jumpHighlightPostNumber == 1,
                              jumpHighlightToken: _jumpHighlightPostNumber == 1
                                  ? _jumpHighlightToken
                                  : 0,
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // 3. 閻燁厽娲濋悵顐﹀础閳?Header
                  SliverToBoxAdapter(
                    key: _repliesSectionAnchorKey,
                    child: const SizedBox.shrink(),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(
                      headerKey: _repliesHeaderKey,
                      title: _labelReplies,
                      count: detail.replyCount,
                      theme: theme,
                      showRealtimeHint:
                          _showTopicCommentsRealtimeRefreshBanner &&
                          _hasRealtimeCommentUpdate,
                      onRealtimeHintTap: _onRealtimeCommentHintTap,
                      onRealtimeHintClose: _dismissRealtimeCommentHint,
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _RepliesFloorJumpHeaderDelegate(
                      theme: theme,
                      visibility: jumpBarVisibility,
                      currentFloor: currentVisibleFloor,
                      maxLoadedFloor: maxLoadedFloor,
                      onJumpPressed: () => _showReplyFloorJumpDialog(
                        topicId: detail.topicId,
                        currentFloor: currentVisibleFloor,
                      ),
                    ),
                  ),

                  // 4. 閻燁厽娲濋悵顐﹀礆濡ゅ嫨鈧?
                  if (_comments.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: Colors.black12,
                              ),
                              SizedBox(height: 16),
                              Text(
                                _labelNoComments,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final post = _comments[index];
                        final delay = (index * 30).clamp(0, 400);
                        final reveal = _commentRevealAnimation(index);

                        return FadeTransition(
                          opacity: reveal,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.025),
                              end: Offset.zero,
                            ).animate(reveal),
                            child: _SlideFadeTransition(
                              animation: _entranceController,
                              delay: 100 + delay,
                              child: Column(
                                children: [
                                  _CommentCard(
                                    // 闂佹彃绉甸～鎰嚗瀹€鈧▓鎴犳噹閺囷紕褰ㄩ悶?
                                    key: _keyForPostNumber(post.postNumber),
                                    post: post,
                                    cookieHeader: cookieHeader,
                                    emojiUrls: _emojiUrls,
                                    onQuoteTap: _showQuoteBottomSheet,
                                    onMentionTap:
                                        _openMentionProfileFromContent,
                                    onTopicLinkTap: _openTopicFromContent,
                                    isReacting: _reactingPostIds.contains(
                                      post.id,
                                    ),
                                    onReactPressed: _onReactPressed,
                                    onTap: _isQingShuiHePanTopic
                                        ? () {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showRiverSnackBar('清水河畔评论详情暂未接入');
                                          }
                                        : () => _openCommentDetail(post),
                                    onLongPress: () =>
                                        _showCommentActions(post),
                                    onAuthorTap: _openAuthorProfileSheetForPost,
                                    onReplyPressed: (target) {
                                      _openReplyComposer(
                                        topicId: target.topicId,
                                        replyToPostNumber: target.postNumber,
                                        quoteUsername: target.authorUsername,
                                        quoteTopicId: target.topicId,
                                        quoteContent: _stripQuotedMarkdown(
                                          target.contentMarkdown,
                                        ),
                                      );
                                    },
                                    onReactionStatusPressed:
                                        (post, reactionId) =>
                                            _onReactionStatusPressed(
                                              post: post,
                                              reactionId: reactionId,
                                            ),
                                    heroTag: _commentHeroTag(post.id),
                                    pendingHeroReactionId:
                                        _pendingReactionHeroByPostId[post.id],
                                    reactionPulseToken:
                                        _reactionPulseTokenByPostId[post.id] ??
                                        0,
                                    showAliasFirst: _isQingShuiHePanTopic,
                                    isJumpHighlighted:
                                        _jumpHighlightPostNumber ==
                                        post.postNumber,
                                    jumpHighlightToken:
                                        _jumpHighlightPostNumber ==
                                            post.postNumber
                                        ? _jumpHighlightToken
                                        : 0,
                                  ),
                                  // 闁告帒妫楁竟濠勬?
                                  if (index != _comments.length - 1)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: post.isSystemActionPost ? 12 : 60,
                                      ), // 閻忓繐绉圭紞鍌炲棘閸パ呮憻
                                      child: Divider(
                                        height: 1,
                                        thickness: 0.5,
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }, childCount: _comments.length),
                    ),

                  // 5. 底部加载/结束提示（空评论时不重复显示“没有更多评论了”）
                  if (_comments.isNotEmpty || _loadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: _loadingMore
                              ? Skeletonizer(
                                  enabled: true,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text('正在加载更多评论...'),
                                  ),
                                )
                              : Text(
                                  _hasMoreComments ? '' : _labelNoMoreReplies,
                                  style: TextStyle(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Floating actions.
            ValueListenableBuilder<bool>(
              valueListenable: _showBackToTopButtonNotifier,
              builder: (context, visible, _) {
                return Positioned(
                  right: 16,
                  bottom: 28,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: visible ? 1 : 0,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      scale: visible ? 1 : 0.84,
                      curve: Curves.easeOutBack,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (visible) ...[
                            FloatingActionButton.small(
                              heroTag: 'reply_topic_fab_${detail.topicId}',
                              onPressed: () => _openReplyComposer(
                                topicId: detail.topicId,
                                aiReferenceText: _stripQuotedMarkdown(
                                  detail.mainPost.contentMarkdown,
                                ),
                              ),
                              elevation: 2,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.reply_rounded),
                            ),
                            const SizedBox(height: 10),
                          ],
                          FloatingActionButton.small(
                            heroTag: 'back_to_top_fab',
                            onPressed: visible ? _scrollToTop : null,
                            elevation: 2,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            child: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _TopicDetailVisibleWatermarkOverlay(
                  text: _topicDetailVisibleWatermarkText,
                  isDarkMode: theme.brightness == Brightness.dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicDetailVisibleWatermarkOverlay extends StatelessWidget {
  const _TopicDetailVisibleWatermarkOverlay({
    required this.text,
    required this.isDarkMode,
  });

  final String text;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TopicDetailVisibleWatermarkPainter(
          text: text,
          isDarkMode: isDarkMode,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _TopicDetailVisibleWatermarkPainter extends CustomPainter {
  const _TopicDetailVisibleWatermarkPainter({
    required this.text,
    required this.isDarkMode,
  });

  final String text;
  final bool isDarkMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || text.trim().isEmpty) {
      return;
    }
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: isDarkMode
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.black.withValues(alpha: 0.028),
    );
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final textSize = textPainter.size;
    if (textSize.width <= 0 || textSize.height <= 0) {
      return;
    }

    final stepX = textSize.width + 54;
    final stepY = textSize.height + 78;
    canvas.save();
    canvas.rotate(-math.pi / 14);
    final startX = -size.height * 0.22;
    final endX = size.width + size.height * 0.6;
    final startY = -size.height * 1.2;
    final endY = size.height * 1.3;
    for (double y = startY; y < endY; y += stepY) {
      for (double x = startX; x < endX; x += stepX) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _TopicDetailVisibleWatermarkPainter oldDelegate,
  ) {
    return oldDelegate.text != text || oldDelegate.isDarkMode != isDarkMode;
  }
}

class _QingReplyUploadImage {
  const _QingReplyUploadImage({
    required this.aid,
    required this.urlName,
    required this.resolvedUrl,
  });

  final String aid;
  final String urlName;
  final String resolvedUrl;
}

class _TopicSharePosterCard extends StatelessWidget {
  const _TopicSharePosterCard({
    required this.detail,
    required this.mainContentMarkdown,
    required this.topicLink,
    required this.accountDisplayName,
    required this.accountUsername,
    required this.accountAvatarUrl,
    required this.appName,
    required this.appVersion,
  });

  final RiverSideTopicDetail detail;
  final String mainContentMarkdown;
  final String topicLink;
  final String accountDisplayName;
  final String accountUsername;
  final String accountAvatarUrl;
  final String appName;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = detail.mainPost;
    final authorName = riverSidePrimaryLabel(
      username: post.authorUsername,
      displayName: post.authorDisplayName,
    );
    final content = mainContentMarkdown.trim().isEmpty
        ? _TopicDetailPageState._labelEmpty
        : mainContentMarkdown.trim();
    final generatedAt = _formatDateTime(DateTime.now());
    final appVersionText = appVersion.trim().isEmpty ? '-' : appVersion.trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: post.authorAvatarUrl.isEmpty
                      ? null
                      : NetworkImage(post.authorAvatarUrl),
                  child: post.authorAvatarUrl.isEmpty
                      ? const Icon(Icons.person_outline_rounded)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        authorName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.28,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      Icons.article_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PosterMetaChip(
                  icon: Icons.person_outline_rounded,
                  text: authorName,
                ),
                _PosterMetaChip(
                  icon: Icons.schedule_rounded,
                  text: _formatDateTime(detail.createdAt),
                ),
                _PosterMetaChip(
                  icon: Icons.mode_comment_outlined,
                  text: '${detail.replyCount}',
                ),
                _PosterMetaChip(
                  icon: Icons.visibility_outlined,
                  text: '${detail.viewCount}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: MarkdownBody(
                data: content,
                selectable: false,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  h1: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  h2: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  blockquote: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.55,
                        ),
                        width: 3,
                      ),
                    ),
                  ),
                  listBullet: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  code: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  a: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.24,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                topicLink,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: accountAvatarUrl.isEmpty
                      ? null
                      : NetworkImage(accountAvatarUrl),
                  child: accountAvatarUrl.isEmpty
                      ? const Icon(Icons.person_outline_rounded)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountDisplayName.trim().isEmpty
                            ? _TopicDetailPageState._labelUnknownUser
                            : accountDisplayName.trim(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        accountUsername.trim().isEmpty
                            ? '@guest'
                            : '@${accountUsername.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$appName  $appVersionText',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      generatedAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterMetaChip extends StatelessWidget {
  const _PosterMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicMetaPill extends StatelessWidget {
  const _TopicMetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicStatsCapsule extends StatelessWidget {
  const _TopicStatsCapsule({
    required this.replyCount,
    required this.viewCount,
    required this.likeCount,
  });

  final int replyCount;
  final int viewCount;
  final int likeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = <({IconData icon, String text})>[
      (icon: Icons.mode_comment_outlined, text: '$replyCount'),
      (icon: Icons.visibility_outlined, text: '$viewCount'),
      (icon: Icons.thumb_up_alt_outlined, text: '$likeCount'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i != 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: 1,
                    height: 12,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
              Icon(
                segments[i].icon,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                segments[i].text,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Simple slide + fade transition wrapper.
// -----------------------------------------------------------------------------
class _SlideFadeTransition extends StatelessWidget {
  final AnimationController animation;
  final int delay;
  final Widget child;

  const _SlideFadeTransition({
    required this.animation,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Delay-aware normalized progress for staggered animations.
        final double delayInSeconds = delay / 1000.0;
        final double animationDurationInSeconds =
            animation.duration!.inMilliseconds / 1000.0;

        // 闁稿繐鍟扮粈宀勬儍閸曨偄鐝氶柣锝庡亰閺嬪﹥鎱ㄧ€ｎ偅顎夐梻浣规崌缁?(0.0 - 1.0)
        final double start = (delayInSeconds / animationDurationInSeconds)
            .clamp(0.0, 0.8);
        // 闁稿繐鍟扮粈宀勬儍閸曨偄鐝氶柣锝庡亝鐎垫梻鐥仦鐐€夐梻?(濞达絾姊婚梽鍕疾閸岀偞娈鹃柣銊ュ閻︻喗绗?闁挎稑鐭傞埀顒佺懆閿涗胶鎳涢鐘蹭槐 0.4 (闁?30% ~ 40% 闁汇劌瀚顏堟⒑閹捐埖鏆忓〒姘閻ｎ剟骞嬮幇顓＄獥闁?
        final double end = (start + 0.4).clamp(0.0, 1.0);

        final curve = CurvedAnimation(
          parent: animation,
          curve: Interval(start, end, curve: Curves.easeOutQuad),
        );

        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Key? headerKey;
  final String title;
  final int count;
  final ThemeData theme;
  final bool showRealtimeHint;
  final VoidCallback? onRealtimeHintTap;
  final VoidCallback? onRealtimeHintClose;

  _SectionHeaderDelegate({
    this.headerKey,
    required this.title,
    required this.count,
    required this.theme,
    this.showRealtimeHint = false,
    this.onRealtimeHintTap,
    this.onRealtimeHintClose,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final opacity = (shrinkOffset / 12).clamp(0.92, 1.0);

    return Container(
      key: headerKey,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: showRealtimeHint
                ? Container(
                    key: const ValueKey<String>('realtime-comment-hint'),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: onRealtimeHintTap,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(9, 5, 6, 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fiber_new_rounded,
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '有新评论',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: onRealtimeHintClose,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.7,
                                ),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('realtime-comment-hint-empty'),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.title != title ||
        oldDelegate.theme != theme ||
        oldDelegate.showRealtimeHint != showRealtimeHint ||
        oldDelegate.headerKey != headerKey;
  }
}

class _ReplyFloorJumpSheet extends StatefulWidget {
  const _ReplyFloorJumpSheet({
    required this.maxLoadedFloor,
    required this.initialFloor,
  });

  final int maxLoadedFloor;
  final int initialFloor;

  @override
  State<_ReplyFloorJumpSheet> createState() => _ReplyFloorJumpSheetState();
}

class _ReplyFloorJumpSheetState extends State<_ReplyFloorJumpSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFloor.clamp(1, widget.maxLoadedFloor);
    _controller = TextEditingController(text: '$initial');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _normalizeFloor(int value) => value.clamp(1, widget.maxLoadedFloor);

  void _applyQuickFloor(int floor) {
    final next = _normalizeFloor(floor);
    _controller
      ..text = '$next'
      ..selection = TextSelection.collapsed(offset: '$next'.length);
    if (_errorText != null) {
      setState(() {
        _errorText = null;
      });
    }
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1 || parsed > widget.maxLoadedFloor) {
      setState(() {
        _errorText = '请输入 1-${widget.maxLoadedFloor} 之间的楼层';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final initialFloor = widget.initialFloor.clamp(1, widget.maxLoadedFloor);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, math.max(12, bottomInset + 10)),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.surfaceContainerHigh, colors.surfaceContainerLow],
            ),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.58),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.route_rounded,
                        size: 18,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '跳转楼层',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Text(
                      '已加载 1-${widget.maxLoadedFloor}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: '#',
                    hintText: '输入要跳转的楼层号',
                    errorText: _errorText,
                    filled: true,
                    fillColor: colors.surface.withValues(alpha: 0.72),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.76),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.76),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.primary, width: 1.2),
                    ),
                  ),
                  onChanged: (_) {
                    if (_errorText == null) {
                      return;
                    }
                    setState(() {
                      _errorText = null;
                    });
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('首楼'),
                      onPressed: () => _applyQuickFloor(1),
                    ),
                    ActionChip(
                      label: Text('当前 $initialFloor'),
                      onPressed: () => _applyQuickFloor(initialFloor),
                    ),
                    ActionChip(
                      label: const Text('-10'),
                      onPressed: () {
                        final current =
                            int.tryParse(_controller.text.trim()) ??
                            initialFloor;
                        _applyQuickFloor(current - 10);
                      },
                    ),
                    ActionChip(
                      label: const Text('+10'),
                      onPressed: () {
                        final current =
                            int.tryParse(_controller.text.trim()) ??
                            initialFloor;
                        _applyQuickFloor(current + 10);
                      },
                    ),
                    ActionChip(
                      label: const Text('最新'),
                      onPressed: () => _applyQuickFloor(widget.maxLoadedFloor),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.arrow_downward_rounded),
                        label: const Text('跳转'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RepliesFloorJumpHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _RepliesFloorJumpHeaderDelegate({
    required this.theme,
    required this.visibility,
    required this.currentFloor,
    required this.maxLoadedFloor,
    required this.onJumpPressed,
  });

  final ThemeData theme;
  final double visibility;
  final int currentFloor;
  final int maxLoadedFloor;
  final VoidCallback onJumpPressed;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = visibility.clamp(0.0, 1.0);
    if (progress <= 0.001 || maxLoadedFloor <= 1) {
      return const SizedBox.shrink();
    }
    final shownFloor = currentFloor.clamp(1, maxLoadedFloor);
    final floorRatio = maxLoadedFloor <= 1
        ? 0.0
        : ((shownFloor - 1) / (maxLoadedFloor - 1)).clamp(0.0, 1.0);

    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, -6 * (1 - progress)),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
                theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.76),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 72),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.62,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '当前 $shownFloor 楼',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已加载 1-$maxLoadedFloor 楼',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: floorRatio,
                        minHeight: 4,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onJumpPressed,
                icon: const Icon(Icons.flag_rounded, size: 16),
                label: const Text('跳转'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent {
    if (maxLoadedFloor <= 1) {
      return 0;
    }
    return _TopicDetailPageState._repliesFloorJumpBarBaseHeight *
        visibility.clamp(0.0, 1.0);
  }

  @override
  double get minExtent => maxExtent;

  @override
  bool shouldRebuild(covariant _RepliesFloorJumpHeaderDelegate oldDelegate) {
    return oldDelegate.theme != theme ||
        (oldDelegate.visibility - visibility).abs() > 0.001 ||
        oldDelegate.currentFloor != currentFloor ||
        oldDelegate.maxLoadedFloor != maxLoadedFloor ||
        oldDelegate.onJumpPressed != onJumpPressed;
  }
}

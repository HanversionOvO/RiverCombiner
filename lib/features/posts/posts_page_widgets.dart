part of 'posts_page.dart';

class _OnlineUserPreview {
  const _OnlineUserPreview({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final String username;
  final String displayName;
  final String avatarUrl;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _OnlineUserPreview &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl;
  }

  @override
  int get hashCode => Object.hash(username, displayName, avatarUrl);
}

class _TopicListTab extends StatefulWidget {
  const _TopicListTab({
    super.key,
    required this.dependencies,
    required this.forumProvider,
    required this.feed,
    this.boardId,
    required this.categoryNameMap,
    required this.filterVersion,
    required this.showInlineRealtimeHint,
    this.onConsumeRealtimeUpdate,
    this.onDismissRealtimeUpdate,
    this.onTopicsSnapshotChanged,
    this.onScrollOffsetChanged,
  });

  final AppDependencies dependencies;
  final _PostsForumProvider forumProvider;
  final RiverSideTopicFeed feed;
  final int? boardId;
  final Map<int, String> categoryNameMap;
  final int filterVersion;
  final bool showInlineRealtimeHint;
  final Future<void> Function()? onConsumeRealtimeUpdate;
  final VoidCallback? onDismissRealtimeUpdate;
  final ValueChanged<List<RiverSideTopicSummary>>? onTopicsSnapshotChanged;
  final ValueChanged<double>? onScrollOffsetChanged;

  @override
  State<_TopicListTab> createState() => _TopicListTabState();
}

class _TopicListTabState extends State<_TopicListTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final GlobalKey _listViewKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackToTopNotifier = ValueNotifier<bool>(false);
  final Map<int, GlobalKey> _topicItemKeys = <int, GlobalKey>{};
  List<RiverSideTopicSummary> _topics = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 0;
  int _requestSerial = 0;
  int? _realtimeHintAnchorIndex;
  late final AnimationController _skeletonPulseController;
  late final Animation<double> _skeletonPulse;

  @override
  bool get wantKeepAlive => true;

  double get currentScrollOffset =>
      _scrollController.hasClients ? _scrollController.offset : 0;

  @override
  void initState() {
    super.initState();
    _skeletonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _skeletonPulse = CurvedAnimation(
      parent: _skeletonPulseController,
      curve: Curves.easeInOut,
    );
    _loadFirstPage();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onScrollOffsetChanged?.call(currentScrollOffset);
    });
  }

  @override
  void didUpdateWidget(covariant _TopicListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showInlineRealtimeHint && widget.showInlineRealtimeHint) {
      _pinRealtimeHintAnchorToCurrentViewport();
    } else if (oldWidget.showInlineRealtimeHint &&
        !widget.showInlineRealtimeHint) {
      _realtimeHintAnchorIndex = null;
    }
    if (oldWidget.boardId != widget.boardId ||
        oldWidget.filterVersion != widget.filterVersion ||
        oldWidget.forumProvider != widget.forumProvider) {
      _scrollToTopAndRefresh();
    }
  }

  @override
  void dispose() {
    _skeletonPulseController.dispose();
    _showBackToTopNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    widget.onScrollOffsetChanged?.call(currentScroll);
    final shouldShowBackToTop = currentScroll >= 420;
    if (_showBackToTopNotifier.value != shouldShowBackToTop) {
      _showBackToTopNotifier.value = shouldShowBackToTop;
    }
    if (currentScroll >= maxScroll - 200 && !_isLoadingMore && _hasMore) {
      _loadMore();
    }
  }

  Future<void> _handleRefresh() async {
    await _loadFirstPage();
  }

  void _pinRealtimeHintAnchorToCurrentViewport() {
    if (_topics.isEmpty) {
      _realtimeHintAnchorIndex = null;
      return;
    }
    final visibleBottomIndex = _findBottomVisibleTopicIndex();
    if (visibleBottomIndex != null) {
      _realtimeHintAnchorIndex = visibleBottomIndex;
      return;
    }
    const estimatedTopicItemExtent = 208.0;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0;
    final viewport = _scrollController.hasClients
        ? _scrollController.position.viewportDimension
        : 0.0;
    final rawIndex = ((offset + viewport) / estimatedTopicItemExtent).floor();
    final clampedIndex = rawIndex.clamp(0, _topics.length - 1);
    _realtimeHintAnchorIndex = clampedIndex;
  }

  int? _findBottomVisibleTopicIndex() {
    final listContext = _listViewKey.currentContext;
    final listRenderObject = listContext?.findRenderObject();
    if (listRenderObject is! RenderBox || !listRenderObject.attached) {
      return null;
    }
    final listTop = listRenderObject.localToGlobal(Offset.zero).dy;
    final listBottom = listTop + listRenderObject.size.height;
    int? targetIndex;
    var maxVisibleBottom = -double.infinity;

    for (final entry in _topicItemKeys.entries) {
      final itemContext = entry.value.currentContext;
      final itemRenderObject = itemContext?.findRenderObject();
      if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
        continue;
      }
      final itemTop = itemRenderObject.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + itemRenderObject.size.height;
      final isVisible = itemBottom > listTop + 1 && itemTop < listBottom - 1;
      if (!isVisible) {
        continue;
      }
      if (itemBottom > maxVisibleBottom) {
        maxVisibleBottom = itemBottom;
        targetIndex = entry.key;
      }
    }
    return targetIndex;
  }

  GlobalKey _topicItemKeyForIndex(int index) {
    return _topicItemKeys.putIfAbsent(
      index,
      () => GlobalKey(debugLabel: 'topic_item_$index'),
    );
  }

  String _displayCategoryName(RiverSideTopicSummary topic) {
    final categoryId = topic.categoryId;
    if (categoryId != null) {
      final mapped = widget.categoryNameMap[categoryId];
      if (mapped != null && mapped.trim().isNotEmpty) {
        return mapped;
      }
    }
    return topic.categoryName;
  }

  Future<void> _scrollToTopAndRefresh() async {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    widget.onScrollOffsetChanged?.call(0);
    _showBackToTopNotifier.value = false;
    await _loadFirstPage();
  }

  Future<void> scrollToTopAndRefresh() {
    return _scrollToTopAndRefresh();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadFirstPage() async {
    final serial = ++_requestSerial;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final topics = await _fetchTopics(page: 0);
      if (!mounted || serial != _requestSerial) return;

      setState(() {
        _topics = topics;
        _topicItemKeys.clear();
        _isLoading = false;
        _hasMore = topics.isNotEmpty;
        _page = 0;
      });
      widget.onTopicsSnapshotChanged?.call(
        List<RiverSideTopicSummary>.unmodifiable(_topics),
      );
    } catch (e) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _isLoading = false;
        _error = e is RiverSideApiException
            ? e.message
            : '\u52a0\u8f7d\u5931\u8d25';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    final serial = _requestSerial;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final newTopics = await _fetchTopics(page: nextPage);
      if (!mounted || serial != _requestSerial) return;

      setState(() {
        if (newTopics.isEmpty) {
          _hasMore = false;
        } else {
          final existingIds = _topics.map((e) => e.id).toSet();
          _topics.addAll(newTopics.where((e) => !existingIds.contains(e.id)));
          _page = nextPage;
        }
        _isLoadingMore = false;
      });
      widget.onTopicsSnapshotChanged?.call(
        List<RiverSideTopicSummary>.unmodifiable(_topics),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<List<RiverSideTopicSummary>> _fetchTopics({required int page}) {
    if (widget.forumProvider == _PostsForumProvider.qingShuiHePan) {
      return _fetchQingTopics(page: page);
    }
    final cookie = widget.dependencies.accountStore.riverSideCookieHeaderFor(
      widget.dependencies.accountStore.activeRiverSideUsername ?? '',
    );
    return widget.dependencies.accountStore.riverSideApiClient
        .fetchTopicSummaries(
          feed: widget.feed,
          categoryId: widget.boardId,
          page: page,
          cookieHeader: cookie,
        );
  }

  Future<List<RiverSideTopicSummary>> _fetchQingTopics({
    required int page,
  }) async {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (username == null || username.trim().isEmpty) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
    final auth = widget.dependencies.accountStore.qingShuiHePanAuthFor(
      username,
    );
    if (auth == null) {
      throw const RiverSideApiException('清水河畔认证信息缺失，请重新登录');
    }

    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final requestBody = <String, String>{
      'r': 'forum/topiclist',
      'isImageList': '1',
      'sortby': _qingSortByFromFeed(widget.feed),
      'page': '${page + 1}',
      'pageSize': '20',
      'accessToken': auth.token,
      'accessSecret': auth.secret,
    };
    final boardId = widget.boardId;
    if (boardId != null && boardId > 0) {
      requestBody['boardId'] = '$boardId';
    }

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: const <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: _formEncode(requestBody),
        )
        .timeout(const Duration(seconds: 14));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔帖子接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final errcode = '${map['errcode'] ?? ''}'.trim();
      final head = map['head'] is Map
          ? map['head'] as Map
          : const <dynamic, dynamic>{};
      final errInfo = '${head['errInfo'] ?? ''}'.trim();
      final message = errcode.isNotEmpty
          ? errcode
          : (errInfo.isNotEmpty ? errInfo : '清水河畔帖子加载失败');
      throw RiverSideApiException(message);
    }
    final listRaw = map['list'];
    if (listRaw is! List) {
      return const <RiverSideTopicSummary>[];
    }
    final topics = <RiverSideTopicSummary>[];
    for (final raw in listRaw) {
      if (raw is! Map) {
        continue;
      }
      final item = raw.map((key, value) => MapEntry('$key', value));
      final topicId = _toInt(item['topic_id']) ?? _toInt(item['id']) ?? 0;
      if (topicId <= 0) {
        continue;
      }
      final title = _pickString(item, const <String>['title', 'subject']);
      final excerpt = _pickString(item, const <String>[
        'subject',
        'summary',
        'content',
      ]);
      final boardName = _pickString(item, const <String>[
        'board_name',
        'forum_name',
        'type_name',
      ]);
      final displayName = _pickString(item, const <String>[
        'user_nick_name',
        'name',
        'userName',
        'username',
      ]);
      final avatar = _pickString(item, const <String>[
        'userAvatar',
        'avatar',
        'icon',
      ]);
      final createdRaw =
          _toInt(item['last_reply_date']) ??
          _toInt(item['create_date']) ??
          _toInt(item['dateline']);
      final createdAt = _parseEpochDate(createdRaw);
      final hot = (_toInt(item['hot']) ?? 0) > 0;
      final pinned = (_toInt(item['top']) ?? 0) > 0;
      final usernameRaw = _pickString(item, const <String>[
        'user_name',
        'username',
        'userName',
        'author',
      ]);
      final authorUsername = usernameRaw.isNotEmpty
          ? usernameRaw
          : 'user_${_toInt(item['user_id']) ?? topicId}';

      topics.add(
        RiverSideTopicSummary(
          id: topicId,
          title: title.isEmpty ? '(无标题)' : title,
          excerpt: excerpt,
          categoryId: _toInt(item['board_id']),
          categoryName: boardName.isEmpty ? '清水河畔' : boardName,
          replyCount: _toInt(item['replies']) ?? 0,
          viewCount: _toInt(item['hits']) ?? 0,
          createdAt: createdAt,
          authorDisplayName: displayName.isEmpty ? authorUsername : displayName,
          authorUsername: authorUsername,
          authorUserId:
              _toInt(item['user_id']) ?? _extractUidFromAvatarUrl(avatar),
          authorAvatarUrl: avatar,
          isHot: hot,
          isPinned: pinned,
        ),
      );
    }
    return topics;
  }

  String _qingSortByFromFeed(RiverSideTopicFeed feed) {
    switch (feed) {
      case RiverSideTopicFeed.latestCreated:
        return 'new';
      case RiverSideTopicFeed.latestReplied:
        return 'all';
      case RiverSideTopicFeed.hot:
        // Align with river_lite: "热门" should map to QingShuiHePan "精华".
        return 'essence';
    }
  }

  String _formEncode(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  int? _toInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
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

  String _pickString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = '${source[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  DateTime? _parseEpochDate(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    final isMillis = value > 1000000000000;
    return DateTime.fromMillisecondsSinceEpoch(isMillis ? value : value * 1000);
  }

  void _openDetail(BuildContext sourceContext, RiverSideTopicSummary topic) {
    // Disable Hero linkage for list -> detail transition on Posts page.
    final avatarHeroTag = 'topic_detail_avatar_nohero_${topic.id}';
    final nameHeroTag = 'topic_detail_name_nohero_${topic.id}';
    final titleHeroTag = 'topic_detail_title_nohero_${topic.id}';
    final provider = widget.forumProvider == _PostsForumProvider.qingShuiHePan
        ? AccountProvider.qingShuiHePan
        : AccountProvider.riverSide;
    Navigator.of(context).push(
      DraggableRoute<void>(
        source: sourceContext,
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: topic.id,
          provider: provider,
          qingBoardId: widget.forumProvider == _PostsForumProvider.qingShuiHePan
              ? widget.boardId
              : null,
          preview: TopicDetailPreview(
            title: topic.title,
            authorDisplayName: topic.authorDisplayName,
            authorUsername: topic.authorUsername,
            authorAvatarUrl: topic.authorAvatarUrl,
            titleHeroTag: titleHeroTag,
            authorAvatarHeroTag: avatarHeroTag,
            authorNameHeroTag: nameHeroTag,
          ),
        ),
      ),
    );
  }

  void _openAuthor(RiverSideTopicSummary topic) {
    if (widget.forumProvider == _PostsForumProvider.qingShuiHePan) {
      final avatarHeroTag = _buildAuthorAvatarHeroTag(topic);
      final nameHeroTag = _buildAuthorNameHeroTag(topic);
      showQingShuiHePanUserProfileSheet(
        context: context,
        dependencies: widget.dependencies,
        userId: topic.authorUserId,
        username: topic.authorUsername,
        displayName: topic.authorDisplayName,
        avatarUrl: topic.authorAvatarUrl,
        heroTagAvatar: avatarHeroTag,
        heroTagName: nameHeroTag,
      );
      return;
    }
    final avatarHeroTag = _buildAuthorAvatarHeroTag(topic);
    final nameHeroTag = _buildAuthorNameHeroTag(topic);

    showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: topic.authorUsername,
      displayName: topic.authorDisplayName,
      avatarUrl: topic.authorAvatarUrl,
      heroTagAvatar: avatarHeroTag,
      heroTagName: nameHeroTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showSkeleton = _isLoading && _topics.isEmpty && _error == null;
    final showError = _error != null && _topics.isEmpty;
    final showEmpty = _topics.isEmpty && !showSkeleton && !showError;

    late final Widget stateChild;
    late final String stateKey;
    if (showSkeleton) {
      stateKey = 'loading';
      stateChild = _buildSkeletonList();
    } else if (showError) {
      stateKey = 'error';
      stateChild = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadFirstPage,
              child: const Text('\u91cd\u8bd5'),
            ),
          ],
        ),
      );
    } else if (showEmpty) {
      stateKey = 'empty';
      stateChild = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              '\u6682\u65e0\u5e16\u5b50',
              style: TextStyle(color: Colors.grey),
            ),
            TextButton(
              onPressed: _loadFirstPage,
              child: const Text('\u5237\u65b0'),
            ),
          ],
        ),
      );
    } else {
      stateKey = 'content';
      stateChild = _buildTopicListContent();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<String>(stateKey), child: stateChild),
    );
  }

  Widget _buildTopicListContent() {
    final isIPhone =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        MediaQuery.sizeOf(context).shortestSide < 600;
    final backToTopBottom = isIPhone ? 98.0 : 16.0;
    final hasInlineHint = widget.showInlineRealtimeHint && _topics.isNotEmpty;
    if (hasInlineHint && _realtimeHintAnchorIndex == null) {
      _pinRealtimeHintAnchorToCurrentViewport();
    }
    final anchorIndex = hasInlineHint
        ? (_realtimeHintAnchorIndex ?? 0).clamp(0, _topics.length - 1)
        : -1;
    final inlineHintIndex = hasInlineHint ? anchorIndex + 1 : -1;
    final extraHintCount = hasInlineHint ? 1 : 0;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _handleRefresh,
          notificationPredicate: (notification) => notification.depth == 0,
          child: ListView.separated(
            key: _listViewKey,
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: _topics.length + extraHintCount + (_hasMore ? 1 : 0),
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (hasInlineHint && index == inlineHintIndex) {
                return _InlineRealtimeHintCard(
                  onTap: () => widget.onConsumeRealtimeUpdate?.call(),
                  onClose: widget.onDismissRealtimeUpdate,
                );
              }

              final topicIndex = hasInlineHint && index > inlineHintIndex
                  ? index - 1
                  : index;
              if (topicIndex == _topics.length) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: _isLoadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            '\u6ca1\u6709\u66f4\u591a\u4e86',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                  ),
                );
              }
              final topic = _topics[topicIndex];
              return KeyedSubtree(
                key: _topicItemKeyForIndex(topicIndex),
                child: _TopicCard(
                  topic: topic,
                  displayCategoryName: _displayCategoryName(topic),
                  isHotFeed: widget.feed == RiverSideTopicFeed.hot,
                  onTap: (sourceContext) => _openDetail(sourceContext, topic),
                  onAuthorTap: () => _openAuthor(topic),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: backToTopBottom,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showBackToTopNotifier,
            builder: (context, visible, _) {
              return IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: visible ? 1 : 0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    scale: visible ? 1 : 0.82,
                    child: FloatingActionButton.small(
                      heroTag: 'posts_back_to_top_${widget.feed.name}',
                      onPressed: visible ? _scrollToTop : null,
                      elevation: 2,
                      child: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonList() {
    return AnimatedBuilder(
      animation: _skeletonPulse,
      builder: (context, _) {
        final theme = Theme.of(context);
        final baseColor = Color.lerp(
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.88),
          _skeletonPulse.value,
        )!;
        final highlightColor = Color.lerp(
          theme.colorScheme.surface.withValues(alpha: 0.45),
          theme.colorScheme.surface.withValues(alpha: 0.85),
          _skeletonPulse.value,
        )!;

        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _TopicCardSkeleton(
            baseColor: baseColor,
            highlightColor: highlightColor,
          ),
        );
      },
    );
  }
}

class _InlineRealtimeHintCard extends StatelessWidget {
  const _InlineRealtimeHintCard({this.onTap, this.onClose});

  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.fiber_new_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '有新帖子，点击刷新',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
String _buildAuthorAvatarHeroTag(RiverSideTopicSummary topic) {
  return 'author_avatar_${topic.id}_${topic.authorUsername}';
}

String _buildAuthorNameHeroTag(RiverSideTopicSummary topic) {
  return 'author_name_${topic.id}_${topic.authorUsername}';
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.displayCategoryName,
    required this.isHotFeed,
    required this.onTap,
    required this.onAuthorTap,
  });

  final RiverSideTopicSummary topic;
  final String displayCategoryName;
  final bool isHotFeed;
  final ValueChanged<BuildContext> onTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPinned = topic.isPinned;
    final isHot = topic.isHot || isHotFeed;

    // Hero tags must stay consistent with profile sheet.
    final avatarHeroTag = _buildAuthorAvatarHeroTag(topic);
    final nameHeroTag = _buildAuthorNameHeroTag(topic);
    final titleHeroTag = 'title_${topic.id}';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          // 优化阴影：更柔和、扩散更平滑
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior:
          Clip.antiAlias, // Keep ripple clipped inside rounded corners.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(context),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 椤堕儴淇℃伅鏍?---
                Row(
                  children: [
                    GestureDetector(
                      onTap: onAuthorTap,
                      child: Hero(
                        tag: avatarHeroTag,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundImage: topic.authorAvatarUrl.isNotEmpty
                              ? NetworkImage(topic.authorAvatarUrl)
                              : null,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: topic.authorAvatarUrl.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: nameHeroTag,
                            child: Material(
                              color: Colors.transparent,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: topic.authorDisplayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                          ),
                          Text(
                            _formatTimeRelative(topic.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 鏍囩鍖哄煙
                    if (isPinned)
                      _buildTag(
                        theme,
                        '置顶',
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.primary,
                      ),
                    if (isPinned && isHot) const SizedBox(width: 6),
                    if (isHot)
                      _buildTag(
                        theme,
                        '热门',
                        Colors.orange.shade50,
                        Colors.orange.shade800,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // --- 标题 (Hero 源) ---
                Hero(
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
                                letterSpacing: -0.1,
                              ) ??
                              const TextStyle(),
                          child: (toHeroContext.widget as Hero).child,
                        );
                      },
                  child: Material(
                    color: Colors.transparent,
                    child: Text(
                      topic.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                if (topic.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    topic.excerpt.replaceAll('\n', ' '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 14),

                // --- 搴曢儴鏁版嵁鏍?---
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        displayCategoryName,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _IconText(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: '${topic.replyCount}',
                    ),
                    const SizedBox(width: 16),
                    _IconText(
                      icon: Icons.remove_red_eye_outlined,
                      text: '${topic.viewCount}',
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

  // 辅助方法：构建标签
  Widget _buildTag(ThemeData theme, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatTimeRelative(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '\u521a\u521a';
    if (diff.inMinutes < 60) return '${diff.inMinutes}\u5206\u949f\u524d';
    if (diff.inHours < 24) return '${diff.inHours}\u5c0f\u65f6\u524d';
    if (diff.inDays < 7) return '${diff.inDays}\u5929\u524d';
    return '${time.month}/${time.day}';
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _TopicCardSkeleton extends StatelessWidget {
  const _TopicCardSkeleton({
    required this.baseColor,
    required this.highlightColor,
  });

  final Color baseColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(
                width: 28,
                height: 28,
                radius: 14,
                color: baseColor,
                highlight: highlightColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(
                      width: 96,
                      height: 12,
                      radius: 6,
                      color: baseColor,
                      highlight: highlightColor,
                    ),
                    const SizedBox(height: 8),
                    _SkeletonBox(
                      width: 72,
                      height: 10,
                      radius: 5,
                      color: baseColor,
                      highlight: highlightColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SkeletonBox(
                width: 42,
                height: 18,
                radius: 6,
                color: baseColor,
                highlight: highlightColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SkeletonBox(
            width: double.infinity,
            height: 16,
            radius: 8,
            color: baseColor,
            highlight: highlightColor,
          ),
          const SizedBox(height: 8),
          _SkeletonBox(
            width: 220,
            height: 14,
            radius: 7,
            color: baseColor,
            highlight: highlightColor,
          ),
          const SizedBox(height: 8),
          _SkeletonBox(
            width: 170,
            height: 14,
            radius: 7,
            color: baseColor,
            highlight: highlightColor,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SkeletonBox(
                width: 84,
                height: 22,
                radius: 11,
                color: baseColor,
                highlight: highlightColor,
              ),
              const Spacer(),
              _SkeletonBox(
                width: 44,
                height: 12,
                radius: 6,
                color: baseColor,
                highlight: highlightColor,
              ),
              const SizedBox(width: 14),
              _SkeletonBox(
                width: 44,
                height: 12,
                radius: 6,
                color: baseColor,
                highlight: highlightColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
    required this.highlight,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [color, highlight, color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

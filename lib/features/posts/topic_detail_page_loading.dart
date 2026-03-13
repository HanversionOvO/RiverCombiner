// ignore_for_file: use_build_context_synchronously

part of 'topic_detail_page.dart';

extension _TopicDetailPageLoading on _TopicDetailPageState {
  static const String _presenceMessageBusChannel =
      '/presence/whos-online/online';
  static const String _presenceStateChannelName = '/whos-online/online';

  void _restartRealtimePolling() {
    _messageBusPoller?.stop();
    _messageBusPoller = null;
    if (_isQingShuiHePanTopic) {
      return;
    }

    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      return;
    }

    final bootstrapSerial = ++_pollingBootstrapSerial;
    unawaited(
      _bootstrapRealtimePolling(
        bootstrapSerial: bootstrapSerial,
        cookieHeader: cookieHeader,
      ),
    );
  }

  Future<void> _bootstrapRealtimePolling({
    required int bootstrapSerial,
    required String cookieHeader,
  }) async {
    final topicChannel = '/topic/${widget.topicId}';
    final apiClient = widget.dependencies.accountStore.riverSideApiClient;
    var presenceLastMessageId = -1;

    try {
      final presenceState = await apiClient.fetchPresenceChannelState(
        channelName: _presenceStateChannelName,
        cookieHeader: cookieHeader,
      );
      if (!mounted || bootstrapSerial != _pollingBootstrapSerial) {
        return;
      }
      if (presenceState != null) {
        presenceLastMessageId = presenceState.lastMessageId;
        if (!presenceState.countOnly) {
          _applyPresenceSnapshot(presenceState.users);
        }
      }
    } catch (_) {
      // Keep poller resilient even if presence bootstrap fails.
    }
    if (!mounted || bootstrapSerial != _pollingBootstrapSerial) {
      return;
    }

    final channelLastIds = <String, int>{
      topicChannel: -1,
      _presenceMessageBusChannel: presenceLastMessageId,
    };
    final poller = RiverSideMessageBusPoller(
      apiClient: apiClient,
      cookieHeader: cookieHeader,
      channelLastIds: channelLastIds,
      onEvents: (events) {
        if (!mounted || events.isEmpty) {
          return;
        }
        var hasTopicEvent = false;
        var hasPresenceEvent = false;
        for (final event in events) {
          if (event.channel == topicChannel) {
            hasTopicEvent = true;
            continue;
          }
          if (event.channel == _presenceMessageBusChannel) {
            hasPresenceEvent =
                _consumePresenceEventData(event.data) || hasPresenceEvent;
          }
        }
        if (!hasTopicEvent || _hasRealtimeCommentUpdate) {
          if (hasPresenceEvent) {
            _applyRealtimePresenceToLoadedPosts();
          }
        } else {
          if (!_showTopicCommentsRealtimeRefreshBanner) {
            if (hasPresenceEvent) {
              _applyRealtimePresenceToLoadedPosts();
            }
            return;
          }
          _mutateState(() {
            _hasRealtimeCommentUpdate = true;
          });
          if (hasPresenceEvent) {
            _applyRealtimePresenceToLoadedPosts();
          }
        }
      },
    );
    if (bootstrapSerial != _pollingBootstrapSerial) {
      poller.stop();
      return;
    }
    _messageBusPoller = poller;
    poller.start();
  }

  void _applyPresenceSnapshot(Iterable<RiverSidePresenceUser> users) {
    final nextOnlineIds = <int>{};
    final nextOnlineUsernames = <String>{};
    for (final user in users) {
      if (user.id > 0) {
        nextOnlineIds.add(user.id);
      }
      final normalizedUsername = _normalizePresenceUsername(user.username);
      if (normalizedUsername.isNotEmpty) {
        nextOnlineUsernames.add(normalizedUsername);
      }
      if (user.id > 0 && normalizedUsername.isNotEmpty) {
        _knownOnlineUsernameById[user.id] = normalizedUsername;
      }
    }

    _onlineUserIds
      ..clear()
      ..addAll(nextOnlineIds);
    _onlineUsernames
      ..clear()
      ..addAll(nextOnlineUsernames);
    _presenceReady = true;
    _applyRealtimePresenceToLoadedPosts();
  }

  bool _consumePresenceEventData(dynamic rawData) {
    final payload = _decodePresencePayload(rawData);
    if (payload is List) {
      final users = _parsePresenceUsers(payload);
      _applyPresenceSnapshot(users);
      return true;
    }

    if (payload is! Map) {
      return false;
    }
    final data = _toStringDynamicMap(payload);
    if (data.isEmpty) {
      return false;
    }

    final enteringUsersRaw = _readListField(data, const <String>[
      'entering_users',
      'users',
      'online_users',
    ]);
    final leavingUserIdsRaw = _readListField(data, const <String>[
      'leaving_user_ids',
    ]);

    var changed = false;
    if (enteringUsersRaw != null && data.containsKey('users')) {
      _applyPresenceSnapshot(_parsePresenceUsers(enteringUsersRaw));
      return true;
    }

    if (enteringUsersRaw != null) {
      final enteringUsers = _parsePresenceUsers(enteringUsersRaw);
      for (final user in enteringUsers) {
        if (user.id > 0) {
          changed = _onlineUserIds.add(user.id) || changed;
        }
        final normalized = _normalizePresenceUsername(user.username);
        if (normalized.isNotEmpty) {
          changed = _onlineUsernames.add(normalized) || changed;
        }
        if (user.id > 0 && normalized.isNotEmpty) {
          _knownOnlineUsernameById[user.id] = normalized;
        }
      }
      if (enteringUsers.isNotEmpty) {
        _presenceReady = true;
      }
    }

    if (leavingUserIdsRaw != null) {
      for (final userId in _parsePresenceUserIds(leavingUserIdsRaw)) {
        if (!_onlineUserIds.remove(userId)) {
          continue;
        }
        changed = true;
        final username = _knownOnlineUsernameById[userId];
        if (username != null) {
          _onlineUsernames.remove(username);
        }
      }
      _presenceReady = true;
    }

    return changed;
  }

  dynamic _decodePresencePayload(dynamic rawData) {
    if (rawData is String) {
      final source = rawData.trim();
      if (source.isEmpty) {
        return null;
      }
      if ((source.startsWith('{') && source.endsWith('}')) ||
          (source.startsWith('[') && source.endsWith(']'))) {
        try {
          return jsonDecode(source);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    return rawData;
  }

  Map<String, dynamic> _toStringDynamicMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      result['${entry.key}'] = entry.value;
    }
    return result;
  }

  List<dynamic>? _readListField(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value;
      }
    }
    return null;
  }

  List<RiverSidePresenceUser> _parsePresenceUsers(List<dynamic> rawUsers) {
    final users = <RiverSidePresenceUser>[];
    for (final rawUser in rawUsers) {
      final map = _toStringDynamicMap(rawUser);
      if (map.isNotEmpty) {
        final id = _parseInt(map['id']) ?? 0;
        final username = (map['username'] ?? '').toString().trim();
        if (id > 0 || username.isNotEmpty) {
          users.add(RiverSidePresenceUser(id: id, username: username));
        }
        continue;
      }

      final id = _parseInt(rawUser);
      if (id != null && id > 0) {
        users.add(RiverSidePresenceUser(id: id, username: ''));
        continue;
      }

      final username = '$rawUser'.trim();
      if (username.isNotEmpty) {
        users.add(RiverSidePresenceUser(id: 0, username: username));
      }
    }
    return users;
  }

  List<int> _parsePresenceUserIds(List<dynamic> rawIds) {
    final ids = <int>[];
    for (final raw in rawIds) {
      final id = _parseInt(raw);
      if (id != null && id > 0) {
        ids.add(id);
      }
    }
    return ids;
  }

  int? _parseInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  String _normalizePresenceUsername(String source) {
    return source.trim().toLowerCase();
  }

  RiverSideTopicPostDetail _applyRealtimePresenceToPost(
    RiverSideTopicPostDetail post,
  ) {
    if (!_presenceReady) {
      return post;
    }
    final normalizedUsername = _normalizePresenceUsername(post.authorUsername);
    final authorUserId = post.authorUserId;
    final isOnline = authorUserId != null && authorUserId > 0
        ? _onlineUserIds.contains(authorUserId)
        : _onlineUsernames.contains(normalizedUsername);
    if (post.isOnline == isOnline) {
      return post;
    }
    return post.copyWith(isOnline: isOnline);
  }

  void _applyRealtimePresenceToLoadedPosts() {
    if (!_presenceReady || !mounted) {
      return;
    }
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final nextMain = _applyRealtimePresenceToPost(detail.mainPost);
    var changed = !identical(nextMain, detail.mainPost);
    final nextComments = <RiverSideTopicPostDetail>[];
    for (final comment in _comments) {
      final next = _applyRealtimePresenceToPost(comment);
      if (!identical(next, comment)) {
        changed = true;
      }
      nextComments.add(next);
    }
    if (!changed) {
      return;
    }

    _mutateState(() {
      _detail = detail.copyWith(mainPost: nextMain, comments: nextComments);
      _comments = nextComments;
    });
  }

  Future<void> _consumeRealtimeCommentUpdate() async {
    if (_hasRealtimeCommentUpdate) {
      _mutateState(() {
        _hasRealtimeCommentUpdate = false;
      });
    }
    await _loadInitial();
    if (!mounted) {
      return;
    }
    await _jumpToLatestComment();
  }

  Future<void> _jumpToLatestComment() async {
    if (!mounted) {
      return;
    }

    var guard = 0;
    while (mounted && _hasMoreComments && guard < 24) {
      guard++;
      await _loadMoreComments();
      await _waitNextFrame();
    }

    if (!mounted || _comments.isEmpty) {
      return;
    }

    var latestPostNumber = 0;
    for (final post in _comments) {
      if (post.postNumber > latestPostNumber) {
        latestPostNumber = post.postNumber;
      }
    }
    if (latestPostNumber <= 1) {
      return;
    }

    await _jumpToPostNumber(
      postNumber: latestPostNumber,
      topicId: widget.topicId,
    );
  }

  Future<void> _loadInitial() async {
    final shouldSkipEntranceAnimation =
        widget.preview != null && _detail == null;
    _mutateState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _error = null;
      _hasRealtimeCommentUpdate = false;
      _topicFavoriteResolved = false;
      if (shouldSkipEntranceAnimation) {
        _skipNextEntranceAnimation = true;
        _contentRevealController.value = 0;
      }
    });
    _showBackToTopButtonNotifier.value = false;

    try {
      if (_isQingShuiHePanTopic) {
        await _loadInitialForQing();
        if (shouldSkipEntranceAnimation) {
          unawaited(_contentRevealController.forward(from: 0));
        } else {
          _contentRevealController.value = 1;
        }
        unawaited(_runInitialOpenNavigation());
        return;
      }

      final cookieHeader = _activeCookieHeader();
      final apiClient = widget.dependencies.accountStore.riverSideApiClient;
      final detailFuture = apiClient.fetchTopicDetail(
        topicId: widget.topicId,
        cookieHeader: cookieHeader,
      );
      final emojiFuture = apiClient
          .fetchEmojiUrlMap(cookieHeader: cookieHeader)
          .catchError((_) => const <String, String>{});
      final emojiGroupsFuture = apiClient
          .fetchEmojiGroups(cookieHeader: cookieHeader)
          .catchError((_) => const <String, List<String>>{});
      final detail = await detailFuture;
      final emojiUrls = await emojiFuture;
      final emojiGroups = await emojiGroupsFuture;
      if (!mounted) {
        return;
      }

      final comments = <RiverSideTopicPostDetail>[];
      final commentIds = <int>{};
      for (final item in detail.comments) {
        if (item.postNumber <= 1 || !commentIds.add(item.id)) {
          continue;
        }
        comments.add(_applyRealtimePresenceToPost(item));
      }
      comments.sort((a, b) => a.postNumber.compareTo(b.postNumber));
      final mainPost = _applyRealtimePresenceToPost(detail.mainPost);
      final mergedDetail = detail.copyWith(
        mainPost: mainPost,
        comments: comments,
      );

      _mutateState(() {
        _detail = mergedDetail;
        _comments = comments;
        _topicFavoriteResolved = true;
        _topicFavorited = mergedDetail.isBookmarked;
        _loadedPostIds
          ..clear()
          ..addAll(detail.loadedPostIds);
        _emojiUrls = emojiUrls;
        _emojiGroups = emojiGroups;
        _loadingInitial = false;
      });
      if (shouldSkipEntranceAnimation) {
        unawaited(_contentRevealController.forward(from: 0));
      } else {
        _contentRevealController.value = 1;
      }
      unawaited(_runInitialOpenNavigation());
      _maybeAutoLoadMore();
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _loadingInitial = false;
        _error = error.message;
      });
      _contentRevealController.value = 1;
    } catch (error, stackTrace) {
      debugPrint('topic detail load failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _loadingInitial = false;
        _error =
            '帖子详情加载失败，请稍后重试';
      });
      _contentRevealController.value = 1;
    }
  }

  Future<void> _loadInitialForQing() async {
    final auth = _activeQingAuth();
    if (auth == null) {
      throw RiverSideApiException(_loginRequiredLabel);
    }
    _qingReplyIdByPostNumber.clear();
    _qingPostNumberByReplyId.clear();
    _qingLikedPostIds.clear();
    _qingDislikedPostIds.clear();
    _qingDislikeCountByPostId.clear();

    final boardId = widget.qingBoardId ?? _qingBoardId;
    final data = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'forum/postlist',
        'topicId': '${widget.topicId}',
        'page': '1',
        'pageSize': '30',
        'order': '0',
        if (boardId != null && boardId > 0) 'boardId': '$boardId',
      },
    );
    if (!mounted) {
      return;
    }

    _emojiUrls = Map<String, String>.from(QingEmojiCatalog.buildEmojiUrlMap());
    _emojiGroups = QingEmojiCatalog.buildEmojiGroups().map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );

    final parsed = _parseQingPostListPage(
      data: data,
      currentComments: const [],
      currentDetail: null,
    );
    _mutateState(() {
      _detail = parsed.detail;
      _comments = parsed.comments;
      _topicFavoriteResolved = true;
      _topicFavorited = parsed.isFavorited;
      _loadedPostIds
        ..clear()
        ..add(parsed.detail.mainPost.id)
        ..addAll(parsed.comments.map((item) => item.id));
      _emojiUrls = Map<String, String>.unmodifiable(_emojiUrls);
      _emojiGroups = _emojiGroups.map(
        (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
      );
      _qingCurrentPage = 1;
      _qingHasMoreComments = parsed.hasMore;
      _qingBoardId = boardId;
      _loadingInitial = false;
    });
    _maybeAutoLoadMore();
  }

  _QingTopicLoadResult _parseQingPostListPage({
    required Map<String, dynamic> data,
    required List<RiverSideTopicPostDetail> currentComments,
    required RiverSideTopicDetail? currentDetail,
  }) {
    final topicMap = _asStringDynamicMap(data['topic']);
    final list = _asStringDynamicMapList(data['list']);
    final topicSource = topicMap.isNotEmpty
        ? topicMap
        : _asStringDynamicMap(data['body']);
    final topicId =
        _pickInt(topicSource, const <String>['topic_id', 'id']) ??
        currentDetail?.topicId ??
        widget.topicId;
    final title = _pickString(topicSource, const <String>['title', 'subject']);
    final boardId = _pickInt(topicSource, const <String>['board_id']);

    final mainPostId = topicId;
    _qingReplyIdByPostNumber[1] = mainPostId;
    _qingPostNumberByReplyId[mainPostId] = 1;
    final mainLike = topicSource.isEmpty
        ? (currentDetail?.mainPost.likeCount ?? 0)
        : _extractQingLikeCount(topicSource);
    final mainDislike = topicSource.isEmpty
        ? (_qingDislikeCountByPostId[mainPostId] ?? 0)
        : _extractQingDislikeCount(topicSource);
    final mainLiked = topicSource.isEmpty
        ? _qingLikedPostIds.contains(mainPostId)
        : _extractQingLiked(topicSource);
    final mainDisliked = topicSource.isEmpty
        ? _qingDislikedPostIds.contains(mainPostId)
        : _extractQingDisliked(topicSource);

    if (mainLiked) {
      _qingLikedPostIds.add(mainPostId);
      _qingDislikedPostIds.remove(mainPostId);
    } else if (mainDisliked) {
      _qingDislikedPostIds.add(mainPostId);
      _qingLikedPostIds.remove(mainPostId);
    }
    _qingDislikeCountByPostId[mainPostId] = mainDislike;

    final mainCurrentReaction = _qingLikedPostIds.contains(mainPostId)
        ? const RiverSideCurrentUserReaction(
            id: '+1',
            type: 'likes',
            canUndo: true,
          )
        : _qingDislikedPostIds.contains(mainPostId)
        ? const RiverSideCurrentUserReaction(
            id: '-1',
            type: 'dislikes',
            canUndo: true,
          )
        : null;
    final isBookmarked = topicSource.isEmpty
        ? (currentDetail?.isBookmarked ?? false)
        : _extractQingFavorited(topicSource);

    final mainPost = RiverSideTopicPostDetail(
      id: mainPostId,
      topicId: topicId,
      postNumber: 1,
      authorUserId:
          _pickInt(topicSource, const <String>['user_id', 'uid']) ??
          _extractUidFromAvatarUrl(
            _pickString(topicSource, const <String>[
              'icon',
              'avatar',
              'userAvatar',
            ]),
          ) ??
          currentDetail?.mainPost.authorUserId,
      authorUsername:
          _pickString(topicSource, const <String>[
            'user_name',
            'username',
            'userName',
            'author',
          ]).trim().isEmpty
          ? (currentDetail?.mainPost.authorUsername.isNotEmpty == true
                ? currentDetail!.mainPost.authorUsername
                : 'user_${_pickInt(topicSource, const <String>['user_id']) ?? topicId}')
          : _pickString(topicSource, const <String>[
              'user_name',
              'username',
              'userName',
              'author',
            ]),
      authorDisplayName:
          _pickString(topicSource, const <String>[
            'user_nick_name',
            'author',
            'user_name',
          ]).trim().isEmpty
          ? (currentDetail?.mainPost.authorDisplayName ?? '')
          : _pickString(topicSource, const <String>[
              'user_nick_name',
              'author',
              'user_name',
            ]),
      authorAvatarUrl: _resolveQingUrl(
        _pickString(topicSource, const <String>[
          'icon',
          'avatar',
          'userAvatar',
        ]),
      ),
      authorTitle: _pickString(topicSource, const <String>[
        'userTitle',
        'title',
      ]),
      isOnline: null,
      contentMarkdown: () {
        final markdown = _qingContentToMarkdown(
          topicSource['content'] ??
              topicSource['contentList'] ??
              topicSource['subject'],
        );
        if (markdown.isNotEmpty) {
          return markdown;
        }
        return currentDetail?.mainPost.contentMarkdown ?? '';
      }(),
      createdAt: _epochToDate(
        _pickInt(topicSource, const <String>[
              'create_date',
              'posts_date',
              'last_reply_date',
              'dateline',
            ]) ??
            currentDetail?.mainPost.createdAt?.millisecondsSinceEpoch,
      ),
      editCount: 0,
      likeCount: mainLike,
      reactions: _buildQingReactionList(
        likeCount: mainLike,
        dislikeCount: mainDislike,
      ),
      currentUserReaction: mainCurrentReaction,
      reactionUsersCount: mainLike + mainDislike,
    );

    final existingById = <int, RiverSideTopicPostDetail>{
      for (final item in currentComments) item.id: item,
    };
    final nextComments = <RiverSideTopicPostDetail>[...currentComments];
    final usedPostNumbers = <int>{
      1,
      ...currentComments.map((e) => e.postNumber),
    };
    var maxPostNumber = usedPostNumbers.isEmpty
        ? 1
        : usedPostNumbers.reduce(math.max);

    for (final raw in list) {
      final replyId =
          _pickInt(raw, const <String>[
            'reply_posts_id',
            'reply_id',
            'post_id',
            'id',
          ]) ??
          0;
      if (replyId <= 0) {
        continue;
      }
      final existing = existingById[replyId];
      final postNumber =
          existing?.postNumber ??
          _pickInt(raw, const <String>[
            'position',
            'floor',
            'post_no',
            'number',
            'lou',
            'lou_num',
          ]) ??
          (() {
            maxPostNumber += 1;
            return maxPostNumber;
          }());
      usedPostNumbers.add(postNumber);
      _qingReplyIdByPostNumber[postNumber] = replyId;
      _qingPostNumberByReplyId[replyId] = postNumber;

      final like = _extractQingLikeCount(raw);
      final dislike = _extractQingDislikeCount(raw);
      final liked = _extractQingLiked(raw);
      final disliked = _extractQingDisliked(raw);
      if (liked) {
        _qingLikedPostIds.add(replyId);
        _qingDislikedPostIds.remove(replyId);
      } else if (disliked) {
        _qingDislikedPostIds.add(replyId);
        _qingLikedPostIds.remove(replyId);
      }
      _qingDislikeCountByPostId[replyId] = dislike;

      final currentReaction = _qingLikedPostIds.contains(replyId)
          ? const RiverSideCurrentUserReaction(
              id: '+1',
              type: 'likes',
              canUndo: true,
            )
          : _qingDislikedPostIds.contains(replyId)
          ? const RiverSideCurrentUserReaction(
              id: '-1',
              type: 'dislikes',
              canUndo: true,
            )
          : null;

      final quoteMeta = _extractQingQuoteMeta(raw);
      final quoteReplyId = _asInt(quoteMeta['quoteReplyId']);
      final replyToPostNumber = quoteReplyId == null
          ? null
          : (_qingPostNumberByReplyId[quoteReplyId] ??
                (quoteReplyId > 0 && quoteReplyId < 10000
                    ? quoteReplyId
                    : null));
      final quoteText = _qingContentToMarkdown(
        raw['quote_content'] ?? raw['quote'],
      );
      final content = _qingContentToMarkdown(
        quoteMeta['contentOverride'] ??
            raw['reply_content'] ??
            raw['content'] ??
            raw['subject'],
      );
      final mergedContent = replyToPostNumber != null
          ? (quoteText.isEmpty ? content : '$quoteText\n\n$content')
          : content;

      final parsed = RiverSideTopicPostDetail(
        id: replyId,
        topicId: topicId,
        postNumber: postNumber,
        authorUserId:
            _pickInt(raw, const <String>['user_id', 'uid']) ??
            _extractUidFromAvatarUrl(
              _pickString(raw, const <String>['icon', 'avatar', 'userAvatar']),
            ),
        authorUsername:
            _pickString(raw, const <String>[
              'user_name',
              'username',
              'userName',
              'author',
            ]).trim().isEmpty
            ? 'user_${_pickInt(raw, const <String>['user_id']) ?? _extractUidFromAvatarUrl(_pickString(raw, const <String>['icon', 'avatar', 'userAvatar'])) ?? replyId}'
            : _pickString(raw, const <String>[
                'user_name',
                'username',
                'userName',
                'author',
              ]),
        authorDisplayName:
            _pickString(raw, const <String>[
              'reply_name',
              'user_nick_name',
              'author',
              'user_name',
            ]).trim().isEmpty
            ? _pickString(raw, const <String>[
                'user_name',
                'username',
                'author',
              ])
            : _pickString(raw, const <String>[
                'reply_name',
                'user_nick_name',
                'author',
                'user_name',
              ]),
        authorAvatarUrl: _resolveQingUrl(
          _pickString(raw, const <String>['icon', 'avatar', 'userAvatar']),
        ),
        authorTitle: _pickString(raw, const <String>['title', 'userTitle']),
        isOnline: null,
        contentMarkdown: mergedContent,
        createdAt: _epochToDate(
          _pickInt(raw, const <String>[
            'posts_date',
            'reply_time',
            'create_date',
            'dateline',
          ]),
        ),
        editCount: 0,
        likeCount: like,
        reactions: _buildQingReactionList(
          likeCount: like,
          dislikeCount: dislike,
        ),
        currentUserReaction: currentReaction,
        reactionUsersCount: like + dislike,
        replyToPostNumber: replyToPostNumber,
        replyToUsername: _pickString(raw, const <String>[
          'quote_user_name',
          'quote_name',
          'reply_to_username',
        ]),
      );

      if (existing != null) {
        final index = nextComments.indexWhere((item) => item.id == replyId);
        if (index >= 0) {
          nextComments[index] = parsed;
        }
      } else {
        nextComments.add(parsed);
      }
    }

    nextComments.sort((a, b) => a.postNumber.compareTo(b.postNumber));
    final hasNext =
        _asBool(data['has_next']) ||
        ((_pickInt(data, const <String>['total_num']) ?? 0) >
            nextComments.length);
    final streamPostIds = <int>[mainPost.id, ...nextComments.map((e) => e.id)];
    final detail = RiverSideTopicDetail(
      topicId: topicId,
      title: title.isEmpty
          ? ((currentDetail?.title ?? '').trim().isEmpty
                ? '(无标题)'
                : currentDetail!.title)
          : title,
      viewCount:
          _pickInt(topicSource, const <String>['hits', 'views']) ??
          currentDetail?.viewCount ??
          0,
      replyCount:
          _pickInt(topicSource, const <String>['replies', 'reply_num']) ??
          currentDetail?.replyCount ??
          (_pickInt(data, const <String>['total_num']) ?? nextComments.length),
      likeCount: mainLike,
      createdAt: _epochToDate(
        _pickInt(topicSource, const <String>[
              'create_date',
              'last_reply_date',
            ]) ??
            currentDetail?.createdAt?.millisecondsSinceEpoch,
      ),
      mainPost: mainPost,
      comments: nextComments,
      streamPostIds: streamPostIds,
      loadedPostIds: streamPostIds.toSet(),
      validReactions: const <String>{'+1', '-1'},
      isBookmarked: isBookmarked,
    );

    _qingBoardId = boardId ?? _qingBoardId;
    return _QingTopicLoadResult(
      detail: detail,
      comments: nextComments,
      hasMore: hasNext,
      isFavorited: isBookmarked,
    );
  }

  Future<void> _loadMoreComments() async {
    if (_loadingInitial || _loadingMore || !_hasMoreComments) {
      return;
    }
    final detail = _detail;
    if (detail == null) {
      return;
    }

    if (_isQingShuiHePanTopic) {
      final auth = _activeQingAuth();
      if (auth == null) {
        return;
      }
      _mutateState(() {
        _loadingMore = true;
      });
      try {
        final nextPage = _qingCurrentPage + 1;
        final data = await _callQingApi(
          auth: auth,
          body: <String, String>{
            'r': 'forum/postlist',
            'topicId': '${widget.topicId}',
            'page': '$nextPage',
            'pageSize': '30',
            'order': '0',
            if (_qingBoardId != null && _qingBoardId! > 0)
              'boardId': '$_qingBoardId',
          },
        );
        if (!mounted) {
          return;
        }
        final parsed = _parseQingPostListPage(
          data: data,
          currentComments: _comments,
          currentDetail: detail,
        );
        _mutateState(() {
          _detail = parsed.detail;
          _comments = parsed.comments;
          _topicFavoriteResolved = true;
          _topicFavorited = parsed.isFavorited;
          _loadedPostIds
            ..clear()
            ..add(parsed.detail.mainPost.id)
            ..addAll(parsed.comments.map((item) => item.id));
          _qingCurrentPage = nextPage;
          _qingHasMoreComments = parsed.hasMore;
          _loadingMore = false;
        });
      } on RiverSideApiException catch (error) {
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
      } catch (_) {
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showRiverSnackBar('评论加载失败');
      }
      return;
    }

    final nextIds = _nextPostIdsToLoad();
    if (nextIds.isEmpty) {
      return;
    }

    _mutateState(() {
      _loadingMore = true;
    });

    try {
      final posts = await widget.dependencies.accountStore.riverSideApiClient
          .fetchTopicPostsByIds(
            topicId: detail.topicId,
            postIds: nextIds,
            cookieHeader: _activeCookieHeader(),
          );
      if (!mounted) {
        return;
      }

      final merged = <RiverSideTopicPostDetail>[..._comments];
      final existingIds = merged.map((post) => post.id).toSet();
      for (final post in posts) {
        _loadedPostIds.add(post.id);
        if (post.postNumber <= 1 || existingIds.contains(post.id)) {
          continue;
        }
        existingIds.add(post.id);
        merged.add(_applyRealtimePresenceToPost(post));
      }
      merged.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      _mutateState(() {
        _comments = merged;
        _loadingMore = false;
      });
      _maybeAutoLoadMore();
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _loadingMore = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('评论加载失败');
    }
  }

  void _maybeAutoLoadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _loadingInitial ||
          _loadingMore ||
          !_hasMoreComments ||
          !_scrollController.hasClients) {
        return;
      }

      final position = _scrollController.position;
      if (position.maxScrollExtent <= position.viewportDimension * 0.15) {
        _loadMoreComments();
      }
    });
  }

  Future<void> _jumpToPostNumber({
    required int postNumber,
    required int topicId,
  }) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    if (topicId != detail.topicId) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelCrossTopicQuote);
      return;
    }
    if (postNumber <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelInvalidQuoteFloor);
      return;
    }

    var rounds = 0;
    while (mounted && rounds < 18) {
      rounds++;
      if (!_hasLoadedPostNumber(postNumber)) {
        if (!_hasMoreComments) {
          break;
        }
        await _loadMoreComments();
        continue;
      }

      final targetContext = await _findPostContext(postNumber);
      if (!mounted) {
        return;
      }
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.1,
        );
        if (!mounted) {
          return;
        }
        _triggerJumpHighlight(postNumber);
        return;
      }

      await _waitNextFrame();
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showRiverSnackBar(_TopicDetailPageState._labelTargetFloorMissing);
  }

  Future<BuildContext?> _findPostContext(int postNumber) async {
    for (var i = 0; i < 12; i++) {
      if (!mounted) {
        return null;
      }
      final key = _postItemKeys[postNumber];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        return targetContext;
      }
      await _scrollTowardPost(postNumber);
      await _waitNextFrame();
    }
    return null;
  }

  Future<void> _scrollTowardPost(int postNumber) async {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }

    final targetOffset = _estimateOffsetForPost(postNumber, maxExtent);
    final current = _scrollController.offset;
    if ((targetOffset - current).abs() < 12) {
      return;
    }

    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
  }

  double _estimateOffsetForPost(int postNumber, double maxExtent) {
    final sortedNumbers = <int>[1, ..._comments.map((post) => post.postNumber)]
      ..sort();
    if (sortedNumbers.isEmpty) {
      return maxExtent;
    }
    final targetIndex = sortedNumbers.indexOf(postNumber);
    if (targetIndex <= 0) {
      return 0;
    }
    final denominator = sortedNumbers.length - 1;
    if (denominator <= 0) {
      return 0;
    }
    final ratio = targetIndex / denominator;
    return (maxExtent * ratio).clamp(0, maxExtent);
  }

  Future<void> _waitNextFrame() async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> _runInitialOpenNavigation() async {
    await _maybeJumpToInitialPostNumberOnOpen();
    await _maybeScrollToRepliesSectionOnOpen();
  }

  Future<void> _maybeJumpToInitialPostNumberOnOpen() async {
    final targetPostNumber = widget.initialPostNumberOnOpen;
    if (targetPostNumber == null ||
        targetPostNumber <= 1 ||
        _didInitialPostNumberJump ||
        !mounted) {
      return;
    }
    _didInitialPostNumberJump = true;
    await _waitNextFrame();
    if (!mounted) {
      return;
    }
    final detail = _detail;
    if (detail == null) {
      return;
    }
    await _jumpToPostNumber(
      postNumber: targetPostNumber,
      topicId: detail.topicId,
    );
  }

  Future<void> _maybeScrollToRepliesSectionOnOpen() async {
    if (!widget.scrollToRepliesOnOpen ||
        _didInitialRepliesScroll ||
        _didInitialPostNumberJump ||
        !mounted) {
      return;
    }
    _didInitialRepliesScroll = true;
    await _waitNextFrame();
    if (!mounted) {
      return;
    }
    final anchorContext = _repliesSectionAnchorKey.currentContext;
    if (anchorContext != null) {
      await Scrollable.ensureVisible(
        anchorContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.03,
      );
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }
    final targetOffset = (maxExtent * 0.35).clamp(0.0, maxExtent);
    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _QingTopicLoadResult {
  const _QingTopicLoadResult({
    required this.detail,
    required this.comments,
    required this.hasMore,
    required this.isFavorited,
  });

  final RiverSideTopicDetail detail;
  final List<RiverSideTopicPostDetail> comments;
  final bool hasMore;
  final bool isFavorited;
}

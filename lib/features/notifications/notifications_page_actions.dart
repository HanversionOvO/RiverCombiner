part of 'notifications_page.dart';

extension _NotificationsPageActions on _NotificationsPageState {
  bool get _showNotificationsRealtimeRefreshBanner {
    return widget
        .dependencies
        .settingsController
        .showNotificationsRealtimeRefreshBanner;
  }

  bool get _isQingForum => _forumProvider == AccountProvider.qingShuiHePan;

  List<RiverSideNotificationItem> get _displayNotifications {
    if (!_isQingForum ||
        _qingNotificationFilter == _QingNotificationFilter.all) {
      return _notifications;
    }
    final target = switch (_qingNotificationFilter) {
      _QingNotificationFilter.atMe => _QingNotificationKind.atMe,
      _QingNotificationFilter.reply => _QingNotificationKind.reply,
      _QingNotificationFilter.notice => _QingNotificationKind.notice,
      _QingNotificationFilter.all => null,
    };
    if (target == null) {
      return _notifications;
    }
    return _qingNotificationRecords
        .where((record) => record.kind == target)
        .map((record) => record.item)
        .toList(growable: false);
  }

  int _qingCountForKind(_QingNotificationKind kind) {
    return _qingNotificationRecords
        .where((record) => record.kind == kind)
        .length;
  }

  void _setQingNotificationFilter(_QingNotificationFilter filter) {
    if (!_isQingForum || _qingNotificationFilter == filter) {
      return;
    }
    _setState(() {
      _qingNotificationFilter = filter;
    });
  }

  void _onRefreshBannerSettingsChanged() {
    if (!mounted) {
      return;
    }
    if (!_showNotificationsRealtimeRefreshBanner && _hasRealtimeNotifications) {
      _setState(() {
        _hasRealtimeNotifications = false;
      });
      return;
    }
    _setState(() {});
  }

  int get _totalUnreadCount {
    final unreadNotifications = _notifications
        .where((item) => !item.read)
        .length;
    if (_isQingForum) {
      return unreadNotifications;
    }
    final unreadChannels = _channelMessages.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    final unreadDirectMessages = _directMessages.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    return unreadNotifications + unreadChannels + unreadDirectMessages;
  }

  void _notifyUnreadCountChanged() {
    widget.onUnreadCountChanged?.call(_totalUnreadCount);
  }

  void _onAccountStoreChanged() {
    final currentRiver =
        widget.dependencies.accountStore.activeRiverSideUsername;
    final currentQing =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (currentRiver == _lastActiveRiverUsername &&
        currentQing == _lastActiveQingUsername) {
      return;
    }
    _lastActiveRiverUsername = currentRiver;
    _lastActiveQingUsername = currentQing;
    _messageBusPoller?.stop();
    _messageBusPoller = null;

    if (mounted) {
      _setState(() {
        _loading = true;
        _error = null;
        _hasRealtimeNotifications = false;
        _nextNotificationsPath = '';
        _notifications = const [];
        _qingNotificationRecords = const [];
        _qingKindByNotificationId.clear();
        _qingBoardIdByNotificationId.clear();
        _qingNextPageByKind.clear();
        _qingKindsHasMore.clear();
        _qingUnreadCounts = const _QingUnreadCounts();
        _qingReadCutoffUsername = null;
        _qingReadCutoffMillis = null;
        _channelMessages = const [];
        _directMessages = const [];
        _deletingDirectMessageIds.clear();
      });
    }
    _loadAll(clearExisting: true);
  }

  void _onNotificationsScroll() {
    if (_tabController.index != 0) {
      return;
    }
    _syncBackToTopVisibility();
    if (_loading || _loadingMoreNotifications) {
      return;
    }
    if (_isQingForum) {
      if (_qingKindsHasMore.isEmpty) {
        return;
      }
    } else if (_nextNotificationsPath.isEmpty) {
      return;
    }
    if (!_notificationsScrollController.hasClients) {
      return;
    }
    final position = _notificationsScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreNotifications();
    }
  }

  void _onChannelScroll() {
    if (_tabController.index == 1) {
      _syncBackToTopVisibility();
    }
  }

  void _onDirectScroll() {
    if (_tabController.index == 2) {
      _syncBackToTopVisibility();
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    if (mounted) {
      _setState(() {});
    }
    _syncBackToTopVisibility();
  }

  ScrollController? _activeScrollController() {
    switch (_tabController.index) {
      case 0:
        return _notificationsScrollController;
      case 1:
        return _channelScrollController;
      case 2:
        return _directScrollController;
    }
    return null;
  }

  void _syncBackToTopVisibility() {
    final controller = _activeScrollController();
    final currentOffset = controller != null && controller.hasClients
        ? controller.position.pixels
        : 0.0;
    final shouldShow = currentOffset >= 360;
    final nextHeaderFactor = (currentOffset / 96).clamp(0.0, 1.0);
    if ((_headerScrollFactor - nextHeaderFactor).abs() >= 0.01 && mounted) {
      _setState(() {
        _headerScrollFactor = nextHeaderFactor;
      });
    }
    if (_showBackToTopNotifier.value != shouldShow) {
      _showBackToTopNotifier.value = shouldShow;
    }
  }

  Future<void> _scrollActiveTabToTop() async {
    final controller = _activeScrollController();
    if (controller == null || !controller.hasClients) {
      return;
    }
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _syncBackToTopVisibility();
  }

  Future<void> _refreshCurrentTab() async {
    await _loadAll(showLoading: false);
  }

  String? _activeCookieHeader() {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(username);
  }

  QingShuiHePanAuth? _activeQingAuth() {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername?.trim() ??
        '';
    if (username.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.qingShuiHePanAuthFor(username);
  }

  Future<void> _loadAll({
    bool showLoading = true,
    bool clearExisting = false,
  }) async {
    if (_isQingForum) {
      await _loadAllQing(
        showLoading: showLoading,
        clearExisting: clearExisting,
      );
    } else {
      await _loadAllRiver(
        showLoading: showLoading,
        clearExisting: clearExisting,
      );
    }
  }

  Future<void> _loadAllRiver({
    required bool showLoading,
    required bool clearExisting,
  }) async {
    final serial = ++_requestSerial;
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _setState(() {
        _loading = false;
        _error = _NotificationsPageState._labelNeedLogin;
        if (clearExisting) {
          _notifications = const [];
          _channelMessages = const [];
          _directMessages = const [];
          _deletingDirectMessageIds.clear();
        }
      });
      _notifyUnreadCountChanged();
      return;
    }

    if (showLoading) {
      _setState(() {
        _loading = true;
        _error = null;
        if (clearExisting) {
          _notifications = const [];
          _channelMessages = const [];
          _directMessages = const [];
        }
      });
    }

    try {
      final api = widget.dependencies.accountStore.riverSideApiClient;
      final results = await Future.wait([
        api.fetchNotificationsPage(cookieHeader: cookieHeader),
        api.fetchMyChatChannels(cookieHeader: cookieHeader),
      ]);
      if (!mounted || serial != _requestSerial) {
        return;
      }
      final notificationPage = results[0] as RiverSideNotificationPage;
      final channels = results[1] as List<RiverSideChatChannelItem>;
      _setState(() {
        _loading = false;
        _error = null;
        _hasRealtimeNotifications = false;
        _notifications = notificationPage.items;
        _nextNotificationsPath = notificationPage.loadMorePath;
        _channelMessages = channels
            .where((item) => !item.isDirectMessage)
            .toList(growable: false);
        _directMessages = channels
            .where((item) => item.isDirectMessage)
            .toList(growable: false);
        _deletingDirectMessageIds.removeWhere(
          (id) => !_directMessages.any((item) => item.id == id),
        );
      });
      _notifyUnreadCountChanged();
      _restartRealtimePolling();
    } catch (e) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _setState(() {
        _loading = false;
        _error =
            e is RiverSideApiException && e.message.contains('session expired')
            ? _NotificationsPageState._labelSessionExpired
            : _NotificationsPageState._labelLoadFailed;
      });
    }
  }

  Future<void> _loadAllQing({
    required bool showLoading,
    required bool clearExisting,
  }) async {
    final serial = ++_requestSerial;
    final auth = _activeQingAuth();
    if (auth == null) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _setState(() {
        _loading = false;
        _error = _NotificationsPageState._labelNeedQingLogin;
        if (clearExisting) {
          _notifications = const [];
          _qingNotificationRecords = const [];
          _qingKindByNotificationId.clear();
          _qingBoardIdByNotificationId.clear();
          _qingNextPageByKind.clear();
          _qingKindsHasMore.clear();
        }
      });
      _notifyUnreadCountChanged();
      return;
    }

    if (showLoading) {
      _setState(() {
        _loading = true;
        _error = null;
        if (clearExisting) {
          _notifications = const [];
          _qingNotificationRecords = const [];
          _qingKindByNotificationId.clear();
          _qingBoardIdByNotificationId.clear();
          _qingNextPageByKind.clear();
          _qingKindsHasMore.clear();
          _qingUnreadCounts = const _QingUnreadCounts();
        }
        _channelMessages = const [];
        _directMessages = const [];
      });
    }

    try {
      await _ensureQingReadCutoffLoaded();
      final results = await Future.wait<_QingNotificationPageResult>([
        _fetchQingNotificationsPage(
          auth: auth,
          kind: _QingNotificationKind.atMe,
          page: 1,
        ),
        _fetchQingNotificationsPage(
          auth: auth,
          kind: _QingNotificationKind.reply,
          page: 1,
        ),
        _fetchQingNotificationsPage(
          auth: auth,
          kind: _QingNotificationKind.notice,
          page: 1,
        ),
      ]);
      final unreadCounts = await _fetchQingUnreadCounts(auth: auth);
      if (!mounted || serial != _requestSerial) {
        return;
      }

      final merged = _mergeQingRecords(
        _qingNotificationRecords,
        <_QingNotificationRecord>[
          ...results[0].records,
          ...results[1].records,
          ...results[2].records,
        ],
      );
      final normalized = _applyQingUnreadStates(
        records: merged,
        unreadCounts: unreadCounts,
      );

      _setState(() {
        _loading = false;
        _error = null;
        _hasRealtimeNotifications = false;
        _nextNotificationsPath = '';
        _qingNotificationFilter = _QingNotificationFilter.all;
        _channelMessages = const [];
        _directMessages = const [];
        _qingUnreadCounts = unreadCounts;
        _applyQingRecords(normalized);
        _qingNextPageByKind
          ..clear()
          ..addAll(<_QingNotificationKind, int>{
            _QingNotificationKind.atMe: 2,
            _QingNotificationKind.reply: 2,
            _QingNotificationKind.notice: 2,
          });
        _qingKindsHasMore
          ..clear()
          ..addAll(<_QingNotificationKind>[
            if (results[0].hasMore) _QingNotificationKind.atMe,
            if (results[1].hasMore) _QingNotificationKind.reply,
            if (results[2].hasMore) _QingNotificationKind.notice,
          ]);
      });
      _notifyUnreadCountChanged();
    } on RiverSideApiException catch (error) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _setState(() {
        _loading = false;
        _error = error.message.isEmpty
            ? _NotificationsPageState._labelLoadFailed
            : error.message;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _setState(() {
        _loading = false;
        _error = _NotificationsPageState._labelLoadFailed;
      });
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (_isQingForum) {
      await _loadMoreQingNotifications();
      return;
    }
    if (_nextNotificationsPath.isEmpty) {
      return;
    }
    _setState(() => _loadingMoreNotifications = true);
    try {
      final cookieHeader = _activeCookieHeader();
      if (cookieHeader == null) {
        return;
      }
      final api = widget.dependencies.accountStore.riverSideApiClient;
      final page = await api.fetchNotificationsPage(
        cookieHeader: cookieHeader,
        loadMorePath: _nextNotificationsPath,
      );
      if (!mounted) {
        return;
      }
      _setState(() {
        final existingIds = _notifications.map((e) => e.id).toSet();
        final newItems = page.items.where((e) => !existingIds.contains(e.id));
        _notifications = [..._notifications, ...newItems];
        _nextNotificationsPath = page.loadMorePath;
        _loadingMoreNotifications = false;
      });
    } catch (_) {
      if (mounted) {
        _setState(() => _loadingMoreNotifications = false);
      }
    }
  }

  Future<void> _loadMoreQingNotifications() async {
    if (_loadingMoreNotifications || _qingKindsHasMore.isEmpty) {
      return;
    }
    final auth = _activeQingAuth();
    if (auth == null) {
      return;
    }
    _setState(() {
      _loadingMoreNotifications = true;
    });
    final kinds = _qingKindsHasMore.toList(growable: false);
    try {
      final results = await Future.wait<_QingNotificationPageResult>(
        kinds.map((kind) {
          final page = _qingNextPageByKind[kind] ?? 2;
          return _fetchQingNotificationsPage(
            auth: auth,
            kind: kind,
            page: page,
          );
        }),
      );
      if (!mounted) {
        return;
      }
      final incoming = <_QingNotificationRecord>[
        for (final page in results) ...page.records,
      ];
      final merged = _mergeQingRecords(_qingNotificationRecords, incoming);
      final normalized = _applyQingUnreadStates(
        records: merged,
        unreadCounts: _qingUnreadCounts,
      );
      _setState(() {
        _applyQingRecords(normalized);
        for (var i = 0; i < kinds.length; i++) {
          final kind = kinds[i];
          if (results[i].hasMore) {
            _qingNextPageByKind[kind] = (_qingNextPageByKind[kind] ?? 2) + 1;
            _qingKindsHasMore.add(kind);
          } else {
            _qingKindsHasMore.remove(kind);
          }
        }
        _loadingMoreNotifications = false;
      });
      _notifyUnreadCountChanged();
    } catch (_) {
      if (mounted) {
        _setState(() => _loadingMoreNotifications = false);
      }
    }
  }

  Future<void> _openNotificationTopic(
    BuildContext sourceContext,
    RiverSideNotificationItem item,
  ) async {
    if (item.topicId == null || item.topicId! <= 0) {
      return;
    }
    if (!item.read) {
      _setState(() {
        final index = _notifications.indexWhere((e) => e.id == item.id);
        if (index != -1) {
          _notifications[index] = _copyNotificationAsRead(item);
        }
      });
      if (_isQingForum) {
        _setState(() {
          _qingNotificationRecords = _qingNotificationRecords
              .map(
                (record) => record.item.id == item.id
                    ? _QingNotificationRecord(
                        item: _copyNotificationAsRead(record.item),
                        kind: record.kind,
                        boardId: record.boardId,
                      )
                    : record,
              )
              .toList(growable: false);
        });
      } else {
        final cookie = _activeCookieHeader();
        if (cookie != null) {
          widget.dependencies.accountStore.riverSideApiClient
              .markNotificationsAsRead(
                cookieHeader: cookie,
                notificationId: item.id,
              )
              .ignore();
        }
      }
      _notifyUnreadCountChanged();
    }

    final title = item.title.trim().isEmpty ? '帖子详情' : item.title.trim();
    final authorName = item.username.trim().isEmpty ? '未知用户' : item.username;
    await Navigator.of(context).push(
      DraggableRoute<void>(
        source: sourceContext,
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: item.topicId!,
          provider: _isQingForum
              ? AccountProvider.qingShuiHePan
              : AccountProvider.riverSide,
          qingBoardId: _isQingForum
              ? _qingBoardIdByNotificationId[item.id]
              : null,
          initialPostNumberOnOpen:
              (item.postNumber != null && item.postNumber! > 1)
              ? item.postNumber
              : null,
          preview: TopicDetailPreview(
            title: title,
            authorDisplayName: authorName,
            authorUsername: authorName,
            authorAvatarUrl: item.avatarUrl,
            titleHeroTag: 'notification_topic_title_nohero_${item.id}',
            authorAvatarHeroTag: 'notification_topic_avatar_nohero_${item.id}',
            authorNameHeroTag: 'notification_topic_name_nohero_${item.id}',
          ),
        ),
      ),
    );
  }

  RiverSideNotificationItem _copyNotificationAsRead(
    RiverSideNotificationItem item,
  ) {
    return RiverSideNotificationItem(
      id: item.id,
      type: item.type,
      read: true,
      highPriority: item.highPriority,
      createdAt: item.createdAt,
      topicId: item.topicId,
      postNumber: item.postNumber,
      slug: item.slug,
      title: item.title,
      excerpt: item.excerpt,
      username: item.username,
      actionText: item.actionText,
      badgeName: item.badgeName,
      count: item.count,
      avatarUrl: item.avatarUrl,
    );
  }

  Future<void> _openChatDetail(RiverSideChatChannelItem channel) async {
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) =>
            ChatDetailPage(dependencies: widget.dependencies, channel: channel),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadAll(showLoading: false);
  }

  Future<bool> _confirmDeleteDirectMessage(
    RiverSideChatChannelItem item,
  ) async {
    final title = item.name.trim().isNotEmpty
        ? item.name.trim()
        : '私信 #${item.id}';
    return showRiverConfirmDialog(
      context: context,
      title: '删除私信',
      message: '是否删除与“$title”的私信会话？',
      confirmText: '删除',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
  }

  Future<bool> _deleteDirectMessageChannel(
    RiverSideChatChannelItem item,
  ) async {
    if (_deletingDirectMessageIds.contains(item.id)) {
      return false;
    }
    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showRiverSnackBar(_NotificationsPageState._labelNeedLogin);
      }
      return false;
    }
    _setState(() {
      _deletingDirectMessageIds.add(item.id);
    });
    try {
      await widget.dependencies.accountStore.riverSideApiClient
          .deleteDirectMessageChannel(channelId: item.id, cookieHeader: cookie);
      if (!mounted) {
        return false;
      }
      _setState(() {
        _directMessages = _directMessages
            .where((channel) => channel.id != item.id)
            .toList(growable: false);
        _deletingDirectMessageIds.remove(item.id);
      });
      _notifyUnreadCountChanged();
      ScaffoldMessenger.of(context).showRiverSnackBar('私信已删除');
      return true;
    } on RiverSideApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
      }
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showRiverSnackBar('删除私信失败，请稍后重试');
      }
      return false;
    } finally {
      if (mounted) {
        _setState(() {
          _deletingDirectMessageIds.remove(item.id);
        });
      }
    }
  }

  Future<void> _consumeRealtimeNotifications() async {
    _setState(() => _hasRealtimeNotifications = false);
    await _loadAll(showLoading: false);
    if (_notificationsScrollController.hasClients) {
      _notificationsScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
    }
  }

  Future<void> _markAllNotificationItemsAsRead() async {
    final unreadCount = _notifications.where((item) => !item.read).length;
    if (unreadCount <= 0) {
      return;
    }
    if (_isQingForum) {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      await _persistQingReadCutoff(nowMillis);
      if (!mounted) {
        return;
      }
      _setState(() {
        _notifications = _notifications
            .map((item) => item.read ? item : _copyNotificationAsRead(item))
            .toList(growable: false);
        _qingNotificationRecords = _qingNotificationRecords
            .map(
              (record) => _QingNotificationRecord(
                item: record.item.read
                    ? record.item
                    : _copyNotificationAsRead(record.item),
                kind: record.kind,
                boardId: record.boardId,
              ),
            )
            .toList(growable: false);
        _qingUnreadCounts = const _QingUnreadCounts(
          atMe: 0,
          reply: 0,
          notice: 0,
          hasServerData: true,
        );
      });
      _notifyUnreadCountChanged();
      ScaffoldMessenger.of(context).showRiverSnackBar('已清除通知未读');
      return;
    }

    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showRiverSnackBar(_NotificationsPageState._labelNeedLogin);
      }
      return;
    }
    final previous = List<RiverSideNotificationItem>.from(_notifications);
    _setState(() {
      _notifications = _notifications
          .map((item) => item.read ? item : _copyNotificationAsRead(item))
          .toList(growable: false);
    });
    _notifyUnreadCountChanged();
    try {
      await widget.dependencies.accountStore.riverSideApiClient
          .markNotificationsAsRead(cookieHeader: cookie);
      if (mounted) {
        ScaffoldMessenger.of(context).showRiverSnackBar('已清除通知未读');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setState(() {
        _notifications = previous;
      });
      _notifyUnreadCountChanged();
      final message = error is RiverSideApiException
          ? error.message
          : '清除未读失败，请稍后重试';
      ScaffoldMessenger.of(context).showRiverSnackBar(message);
    }
  }

  Future<void> _restartRealtimePolling() async {
    _messageBusPoller?.stop();
    _messageBusPoller = null;
    if (_isQingForum) {
      return;
    }
    final cookie = _activeCookieHeader();
    if (cookie == null) {
      return;
    }
    final userId = await _resolvePollingUserId(cookie: cookie);
    if (!mounted || userId == null) {
      return;
    }
    final channel = '/notification/$userId';
    _messageBusPoller = RiverSideMessageBusPoller(
      apiClient: widget.dependencies.accountStore.riverSideApiClient,
      cookieHeader: cookie,
      channelLastIds: RiverSideMessageBusPoller.buildInitialChannels([channel]),
      onEvents: (events) {
        if (!mounted) {
          return;
        }
        if (events.any((e) => e.channel == channel)) {
          if (!_showNotificationsRealtimeRefreshBanner) {
            return;
          }
          _setState(() => _hasRealtimeNotifications = true);
        }
      },
    );
    _messageBusPoller?.start();
  }

  Future<int?> _resolvePollingUserId({required String cookie}) async {
    final account = widget.dependencies.accountStore.activeRiverSideAccount;
    final currentId = account?.userId;
    if (currentId != null && currentId > 0) {
      return currentId;
    }
    final activeUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    if (activeUsername == null || activeUsername.isEmpty) {
      return null;
    }
    try {
      final profile = await widget.dependencies.accountStore.riverSideApiClient
          .fetchCurrentUserByCookie(
            cookieHeader: cookie,
            fallbackLogin: activeUsername,
          );
      await widget.dependencies.accountStore.upsertRiverSideAccount(profile);
      final refreshedId = profile.userId;
      if (refreshedId != null && refreshedId > 0) {
        return refreshedId;
      }
    } catch (_) {}
    return null;
  }

  void _applyQingRecords(List<_QingNotificationRecord> records) {
    _qingNotificationRecords = records;
    _notifications = records
        .map((record) => record.item)
        .toList(growable: false);
    _qingKindByNotificationId
      ..clear()
      ..addEntries(
        records.map((record) => MapEntry(record.item.id, record.kind)),
      );
    _qingBoardIdByNotificationId
      ..clear()
      ..addEntries(
        records.map((record) => MapEntry(record.item.id, record.boardId)),
      );
  }

  List<_QingNotificationRecord> _mergeQingRecords(
    List<_QingNotificationRecord> current,
    List<_QingNotificationRecord> incoming,
  ) {
    final byId = <int, _QingNotificationRecord>{
      for (final record in current) record.item.id: record,
    };
    for (final record in incoming) {
      final old = byId[record.item.id];
      if (old == null) {
        byId[record.item.id] = record;
        continue;
      }
      final oldTime = old.item.createdAt?.millisecondsSinceEpoch ?? 0;
      final newTime = record.item.createdAt?.millisecondsSinceEpoch ?? 0;
      if (newTime >= oldTime) {
        byId[record.item.id] = record;
      }
    }
    final merged = byId.values.toList(growable: false);
    merged.sort((a, b) {
      final at = a.item.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.item.createdAt?.millisecondsSinceEpoch ?? 0;
      final diff = bt.compareTo(at);
      if (diff != 0) {
        return diff;
      }
      return b.item.id.compareTo(a.item.id);
    });
    return merged;
  }

  Future<void> _ensureQingReadCutoffLoaded() async {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername?.trim() ??
        '';
    if (username.isEmpty) {
      _qingReadCutoffUsername = null;
      _qingReadCutoffMillis = null;
      return;
    }
    if (_qingReadCutoffUsername == username) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key =
        '${_NotificationsPageState._qingReadCutoffStorageKeyPrefix}$username';
    _qingReadCutoffMillis = prefs.getInt(key);
    _qingReadCutoffUsername = username;
  }

  Future<void> _persistQingReadCutoff(int millis) async {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername?.trim() ??
        '';
    if (username.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key =
        '${_NotificationsPageState._qingReadCutoffStorageKeyPrefix}$username';
    await prefs.setInt(key, millis);
    _qingReadCutoffUsername = username;
    _qingReadCutoffMillis = millis;
  }

  Future<_QingUnreadCounts> _fetchQingUnreadCounts({
    required QingShuiHePanAuth auth,
  }) async {
    try {
      final map = await _callQingApi(
        auth: auth,
        body: const <String, String>{
          'r': 'message/heart',
          'sdkVersion': '2.4.2',
        },
      );
      final body = _asQingMap(map['body']);
      final atMe = _asQingInt(_asQingMap(body['atMeInfo'])['count']) ?? 0;
      final reply = _asQingInt(_asQingMap(body['replyInfo'])['count']) ?? 0;
      final notice = _asQingInt(_asQingMap(body['systemInfo'])['count']) ?? 0;
      return _QingUnreadCounts(
        atMe: atMe < 0 ? 0 : atMe,
        reply: reply < 0 ? 0 : reply,
        notice: notice < 0 ? 0 : notice,
        hasServerData: true,
      );
    } catch (_) {
      return const _QingUnreadCounts(hasServerData: false);
    }
  }

  List<_QingNotificationRecord> _applyQingUnreadStates({
    required List<_QingNotificationRecord> records,
    required _QingUnreadCounts unreadCounts,
  }) {
    final cutoff = _qingReadCutoffMillis;
    final sorted = List<_QingNotificationRecord>.from(records)
      ..sort((a, b) {
        final at = a.item.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.item.createdAt?.millisecondsSinceEpoch ?? 0;
        final diff = bt.compareTo(at);
        if (diff != 0) {
          return diff;
        }
        return b.item.id.compareTo(a.item.id);
      });
    final unreadRemain = <_QingNotificationKind, int>{
      _QingNotificationKind.atMe: unreadCounts.atMe,
      _QingNotificationKind.reply: unreadCounts.reply,
      _QingNotificationKind.notice: unreadCounts.notice,
    };
    final normalized = <_QingNotificationRecord>[];
    for (final record in sorted) {
      final millis = record.item.createdAt?.millisecondsSinceEpoch ?? 0;
      final readByCutoff =
          cutoff != null && cutoff > 0 && millis > 0 && millis <= cutoff;
      final remain = unreadRemain[record.kind] ?? 0;
      final markUnread = unreadCounts.hasServerData
          ? !readByCutoff && remain > 0
          : !readByCutoff && !record.item.read;
      if (markUnread && unreadCounts.hasServerData) {
        unreadRemain[record.kind] = remain - 1;
      }
      final nextItem = RiverSideNotificationItem(
        id: record.item.id,
        type: record.item.type,
        read: !markUnread,
        highPriority: record.item.highPriority,
        createdAt: record.item.createdAt,
        topicId: record.item.topicId,
        postNumber: record.item.postNumber,
        slug: record.item.slug,
        title: record.item.title,
        excerpt: record.item.excerpt,
        username: record.item.username,
        actionText: record.item.actionText,
        badgeName: record.item.badgeName,
        count: record.item.count,
        avatarUrl: record.item.avatarUrl,
      );
      normalized.add(
        _QingNotificationRecord(
          item: nextItem,
          kind: record.kind,
          boardId: record.boardId,
        ),
      );
    }
    return normalized;
  }

  Future<_QingNotificationPageResult> _fetchQingNotificationsPage({
    required QingShuiHePanAuth auth,
    required _QingNotificationKind kind,
    required int page,
  }) async {
    if (kind == _QingNotificationKind.notice) {
      final map = await _callQingApi(
        auth: auth,
        body: <String, String>{
          'r': 'message/notifylistex',
          'type': 'system',
          'page': '$page',
          'pageSize': '${_NotificationsPageState._qingNotificationsPageSize}',
        },
      );
      final records = _parseQingNotice(map, page: page);
      return _QingNotificationPageResult(
        records: records,
        hasMore:
            records.length >=
            _NotificationsPageState._qingNotificationsPageSize,
      );
    }
    final map = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'message/notifylist',
        'type': kind == _QingNotificationKind.atMe ? 'at' : 'post',
        'page': '$page',
        'pageSize': '${_NotificationsPageState._qingNotificationsPageSize}',
      },
    );
    final records = _parseQingAtOrReply(map, kind: kind, page: page);
    return _QingNotificationPageResult(
      records: records,
      hasMore:
          records.length >= _NotificationsPageState._qingNotificationsPageSize,
    );
  }

  List<_QingNotificationRecord> _parseQingAtOrReply(
    Map<String, dynamic> map, {
    required _QingNotificationKind kind,
    required int page,
  }) {
    final body = _asQingMap(map['body']);
    final dataList = _asQingMapList(body['data']);
    final forumList = _asQingMapList(map['list']);
    final maxCount = dataList.length > forumList.length
        ? dataList.length
        : forumList.length;
    final records = <_QingNotificationRecord>[];
    for (var i = 0; i < maxCount; i++) {
      final data = i < dataList.length
          ? dataList[i]
          : const <String, dynamic>{};
      final forum = i < forumList.length
          ? forumList[i]
          : const <String, dynamic>{};
      final merged = <String, dynamic>{...forum, ...data};
      if (merged.isEmpty) {
        continue;
      }
      final createdAt = _parseQingEpochDate(
        _asQingInt(
          merged['replied_date'] ??
              merged['reply_date'] ??
              merged['last_reply_date'] ??
              merged['dateline'],
        ),
      );
      final title = _pickQingString(merged, const <String>[
        'topic_subject',
        'title',
        'subject',
      ]);
      final excerpt = _sanitizeQingText(
        _pickQingString(merged, const <String>[
          'reply_content',
          'note',
          'summary',
          'content',
        ]),
      );
      final username = _pickQingString(merged, const <String>[
        'author',
        'user_name',
        'reply_name',
        'username',
      ]);
      final avatar = _resolveQingUrl(
        _pickQingString(merged, const <String>[
          'authorAvatar',
          'icon',
          'avatar',
          'userAvatar',
        ]),
      );
      records.add(
        _QingNotificationRecord(
          kind: kind,
          boardId: _asQingInt(merged['board_id'] ?? merged['fid']),
          item: RiverSideNotificationItem(
            id: _buildQingNotificationId(kind, merged, page, i),
            type: kind == _QingNotificationKind.atMe ? 1 : 2,
            read: _inferQingRead(merged),
            highPriority: false,
            createdAt: createdAt,
            topicId: _asQingInt(merged['topic_id'] ?? merged['tid']),
            postNumber: _asQingInt(
              merged['position'] ?? merged['post_number'] ?? merged['reply_id'],
            ),
            slug: '',
            title: title,
            excerpt: excerpt,
            username: username.isEmpty ? '用户' : username,
            actionText: kind == _QingNotificationKind.atMe ? '@了你' : '回复了你',
            badgeName: '',
            count: 1,
            avatarUrl: avatar,
          ),
        ),
      );
    }
    return records;
  }

  List<_QingNotificationRecord> _parseQingNotice(
    Map<String, dynamic> map, {
    required int page,
  }) {
    final body = _asQingMap(map['body']);
    final list = _asQingMapList(body['data']);
    return List<_QingNotificationRecord>.generate(list.length, (index) {
      final item = list[index];
      final title = _pickQingString(item, const <String>[
        'title',
        'subject',
        'topic_subject',
      ]);
      final note = _sanitizeQingText(
        _pickQingString(item, const <String>['note', 'summary', 'content']),
      );
      final username = _pickQingString(item, const <String>[
        'user_name',
        'author',
        'username',
      ]);
      return _QingNotificationRecord(
        kind: _QingNotificationKind.notice,
        boardId: _asQingInt(item['board_id'] ?? item['fid']),
        item: RiverSideNotificationItem(
          id: _buildQingNotificationId(
            _QingNotificationKind.notice,
            item,
            page,
            index,
          ),
          type: 13,
          read: _inferQingRead(item),
          highPriority: false,
          createdAt: _parseQingEpochDate(
            _asQingInt(item['replied_date'] ?? item['dateline']),
          ),
          topicId: _asQingInt(item['topic_id'] ?? item['tid']),
          postNumber: _asQingInt(item['position'] ?? item['post_number']),
          slug: '',
          title: title.isEmpty ? '系统通知' : title,
          excerpt: note,
          username: username.isEmpty ? '系统' : username,
          actionText: '发送通知',
          badgeName: '',
          count: 1,
          avatarUrl: _resolveQingUrl(
            _pickQingString(item, const <String>[
              'authorAvatar',
              'icon',
              'avatar',
            ]),
          ),
        ),
      );
    });
  }

  int _buildQingNotificationId(
    _QingNotificationKind kind,
    Map<String, dynamic> item,
    int page,
    int index,
  ) {
    final seed = <String>[
      kind.name,
      '${item['id'] ?? ''}',
      '${item['topic_id'] ?? item['tid'] ?? ''}',
      '${item['reply_id'] ?? item['post_id'] ?? ''}',
      '${item['replied_date'] ?? item['dateline'] ?? ''}',
      '${item['author'] ?? item['user_name'] ?? item['username'] ?? ''}',
      '$page',
      '$index',
    ].join('|');
    var hash = 2166136261;
    for (final code in seed.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  bool _inferQingRead(Map<String, dynamic> item) {
    if (item.containsKey('isRead')) return _asQingBool(item['isRead']);
    if (item.containsKey('is_read')) return _asQingBool(item['is_read']);
    if (item.containsKey('read')) return _asQingBool(item['read']);
    return true;
  }

  Future<Map<String, dynamic>> _callQingApi({
    required QingShuiHePanAuth auth,
    required Map<String, String> body,
  }) async {
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: const <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: _formEncode(<String, String>{
            ...body,
            'accessToken': auth.token,
            'accessSecret': auth.secret,
          }),
        )
        .timeout(const Duration(seconds: 14));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final head = _asQingMap(map['head']);
      final message = '${map['errcode'] ?? head['errInfo'] ?? '请求失败'}'.trim();
      throw RiverSideApiException(message.isEmpty ? '清水河畔请求失败' : message);
    }
    return map;
  }

  String _formEncode(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  Map<String, dynamic> _asQingMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asQingMapList(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw.map<Map<String, dynamic>>((item) => _asQingMap(item)).toList();
  }

  int? _asQingInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    return int.tryParse('${raw ?? ''}'.trim());
  }

  bool _asQingBool(dynamic raw) {
    if (raw is bool) return raw;
    final value = '${raw ?? ''}'.trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  String _pickQingString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = '${source[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  DateTime? _parseQingEpochDate(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    final isMillis = value > 1000000000000;
    return DateTime.fromMillisecondsSinceEpoch(isMillis ? value : value * 1000);
  }

  String _resolveQingUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      return value;
    }
    final base = Uri.tryParse(RiverServerConfig.instance.qingShuiHePanBaseUrl);
    if (base == null) {
      return value;
    }
    if (value.startsWith('//')) {
      return '${base.scheme}:$value';
    }
    if (value.startsWith('/')) {
      return '${base.scheme}://${base.host}$value';
    }
    return '${base.scheme}://${base.host}/$value';
  }

  String _sanitizeQingText(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

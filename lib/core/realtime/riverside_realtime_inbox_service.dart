import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_message_bus_models.dart';
import 'package:river/core/network/riverside_notification_models.dart';
import 'package:river/core/realtime/riverside_message_bus_poller.dart';

enum RiverSideInAppMessageKind { notification, channelMessage, directMessage }

@immutable
class RiverSideInAppMessageBanner {
  const RiverSideInAppMessageBanner({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    this.notification,
    this.channel,
  });

  final String id;
  final RiverSideInAppMessageKind kind;
  final String title;
  final String message;
  final RiverSideNotificationItem? notification;
  final RiverSideChatChannelItem? channel;
}

class RiverSideRealtimeInboxService extends ChangeNotifier {
  RiverSideRealtimeInboxService({
    required this.accountStore,
    required this.settingsController,
  }) {
    _lastRiverUsername = accountStore.activeRiverSideUsername?.trim();
    accountStore.addListener(_handleAccountStoreChanged);
  }

  final AccountStore accountStore;
  final AppSettingsController settingsController;
  final StreamController<RiverSideInAppMessageBanner> _bannerController =
      StreamController<RiverSideInAppMessageBanner>.broadcast();

  RiverSideMessageBusPoller? _messageBusPoller;
  AccountProvider _forumProvider = AccountProvider.riverSide;
  List<RiverSideNotificationItem> _notifications = const [];
  List<RiverSideChatChannelItem> _chatChannels = const [];
  String _nextNotificationsPath = '';
  String? _notificationsError;
  String? _chatError;
  bool _loading = false;
  bool _hasLoadedSnapshot = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  String? _lastRiverUsername;
  int? _pollingUserId;
  int? _activeChatChannelId;
  String _pollerCookie = '';
  int _bannerSequence = 0;

  Stream<RiverSideInAppMessageBanner> get bannerStream => _bannerController.stream;
  bool get loading => _loading;
  List<RiverSideNotificationItem> get notifications =>
      List<RiverSideNotificationItem>.unmodifiable(_notifications);
  List<RiverSideChatChannelItem> get channelMessages => List.unmodifiable(
    _chatChannels.where((item) => !item.isDirectMessage),
  );
  List<RiverSideChatChannelItem> get directMessages => List.unmodifiable(
    _chatChannels.where((item) => item.isDirectMessage),
  );
  String? get notificationsError => _notificationsError;
  String? get chatError => _chatError;
  String get nextNotificationsPath => _nextNotificationsPath;
  int get totalUnreadCount {
    final notificationsUnread = _notifications.where((item) => !item.read).length;
    final chatsUnread = _chatChannels.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    return notificationsUnread + chatsUnread;
  }

  void updateForumProvider(AccountProvider provider) {
    if (_forumProvider == provider) {
      return;
    }
    _forumProvider = provider;
    if (_forumProvider != AccountProvider.riverSide) {
      _stopPolling();
      notifyListeners();
      return;
    }
    unawaited(refresh(showLoading: !_hasLoadedSnapshot, allowBanner: false));
  }

  void setActiveChatChannel(int? channelId) {
    if (_activeChatChannelId == channelId) {
      return;
    }
    _activeChatChannelId = channelId;
  }

  Future<void> refresh({
    bool showLoading = false,
    bool allowBanner = false,
  }) async {
    if (_disposed || _forumProvider != AccountProvider.riverSide) {
      _stopPolling();
      return;
    }
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }

    final cookie = _activeCookieHeader();
    if (cookie == null) {
      _stopPolling();
      _replaceSnapshot(
        notifications: const <RiverSideNotificationItem>[],
        chatChannels: const <RiverSideChatChannelItem>[],
        nextNotificationsPath: '',
        notificationsError: '请先登录 RiverSide 账号',
        chatError: '请先登录 RiverSide 账号',
        loading: false,
      );
      return;
    }

    _refreshing = true;
    if (showLoading && !_loading) {
      _replaceSnapshot(
        notifications: _notifications,
        chatChannels: _chatChannels,
        nextNotificationsPath: _nextNotificationsPath,
        notificationsError: _notificationsError,
        chatError: _chatError,
        loading: true,
      );
    }

    try {
      do {
        _refreshQueued = false;
        final previousNotifications = _notifications;
        final previousChatChannels = _chatChannels;
        final results = await Future.wait<Object?>(<Future<Object?>>[
          accountStore.riverSideApiClient
              .fetchNotificationsPage(cookieHeader: cookie)
              .then<Object?>((value) => value)
              .catchError((Object error) => error),
          accountStore.riverSideApiClient
              .fetchMyChatChannels(cookieHeader: cookie)
              .then<Object?>((value) => value)
              .catchError((Object error) => error),
        ]);

        if (_disposed || _forumProvider != AccountProvider.riverSide) {
          return;
        }

        final notificationsResult = results[0];
        final chatResult = results[1];
        final notificationPage =
            notificationsResult is RiverSideNotificationPage
            ? notificationsResult
            : const RiverSideNotificationPage(
                items: <RiverSideNotificationItem>[],
                totalRows: null,
                seenNotificationId: null,
                loadMorePath: '',
              );
        final chatChannels = chatResult is List<RiverSideChatChannelItem>
            ? chatResult
            : const <RiverSideChatChannelItem>[];

        _replaceSnapshot(
          notifications: notificationPage.items,
          chatChannels: chatChannels,
          nextNotificationsPath: notificationPage.loadMorePath,
          notificationsError: notificationsResult is RiverSideApiException
              ? _resolveErrorMessage(notificationsResult)
              : null,
          chatError: chatResult is RiverSideApiException
              ? _resolveErrorMessage(chatResult)
              : null,
          loading: false,
        );

        if (!_hasLoadedSnapshot) {
          _hasLoadedSnapshot = true;
        } else if (allowBanner) {
          final banner = _buildBanner(
            previousNotifications: previousNotifications,
            nextNotifications: _notifications,
            previousChatChannels: previousChatChannels,
            nextChatChannels: _chatChannels,
          );
          if (banner != null) {
            _bannerController.add(banner);
          }
        }

        await _ensurePolling(cookie: cookie);
      } while (_refreshQueued && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  void _handleAccountStoreChanged() {
    final currentRiver = accountStore.activeRiverSideUsername?.trim();
    if (currentRiver == _lastRiverUsername) {
      return;
    }
    _lastRiverUsername = currentRiver;
    _pollingUserId = null;
    if (_forumProvider != AccountProvider.riverSide) {
      _stopPolling();
      return;
    }
    if (currentRiver == null || currentRiver.isEmpty) {
      _stopPolling();
      _replaceSnapshot(
        notifications: const <RiverSideNotificationItem>[],
        chatChannels: const <RiverSideChatChannelItem>[],
        nextNotificationsPath: '',
        notificationsError: '请先登录 RiverSide 账号',
        chatError: '请先登录 RiverSide 账号',
        loading: false,
      );
      return;
    }
    _hasLoadedSnapshot = false;
    unawaited(refresh(showLoading: true, allowBanner: false));
  }

  Future<void> _ensurePolling({required String cookie}) async {
    if (_forumProvider != AccountProvider.riverSide) {
      _stopPolling();
      return;
    }
    final userId = await _resolvePollingUserId(cookie: cookie);
    if (_disposed || userId == null || userId <= 0) {
      return;
    }
    final channels = <String, int>{
      '/notification/$userId': -1,
      '/chat': -1,
      for (final item in _chatChannels) ...<String, int>{
        '/chat/${item.id}': -1,
        '/chat/${item.id}/new-messages': -1,
      },
    };

    if (_messageBusPoller == null ||
        _pollerCookie != cookie ||
        _pollingUserId != userId) {
      _stopPolling();
      _pollingUserId = userId;
      _pollerCookie = cookie;
      _messageBusPoller = RiverSideMessageBusPoller(
        apiClient: accountStore.riverSideApiClient,
        cookieHeader: cookie,
        channelLastIds: channels,
        onEvents: _handleRealtimeEvents,
        onError: (_) {},
      );
      _messageBusPoller?.start();
      return;
    }

    _messageBusPoller?.updateChannels(channels);
  }

  void _handleRealtimeEvents(List<RiverSideMessageBusEvent> events) {
    if (_disposed || events.isEmpty) {
      return;
    }
    final userId = _pollingUserId;
    if (userId == null) {
      return;
    }
    final hasRelevant = events.any((event) {
      final channel = event.channel.trim();
      if (channel.isEmpty) {
        return false;
      }
      if (channel == '/notification/$userId') {
        return true;
      }
      return channel == '/chat' || channel.startsWith('/chat/');
    });
    if (!hasRelevant) {
      return;
    }
    unawaited(refresh(showLoading: false, allowBanner: true));
  }

  RiverSideInAppMessageBanner? _buildBanner({
    required List<RiverSideNotificationItem> previousNotifications,
    required List<RiverSideNotificationItem> nextNotifications,
    required List<RiverSideChatChannelItem> previousChatChannels,
    required List<RiverSideChatChannelItem> nextChatChannels,
  }) {
    if (!settingsController.showInAppMessages) {
      return null;
    }

    final previousNotificationIds = previousNotifications
        .map((item) => item.id)
        .toSet();
    for (final item in nextNotifications) {
      if (previousNotificationIds.contains(item.id) || item.read) {
        continue;
      }
      final title = item.actionText.trim().isNotEmpty
          ? item.actionText.trim()
          : '收到新通知';
      final message = item.title.trim().isNotEmpty
          ? item.title.trim()
          : (item.excerpt.trim().isNotEmpty ? item.excerpt.trim() : '点击查看详情');
      return RiverSideInAppMessageBanner(
        id: 'river_banner_${_bannerSequence++}',
        kind: RiverSideInAppMessageKind.notification,
        title: title,
        message: message,
        notification: item,
      );
    }

    final previousChannelsById = <int, RiverSideChatChannelItem>{
      for (final item in previousChatChannels) item.id: item,
    };
    for (final item in nextChatChannels) {
      if (!item.isDirectMessage) {
        continue;
      }
      if (_activeChatChannelId == item.id) {
        continue;
      }
      final previous = previousChannelsById[item.id];
      final unreadIncreased =
          item.unreadCount > (previous?.unreadCount ?? 0);
      final timestampAdvanced =
          (item.lastMessageAt?.millisecondsSinceEpoch ?? 0) >
          (previous?.lastMessageAt?.millisecondsSinceEpoch ?? 0);
      if (!unreadIncreased && !timestampAdvanced) {
        continue;
      }
      final title = '来自 ${item.name} 的新私信';
      final message = item.lastMessage.trim().isNotEmpty
          ? item.lastMessage.trim()
          : '点击查看详情';
      return RiverSideInAppMessageBanner(
        id: 'river_banner_${_bannerSequence++}',
        kind: RiverSideInAppMessageKind.directMessage,
        title: title,
        message: message,
        channel: item,
      );
    }
    return null;
  }

  Future<int?> _resolvePollingUserId({required String cookie}) async {
    final currentId = accountStore.activeRiverSideAccount?.userId;
    if (currentId != null && currentId > 0) {
      return currentId;
    }
    final activeUsername = accountStore.activeRiverSideUsername?.trim() ?? '';
    if (activeUsername.isEmpty) {
      return null;
    }
    try {
      final profile = await accountStore.riverSideApiClient.fetchCurrentUserByCookie(
        cookieHeader: cookie,
        fallbackLogin: activeUsername,
      );
      await accountStore.upsertRiverSideAccount(profile);
      return profile.userId;
    } catch (_) {
      return null;
    }
  }

  String? _activeCookieHeader() {
    final username = accountStore.activeRiverSideUsername?.trim() ?? '';
    if (username.isEmpty) {
      return null;
    }
    final cookie = accountStore.riverSideCookieHeaderFor(username)?.trim() ?? '';
    return cookie.isEmpty ? null : cookie;
  }

  String _resolveErrorMessage(RiverSideApiException error) {
    final message = error.message.trim();
    if (message.isEmpty) {
      return '加载失败，请重试';
    }
    if (message.toLowerCase().contains('session expired')) {
      return '登录态已失效，请重新登录';
    }
    return message;
  }

  void _replaceSnapshot({
    required List<RiverSideNotificationItem> notifications,
    required List<RiverSideChatChannelItem> chatChannels,
    required String nextNotificationsPath,
    required String? notificationsError,
    required String? chatError,
    required bool loading,
  }) {
    _notifications = List<RiverSideNotificationItem>.unmodifiable(notifications);
    _chatChannels = List<RiverSideChatChannelItem>.unmodifiable(chatChannels);
    _nextNotificationsPath = nextNotificationsPath;
    _notificationsError = notificationsError;
    _chatError = chatError;
    _loading = loading;
    notifyListeners();
  }

  void _stopPolling() {
    _messageBusPoller?.stop();
    _messageBusPoller = null;
    _pollerCookie = '';
    _pollingUserId = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    accountStore.removeListener(_handleAccountStoreChanged);
    _stopPolling();
    unawaited(_bannerController.close());
    super.dispose();
  }
}

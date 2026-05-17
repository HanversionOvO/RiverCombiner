import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:draggable_route/draggable_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:river/core/theme/river_design_tokens.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:http/http.dart' as http;
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_notification_models.dart';
import 'package:river/core/realtime/riverside_realtime_inbox_service.dart';
import 'package:river/core/widgets/river_confirm_dialog.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:river/features/notifications/chat_detail_page.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

part 'notifications_page_actions.dart';
part 'notifications_page_view.dart';

enum _QingNotificationKind { atMe, reply, notice }

enum _QingNotificationFilter { all, atMe, reply, notice }

class _QingNotificationRecord {
  const _QingNotificationRecord({
    required this.item,
    required this.kind,
    this.boardId,
  });

  final RiverSideNotificationItem item;
  final _QingNotificationKind kind;
  final int? boardId;
}

class _QingNotificationPageResult {
  const _QingNotificationPageResult({
    required this.records,
    required this.hasMore,
  });

  final List<_QingNotificationRecord> records;
  final bool hasMore;
}

class _QingUnreadCounts {
  const _QingUnreadCounts({
    this.atMe = 0,
    this.reply = 0,
    this.notice = 0,
    this.hasServerData = false,
  });

  final int atMe;
  final int reply;
  final int notice;
  final bool hasServerData;
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.dependencies,
    required this.forumProvider,
    this.onUnreadCountChanged,
  });

  final AppDependencies dependencies;
  final AccountProvider forumProvider;
  final ValueChanged<int>? onUnreadCountChanged;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  static const String _qingReadCutoffStorageKeyPrefix =
      'notifications.qing.read_cutoff.';
  static const String _labelNeedLogin = '请先登录 RiverSide 账号';
  static const String _labelNeedQingLogin = '请先登录清水河畔账号';
  static const String _labelLoadFailed = '加载失败，请重试';
  static const String _labelNeedSwitchToRiverSideRealtimeChat =
      '请切换至RiverSide论坛以使用实时聊天功能';
  static const int _qingNotificationsPageSize = 20;

  late TabController _tabController;
  final ScrollController _notificationsScrollController = ScrollController();
  final ScrollController _channelScrollController = ScrollController();
  final ScrollController _directScrollController = ScrollController();
  final ValueNotifier<bool> _showBackToTopNotifier = ValueNotifier<bool>(false);

  List<RiverSideNotificationItem> _notifications = const [];
  List<RiverSideChatChannelItem> _channelMessages = const [];
  List<RiverSideChatChannelItem> _directMessages = const [];
  final Set<int> _deletingDirectMessageIds = <int>{};

  String _nextNotificationsPath = '';
  bool _loading = true;
  bool _loadingMoreNotifications = false;
  double _headerScrollFactor = 0;
  int _requestSerial = 0;
  String? _notificationsError;
  String? _chatError;
  String? _lastActiveRiverUsername;
  String? _lastActiveQingUsername;
  late AccountProvider _forumProvider;
  _QingNotificationFilter _qingNotificationFilter = _QingNotificationFilter.all;
  List<_QingNotificationRecord> _qingNotificationRecords = const [];
  final Map<int, _QingNotificationKind> _qingKindByNotificationId =
      <int, _QingNotificationKind>{};
  final Map<int, int?> _qingBoardIdByNotificationId = <int, int?>{};
  final Map<_QingNotificationKind, int> _qingNextPageByKind =
      <_QingNotificationKind, int>{};
  final Set<_QingNotificationKind> _qingKindsHasMore =
      <_QingNotificationKind>{};
  _QingUnreadCounts _qingUnreadCounts = const _QingUnreadCounts();
  String? _qingReadCutoffUsername;
  int? _qingReadCutoffMillis;

  void _setState(VoidCallback fn) {
    setState(fn);
  }

  bool _isIPhoneDevice(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    return MediaQuery.sizeOf(context).shortestSide < 600;
  }

  @override
  void initState() {
    super.initState();
    _forumProvider = widget.forumProvider;
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _lastActiveRiverUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    _lastActiveQingUsername =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    widget.dependencies.accountStore.addListener(_onAccountStoreChanged);
    widget.dependencies.riverSideRealtimeInboxService.addListener(
      _onRiverRealtimeInboxChanged,
    );
    widget.dependencies.riverSideRealtimeInboxService.updateForumProvider(
      _forumProvider,
    );
    _notificationsScrollController.addListener(_onNotificationsScroll);
    _channelScrollController.addListener(_onChannelScroll);
    _directScrollController.addListener(_onDirectScroll);
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forumProvider == widget.forumProvider) {
      return;
    }
    _forumProvider = widget.forumProvider;
    widget.dependencies.riverSideRealtimeInboxService.updateForumProvider(
      _forumProvider,
    );
    _setState(() {
      _loading = true;
      _notificationsError = null;
      _chatError = null;
      _notifications = const [];
      _qingNotificationRecords = const [];
      _channelMessages = const [];
      _directMessages = const [];
      _deletingDirectMessageIds.clear();
      _nextNotificationsPath = '';
      _qingNotificationFilter = _QingNotificationFilter.all;
      _qingKindByNotificationId.clear();
      _qingBoardIdByNotificationId.clear();
      _qingNextPageByKind.clear();
      _qingKindsHasMore.clear();
      _qingUnreadCounts = const _QingUnreadCounts();
      _qingReadCutoffUsername = null;
      _qingReadCutoffMillis = null;
    });
    _loadAll(clearExisting: true);
  }

  @override
  void dispose() {
    widget.dependencies.accountStore.removeListener(_onAccountStoreChanged);
    widget.dependencies.riverSideRealtimeInboxService.removeListener(
      _onRiverRealtimeInboxChanged,
    );
    _tabController.removeListener(_onTabChanged);
    _showBackToTopNotifier.dispose();
    _directScrollController.dispose();
    _channelScrollController.dispose();
    _notificationsScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopHeader(
                theme,
                Curves.easeOutCubic.transform(_headerScrollFactor),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const PageScrollPhysics(),
                  children: [
                    _buildNotificationsList(theme),
                    if (_forumProvider == AccountProvider.qingShuiHePan)
                      _buildRealtimeChatUnavailablePlaceholder(
                        theme,
                        controller: _channelScrollController,
                      )
                    else
                      _buildChatList(
                        theme,
                        _channelMessages,
                        '暂无频道消息',
                        controller: _channelScrollController,
                      ),
                    if (_forumProvider == AccountProvider.qingShuiHePan)
                      _buildRealtimeChatUnavailablePlaceholder(
                        theme,
                        controller: _directScrollController,
                      )
                    else
                      _buildChatList(
                        theme,
                        _directMessages,
                        '暂无私信消息',
                        controller: _directScrollController,
                      ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 98,
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
                        heroTag: 'notifications_back_to_top_fab',
                        onPressed: visible ? _scrollActiveTabToTop : null,
                        child: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

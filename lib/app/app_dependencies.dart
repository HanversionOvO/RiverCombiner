import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/categories/riverside_category_store.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/mini_apps/river_mini_app_floating_store.dart';
import 'package:river/core/mini_apps/river_mini_app_host_store.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/posts/topic_footprint_store.dart';
import 'package:river/core/realtime/riverside_realtime_inbox_service.dart';
import 'package:river/core/update/app_update_checker.dart';

class AppDependencies {
  AppDependencies({
    required this.settingsController,
    required this.accountStore,
    required this.updateChecker,
  }) : postsStartupPreloadStore = PostsStartupPreloadStore();

  final AppSettingsController settingsController;
  final AccountStore accountStore;
  final AppUpdateChecker updateChecker;
  final PostsStartupPreloadStore postsStartupPreloadStore;
  final TopicFootprintStore topicFootprintStore = TopicFootprintStore();
  final RiverMiniAppFloatingStore miniAppFloatingStore =
      RiverMiniAppFloatingStore();
  final RiverMiniAppHostStore miniAppHostStore = RiverMiniAppHostStore();
  late final RiverSideRealtimeInboxService riverSideRealtimeInboxService =
      RiverSideRealtimeInboxService(
        accountStore: accountStore,
        settingsController: settingsController,
      );
}

class PostsStartupPreloadStore {
  static const Duration _networkTimeout = Duration(seconds: 14);

  Future<void>? _runningTask;
  List<RiverSideCategoryOption>? _riverCategories;
  List<RiverSideCategoryOption>? _qingCategories;
  final Map<RiverSideTopicFeed, List<RiverSideTopicSummary>>
  _riverTopicsFirstPage = <RiverSideTopicFeed, List<RiverSideTopicSummary>>{};
  final Map<RiverSideTopicFeed, List<RiverSideTopicSummary>>
  _qingTopicsFirstPage = <RiverSideTopicFeed, List<RiverSideTopicSummary>>{};

  void start({required AccountStore accountStore, bool forceRestart = false}) {
    if (_runningTask != null && !forceRestart) {
      return;
    }
    if (forceRestart) {
      _runningTask = null;
      _riverCategories = null;
      _qingCategories = null;
      _riverTopicsFirstPage.clear();
      _qingTopicsFirstPage.clear();
    }
    _runningTask = _run(accountStore);
  }

  Future<List<RiverSideCategoryOption>?> takeRiverCategories({
    bool waitForRunningTask = false,
  }) async {
    if (waitForRunningTask) {
      await _runningTask;
    }
    final categories = _riverCategories;
    _riverCategories = null;
    if (categories == null) {
      return null;
    }
    return List<RiverSideCategoryOption>.unmodifiable(categories);
  }

  Future<List<RiverSideTopicSummary>?> takeRiverTopicsFirstPage({
    required RiverSideTopicFeed feed,
    bool waitForRunningTask = false,
  }) async {
    if (waitForRunningTask) {
      await _runningTask;
    }
    final topics = _riverTopicsFirstPage.remove(feed);
    if (topics == null) {
      return null;
    }
    return List<RiverSideTopicSummary>.unmodifiable(topics);
  }

  Future<List<RiverSideCategoryOption>?> takeQingCategories({
    bool waitForRunningTask = false,
  }) async {
    if (waitForRunningTask) {
      await _runningTask;
    }
    final categories = _qingCategories;
    _qingCategories = null;
    if (categories == null) {
      return null;
    }
    return List<RiverSideCategoryOption>.unmodifiable(categories);
  }

  Future<List<RiverSideTopicSummary>?> takeQingTopicsFirstPage({
    required RiverSideTopicFeed feed,
    bool waitForRunningTask = false,
  }) async {
    if (waitForRunningTask) {
      await _runningTask;
    }
    final topics = _qingTopicsFirstPage.remove(feed);
    if (topics == null) {
      return null;
    }
    return List<RiverSideTopicSummary>.unmodifiable(topics);
  }

  Future<void> _run(AccountStore accountStore) async {
    final preloadTasks = <Future<void>>[
      _preloadRiverData(accountStore),
      _preloadQingData(accountStore),
    ];
    await Future.wait(preloadTasks);
  }

  Future<void> _preloadRiverData(AccountStore accountStore) async {
    final username = accountStore.activeRiverSideUsername?.trim() ?? '';
    if (username.isEmpty) {
      return;
    }
    final cookie = accountStore.riverSideCookieHeaderFor(username);
    if (cookie == null || cookie.trim().isEmpty) {
      return;
    }
    final preloadTasks = <Future<void>>[
      _preloadRiverCategories(
        accountStore: accountStore,
        username: username,
        cookie: cookie,
      ),
      for (final feed in RiverSideTopicFeed.values)
        _preloadRiverFeedFirstPage(
          accountStore: accountStore,
          cookie: cookie,
          feed: feed,
        ),
    ];
    await Future.wait(preloadTasks);
  }

  Future<void> _preloadQingData(AccountStore accountStore) async {
    final username = accountStore.activeQingShuiHePanUsername?.trim() ?? '';
    if (username.isEmpty) {
      return;
    }
    final auth = accountStore.qingShuiHePanAuthFor(username);
    if (auth == null) {
      return;
    }
    final preloadTasks = <Future<void>>[
      _preloadQingCategories(authToken: auth.token, authSecret: auth.secret),
      for (final feed in RiverSideTopicFeed.values)
        _preloadQingFeedFirstPage(
          feed: feed,
          authToken: auth.token,
          authSecret: auth.secret,
        ),
    ];
    await Future.wait(preloadTasks);
  }

  Future<void> _preloadRiverCategories({
    required AccountStore accountStore,
    required String username,
    required String cookie,
  }) async {
    try {
      final categories = await RiverSideCategoryStore.instance
          .load(
            apiClient: accountStore.riverSideApiClient,
            username: username,
            cookieHeader: cookie,
            forceRefresh: false,
          )
          .timeout(_networkTimeout);
      _riverCategories = List<RiverSideCategoryOption>.unmodifiable(categories);
    } catch (_) {
      // Startup preload should never block app startup.
    }
  }

  Future<void> _preloadRiverFeedFirstPage({
    required AccountStore accountStore,
    required String cookie,
    required RiverSideTopicFeed feed,
  }) async {
    try {
      final topics = await accountStore.riverSideApiClient
          .fetchTopicSummaries(feed: feed, page: 0, cookieHeader: cookie)
          .timeout(_networkTimeout);
      _riverTopicsFirstPage[feed] = List<RiverSideTopicSummary>.unmodifiable(
        topics,
      );
    } catch (_) {
      // Startup preload should never block app startup.
    }
  }

  Future<void> _preloadQingCategories({
    required String authToken,
    required String authSecret,
  }) async {
    try {
      final endpoint =
          '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Accept': 'application/json, text/plain, */*',
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: _formEncode(<String, String>{
              'r': 'forum/forumlist',
              'accessToken': authToken,
              'accessSecret': authSecret,
            }),
          )
          .timeout(_networkTimeout);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return;
      }
      final map = decoded.map((key, value) => MapEntry('$key', value));
      if ('${map['rs']}' == '0') {
        return;
      }
      final listRaw = map['list'];
      if (listRaw is! List) {
        return;
      }

      final categories = <RiverSideCategoryOption>[];
      final seenBoardIds = <int>{};
      var position = 0;
      var syntheticParentSeed = 1;
      for (final rawGroup in listRaw) {
        final group = _toStringMap(rawGroup);
        if (group.isEmpty) {
          continue;
        }
        final groupName = _pickString(group, const <String>[
          'board_category_name',
          'category_name',
          'name',
        ]);
        final groupIdRaw = _toInt(group['board_category_id']);
        int? parentId;
        if (groupName.isNotEmpty) {
          final safeGroupId =
              groupIdRaw != null &&
                  groupIdRaw > 0 &&
                  !seenBoardIds.contains(groupIdRaw)
              ? groupIdRaw
              : -(100000 + syntheticParentSeed++);
          parentId = safeGroupId;
          categories.add(
            RiverSideCategoryOption(
              id: safeGroupId,
              name: groupName,
              position: position++,
              parentCategoryId: null,
              description: '',
            ),
          );
        }
        final boardList = group['board_list'];
        if (boardList is! List) {
          continue;
        }
        for (final rawBoard in boardList) {
          final board = _toStringMap(rawBoard);
          if (board.isEmpty) {
            continue;
          }
          final boardId = _toInt(board['board_id']);
          if (boardId == null ||
              boardId <= 0 ||
              seenBoardIds.contains(boardId)) {
            continue;
          }
          final boardName = _pickString(board, const <String>[
            'board_name',
            'forum_name',
            'name',
          ]);
          if (boardName.isEmpty) {
            continue;
          }
          seenBoardIds.add(boardId);
          categories.add(
            RiverSideCategoryOption(
              id: boardId,
              name: boardName,
              position: position++,
              parentCategoryId: parentId,
              description: '',
            ),
          );
        }
      }
      _qingCategories = List<RiverSideCategoryOption>.unmodifiable(categories);
    } catch (_) {
      // Startup preload should never block app startup.
    }
  }

  Future<void> _preloadQingFeedFirstPage({
    required RiverSideTopicFeed feed,
    required String authToken,
    required String authSecret,
  }) async {
    try {
      final endpoint =
          '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Accept': 'application/json, text/plain, */*',
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: _formEncode(<String, String>{
              'r': 'forum/topiclist',
              'isImageList': '1',
              'sortby': _qingSortBy(feed),
              'page': '1',
              'pageSize': '20',
              'accessToken': authToken,
              'accessSecret': authSecret,
            }),
          )
          .timeout(_networkTimeout);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return;
      }
      final map = decoded.map((key, value) => MapEntry('$key', value));
      if ('${map['rs']}' == '0') {
        return;
      }
      final listRaw = map['list'];
      if (listRaw is! List) {
        return;
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
            authorDisplayName: displayName.isEmpty
                ? authorUsername
                : displayName,
            authorUsername: authorUsername,
            authorUserId:
                _toInt(item['user_id']) ?? _extractUidFromAvatarUrl(avatar),
            authorAvatarUrl: avatar,
            isHot: (_toInt(item['hot']) ?? 0) > 0,
            isPinned: (_toInt(item['top']) ?? 0) > 0,
          ),
        );
      }
      _qingTopicsFirstPage[feed] = List<RiverSideTopicSummary>.unmodifiable(
        topics,
      );
    } catch (_) {
      // Startup preload should never block app startup.
    }
  }

  String _qingSortBy(RiverSideTopicFeed feed) {
    switch (feed) {
      case RiverSideTopicFeed.latestCreated:
        return 'new';
      case RiverSideTopicFeed.latestReplied:
        return 'all';
      case RiverSideTopicFeed.hot:
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

  Map<String, dynamic> _toStringMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
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

  DateTime? _parseEpochDate(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    final isMillis = value > 1000000000000;
    return DateTime.fromMillisecondsSinceEpoch(isMillis ? value : value * 1000);
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
}

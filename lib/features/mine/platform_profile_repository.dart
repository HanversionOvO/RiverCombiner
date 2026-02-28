import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_profile_models.dart';
import 'package:river/features/mine/platform_profile_models.dart';

class PlatformProfileRepository {
  const PlatformProfileRepository({required this.dependencies});

  final AppDependencies dependencies;

  Future<PlatformProfileOverview> loadOverview(UserAccount account) async {
    switch (account.provider) {
      case AccountProvider.riverSide:
        return _loadRiverSideOverview(account);
      case AccountProvider.qingShuiHePan:
        return _loadQingShuiHePanOverview(account);
    }
  }

  List<PlatformProfileTab> tabsFor(UserAccount account) {
    switch (account.provider) {
      case AccountProvider.riverSide:
        return const <PlatformProfileTab>[
          PlatformProfileTab(id: 'all', label: '全部', supportsTopicOpen: true),
          PlatformProfileTab(
            id: 'topics',
            label: '主题',
            supportsTopicOpen: true,
          ),
          PlatformProfileTab(
            id: 'replies',
            label: '回复',
            supportsTopicOpen: true,
          ),
          PlatformProfileTab(id: 'likes', label: '点赞', supportsTopicOpen: true),
        ];
      case AccountProvider.qingShuiHePan:
        return const <PlatformProfileTab>[
          PlatformProfileTab(
            id: 'topic',
            label: '主题',
            supportsTopicOpen: false,
          ),
          PlatformProfileTab(
            id: 'reply',
            label: '回复',
            supportsTopicOpen: false,
          ),
          PlatformProfileTab(
            id: 'favorite',
            label: '收藏',
            supportsTopicOpen: false,
          ),
        ];
    }
  }

  Future<List<PlatformProfileActivityItem>> loadActivities({
    required UserAccount account,
    required PlatformProfileTab tab,
    int page = 1,
    int pageSize = 20,
  }) async {
    switch (account.provider) {
      case AccountProvider.riverSide:
        return _loadRiverSideActivities(
          account: account,
          tab: tab,
          page: page,
          pageSize: pageSize,
        );
      case AccountProvider.qingShuiHePan:
        return _loadQingShuiHePanActivities(
          account: account,
          tab: tab,
          page: page,
          pageSize: pageSize,
        );
    }
  }

  Future<List<PlatformProfileFollowUser>> loadFollowUsers({
    required UserAccount account,
    required bool followers,
    int page = 1,
    int pageSize = 20,
  }) async {
    switch (account.provider) {
      case AccountProvider.riverSide:
        final cookie = _requiredRiverCookie(account.username);
        final users = await dependencies.accountStore.riverSideApiClient
            .fetchProfileFollowUsers(
              account.username,
              followers: followers,
              cookieHeader: cookie,
            );
        return users
            .map(
              (item) => PlatformProfileFollowUser(
                id: item.id,
                username: item.username,
                displayName: item.displayName,
                avatarUrl: item.avatarUrl,
              ),
            )
            .toList();
      case AccountProvider.qingShuiHePan:
        return _loadQingShuiHePanFollowUsers(
          account: account,
          followers: followers,
          page: page,
          pageSize: pageSize,
        );
    }
  }

  Future<PlatformProfileOverview> _loadRiverSideOverview(
    UserAccount account,
  ) async {
    final cookie = _requiredRiverCookie(account.username);
    final overview = await dependencies.accountStore.riverSideApiClient
        .fetchProfileOverview(account.username, cookieHeader: cookie);
    final profileUrl =
        '${RiverServerConfig.instance.baseUrl}/u/${Uri.encodeComponent(account.username)}';
    return PlatformProfileOverview(
      provider: PlatformProfileProvider.riverSide,
      account: overview.account,
      bio: overview.bio,
      location: overview.location,
      website: overview.website,
      createdAt: overview.createdAt,
      lastSeenAt: overview.lastSeenAt,
      topicCount: overview.topicCount,
      replyCount: overview.postCount,
      likesOrFavoritesCount: overview.likesReceived,
      followersCount: overview.followersCount,
      followingCount: overview.followingCount,
      trustLevel: overview.trustLevel,
      profileUrl: profileUrl,
      extraDescription: overview.isProfileHidden ? '资料部分隐藏' : '',
    );
  }

  Future<List<PlatformProfileActivityItem>> _loadRiverSideActivities({
    required UserAccount account,
    required PlatformProfileTab tab,
    required int page,
    required int pageSize,
  }) async {
    final cookie = _requiredRiverCookie(account.username);
    final kind = _riverKindFromTab(tab.id);
    final list = await dependencies.accountStore.riverSideApiClient
        .fetchProfileActivities(
          account.username,
          kind: kind,
          cookieHeader: cookie,
          offset: (page - 1) * pageSize,
        );
    return list.map(_mapRiverActivity).toList();
  }

  RiverSideProfileActivityKind _riverKindFromTab(String tabId) {
    switch (tabId) {
      case 'topics':
        return RiverSideProfileActivityKind.topics;
      case 'replies':
        return RiverSideProfileActivityKind.replies;
      case 'likes':
        return RiverSideProfileActivityKind.likesGiven;
      case 'all':
      default:
        return RiverSideProfileActivityKind.all;
    }
  }

  PlatformProfileActivityItem _mapRiverActivity(
    RiverSideProfileActivityItem item,
  ) {
    final category = item.categoryName.trim().isEmpty
        ? '未知分类'
        : item.categoryName;
    final meta = '$category · 回复 ${item.replyCount} · 浏览 ${item.viewCount}';
    return PlatformProfileActivityItem(
      id: '${item.topicId}-${item.postNumber ?? 0}',
      title: item.title,
      subtitle: item.excerpt,
      meta: meta,
      createdAt: item.createdAt,
      topicId: item.topicId,
      postNumber: item.postNumber,
    );
  }

  Future<PlatformProfileOverview> _loadQingShuiHePanOverview(
    UserAccount account,
  ) async {
    final auth = _requiredQingAuth(account.username);
    var targetUid = account.userId;
    final searchUser = await _tryLoadQingSearchUser(
      auth: auth,
      account: account,
      targetUid: targetUid ?? auth.userId,
    );
    targetUid ??=
        _asInt(searchUser['uid']) ??
        _asInt(searchUser['user_id']) ??
        auth.userId;
    final overviewBody = await _tryLoadQingUserInfo(auth, targetUid: targetUid);
    final body = _asMap(overviewBody['body']);
    final externInfo = _asMap(body['externInfo']);
    final userInfo = _asMap(overviewBody['userInfo']);
    final userMap = userInfo.isNotEmpty
        ? userInfo
        : _asMap(overviewBody['user']);
    final merged = <String, dynamic>{
      ...overviewBody,
      ...body,
      ...externInfo,
      ...userMap,
    };
    final mergedUid = _pickInt(merged, <String>['uid', 'user_id', 'id']);
    final targetUidStable = targetUid;
    final userInfoMismatched =
        (targetUidStable ?? 0) > 0 &&
        mergedUid != null &&
        mergedUid > 0 &&
        mergedUid != targetUidStable;
    final profileBase = userInfoMismatched ? searchUser : merged;

    final displayName = _pickString(profileBase, <String>[
      'name',
      'userName',
      'nickname',
    ]);
    final avatar = _pickString(profileBase, <String>[
      'avatar',
      'icon',
      'userAvatar',
    ]);
    final bio = userInfoMismatched
        ? ''
        : _pickString(merged, <String>['sign', 'signature', 'bio']);
    final location = _pickString(profileBase, <String>[
      'location',
      'province',
      'city',
    ]);
    final website = _pickString(profileBase, <String>['homepage', 'website']);

    final followTotals = await _tryLoadQingFollowTotals(
      auth: auth,
      targetUid: targetUid,
    );
    final activityTotals = await _tryLoadQingActivityTotals(
      auth: auth,
      targetUid: targetUid,
    );

    final createdAtRaw =
        _pickInt(merged, <String>[
          'regdate',
          'registerDate',
          'register_date',
          'registerTime',
          'register_time',
          'reg_time',
          'join_date',
          'dateline',
        ]) ??
        _pickInt(searchUser, <String>[
          'regdate',
          'register_date',
          'dateline',
        ]) ??
        _pickDateFromProfileList(body, <String>['注册', '加入', '创建']);
    final lastSeenRaw =
        _pickInt(merged, <String>[
          'lastactivity',
          'lastVisit',
          'last_visit',
          'lastvisit',
          'last_active',
          'lastActiveTime',
          'last_reply_date',
          'lastLogin',
          'dateline',
        ]) ??
        _pickInt(searchUser, <String>['lastLogin', 'last_visit', 'dateline']) ??
        _pickDateFromProfileList(body, <String>['访问', '活跃']);
    final topicCount =
        activityTotals.topicCount ??
        _pickInt(merged, <String>['topic_num', 'thread_num', 'topics']);
    final replyCount =
        activityTotals.replyCount ??
        _pickInt(merged, <String>[
          'reply_posts_num',
          'post_num',
          'reply_num',
          'replies',
        ]);
    final favCount =
        activityTotals.favoriteCount ??
        _pickInt(merged, <String>['favorite_num', 'favorites', 'fav_num']);
    final followCount =
        followTotals.followingCount ??
        _pickInt(merged, <String>['follow_num', 'following', 'following_num']);
    final fanCount =
        followTotals.followersCount ??
        _pickInt(merged, <String>[
          'fans_num',
          'followers',
          'friend_num',
          'followed_num',
          'follower_num',
        ]);
    final level = _pickInt(merged, <String>['level', 'level_id', 'user_level']);

    final profileUrl = targetUid == null
        ? null
        : '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/home.php?mod=space&uid=$targetUid';

    return PlatformProfileOverview(
      provider: PlatformProfileProvider.qingShuiHePan,
      account: account.copyWith(
        displayName: displayName.isEmpty ? account.displayName : displayName,
        avatarUrl: avatar.isEmpty ? account.avatarUrl : avatar,
      ),
      bio: bio,
      location: location,
      website: website,
      createdAt: _millisOrSecondsToDate(createdAtRaw),
      lastSeenAt: _millisOrSecondsToDate(lastSeenRaw),
      topicCount: topicCount,
      replyCount: replyCount,
      likesOrFavoritesCount: favCount,
      followersCount: fanCount,
      followingCount: followCount,
      trustLevel: level,
      profileUrl: profileUrl,
      extraDescription: '数据来源于清水河畔接口，字段可能不完整',
    );
  }

  Future<List<PlatformProfileActivityItem>> _loadQingShuiHePanActivities({
    required UserAccount account,
    required PlatformProfileTab tab,
    required int page,
    required int pageSize,
  }) async {
    final auth = _requiredQingAuth(account.username);
    final targetUid = account.userId ?? auth.userId;
    final data = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'user/topiclist',
        'type': tab.id,
        if (targetUid != null) 'uid': '$targetUid',
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final listRaw = data['list'];
    if (listRaw is! List) {
      return const <PlatformProfileActivityItem>[];
    }
    final result = <PlatformProfileActivityItem>[];
    for (final raw in listRaw) {
      final map = _asMap(raw);
      if (map.isEmpty) {
        continue;
      }
      final topicId = _asInt(map['topic_id']);
      final title = _pickString(map, ['title', 'subject', 'topic_title']);
      final excerpt = _pickString(map, ['subject', 'summary', 'content']);
      final board = _pickString(map, ['board_name', 'forum_name']);
      final replies = _asInt(map['replies']) ?? 0;
      final hits = _asInt(map['hits']) ?? 0;
      final meta = '${board.isEmpty ? '论坛' : board} · 回复 $replies · 浏览 $hits';
      final createdAt = _millisOrSecondsToDate(
        _asInt(map['last_reply_date']) ?? _asInt(map['create_date']),
      );
      result.add(
        PlatformProfileActivityItem(
          id: '${map['topic_id'] ?? map['source_id'] ?? result.length}',
          title: title.isEmpty ? '(无标题)' : title,
          subtitle: excerpt,
          meta: meta,
          createdAt: createdAt,
          topicId: topicId,
          boardId: _asInt(map['board_id']),
        ),
      );
    }
    return result;
  }

  Future<List<PlatformProfileFollowUser>> _loadQingShuiHePanFollowUsers({
    required UserAccount account,
    required bool followers,
    required int page,
    required int pageSize,
  }) async {
    final auth = _requiredQingAuth(account.username);
    final targetUid = account.userId ?? auth.userId;
    final candidates = <Map<String, String>>[
      <String, String>{
        'r': 'user/userlist',
        'type': followers ? 'followed' : 'follow',
      },
      <String, String>{
        'r': 'user/userlist',
        'type': followers ? 'fans' : 'follow',
      },
      <String, String>{'r': followers ? 'user/fanslist' : 'user/followlist'},
    ];
    for (final body in candidates) {
      try {
        final data = await _callQingApi(
          auth: auth,
          body: <String, String>{
            ...body,
            if (targetUid != null) 'uid': '$targetUid',
            'page': '$page',
            'pageSize': '$pageSize',
          },
        );
        final list = _extractQingFollowList(data);
        if (list.isNotEmpty) {
          return list;
        }
      } catch (_) {
        // Try next candidate endpoint.
      }
    }
    return const <PlatformProfileFollowUser>[];
  }

  Future<_QingFollowTotals> _tryLoadQingFollowTotals({
    required QingShuiHePanAuth auth,
    int? targetUid,
  }) async {
    int? followingCount;
    int? followersCount;

    final followingResp = await _safeQingApiCall(
      auth: auth,
      body: <String, String>{
        'r': 'user/userlist',
        'type': 'follow',
        if (targetUid != null) 'uid': '$targetUid',
        'page': '1',
        'pageSize': '1',
      },
    );
    if (followingResp != null) {
      followingCount = _asInt(followingResp['total_num']);
    }

    final followersResp = await _safeQingApiCall(
      auth: auth,
      body: <String, String>{
        'r': 'user/userlist',
        'type': 'followed',
        if (targetUid != null) 'uid': '$targetUid',
        'page': '1',
        'pageSize': '1',
      },
    );
    if (followersResp != null) {
      followersCount = _asInt(followersResp['total_num']);
    } else {
      final fallbackFollowersResp = await _safeQingApiCall(
        auth: auth,
        body: <String, String>{
          'r': 'user/userlist',
          'type': 'fans',
          if (targetUid != null) 'uid': '$targetUid',
          'page': '1',
          'pageSize': '1',
        },
      );
      if (fallbackFollowersResp != null) {
        followersCount = _asInt(fallbackFollowersResp['total_num']);
      }
    }
    return _QingFollowTotals(
      followingCount: followingCount,
      followersCount: followersCount,
    );
  }

  Future<_QingActivityTotals> _tryLoadQingActivityTotals({
    required QingShuiHePanAuth auth,
    int? targetUid,
  }) async {
    int? topicCount;
    int? replyCount;
    int? favoriteCount;

    Future<int?> fetchTotal(String type) async {
      final response = await _safeQingApiCall(
        auth: auth,
        body: <String, String>{
          'r': 'user/topiclist',
          'type': type,
          if (targetUid != null) 'uid': '$targetUid',
          'page': '1',
          'pageSize': '1',
        },
      );
      if (response == null) {
        return null;
      }
      return _asInt(response['total_num']) ?? _asInt(response['total']);
    }

    topicCount = await fetchTotal('topic');
    replyCount = await fetchTotal('reply');
    favoriteCount = await fetchTotal('favorite');

    return _QingActivityTotals(
      topicCount: topicCount,
      replyCount: replyCount,
      favoriteCount: favoriteCount,
    );
  }

  Future<Map<String, dynamic>> _tryLoadQingSearchUser({
    required QingShuiHePanAuth auth,
    required UserAccount account,
    int? targetUid,
  }) async {
    final keywordSet = <String>{
      account.username.trim(),
      account.displayName.trim(),
    };
    if ((targetUid ?? 0) <= 0) {
      keywordSet
        ..add(auth.username.trim())
        ..add(auth.displayName.trim());
    }
    final keywords = keywordSet.where((value) => value.isNotEmpty).toList();
    if (keywords.isEmpty) {
      return const <String, dynamic>{};
    }

    Map<String, dynamic>? firstCandidate;

    for (final keyword in keywords) {
      final response = await _safeQingApiCall(
        auth: auth,
        body: <String, String>{
          'r': 'user/searchuser',
          'keyword': keyword,
          if (targetUid != null) 'uid': '$targetUid',
          'page': '1',
          'pageSize': '50',
        },
      );
      if (response == null) {
        continue;
      }
      final listRaw = response['list'] ?? _asMap(response['body'])['list'];
      if (listRaw is! List) {
        continue;
      }
      for (final raw in listRaw) {
        final map = _asMap(raw);
        if (map.isEmpty) {
          continue;
        }
        firstCandidate ??= map;
        final uid = _asInt(map['uid']) ?? _asInt(map['user_id']);
        if (targetUid != null && uid == targetUid) {
          return map;
        }
        final name = _pickString(map, <String>['name', 'userName', 'username']);
        if (name.isEmpty) {
          continue;
        }
        final normalized = name.toLowerCase();
        if (normalized == account.username.trim().toLowerCase() ||
            normalized == account.displayName.trim().toLowerCase() ||
            normalized == auth.username.trim().toLowerCase() ||
            normalized == auth.displayName.trim().toLowerCase()) {
          return map;
        }
      }
    }
    if ((targetUid ?? 0) > 0) {
      return const <String, dynamic>{};
    }
    return firstCandidate ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> _safeQingApiCall({
    required QingShuiHePanAuth auth,
    required Map<String, String> body,
  }) async {
    try {
      return await _callQingApi(auth: auth, body: body);
    } catch (_) {
      return null;
    }
  }

  List<PlatformProfileFollowUser> _extractQingFollowList(
    Map<String, dynamic> data,
  ) {
    final listRaw =
        data['list'] ??
        _asMap(data['body'])['list'] ??
        data['users'] ??
        data['user_list'];
    if (listRaw is! List) {
      return const <PlatformProfileFollowUser>[];
    }
    final result = <PlatformProfileFollowUser>[];
    for (final raw in listRaw) {
      final map = _asMap(raw);
      if (map.isEmpty) {
        continue;
      }
      final id =
          _asInt(map['uid']) ??
          _asInt(map['user_id']) ??
          _asInt(map['id']) ??
          0;
      final username = _pickString(map, <String>[
        'user_name',
        'username',
        'userName',
      ]);
      final displayName = _pickString(map, <String>[
        'nick_name',
        'name',
        'nickname',
        'user_nick_name',
        'userName',
      ]);
      final avatar = _pickString(map, <String>['icon', 'avatar', 'userAvatar']);
      if (id <= 0 && username.isEmpty && displayName.isEmpty) {
        continue;
      }
      final resolvedUsername = username.isEmpty
          ? (displayName.isEmpty ? 'user_$id' : displayName)
          : username;
      final resolvedDisplayName = displayName.isEmpty
          ? resolvedUsername
          : displayName;
      result.add(
        PlatformProfileFollowUser(
          id: id,
          username: resolvedUsername,
          displayName: resolvedDisplayName,
          avatarUrl: avatar,
        ),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _tryLoadQingUserInfo(
    QingShuiHePanAuth auth, {
    int? targetUid,
  }) async {
    final uid = targetUid ?? auth.userId;
    final candidates = <Map<String, String>>[
      <String, String>{
        'r': 'user/userinfo',
        if (uid != null) 'userId': '$uid',
        if (uid != null) 'uid': '$uid',
      },
      <String, String>{
        'r': 'user/getuserinfo',
        if (uid != null) 'userId': '$uid',
        if (uid != null) 'uid': '$uid',
      },
      <String, String>{
        'r': 'user/profile',
        if (uid != null) 'userId': '$uid',
        if (uid != null) 'uid': '$uid',
      },
    ];
    for (final body in candidates) {
      try {
        final data = await _callQingApi(auth: auth, body: body);
        if (_asMap(data['body']).isNotEmpty ||
            _asMap(data['userInfo']).isNotEmpty ||
            _asMap(data['user']).isNotEmpty) {
          return data;
        }
      } catch (_) {
        // try next candidate
      }
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _callQingApi({
    required QingShuiHePanAuth auth,
    required Map<String, String> body,
  }) async {
    final apiUrl =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final requestBody = <String, String>{
      ...body,
      'accessToken': auth.token,
      'accessSecret': auth.secret,
    };
    final response = await http
        .post(
          Uri.parse(apiUrl),
          headers: const <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: _formEncode(requestBody),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final err = (map['errcode'] ?? _asMap(map['head'])['errInfo'] ?? '请求失败')
          .toString();
      throw RiverSideApiException(err);
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

  String _requiredRiverCookie(String username) {
    final cookie = dependencies.accountStore.riverSideCookieHeaderFor(username);
    if (cookie == null || cookie.trim().isEmpty) {
      throw const RiverSideApiException('当前 RiverSide 账号登录态已失效');
    }
    return cookie;
  }

  QingShuiHePanAuth _requiredQingAuth(String username) {
    final normalized = username.trim();
    if (normalized.isNotEmpty) {
      final matched = dependencies.accountStore.qingShuiHePanAuthFor(
        normalized,
      );
      if (matched != null) {
        return matched;
      }
    }

    final activeUsername = dependencies.accountStore.activeQingShuiHePanUsername
        ?.trim();
    if (activeUsername != null && activeUsername.isNotEmpty) {
      final active = dependencies.accountStore.qingShuiHePanAuthFor(
        activeUsername,
      );
      if (active != null) {
        return active;
      }
    }
    throw const RiverSideApiException('当前清水河畔账号认证信息缺失');
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }

  int? _asInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.toInt();
    }
    return int.tryParse('${raw ?? ''}');
  }

  String _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = '${map[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  int? _pickInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _asInt(map[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _pickDateFromProfileList(Map<String, dynamic> body, List<String> words) {
    final profileRaw = body['profileList'];
    if (profileRaw is! List) {
      return null;
    }
    for (final raw in profileRaw) {
      final map = _asMap(raw);
      if (map.isEmpty) {
        continue;
      }
      final title = _pickString(map, <String>['title', 'type']);
      if (title.isEmpty || !words.any((word) => title.contains(word))) {
        continue;
      }
      final data = '${map['data'] ?? ''}'.trim();
      if (data.isEmpty) {
        continue;
      }
      final rawInt = _asInt(data);
      if (rawInt != null) {
        return rawInt;
      }
      final match = RegExp(r'\d{10,13}').firstMatch(data);
      if (match != null) {
        return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  DateTime? _millisOrSecondsToDate(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    final isMillis = value > 1000000000000;
    return DateTime.fromMillisecondsSinceEpoch(isMillis ? value : value * 1000);
  }
}

class _QingFollowTotals {
  const _QingFollowTotals({
    required this.followingCount,
    required this.followersCount,
  });

  final int? followingCount;
  final int? followersCount;
}

class _QingActivityTotals {
  const _QingActivityTotals({
    required this.topicCount,
    required this.replyCount,
    required this.favoriteCount,
  });

  final int? topicCount;
  final int? replyCount;
  final int? favoriteCount;
}

part of 'riverside_api_client.dart';

extension RiverSideApiClientNotificationMethods on RiverSideApiClient {
  Future<RiverSideNotificationPage> fetchNotificationsPage({
    String? cookieHeader,
    String? loadMorePath,
  }) async {
    final cookie = cookieHeader?.trim() ?? '';
    if (cookie.isEmpty) {
      return const RiverSideNotificationPage(
        items: <RiverSideNotificationItem>[],
        totalRows: null,
        seenNotificationId: null,
        loadMorePath: '',
      );
    }

    final response = await http.get(
      _resolveNotificationsUri(loadMorePath),
      headers: <String, String>{
        ..._buildJsonHeaders(cookieHeader: cookie),
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': riverSideBaseUrl,
      },
    );

    if (response.statusCode == 403) {
      final message = _extractErrorMessageFromResponse(response).trim();
      throw RiverSideApiException(
        message.isEmpty ? 'Login session expired. Please sign in again.' : message,
      );
    }
    if (response.statusCode != 200) {
      final message = _extractErrorMessageFromResponse(response).trim();
      throw RiverSideApiException(
        message.isEmpty
            ? 'Failed to load notifications, HTTP ${response.statusCode}'
            : message,
      );
    }

    final decoded = _decodeJsonObject(
      response,
      fallbackMessage: 'Invalid notifications response format',
    );
    return _parseNotificationsPage(decoded);
  }

  Future<List<RiverSideNotificationItem>> fetchNotifications({
    String? cookieHeader,
  }) async {
    final page = await fetchNotificationsPage(cookieHeader: cookieHeader);
    return page.items;
  }

  Future<void> markNotificationsAsRead({
    String? cookieHeader,
    int? notificationId,
  }) async {
    final cookie = cookieHeader?.trim() ?? '';
    if (cookie.isEmpty) {
      throw const RiverSideApiException('Cookie header is empty.');
    }

    final csrf = await fetchSessionCsrfToken(cookieHeader: cookie);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Cookie': cookie,
      'X-CSRF-Token': csrf,
      'X-Requested-With': 'XMLHttpRequest',
      'Origin': riverSideBaseUrl,
      'Referer': '$riverSideBaseUrl/',
    };
    final body = notificationId == null
        ? <String, String>{}
        : <String, String>{'id': '$notificationId'};

    var response = await http.put(
      Uri.parse('$riverSideBaseUrl/notifications/mark-read.json'),
      headers: headers,
      body: body,
      encoding: utf8,
    );
    if (response.statusCode == 404) {
      response = await http.put(
        Uri.parse('$riverSideBaseUrl/notifications/read.json'),
        headers: headers,
        body: body,
        encoding: utf8,
      );
    }

    if (response.statusCode == 403) {
      throw const RiverSideApiException(
        'Login session expired. Please sign in again.',
      );
    }
    if (response.statusCode != 200) {
      throw RiverSideApiException(
        'Failed to mark notifications as read, HTTP ${response.statusCode}',
      );
    }

    final decoded = _decodeJsonObject(
      response,
      fallbackMessage: 'Invalid mark notification response format',
    );
    final success = (decoded['success'] ?? '').toString().trim().toUpperCase();
    if (success.isNotEmpty && success != 'OK') {
      throw const RiverSideApiException('Failed to mark notification as read.');
    }
  }

  RiverSideNotificationPage _parseNotificationsPage(
    Map<String, dynamic> decoded,
  ) {
    final notificationsRaw = decoded['notifications'];
    final totalRows = _asInt(decoded['total_rows_notifications']);
    final loadMorePathRaw = _sanitizeLoadMorePath(
      decoded['load_more_notifications'],
    );
    final loadMorePath = _ensureOffsetInNotificationsPath(loadMorePathRaw);
    if (notificationsRaw is! List) {
      return RiverSideNotificationPage(
        items: const <RiverSideNotificationItem>[],
        totalRows: totalRows,
        seenNotificationId: _asInt(decoded['seen_notification_id']),
        loadMorePath: loadMorePath,
      );
    }

    final result = <RiverSideNotificationItem>[];
    for (final raw in notificationsRaw) {
      final item = _toStringMap(raw);
      final id = _asInt(item['id']) ?? 0;
      if (id <= 0) {
        continue;
      }

      final data = _toStringMap(item['data']);
      final type = _asInt(item['notification_type']) ?? 0;
      final topicId = _asInt(item['topic_id']);
      final badgeName = _firstNonEmpty(<dynamic>[data['badge_name']]);
      final username = _firstNonEmpty(<dynamic>[
        data['display_name'],
        data['display_username'],
        data['username'],
        data['original_username'],
      ]);
      final count = _asInt(data['count']) ?? 0;

      final title = _firstNonEmpty(<dynamic>[
        data['topic_title'],
        data['fancy_title'],
        data['title'],
        data['original_post_title'],
        item['fancy_title'],
        badgeName.isEmpty ? '' : '徽章：$badgeName',
        username,
        topicId == null ? '' : 'Topic #$topicId',
        'Notification #$id',
      ]);
      final actionText = _buildNotificationActionLine(
        type: type,
        username: username,
        badgeName: badgeName,
        count: count,
      );
      final excerpt = _firstNonEmpty(<dynamic>[
        data['excerpt'],
        data['message'],
        actionText,
        data['display_username'],
        badgeName,
      ]);

      result.add(
        RiverSideNotificationItem(
          id: id,
          type: type,
          read: _asBool(item['read']),
          highPriority: _asBool(item['high_priority']),
          createdAt: DateTime.tryParse((item['created_at'] ?? '').toString()),
          topicId: topicId,
          postNumber: _asInt(item['post_number']),
          slug: (item['slug'] ?? '').toString().trim(),
          title: _sanitizeExcerpt(title),
          excerpt: _sanitizeExcerpt(excerpt),
          username: _sanitizeExcerpt(username),
          actionText: _sanitizeExcerpt(actionText),
          badgeName: _sanitizeExcerpt(badgeName),
          count: count,
          avatarUrl: _normalizeAvatarUrl(
            _firstNonEmpty(<dynamic>[
              data['avatar_template'],
              data['user_avatar_template'],
            ]),
          ),
        ),
      );
    }

    final fallbackLoadMorePath =
        (loadMorePath.isEmpty && totalRows != null && totalRows > result.length)
        ? _buildFallbackNotificationsLoadMorePath(offset: 60)
        : loadMorePath;

    return RiverSideNotificationPage(
      items: result,
      totalRows: totalRows,
      seenNotificationId: _asInt(decoded['seen_notification_id']),
      loadMorePath: fallbackLoadMorePath,
    );
  }

  Uri _resolveNotificationsUri(String? loadMorePath) {
    var path = _ensureOffsetInNotificationsPath(loadMorePath?.trim() ?? '');
    if (path.isEmpty) {
      return Uri.parse('$riverSideBaseUrl/notifications.json');
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    if (path.startsWith('/')) {
      return Uri.parse('$riverSideBaseUrl$path');
    }
    return Uri.parse('$riverSideBaseUrl/$path');
  }

  String _sanitizeLoadMorePath(dynamic raw) {
    final text = '$raw'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return '';
    }
    return text;
  }

  String _ensureOffsetInNotificationsPath(String path) {
    final raw = path.trim();
    if (raw.isEmpty) {
      return '';
    }

    Uri? uri;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      uri = Uri.tryParse(raw);
    } else if (raw.startsWith('/')) {
      uri = Uri.tryParse('$riverSideBaseUrl$raw');
    } else {
      uri = Uri.tryParse('$riverSideBaseUrl/$raw');
    }

    if (uri == null) {
      return raw;
    }

    final query = Map<String, String>.from(uri.queryParameters);
    if (query['offset'] == null || query['offset']!.trim().isEmpty) {
      query['offset'] = '60';
    }

    return uri.replace(queryParameters: query).toString();
  }

  String _buildFallbackNotificationsLoadMorePath({required int offset}) {
    return '/notifications.json?filter=all&limit=60&offset=$offset';
  }

  String _buildNotificationActionLine({
    required int type,
    required String username,
    required String badgeName,
    required int count,
  }) {
    final prefix = username.isEmpty ? '' : '@$username ';
    final countPrefix = count > 1 ? '$count 人' : prefix;
    switch (type) {
      case 1:
        return '$prefix提到了你';
      case 2:
        return '$countPrefix回复了你';
      case 3:
        return '$prefix引用了你';
      case 4:
        return '$prefix编辑了相关内容';
      case 5:
        return '$countPrefix点赞了你';
      case 6:
        return '$prefix给你发来了私信';
      case 9:
        return '$prefix发布了新帖';
      case 10:
        return '你关注的分类/标签有新动态';
      case 11:
        return '新功能通知';
      case 12:
      case 15:
        return badgeName.isEmpty
            ? '你获得了徽章'
            : '你获得了徽章：$badgeName';
      case 13:
      case 16:
        return '$prefix邀请你参与话题';
      case 14:
        return '$prefix提及了你的内容';
      case 18:
        return '$prefix在组内提到了你';
      case 36:
        return '系统通知';
      case 800:
        return '$prefix关注了你';
      case 801:
        return '$prefix发布了新帖';
      default:
        return prefix.isEmpty
            ? '新通知'
            : '$prefix发来了通知';
    }
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = '$candidate'.trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }
}

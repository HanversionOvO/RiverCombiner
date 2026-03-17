part of 'riverside_api_client.dart';

extension RiverSideApiClientParsingMethods on RiverSideApiClient {
  RiverSideTopicPostDetail? _parseTopicPost(
    dynamic rawPost, {
    required int topicId,
  }) {
    final post = _toStringMap(rawPost);
    if (post.isEmpty) {
      return null;
    }

    final id = _asInt(post['id']);
    final postNumber = _asInt(post['post_number']);
    final postType = _asInt(post['post_type']) ?? 1;
    final actionCode = (post['action_code'] ?? '').toString().trim();
    final authorUserId = _asInt(post['user_id']);
    if (id == null || postNumber == null) {
      return null;
    }

    final username = (post['username'] ?? '').toString().trim();
    final displayUsername = (post['display_username'] ?? '').toString().trim();
    final name = (post['name'] ?? '').toString().trim();
    final displayName = displayUsername.isNotEmpty
        ? displayUsername
        : (name.isNotEmpty
              ? name
              : (username.isEmpty ? '未知用户' : username));
    final avatarTemplate = (post['avatar_template'] ?? '').toString();
    final authorTitle = (post['user_title'] ?? post['primary_group_name'] ?? '')
        .toString()
        .trim();
    final createdAt = DateTime.tryParse((post['created_at'] ?? '').toString());
    final version = _asInt(post['version']) ?? 1;
    final editCount = version > 1 ? version - 1 : 0;
    final rawMarkdown = (post['raw'] ?? '').toString().trim();
    final cooked = (post['cooked'] ?? '').toString();
    final resolvedRawMarkdown = _resolveUploadMarkdown(
      rawMarkdown: rawMarkdown,
      cookedHtml: cooked,
      uploadsRaw: post['uploads'],
    );
    final votedOptionIdsByPoll = _parsePollVotesMap(post['polls_votes']);
    final polls = _extractTopicPolls(
      post['polls'],
      canVote: true,
      votedOptionIdsByPoll: votedOptionIdsByPoll,
    );
    final canVotePoll = polls.any((item) => item.canVote);
    final reactions = _extractPostReactions(post['reactions']);
    final currentUserReaction = _extractCurrentUserReaction(
      post['current_user_reaction'],
    );
    final reactionUsersCount = _asInt(post['reaction_users_count']) ?? 0;
    final replyToPostNumber = _asInt(post['reply_to_post_number']);
    final replyToUserMap = _toStringMap(post['reply_to_user']);
    final replyToUsername =
        (post['reply_to_username'] ??
                post['reply_to_user_username'] ??
                replyToUserMap['username'] ??
                '')
            .toString()
            .trim();

    final onlineValue = post['online'];
    final isOnline = onlineValue is bool
        ? onlineValue
        : (onlineValue is String ? onlineValue.toLowerCase() == 'true' : null);
    final actionDescription = _resolvePostActionDescription(
      postType: postType,
      actionCode: actionCode,
      rawMarkdown: resolvedRawMarkdown,
      cooked: cooked,
    );
    final normalizedMarkdown = _normalizePostRawMarkdown(
      actionDescription.isNotEmpty
          ? actionDescription
          : (resolvedRawMarkdown.isNotEmpty
                ? resolvedRawMarkdown
                : _cookHtmlToMarkdown(cooked)),
    );

    return RiverSideTopicPostDetail(
      id: id,
      topicId: topicId,
      postNumber: postNumber,
      postType: postType,
      actionCode: actionCode,
      actionDescription: actionDescription,
      authorUserId: authorUserId,
      authorUsername: username,
      authorDisplayName: displayName,
      authorAvatarUrl: _normalizeAvatarUrl(avatarTemplate),
      authorTitle: authorTitle,
      isOnline: isOnline,
      contentMarkdown: normalizedMarkdown,
      contentCookedHtml: cooked.trim(),
      createdAt: createdAt,
      editCount: editCount,
      likeCount: _extractLikeCount(post['actions_summary']),
      reactions: reactions,
      currentUserReaction: currentUserReaction,
      reactionUsersCount: reactionUsersCount,
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      polls: polls,
      canVotePoll: canVotePoll,
    );
  }

  RiverSideTopicPostDetail? _parsePostFromPayload(
    Map<String, dynamic> payload,
  ) {
    final directTopicId = _asInt(payload['topic_id']);
    final direct = _parseTopicPost(payload, topicId: directTopicId ?? 0);
    if (direct != null) {
      return direct;
    }

    final nested = _toStringMap(payload['post']);
    if (nested.isEmpty) {
      return null;
    }
    final nestedTopicId = _asInt(nested['topic_id']) ?? directTopicId ?? 0;
    return _parseTopicPost(nested, topicId: nestedTopicId);
  }

  String _normalizeAvatarUrl(String template) {
    if (template.isEmpty) {
      return '';
    }

    final path = template.replaceAll('{size}', '120');
    if (path.startsWith('https://') || path.startsWith('http://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return 'https:$path';
    }
    if (path.startsWith('/')) {
      return '$riverSideBaseUrl$path';
    }
    return '$riverSideBaseUrl/$path';
  }

  Map<String, String> _buildJsonHeaders({
    String? cookieHeader,
    String? userApiKey,
    String? userApiClientId,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    final cookie = cookieHeader?.trim();
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    final key = userApiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['User-Api-Key'] = key;
    }
    final clientId = userApiClientId?.trim();
    if (clientId != null && clientId.isNotEmpty) {
      headers['User-Api-Client-Id'] = clientId;
    }
    return headers;
  }

  String _categoryCacheKey({
    String? cookieHeader,
    String? userApiKey,
    String? userApiClientId,
  }) {
    final cookie = cookieHeader?.trim();
    final key = userApiKey?.trim();
    final clientId = userApiClientId?.trim();
    if (cookie == null || cookie.isEmpty) {
      if (key == null || key.isEmpty) {
        return 'guest';
      }
      return 'ua:$key/$clientId';
    }
    return cookie;
  }

  Map<String, dynamic> _decodeJsonObject(
    http.Response response, {
    required String fallbackMessage,
  }) {
    final body = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw RiverSideApiException(fallbackMessage);
    }
    return decoded;
  }

  Map<int, Map<String, dynamic>> _extractUsersById(dynamic usersRaw) {
    if (usersRaw is! List) {
      return const <int, Map<String, dynamic>>{};
    }

    final result = <int, Map<String, dynamic>>{};
    for (final rawUser in usersRaw) {
      final user = _toStringMap(rawUser);
      final id = _asInt(user['id']);
      if (id != null) {
        result[id] = user;
      }
    }
    return result;
  }

  Map<int, String> _extractCategoryNamesFromTopicPayload(
    Map<String, dynamic> decoded,
  ) {
    final topicList = _toStringMap(decoded['topic_list']);
    final categoriesRaw = topicList['categories'];
    if (categoriesRaw is! List) {
      return const <int, String>{};
    }

    final categoryById = <int, Map<String, dynamic>>{};
    for (final raw in categoriesRaw) {
      final category = _toStringMap(raw);
      final id = _asInt(category['id']);
      if (id == null) {
        continue;
      }
      categoryById[id] = category;
    }

    if (categoryById.isEmpty) {
      return const <int, String>{};
    }

    final names = <int, String>{};
    for (final entry in categoryById.entries) {
      final id = entry.key;
      final category = entry.value;
      final name = (category['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }

      final parentId = _asInt(category['parent_category_id']);
      if (parentId == null || !categoryById.containsKey(parentId)) {
        names[id] = name;
        continue;
      }

      final parentName = (categoryById[parentId]!['name'] ?? '')
          .toString()
          .trim();
      names[id] = parentName.isEmpty ? name : '$parentName / $name';
    }

    return names;
  }

  int? _findPrimaryPosterUserId(dynamic postersRaw) {
    if (postersRaw is List) {
      for (final rawPoster in postersRaw) {
        final poster = _toStringMap(rawPoster);
        final description = (poster['description'] ?? '').toString();
        if (description.contains('Original Poster') ||
            description.contains('原始')) {
          return _asInt(poster['user_id']);
        }
      }

      for (final rawPoster in postersRaw) {
        final poster = _toStringMap(rawPoster);
        final id = _asInt(poster['user_id']);
        if (id != null) {
          return id;
        }
      }
    }

    if (postersRaw is Map) {
      return _asInt(postersRaw['user_id']);
    }

    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  List<int> _asIntList(dynamic value) {
    if (value is! List) {
      return const <int>[];
    }
    final result = <int>[];
    for (final item in value) {
      final number = _asInt(item);
      if (number != null) {
        result.add(number);
      }
    }
    return result;
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  Map<String, dynamic> _toStringMap(dynamic value) {
    if (value is! Map) {
      return const <String, dynamic>{};
    }
    return value.map((key, item) => MapEntry('$key', item));
  }

  String _sanitizeExcerpt(String source) {
    if (source.isEmpty) {
      return '';
    }

    return source
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&hellip;', '...')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  String _cookHtmlToMarkdown(String source) {
    if (source.isEmpty) {
      return '';
    }

    final markdown = html2md.convert(source).trim();
    if (markdown.isEmpty) {
      return _sanitizeCookedAsPlainText(source);
    }

    return markdown.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _extractErrorMessageFromResponse(http.Response response) {
    try {
      final decoded = _decodeJsonObject(
        response,
        fallbackMessage: 'Invalid error response format',
      );

      final errorsRaw = decoded['errors'];
      if (errorsRaw is List) {
        final errors = errorsRaw.map((it) => '$it'.trim()).where((it) {
          return it.isNotEmpty;
        }).toList();
        if (errors.isNotEmpty) {
          return errors.join('\n');
        }
      }

      final candidates = <dynamic>[
        decoded['message'],
        decoded['error'],
        decoded['error_type'],
      ];
      for (final candidate in candidates) {
        final text = '$candidate'.trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  int _extractLikeCount(dynamic actionsSummaryRaw) {
    if (actionsSummaryRaw is! List) {
      return 0;
    }

    for (final rawAction in actionsSummaryRaw) {
      final action = _toStringMap(rawAction);
      final id = _asInt(action['id']);
      if (id == 2) {
        return _asInt(action['count']) ?? 0;
      }
    }

    return 0;
  }

  String _normalizePostRawMarkdown(String source) {
    if (source.trim().isEmpty) {
      return '';
    }
    var normalized = source.replaceAll('\r\n', '\n');
    normalized = normalized.replaceAll('\r', '\n');
    normalized = _stripPollBlocks(normalized);
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return normalized;
  }

  String _resolvePostActionDescription({
    required int postType,
    required String actionCode,
    required String rawMarkdown,
    required String cooked,
  }) {
    final normalizedCode = actionCode.trim().toLowerCase();
    const actionLabelByCode = <String, String>{
      'pinned_globally.enabled': '全站置顶',
      'pinned_globally.disabled': '取消全站置顶',
      'pinned.enabled': '置顶',
      'pinned.disabled': '取消置顶',
      'closed.enabled': '关闭',
      'closed.disabled': '重新开放',
      'archived.enabled': '归档',
      'archived.disabled': '取消归档',
      'unlisted.enabled': '取消公开',
      'unlisted.disabled': '恢复公开',
      'visible.enabled': '恢复公开',
      'visible.disabled': '取消公开',
    };
    final codeLabel = actionLabelByCode[normalizedCode];
    if (codeLabel != null && codeLabel.isNotEmpty) {
      return codeLabel;
    }
    if (postType != 3 && normalizedCode.isEmpty) {
      return '';
    }

    final cookedPlain = _sanitizeExcerpt(cooked);
    if (cookedPlain.isNotEmpty) {
      final stripped = _stripLeadingRelativeTimePrefix(cookedPlain);
      if (stripped.isNotEmpty) {
        return stripped;
      }
    }

    final rawPlain = rawMarkdown.trim();
    if (rawPlain.isNotEmpty) {
      final stripped = _stripLeadingRelativeTimePrefix(rawPlain);
      if (stripped.isNotEmpty) {
        return stripped;
      }
    }

    if (normalizedCode.isNotEmpty) {
      return '系统操作：${normalizedCode.replaceAll('.', ' · ')}';
    }
    return '';
  }

  String _stripLeadingRelativeTimePrefix(String source) {
    var text = source.trim();
    if (text.isEmpty) {
      return '';
    }
    final patterns = <RegExp>[
      RegExp(r'^\d+\s*秒前\s*'),
      RegExp(r'^\d+\s*分钟前\s*'),
      RegExp(r'^\d+\s*小时前\s*'),
      RegExp(r'^\d+\s*天前\s*'),
      RegExp(r'^\d+\s*周前\s*'),
      RegExp(r'^\d+\s*月前\s*'),
      RegExp(r'^\d+\s*年前\s*'),
      RegExp(
        r'^\d+\s*(second|minute|hour|day|week|month|year)s?\s+ago\s*',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      text = text.replaceFirst(pattern, '').trim();
    }
    return text;
  }

  String _stripPollBlocks(String source) {
    if (source.trim().isEmpty) {
      return '';
    }
    return source.replaceAll(
      RegExp(r'\[poll[^\]]*\][\s\S]*?\[/poll\]', caseSensitive: false),
      '',
    );
  }

  List<RiverSideTopicPoll> _extractTopicPolls(
    dynamic rawPolls, {
    required bool canVote,
    Map<String, Set<String>> votedOptionIdsByPoll =
        const <String, Set<String>>{},
  }) {
    if (rawPolls is! List) {
      return const <RiverSideTopicPoll>[];
    }
    final polls = <RiverSideTopicPoll>[];
    for (final rawPoll in rawPolls) {
      final parsed = _parseTopicPoll(
        rawPoll,
        canVote: canVote,
        votedOptionIdsByPoll: votedOptionIdsByPoll,
      );
      if (parsed != null) {
        polls.add(parsed);
      }
    }
    return polls;
  }

  RiverSideTopicPoll? _parseTopicPoll(
    dynamic rawPoll, {
    required bool canVote,
    Map<String, Set<String>> votedOptionIdsByPoll =
        const <String, Set<String>>{},
  }) {
    final poll = _toStringMap(rawPoll);
    if (poll.isEmpty) {
      return null;
    }
    final pollId = _asInt(poll['id']) ?? 0;
    final pollName = (poll['name'] ?? '').toString().trim();
    final optionsRaw = poll['options'];
    if (pollName.isEmpty || optionsRaw is! List) {
      return null;
    }
    final selectedOptionIds = votedOptionIdsByPoll[pollName] ?? <String>{};
    final preloadedVotersByOptionId = _parsePollPreloadedVoters(
      poll['preloaded_voters'],
    );
    final options = <RiverSideTopicPollOption>[];
    for (final rawOption in optionsRaw) {
      final option = _toStringMap(rawOption);
      if (option.isEmpty) {
        continue;
      }
      final optionId = (option['id'] ?? '').toString().trim();
      if (optionId.isEmpty) {
        continue;
      }
      options.add(
        RiverSideTopicPollOption(
          id: optionId,
          html: (option['html'] ?? option['title'] ?? '').toString(),
          votes: _asInt(option['votes']) ?? 0,
          selected:
              selectedOptionIds.contains(optionId) ||
              _asBool(option['selected']) ||
              _asBool(option['is_selected']) ||
              _asBool(option['is_chosen']) ||
              _asBool(option['chosen']),
          voters:
              preloadedVotersByOptionId[optionId] ??
              const <RiverSideTopicPollVoter>[],
        ),
      );
    }
    if (options.isEmpty) {
      return null;
    }

    final status = (poll['status'] ?? '').toString().trim();
    final isOpen = status.toLowerCase() == 'open';
    return RiverSideTopicPoll(
      id: pollId,
      name: pollName,
      title: (poll['title'] ?? '').toString().trim(),
      type: (poll['type'] ?? '').toString().trim(),
      status: status,
      public: _asBool(poll['public']),
      dynamic: _asBool(poll['dynamic']),
      results: (poll['results'] ?? '').toString().trim(),
      chartType: (poll['chart_type'] ?? '').toString().trim(),
      voters: _asInt(poll['voters']) ?? 0,
      options: options,
      canVote:
          canVote &&
          isOpen &&
          !_asBool(poll['closed']) &&
          !_asBool(poll['readonly']),
    );
  }

  Map<String, Set<String>> _parsePollVotesMap(dynamic rawVotes) {
    if (rawVotes is! Map) {
      return const <String, Set<String>>{};
    }
    final result = <String, Set<String>>{};
    rawVotes.forEach((key, value) {
      final pollName = '$key'.trim();
      if (pollName.isEmpty) {
        return;
      }
      final ids = _asStringList(value).map((item) => item.trim()).where((item) {
        return item.isNotEmpty;
      }).toSet();
      if (ids.isNotEmpty) {
        result[pollName] = ids;
      }
    });
    return result;
  }

  List<String> _asStringList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw.map((item) => '$item').toList(growable: false);
  }

  Map<String, List<RiverSideTopicPollVoter>> _parsePollPreloadedVoters(
    dynamic rawPreloadedVoters,
  ) {
    if (rawPreloadedVoters is! Map) {
      return const <String, List<RiverSideTopicPollVoter>>{};
    }
    final byOptionId = <String, List<RiverSideTopicPollVoter>>{};
    rawPreloadedVoters.forEach((key, value) {
      final optionId = '$key'.trim();
      if (optionId.isEmpty || value is! List) {
        return;
      }
      final voters = <RiverSideTopicPollVoter>[];
      for (final rawUser in value) {
        final user = _toStringMap(rawUser);
        if (user.isEmpty) {
          continue;
        }
        final username = (user['username'] ?? '').toString().trim();
        if (username.isEmpty) {
          continue;
        }
        final displayNameRaw = (user['name'] ?? '').toString().trim();
        final displayName = displayNameRaw.isEmpty ? username : displayNameRaw;
        voters.add(
          RiverSideTopicPollVoter(
            id: _asInt(user['id']) ?? 0,
            username: username,
            displayName: displayName,
            avatarUrl: _normalizeAvatarUrl(
              (user['avatar_template'] ?? '').toString(),
            ),
            title: (user['title'] ?? '').toString().trim(),
          ),
        );
      }
      byOptionId[optionId] = voters;
    });
    return byOptionId;
  }
}


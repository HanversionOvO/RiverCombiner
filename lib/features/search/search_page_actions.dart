part of 'search_page.dart';

extension _SearchPageActions on _SearchPageState {
  void _onKeywordFocusChanged() {
    _mutateState(() {
      _keywordFocused = _keywordFocusNode.hasFocus;
    });
    if (_keywordFocused) {
      _scheduleSuggestionQuery(immediate: true);
    } else {
      _suggestionDebounce?.cancel();
    }
  }

  void _onKeywordInputChanged(String _) {
    _mutateState(() {});
    _scheduleSuggestionQuery();
  }

  void _scheduleSuggestionQuery({bool immediate = false}) {
    if (_searchMode == _SearchMode.miniApps) {
      _clearSuggestionState();
      return;
    }
    _suggestionDebounce?.cancel();
    final query = _keywordController.text.trim();
    if (query.isEmpty) {
      _clearSuggestionState();
      return;
    }
    if (!_keywordFocused && !immediate) {
      return;
    }
    if (immediate) {
      unawaited(_fetchSuggestions(query));
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_fetchSuggestions(query));
    });
  }

  void _clearSuggestionState() {
    _suggestionSerial++;
    _mutateState(() {
      _loadingSuggestions = false;
      _keywordSuggestions = const <String>[];
      _postSuggestions = const <RiverSidePostSearchItem>[];
      _userSuggestions = const <RiverSideUserSearchItem>[];
    });
  }

  List<String> _buildKeywordSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <String>[];
    }
    final startsWith = <String>[];
    final contains = <String>[];
    for (final keyword in _recentSearches) {
      final item = keyword.trim();
      if (item.isEmpty) {
        continue;
      }
      final lower = item.toLowerCase();
      if (lower == normalized) {
        startsWith.insert(0, item);
        continue;
      }
      if (lower.startsWith(normalized)) {
        startsWith.add(item);
      } else if (lower.contains(normalized)) {
        contains.add(item);
      }
    }
    return <String>[...startsWith, ...contains].take(6).toList(growable: false);
  }

  bool _isSuggestionStale({required int serial, required String query}) {
    if (!mounted || serial != _suggestionSerial) {
      return true;
    }
    return _keywordController.text.trim() != query;
  }

  Future<void> _fetchSuggestions(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      _clearSuggestionState();
      return;
    }
    final serial = ++_suggestionSerial;
    final keywordSuggestions = _buildKeywordSuggestions(normalized);
    _mutateState(() {
      _loadingSuggestions = true;
      _keywordSuggestions = keywordSuggestions;
    });
    try {
      List<RiverSidePostSearchItem> postSuggestions =
          const <RiverSidePostSearchItem>[];
      List<RiverSideUserSearchItem> userSuggestions =
          const <RiverSideUserSearchItem>[];
      switch (_searchMode) {
        case _SearchMode.posts:
          if (_searchProvider == AccountProvider.qingShuiHePan) {
            final page = await _searchQingPosts(query: normalized, page: 1);
            postSuggestions = page.items.take(6).toList(growable: false);
          } else {
            final page = await widget
                .dependencies
                .accountStore
                .riverSideApiClient
                .searchPosts(
                  query: normalized,
                  page: 1,
                  cookieHeader: _activeCookieHeader(),
                );
            postSuggestions = page.items.take(6).toList(growable: false);
          }
          break;
        case _SearchMode.users:
          if (_searchProvider == AccountProvider.qingShuiHePan) {
            final users = await _searchQingUsers(term: normalized, limit: 8);
            userSuggestions = users.take(8).toList(growable: false);
          } else {
            final users = await widget
                .dependencies
                .accountStore
                .riverSideApiClient
                .searchUsers(
                  term: normalized,
                  limit: 8,
                  cookieHeader: _activeCookieHeader(),
                );
            userSuggestions = users.take(8).toList(growable: false);
          }
          break;
        case _SearchMode.miniApps:
          break;
      }
      if (_isSuggestionStale(serial: serial, query: normalized)) {
        return;
      }
      _mutateState(() {
        _loadingSuggestions = false;
        _keywordSuggestions = keywordSuggestions;
        _postSuggestions = postSuggestions;
        _userSuggestions = userSuggestions;
      });
    } catch (_) {
      if (_isSuggestionStale(serial: serial, query: normalized)) {
        return;
      }
      _mutateState(() {
        _loadingSuggestions = false;
        _keywordSuggestions = keywordSuggestions;
        _postSuggestions = const <RiverSidePostSearchItem>[];
        _userSuggestions = const <RiverSideUserSearchItem>[];
      });
    }
  }

  void _onAccountStoreChanged() {
    final riverCurrent =
        widget.dependencies.accountStore.activeRiverSideUsername;
    final qingCurrent =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    final riverChanged = riverCurrent != _lastActiveRiverSideUsername;
    final qingChanged = qingCurrent != _lastActiveQingShuiHePanUsername;
    if (!riverChanged && !qingChanged) {
      return;
    }
    _lastActiveRiverSideUsername = riverCurrent;
    _lastActiveQingShuiHePanUsername = qingCurrent;
    if (_searchProvider == AccountProvider.riverSide) {
      _loadRecentSearches();
    }
    if (_searchMode == _SearchMode.miniApps) {
      unawaited(_loadMiniAppCatalog(forceRefresh: true));
    }
    if (_activeQuery.isNotEmpty) {
      final shouldRefresh =
          (_searchProvider == AccountProvider.riverSide && riverChanged) ||
          (_searchProvider == AccountProvider.qingShuiHePan && qingChanged);
      if (shouldRefresh) {
        _runSearch(reset: true);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final shouldShowBackToTop =
        _scrollController.offset >= _SearchPageState._showBackToTopOffset;
    if (_showBackToTop.value != shouldShowBackToTop) {
      _showBackToTop.value = shouldShowBackToTop;
    }

    if (_searchMode != _SearchMode.posts) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >=
        position.maxScrollExtent - _SearchPageState._loadMoreTriggerOffset) {
      _loadMorePosts();
    }
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

  String? _activeCookieHeader() {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(username);
  }

  QingShuiHePanAuth? _activeQingAuth() {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername ?? '';
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.qingShuiHePanAuthFor(normalized);
  }

  String _needLoginLabel() {
    return _searchProvider == AccountProvider.qingShuiHePan
        ? _SearchPageState._labelNeedQingShuiHePanLogin
        : _SearchPageState._labelNeedRiverSideLogin;
  }

  Future<void> _loadRecentSearches() async {
    if (_searchProvider != AccountProvider.riverSide) {
      _mutateState(() {
        _recentSearches = const <String>[];
        _loadingRecentSearches = false;
      });
      return;
    }
    if (_loadingRecentSearches) {
      return;
    }

    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      _mutateState(() {
        _recentSearches = const <String>[];
        _loadingRecentSearches = false;
      });
      return;
    }

    _mutateState(() {
      _loadingRecentSearches = true;
    });

    try {
      final recent = await widget.dependencies.accountStore.riverSideApiClient
          .fetchRecentSearches(cookieHeader: cookieHeader);
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _recentSearches = recent;
      });
      if (_keywordFocused && _keywordController.text.trim().isNotEmpty) {
        _scheduleSuggestionQuery(immediate: true);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      // Keep UI resilient: recent-search endpoint can fail independently.
    } finally {
      _mutateState(() {
        _loadingRecentSearches = false;
      });
    }
  }

  Future<void> _clearRecentSearches() async {
    if (_searchProvider != AccountProvider.riverSide) {
      _showSnackBar('清水河畔暂不支持云端搜索历史');
      return;
    }
    if (_clearingRecentSearches) {
      return;
    }

    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      _showSnackBar(_needLoginLabel());
      return;
    }

    _mutateState(() {
      _clearingRecentSearches = true;
    });

    try {
      await widget.dependencies.accountStore.riverSideApiClient
          .clearRecentSearches(cookieHeader: cookieHeader);
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _recentSearches = const <String>[];
      });
      _showSnackBar(_SearchPageState._labelClearRecentSuccess);
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar(_SearchPageState._labelSearchFailed);
    } finally {
      _mutateState(() {
        _clearingRecentSearches = false;
      });
    }
  }

  Future<void> _runSearch({required bool reset}) async {
    final query = _keywordController.text.trim();
    if (query.isEmpty) {
      _suggestionDebounce?.cancel();
      _mutateState(() {
        _activeQuery = '';
        _error = null;
        _loading = false;
        _loadingMorePosts = false;
        _hasMorePostPages = false;
        _currentPostPage = 0;
        _postItems = const <RiverSidePostSearchItem>[];
        _userItems = const <RiverSideUserSearchItem>[];
        _miniAppItems = const <RiverMiniAppEntry>[];
        _showBackToTop.value = false;
      });
      _clearSuggestionState();
      if (_searchMode == _SearchMode.miniApps) {
        await _loadMiniAppCatalog(forceRefresh: false);
      }
      await _loadRecentSearches();
      return;
    }

    if (!reset && (_searchMode != _SearchMode.posts || !_hasMorePostPages)) {
      return;
    }

    final targetQuery = reset ? query : _activeQuery;
    if (targetQuery.isEmpty) {
      return;
    }

    final nextPage = reset ? 1 : (_currentPostPage + 1);
    _keywordFocusNode.unfocus();
    _suggestionDebounce?.cancel();
    _clearSuggestionState();
    final serial = ++_requestSerial;
    _mutateState(() {
      _error = null;
      if (reset) {
        _loading = true;
        _activeQuery = targetQuery;
      } else {
        _loadingMorePosts = true;
      }
    });
    if (reset) {
      _showBackToTop.value = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }

    try {
      switch (_searchMode) {
        case _SearchMode.posts:
          final page = _searchProvider == AccountProvider.qingShuiHePan
              ? await _searchQingPosts(query: targetQuery, page: nextPage)
              : await widget.dependencies.accountStore.riverSideApiClient
                    .searchPosts(
                      query: targetQuery,
                      page: nextPage,
                      cookieHeader: _activeCookieHeader(),
                    );
          if (!mounted || serial != _requestSerial) {
            return;
          }
          final merged = reset
              ? page.items
              : <RiverSidePostSearchItem>[
                  ..._postItems,
                  ...page.items.where(
                    (item) => !_postItems.any(
                      (current) => current.topicId == item.topicId,
                    ),
                  ),
                ];
          _mutateState(() {
            _postItems = merged;
            _userItems = const <RiverSideUserSearchItem>[];
            _currentPostPage = page.page;
            _hasMorePostPages = page.hasMore;
            if (reset) {
              _resultAnimationEpoch++;
            }
          });
          break;
        case _SearchMode.users:
          final users = _searchProvider == AccountProvider.qingShuiHePan
              ? await _searchQingUsers(
                  term: targetQuery,
                  limit: _SearchPageState._userSearchLimit,
                )
              : await widget.dependencies.accountStore.riverSideApiClient
                    .searchUsers(
                      term: targetQuery,
                      limit: _SearchPageState._userSearchLimit,
                      cookieHeader: _activeCookieHeader(),
                    );
          if (!mounted || serial != _requestSerial) {
            return;
          }
          _mutateState(() {
            _userItems = users;
            _postItems = const <RiverSidePostSearchItem>[];
            _currentPostPage = 0;
            _hasMorePostPages = false;
            if (reset) {
              _resultAnimationEpoch++;
            }
          });
          break;
        case _SearchMode.miniApps:
          final items = await _miniAppRepository.search(
            manifestUrl:
                widget.dependencies.settingsController.miniAppsManifestUrl,
            query: targetQuery,
            cookieHeader: _activeCookieHeader(),
            limit: 40,
          );
          if (!mounted || serial != _requestSerial) {
            return;
          }
          _mutateState(() {
            _miniAppItems = items;
            _postItems = const <RiverSidePostSearchItem>[];
            _userItems = const <RiverSideUserSearchItem>[];
            _currentPostPage = 0;
            _hasMorePostPages = false;
            if (reset) {
              _resultAnimationEpoch++;
            }
          });
          break;
      }
    } on RiverSideApiException catch (error) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _mutateState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) {
        return;
      }
      _mutateState(() {
        _error = _SearchPageState._labelSearchFailed;
      });
    } finally {
      if (mounted && serial == _requestSerial) {
        _mutateState(() {
          _loading = false;
          _loadingMorePosts = false;
        });
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loading || _loadingMorePosts || !_hasMorePostPages) {
      return;
    }
    await _runSearch(reset: false);
  }

  void _onModeChanged(_SearchMode mode) {
    if (mode == _searchMode) {
      return;
    }
    _mutateState(() {
      _searchMode = mode;
      _error = null;
      _requestSerial++;
      _loading = false;
      _loadingMorePosts = false;
      _postItems = const <RiverSidePostSearchItem>[];
      _userItems = const <RiverSideUserSearchItem>[];
      _miniAppItems = const <RiverMiniAppEntry>[];
      _currentPostPage = 0;
      _hasMorePostPages = false;
      _showBackToTop.value = false;
      _loadingSuggestions = false;
      _keywordSuggestions = const <String>[];
      _postSuggestions = const <RiverSidePostSearchItem>[];
      _userSuggestions = const <RiverSideUserSearchItem>[];
    });
    if (mode == _SearchMode.miniApps) {
      unawaited(_loadMiniAppCatalog(forceRefresh: false));
    }
    if (_keywordController.text.trim().isNotEmpty) {
      if (_keywordFocused) {
        _scheduleSuggestionQuery(immediate: true);
      } else {
        _runSearch(reset: true);
      }
    }
  }

  void _onProviderChanged(AccountProvider provider) {
    if (provider == _searchProvider) {
      return;
    }
    _mutateState(() {
      _searchProvider = provider;
      _error = null;
      _requestSerial++;
      _loading = false;
      _loadingMorePosts = false;
      _postItems = const <RiverSidePostSearchItem>[];
      _userItems = const <RiverSideUserSearchItem>[];
      _currentPostPage = 0;
      _hasMorePostPages = false;
      _showBackToTop.value = false;
      _loadingSuggestions = false;
      _keywordSuggestions = const <String>[];
      _postSuggestions = const <RiverSidePostSearchItem>[];
      _userSuggestions = const <RiverSideUserSearchItem>[];
      _recentSearches = const <String>[];
    });
    if (_searchProvider == AccountProvider.riverSide) {
      unawaited(_loadRecentSearches());
    }
    if (_keywordController.text.trim().isNotEmpty) {
      if (_keywordFocused) {
        _scheduleSuggestionQuery(immediate: true);
      } else {
        unawaited(_runSearch(reset: true));
      }
    }
  }

  Future<void> _openTopicDetail(RiverSidePostSearchItem item) async {
    await Navigator.of(context).push(
      DraggableRoute<void>(
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: item.topicId,
          provider: _searchProvider,
          qingBoardId: _searchProvider == AccountProvider.qingShuiHePan
              ? item.boardId
              : null,
        ),
      ),
    );
  }

  Future<void> _openUserProfile(RiverSideUserSearchItem user) async {
    final account = UserAccount(
      provider: _searchProvider,
      userId: user.id <= 0 ? null : user.id,
      username: user.username,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
    );
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => RiverSideProfilePage(
          dependencies: widget.dependencies,
          account: account,
          cookieHeader: _searchProvider == AccountProvider.riverSide
              ? _activeCookieHeader()
              : null,
        ),
      ),
    );
  }

  void _applyRecentSearch(String keyword) {
    final text = keyword.trim();
    if (text.isEmpty) {
      return;
    }
    _keywordController.text = text;
    _keywordController.selection = TextSelection.collapsed(offset: text.length);
    _runSearch(reset: true);
  }

  void _applySuggestionKeyword(String keyword) {
    final text = keyword.trim();
    if (text.isEmpty) {
      return;
    }
    _keywordController.text = text;
    _keywordController.selection = TextSelection.collapsed(offset: text.length);
    _runSearch(reset: true);
  }

  Future<void> _onRefresh() async {
    if (_searchMode == _SearchMode.miniApps) {
      if (_activeQuery.isEmpty) {
        await _loadMiniAppCatalog(forceRefresh: true);
      } else {
        await _runSearch(reset: true);
      }
      return;
    }
    if (_activeQuery.isEmpty) {
      await _loadRecentSearches();
      return;
    }
    await _runSearch(reset: true);
  }

  Future<RiverSidePostSearchPage> _searchQingPosts({
    required String query,
    required int page,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return RiverSidePostSearchPage(
        items: const <RiverSidePostSearchItem>[],
        page: page,
        hasMore: false,
      );
    }
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException(
        _SearchPageState._labelNeedQingShuiHePanLogin,
      );
    }

    final safePage = page <= 0 ? 1 : page;
    final response = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'forum/search',
        'keyword': keyword,
        'page': '$safePage',
        'pageSize': '20',
      },
    );

    final listRaw = response['list'] ?? _asQingMap(response['body'])['list'];
    if (listRaw is! List) {
      return RiverSidePostSearchPage(
        items: const <RiverSidePostSearchItem>[],
        page: safePage,
        hasMore: false,
      );
    }

    final items = <RiverSidePostSearchItem>[];
    for (final raw in listRaw) {
      final item = _asQingMap(raw);
      if (item.isEmpty) {
        continue;
      }
      final topicId =
          _asQingInt(item['topic_id']) ?? _asQingInt(item['id']) ?? 0;
      if (topicId <= 0) {
        continue;
      }

      final boardId =
          _asQingInt(item['board_id']) ??
          _asQingInt(item['fid']) ??
          _asQingInt(item['forum_id']);
      final title = _sanitizeQingText(
        _pickQingString(item, const <String>['title', 'subject']),
      );
      final excerpt = _sanitizeQingText(
        _pickQingString(item, const <String>['summary', 'subject', 'content']),
      );
      final displayName = _pickQingString(item, const <String>[
        'user_nick_name',
        'nick_name',
        'name',
        'userName',
        'username',
      ]);
      final username = _pickQingString(item, const <String>[
        'user_name',
        'username',
        'userName',
      ]);
      final avatar = _resolveQingUrl(
        _pickQingString(item, const <String>['icon', 'avatar', 'userAvatar']),
      );
      final createdAt = _parseQingEpochDate(
        _asQingInt(item['last_reply_date']) ??
            _asQingInt(item['create_date']) ??
            _asQingInt(item['dateline']),
      );
      final categoryName = _pickQingString(item, const <String>[
        'board_name',
        'forum_name',
        'type_name',
      ]);

      items.add(
        RiverSidePostSearchItem(
          topicId: topicId,
          boardId: boardId,
          title: title.isEmpty ? '(无标题)' : title,
          excerpt: excerpt,
          authorUsername: username.isEmpty
              ? (displayName.isEmpty ? 'user_$topicId' : displayName)
              : username,
          authorDisplayName: displayName.isEmpty
              ? (username.isEmpty ? '未知用户' : username)
              : displayName,
          authorAvatarUrl: avatar,
          categoryName: categoryName.isEmpty ? '清水河畔' : categoryName,
          replyCount: _asQingInt(item['replies']) ?? 0,
          viewCount: _asQingInt(item['hits']) ?? 0,
          createdAt: createdAt,
        ),
      );
    }

    final hasMoreHint =
        _asQingBool(response['has_next']) ||
        _asQingBool(response['hasMore']) ||
        _asQingBool(_asQingMap(response['body'])['has_next']) ||
        _asQingBool(_asQingMap(response['body'])['hasMore']);
    final hasMore = hasMoreHint || items.length >= 20;
    return RiverSidePostSearchPage(
      items: items,
      page: safePage,
      hasMore: hasMore,
    );
  }

  Future<List<RiverSideUserSearchItem>> _searchQingUsers({
    required String term,
    int limit = 20,
  }) async {
    final keyword = term.trim();
    if (keyword.isEmpty) {
      return const <RiverSideUserSearchItem>[];
    }
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException(
        _SearchPageState._labelNeedQingShuiHePanLogin,
      );
    }
    final safeLimit = limit <= 0 ? 20 : limit;
    final response = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'user/searchuser',
        'keyword': keyword,
        'page': '1',
        'pageSize': '$safeLimit',
      },
    );

    final listRaw = response['list'] ?? _asQingMap(response['body'])['list'];
    if (listRaw is! List) {
      return const <RiverSideUserSearchItem>[];
    }

    final result = <RiverSideUserSearchItem>[];
    for (final raw in listRaw) {
      final item = _asQingMap(raw);
      if (item.isEmpty) {
        continue;
      }
      final userId =
          _asQingInt(item['uid']) ??
          _asQingInt(item['user_id']) ??
          _asQingInt(item['id']) ??
          0;
      final username = _pickQingString(item, const <String>[
        'username',
        'user_name',
        'userName',
        'name',
      ]);
      final displayName = _pickQingString(item, const <String>[
        'name',
        'nick_name',
        'nickname',
        'user_nick_name',
        'userName',
      ]);
      final resolvedName = displayName.isEmpty
          ? (username.isEmpty ? 'user_$userId' : username)
          : displayName;
      final resolvedUsername = username.isEmpty ? resolvedName : username;
      if (resolvedUsername.trim().isEmpty) {
        continue;
      }
      final avatar = _resolveQingUrl(
        _pickQingString(item, const <String>['icon', 'avatar', 'userAvatar']),
      );
      result.add(
        RiverSideUserSearchItem(
          id: userId,
          username: resolvedUsername,
          displayName: resolvedName,
          avatarUrl: avatar,
        ),
      );
    }
    return result;
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
          body: _formEncode(requestBody),
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
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }

  int? _asQingInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.toInt();
    }
    return int.tryParse('${raw ?? ''}'.trim());
  }

  bool _asQingBool(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
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

  Future<void> _loadInstalledMiniApps() async {
    try {
      final installed = await _miniAppInstallStore.loadInstalledApps();
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _installedMiniApps = installed;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _installedMiniApps = const <RiverMiniAppEntry>[];
      });
    }
  }

  bool _isMiniAppInstalled(String id) {
    return _installedMiniApps.any((item) => item.id == id);
  }

  RiverMiniAppEntry? _installedMiniAppById(String id) {
    for (final item in _installedMiniApps) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _loadMiniAppCatalog({required bool forceRefresh}) async {
    if (_loadingMiniAppCatalog && !forceRefresh) {
      return;
    }
    _mutateState(() {
      _loadingMiniAppCatalog = true;
    });
    try {
      final manifest = await _miniAppRepository.load(
        manifestUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
        cookieHeader: _activeCookieHeader(),
        forceRefresh: forceRefresh,
      );
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _miniAppCatalog = manifest.entries;
        _loadingMiniAppCatalog = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _loadingMiniAppCatalog = false;
      });
      _showSnackBar('加载小程序清单失败：$error');
    }
  }

  Future<bool> _installMiniApp(RiverMiniAppEntry app) async {
    if (_installingMiniAppIds.contains(app.id)) {
      return false;
    }
    _mutateState(() {
      _installingMiniAppIds.add(app.id);
    });
    try {
      final installed = await _miniAppInstallStore.install(
        app: app,
        cookieHeader: _activeCookieHeader(),
      );
      if (!mounted) {
        return false;
      }
      final nextInstalled = <String, RiverMiniAppEntry>{
        for (final item in _installedMiniApps) item.id: item,
      };
      nextInstalled[installed.id] = installed;
      _mutateState(() {
        _installedMiniApps = nextInstalled.values.toList(growable: false)
          ..sort((a, b) {
            final orderCmp = a.order.compareTo(b.order);
            if (orderCmp != 0) {
              return orderCmp;
            }
            return a.name.compareTo(b.name);
          });
      });
      _showSnackBar('已添加 ${installed.name}');
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      final raw = '$error';
      final hint =
          raw.toLowerCase().contains('connection closed while receiving data')
          ? '\n请检查小程序服务器是否稳定在线，并重试。'
          : '';
      _showSnackBar('添加小程序失败：$raw$hint');
      return false;
    } finally {
      if (mounted) {
        _mutateState(() {
          _installingMiniAppIds.remove(app.id);
        });
      }
    }
  }

  Future<void> _openMiniApp(RiverMiniAppEntry app) async {
    if (app.requiresAuth) {
      final username = widget.dependencies.accountStore.activeRiverSideUsername;
      final cookie = _activeCookieHeader() ?? '';
      if (username == null || username.isEmpty || cookie.isEmpty) {
        _showSnackBar('该小程序需要先登录 RiverSide 账号');
        return;
      }
    }

    widget.dependencies.miniAppFloatingStore.removeById(app.id);
    widget.dependencies.miniAppHostStore.open(
      miniApp: app,
      launchSource: 'search',
    );
  }

  Future<void> _openMiniAppDetailSheet(RiverMiniAppEntry app) async {
    final detailTheme = Theme.of(context);
    final packageName = app.appCode.trim().isNotEmpty
        ? app.appCode.trim()
        : (app.projectId.trim().isNotEmpty ? app.projectId.trim() : app.id);
    final developerName = app.developerName.trim().isEmpty
        ? '未知'
        : app.developerName.trim();
    final version = app.version.trim().isEmpty ? '-' : app.version.trim();
    final description = app.description.trim().isEmpty
        ? '暂无描述'
        : app.description.trim();
    final updatedAt = _formatUpdatedAt(app.updatedAtRaw);
    final sizeText = app.packageBytes > 0
        ? '${(app.packageBytes / 1024).toStringAsFixed(1)} KB'
        : '-';
    final iconProvider = _miniAppIconProvider(app.iconUrl);
    final initials = app.name.trim().isEmpty ? 'A' : app.name.trim()[0];

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: detailTheme.colorScheme.surface,
      builder: (detailContext) {
        return StatefulBuilder(
          builder: (detailContext, setDetailState) {
            final installed = _isMiniAppInstalled(app.id);
            final installing = _installingMiniAppIds.contains(app.id);

            Future<void> handleAction() async {
              if (installed) {
                if (detailContext.mounted) {
                  Navigator.of(detailContext).pop();
                }
                final target = _installedMiniAppById(app.id) ?? app;
                await _openMiniApp(target);
                return;
              }
              if (installing) {
                return;
              }
              setDetailState(() {});
              final ok = await _installMiniApp(app);
              if (!mounted) {
                return;
              }
              if (ok && detailContext.mounted) {
                Navigator.of(detailContext).pop();
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                6,
                16,
                12 + MediaQuery.paddingOf(detailContext).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: detailTheme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: detailTheme.colorScheme.outlineVariant
                            .withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (iconProvider == null)
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: detailTheme.colorScheme.primary
                                .withValues(alpha: 0.14),
                            child: Text(
                              initials,
                              style: detailTheme.textTheme.titleMedium
                                  ?.copyWith(
                                    color: detailTheme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          )
                        else
                          ClipOval(
                            child: Image(
                              image: iconProvider,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, errorObject, stackTraceObject) =>
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: detailTheme
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.14),
                                        child: Text(
                                          initials,
                                          style: detailTheme
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: detailTheme
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: detailTheme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  if (installing)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _MiniAppMetaBadge(
                                    icon: Icons.code_rounded,
                                    text: packageName,
                                  ),
                                  _MiniAppMetaBadge(
                                    icon: installed
                                        ? Icons.check_circle_rounded
                                        : Icons.download_done_rounded,
                                    text: installed ? '已安装' : '未安装',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: detailTheme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: detailTheme.colorScheme.outlineVariant
                            .withValues(alpha: 0.32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description,
                          style: detailTheme.textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiniAppMetaBadge(
                              icon: Icons.person_outline_rounded,
                              text: developerName,
                            ),
                            _MiniAppMetaBadge(
                              icon: Icons.new_releases_outlined,
                              text: '版本 $version',
                            ),
                            _MiniAppMetaBadge(
                              icon: Icons.schedule_rounded,
                              text: updatedAt,
                            ),
                            _MiniAppMetaBadge(
                              icon: Icons.sd_storage_outlined,
                              text: sizeText,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _MiniAppMetaRow(label: '包名', value: packageName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(detailContext).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: installing ? null : handleAction,
                          icon: Icon(
                            installed
                                ? Icons.open_in_new_rounded
                                : Icons.add_rounded,
                          ),
                          label: Text(installed ? '打开小程序' : '添加小程序'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatUpdatedAt(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$mi';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showRiverSnackBar(message);
  }
}

part of 'compose_topic_page.dart';

extension _ComposeTopicPageActions on _ComposeTopicPageState {
  Stream<String> _generateAiContentStreamForCompose(
    RiverMarkdownAiRequest request,
  ) {
    final service = RiverAiService(widget.dependencies.settingsController);
    return service.generateStream(
      instruction: request.instruction,
      currentText: request.currentMarkdown,
      referenceText: request.referenceMarkdown,
    );
  }

  String _topicDraftKey() {
    final username =
        widget.dependencies.accountStore.activeRiverSideUsername?.trim() ?? '';
    if (username.isEmpty) return 'river_topic_guest';
    return 'river_topic_${username.toLowerCase()}';
  }

  RiverMarkdownDraftEntry _mapDraftToEditorEntry(RiverSideComposerDraft draft) {
    final subtitle = draft.markdown.trim().isNotEmpty
        ? draft.markdown.trim()
        : '无内容';
    final title = draft.title.trim().isNotEmpty ? draft.title.trim() : '发帖草稿';
    return RiverMarkdownDraftEntry(
      draftKey: draft.draftKey,
      sequence: draft.sequence,
      markdown: draft.markdown,
      title: title,
      subtitle: subtitle,
      updatedAt: draft.createdAt,
    );
  }

  Future<List<RiverMarkdownDraftEntry>> _loadComposeDraftsForEditor({
    required String draftKey,
  }) async {
    final cookie = _activeRiverCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return const <RiverMarkdownDraftEntry>[];
    }
    final drafts = await widget.dependencies.accountStore.riverSideApiClient
        .fetchComposerDrafts(cookieHeader: cookie, offset: 0, limit: 50);
    return drafts
        .where((draft) {
          final action = draft.action.trim().toLowerCase();
          return draft.draftKey == draftKey ||
              action == 'createtopic' ||
              action == 'create_topic';
        })
        .map(_mapDraftToEditorEntry)
        .toList(growable: false);
  }

  Future<bool> _deleteComposeDraftForEditor(
    RiverMarkdownDraftEntry draft,
  ) async {
    final cookie = _activeRiverCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) return false;
    await widget.dependencies.accountStore.riverSideApiClient
        .deleteComposerDraft(
          draftKey: draft.draftKey,
          sequence: draft.sequence,
          cookieHeader: cookie,
        );
    if (mounted) {
      _showToast('草稿已删除');
    }
    return true;
  }

  Future<void> _clearComposeContentAfterPublishSuccess() async {
    _mutateState(() {
      _titleController.clear();
      _contentMarkdown = '';
      _qingUploadedImagesByDisplayUrl.clear();
    });
    await _deleteCurrentComposeDraftSilently();
  }

  Future<void> _deleteCurrentComposeDraftSilently() async {
    final cookie = _activeRiverCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return;
    }
    final draftKey = _topicDraftKey();
    try {
      final draft = await widget.dependencies.accountStore.riverSideApiClient
          .fetchComposerDraft(draftKey: draftKey, cookieHeader: cookie);
      if (draft == null) {
        return;
      }
      await widget.dependencies.accountStore.riverSideApiClient
          .deleteComposerDraft(
            draftKey: draft.draftKey,
            sequence: draft.sequence,
            cookieHeader: cookie,
          );
    } catch (_) {
      // 发布成功后的清理不应影响主流程，失败时静默忽略。
    }
  }

  Future<void> _loadMetaData() async {
    _mutateState(() {
      _loadingMeta = true;
      _loadingRiverMeta = true;
      _loadingQingMeta = true;
    });
    try {
      final river = await _loadRiverMeta();
      final qingCategories = await _loadQingCategories(forceRefresh: true);
      final qingEmojiUrls = QingEmojiCatalog.buildEmojiUrlMap();
      final qingEmojiGroups = QingEmojiCatalog.buildEmojiGroups().map(
        (key, value) => MapEntry('清水河畔 · $key', List<String>.from(value)),
      );

      if (!mounted) return;
      _mutateState(() {
        _riverCategories = river.categories;
        _qingCategories = qingCategories;
        if (_selectedRiverCategoryId != null &&
            !_riverCategories.any(
              (item) => item.id == _selectedRiverCategoryId,
            )) {
          _selectedRiverCategoryId = null;
        }
        if (_selectedQingBoardId != null &&
            !_qingCategories.any((item) => item.id == _selectedQingBoardId)) {
          _selectedQingBoardId = null;
        }
        _riverEmojiUrls = <String, String>{...river.emojiUrls};
        _riverEmojiGroups = <String, List<String>>{
          ...river.emojiGroups.map(
            (key, value) => MapEntry(key, List<String>.from(value)),
          ),
        };
        _qingEmojiUrls = <String, String>{...qingEmojiUrls};
        _qingEmojiGroups = <String, List<String>>{...qingEmojiGroups};
        if (_activeRiverCookieHeader() == null) _enableRiverCompose = false;
        if (_activeQingAuth() == null) _enableQingCompose = false;
        if (!_enableRiverCompose && !_enableQingCompose) {
          if (_activeRiverCookieHeader() != null) {
            _enableRiverCompose = true;
          } else if (_activeQingAuth() != null) {
            _enableQingCompose = true;
          }
        }
        _loadingMeta = false;
        _loadingRiverMeta = false;
        _loadingQingMeta = false;
      });
    } catch (_) {
      if (!mounted) return;
      _mutateState(() {
        _loadingMeta = false;
        _loadingRiverMeta = false;
        _loadingQingMeta = false;
      });
    }
  }

  Future<_RiverComposeMeta> _loadRiverMeta() async {
    final cookie = _activeRiverCookieHeader();
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (cookie == null || cookie.trim().isEmpty || username == null) {
      return const _RiverComposeMeta(
        categories: <RiverSideCategoryOption>[],
        emojiUrls: <String, String>{},
        emojiGroups: <String, List<String>>{},
      );
    }
    final api = widget.dependencies.accountStore.riverSideApiClient;
    var categories = await RiverSideCategoryStore.instance.load(
      apiClient: api,
      username: username,
      cookieHeader: cookie,
    );
    if (categories.isEmpty) {
      categories = await RiverSideCategoryStore.instance.load(
        apiClient: api,
        username: username,
        cookieHeader: cookie,
        forceRefresh: true,
      );
    }
    categories = filterRiverSidePublishableCategories(categories);
    final emojiUrls = await api
        .fetchEmojiUrlMap(cookieHeader: cookie)
        .catchError((_) {
          return const <String, String>{};
        });
    final emojiGroups = await api
        .fetchEmojiGroups(cookieHeader: cookie)
        .catchError((_) {
          return const <String, List<String>>{};
        });
    return _RiverComposeMeta(
      categories: categories,
      emojiUrls: emojiUrls,
      emojiGroups: emojiGroups,
    );
  }

  Future<List<RiverSideCategoryOption>> _loadQingCategories({
    required bool forceRefresh,
  }) async {
    final auth = _activeQingAuth();
    if (auth == null) {
      _qingCategoryRoots = const <_QingComposeForumNode>[];
      return const <RiverSideCategoryOption>[];
    }
    if (!forceRefresh && _qingCategories.isNotEmpty) return _qingCategories;
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/_/forum/list';
    final uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        // 清水河畔板块接口需要携带当前登录用户信息，否则可能返回不完整。
        if (auth.userId != null && auth.userId! > 0) 'uid': '${auth.userId}',
        'accessToken': auth.token,
        'accessSecret': auth.secret,
        '_t': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': RiverServerConfig.instance.qingShuiHePanBaseUrl,
      if (auth.cookieHeader.trim().isNotEmpty) 'Cookie': auth.cookieHeader,
    };
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 16));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      final legacy = await _loadQingCategoriesLegacyMobcent(auth);
      if (legacy.categories.isNotEmpty) {
        _qingCategoryRoots = legacy.roots;
        return _injectQingDeveloperCategoryIfNeeded(legacy.categories);
      }
      throw const RiverSideApiException('清水河畔板块接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if (map.containsKey('code')) {
      final code = _parseInt(map['code']) ?? -1;
      if (code != 0) {
        final legacy = await _loadQingCategoriesLegacyMobcent(auth);
        if (legacy.categories.isNotEmpty) {
          _qingCategoryRoots = legacy.roots;
          return _injectQingDeveloperCategoryIfNeeded(legacy.categories);
        }
        final message = '${map['message'] ?? '清水河畔板块加载失败'}'.trim();
        throw RiverSideApiException(message.isEmpty ? '清水河畔板块加载失败' : message);
      }
      final parsed = _parseQingForumTreeCategories(map['data']);
      if (parsed.categories.isNotEmpty) {
        _qingCategoryRoots = parsed.roots;
        return _injectQingDeveloperCategoryIfNeeded(parsed.categories);
      }
      final legacy = await _loadQingCategoriesLegacyMobcent(auth);
      if (legacy.categories.isNotEmpty) {
        _qingCategoryRoots = legacy.roots;
        return _injectQingDeveloperCategoryIfNeeded(legacy.categories);
      }
      _qingCategoryRoots = parsed.roots;
      return _injectQingDeveloperCategoryIfNeeded(parsed.categories);
    }
    if ('${map['rs']}' == '0') {
      final head = map['head'] is Map
          ? (map['head'] as Map)
          : const <dynamic, dynamic>{};
      final message = '${head['errInfo'] ?? map['errcode'] ?? '清水河畔板块加载失败'}'
          .trim();
      throw RiverSideApiException(message.isEmpty ? '清水河畔板块加载失败' : message);
    }
    final parsed = _parseQingForumCategories(map['list']);
    _qingCategoryRoots = parsed.roots;
    return _injectQingDeveloperCategoryIfNeeded(parsed.categories);
  }

  List<RiverSideCategoryOption> _injectQingDeveloperCategoryIfNeeded(
    List<RiverSideCategoryOption> source,
  ) {
    if (!widget.dependencies.settingsController.developerModeEnabled) {
      return source;
    }
    const developerBoardId = 138;
    for (final item in source) {
      if (item.id == developerBoardId) {
        return source;
      }
    }
    final next = List<RiverSideCategoryOption>.from(source);
    next.add(
      RiverSideCategoryOption(
        id: developerBoardId,
        name: '开发者专区',
        position: next.length + 1,
        parentCategoryId: null,
        description: '',
        displayName: '开发者专区',
      ),
    );
    return next;
  }

  Future<_QingComposeCategoryLoadResult> _loadQingCategoriesLegacyMobcent(
    QingShuiHePanAuth auth,
  ) async {
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            if (auth.cookieHeader.trim().isNotEmpty)
              'Cookie': auth.cookieHeader,
          },
          body: _encodeQingForm(<String, String>{
            'r': 'forum/forumlist',
            'accessToken': auth.token,
            'accessSecret': auth.secret,
          }),
        )
        .timeout(const Duration(seconds: 16));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      return const _QingComposeCategoryLoadResult(
        categories: <RiverSideCategoryOption>[],
        roots: <_QingComposeForumNode>[],
      );
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      return const _QingComposeCategoryLoadResult(
        categories: <RiverSideCategoryOption>[],
        roots: <_QingComposeForumNode>[],
      );
    }
    return _parseQingForumCategories(map['list']);
  }

  _QingComposeCategoryLoadResult _parseQingForumTreeCategories(
    dynamic dataRaw,
  ) {
    if (dataRaw is! List) {
      return const _QingComposeCategoryLoadResult(
        categories: <RiverSideCategoryOption>[],
        roots: <_QingComposeForumNode>[],
      );
    }
    final categories = <RiverSideCategoryOption>[];
    final roots = <_QingComposeForumNode>[];
    final seenIds = <int>{};
    var position = 0;
    var syntheticParentSeed = 1;
    int nextSyntheticId() => -(900000 + syntheticParentSeed++);

    bool canPostThread(Map<String, dynamic> node) {
      final raw = node['can_post_thread'];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      final text = '$raw'.trim().toLowerCase();
      return text == '1' || text == 'true';
    }

    _QingComposeForumNode? buildNode(
      Map<String, dynamic> node, {
      required List<String> path,
    }) {
      if (node.isEmpty) {
        return null;
      }
      final name = _pickStringFromMap(node, const <String>['name']);
      if (name.isEmpty) {
        return null;
      }
      final fid = _parseInt(node['fid']);
      final canCreate = fid != null && fid > 0 && canPostThread(node);
      final currentPath = <String>[...path, name];
      final children = <_QingComposeForumNode>[];
      final nestedChildren = node['children'];
      if (nestedChildren is List) {
        for (final rawChild in nestedChildren) {
          final parsed = buildNode(
            _toStringDynamicMap(rawChild),
            path: currentPath,
          );
          if (parsed != null) {
            children.add(parsed);
          }
        }
      }
      if (!canCreate && children.isEmpty) {
        return null;
      }
      final displayName = currentPath.join(' · ');
      final includeAsBoard = canCreate && currentPath.length > 1;
      if (includeAsBoard && seenIds.add(fid)) {
        categories.add(
          RiverSideCategoryOption(
            id: fid,
            name: name,
            position: position++,
            parentCategoryId: null,
            description: '',
            displayName: displayName,
          ),
        );
      }
      return _QingComposeForumNode(
        id: includeAsBoard ? fid : nextSyntheticId(),
        boardId: includeAsBoard ? fid : null,
        name: name,
        displayName: displayName,
        canCreateTopic: includeAsBoard,
        children: List<_QingComposeForumNode>.unmodifiable(children),
      );
    }

    for (final rawRoot in dataRaw) {
      final root = buildNode(
        _toStringDynamicMap(rawRoot),
        path: const <String>[],
      );
      if (root != null) {
        roots.add(root);
      }
    }

    return _QingComposeCategoryLoadResult(
      categories: List<RiverSideCategoryOption>.unmodifiable(categories),
      roots: List<_QingComposeForumNode>.unmodifiable(roots),
    );
  }

  _QingComposeCategoryLoadResult _parseQingForumCategories(dynamic listRaw) {
    if (listRaw is! List) {
      return const _QingComposeCategoryLoadResult(
        categories: <RiverSideCategoryOption>[],
        roots: <_QingComposeForumNode>[],
      );
    }
    final categories = <RiverSideCategoryOption>[];
    final roots = <_QingComposeForumNode>[];
    final seenBoardIds = <int>{};
    var position = 0;
    var syntheticSeed = 1;
    int nextSyntheticId() => -(100000 + syntheticSeed++);

    for (final rawGroup in listRaw) {
      final group = _toStringDynamicMap(rawGroup);
      if (group.isEmpty) continue;
      final groupName = _pickStringFromMap(group, const <String>[
        'board_category_name',
        'category_name',
        'name',
      ]);
      final groupId = _parseInt(group['board_category_id']);
      final boardList = group['board_list'];
      final children = <_QingComposeForumNode>[];
      if (boardList is List) {
        for (final rawBoard in boardList) {
          final board = _toStringDynamicMap(rawBoard);
          if (board.isEmpty) continue;
          final boardId = _parseInt(board['board_id']);
          if (boardId == null ||
              boardId <= 0 ||
              seenBoardIds.contains(boardId)) {
            continue;
          }
          final boardName = _pickStringFromMap(board, const <String>[
            'board_name',
            'forum_name',
            'name',
          ]);
          if (boardName.isEmpty) continue;
          seenBoardIds.add(boardId);
          final displayName = groupName.isEmpty
              ? boardName
              : '$groupName · $boardName';
          categories.add(
            RiverSideCategoryOption(
              id: boardId,
              name: boardName,
              position: position++,
              parentCategoryId: null,
              description: '',
              displayName: displayName,
            ),
          );
          children.add(
            _QingComposeForumNode(
              id: boardId,
              boardId: boardId,
              name: boardName,
              displayName: displayName,
              canCreateTopic: true,
            ),
          );
        }
      }
      if (groupName.isEmpty) {
        roots.addAll(children);
        continue;
      }
      if (children.isEmpty) continue;
      roots.add(
        _QingComposeForumNode(
          id: groupId != null && groupId > 0 ? groupId : nextSyntheticId(),
          name: groupName,
          displayName: groupName,
          canCreateTopic: false,
          children: List<_QingComposeForumNode>.unmodifiable(children),
        ),
      );
    }
    return _QingComposeCategoryLoadResult(
      categories: List<RiverSideCategoryOption>.unmodifiable(categories),
      roots: List<_QingComposeForumNode>.unmodifiable(roots),
    );
  }

  Future<String?> _uploadComposeImage(String fileName, List<int> bytes) async {
    final picUiInserted = await _uploadImageViaPicUiIfEnabled(
      fileName: fileName,
      bytes: bytes,
    );
    if (picUiInserted != null) {
      return picUiInserted;
    }

    final publishToRiver = _enableRiverCompose;
    final publishToQing = _enableQingCompose;
    if (!publishToRiver && !publishToQing) {
      throw const RiverSideApiException('请先启用发帖目标');
    }

    String? riverDisplayUrl;
    _QingComposeUploadImage? qingImage;

    if (publishToRiver) {
      final cookie = _activeRiverCookieHeader();
      if (cookie == null || cookie.trim().isEmpty) {
        throw const RiverSideApiException(
          _ComposeTopicPageState._labelNeedRiverLogin,
        );
      }
      final uploaded = await widget.dependencies.accountStore.riverSideApiClient
          .uploadComposerImage(
            cookieHeader: cookie,
            fileName: fileName,
            bytes: bytes,
          );
      riverDisplayUrl = uploaded.startsWith('upload://')
          ? uploaded
          : _resolveForumUrl(uploaded);
    }

    if (publishToQing) {
      final auth = _activeQingAuth();
      if (auth == null) {
        throw const RiverSideApiException(
          _ComposeTopicPageState._labelNeedQingLogin,
        );
      }
      qingImage = await _uploadQingComposeImage(
        auth: auth,
        fileName: fileName,
        bytes: bytes,
      );
    }

    final displayUrl = riverDisplayUrl ?? qingImage?.resolvedUrl ?? '';
    if (displayUrl.isEmpty) {
      throw const RiverSideApiException('图片上传失败');
    }
    if (qingImage != null) {
      _qingUploadedImagesByDisplayUrl[displayUrl] = qingImage;
      _qingUploadedImagesByDisplayUrl[qingImage.resolvedUrl] = qingImage;
      _qingUploadedImagesByDisplayUrl[qingImage.urlName] = qingImage;
      if (riverDisplayUrl != null) {
        _qingUploadedImagesByDisplayUrl[riverDisplayUrl] = qingImage;
      }
    }
    return '![]($displayUrl)';
  }

  Future<String?> _uploadImageViaPicUiIfEnabled({
    required String fileName,
    required List<int> bytes,
  }) async {
    final settings = widget.dependencies.settingsController;
    if (!settings.picUiEnabled) {
      return null;
    }
    try {
      final service = PicUiImageHostService(
        apiBaseUrl: settings.picUiApiBaseUrl,
      );
      final uploaded = await service.uploadBytes(
        fileName: fileName,
        bytes: bytes,
        apiToken: settings.picUiApiToken,
        options: PicUiUploadOptions(
          permission: 1,
          albumId: settings.picUiDefaultAlbumId,
        ),
      );
      final url = uploaded.links.url.trim();
      if (url.isEmpty) {
        throw const PicUiImageHostException('PicUI 返回的图片地址为空');
      }
      return '![]($url)';
    } catch (error) {
      _showToast('PicUI 上传失败，已回退论坛上传：$error', isError: true);
      return null;
    }
  }

  Future<_QingComposeUploadImage> _uploadQingComposeImage({
    required QingShuiHePanAuth auth,
    required String fileName,
    required List<int> bytes,
  }) async {
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php'
        '?r=forum/sendattachmentex&type=image&module=forum'
        '&accessToken=${Uri.encodeQueryComponent(auth.token)}'
        '&accessSecret=${Uri.encodeQueryComponent(auth.secret)}';

    final mediaType = _guessImageMediaType(fileName);
    final normalizedFileName = _normalizeUploadFileName(fileName, mediaType);
    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers['Accept'] = 'application/json, text/plain, */*'
      ..files.add(
        http.MultipartFile.fromBytes(
          'uploadFile[]',
          bytes,
          filename: normalizedFileName,
          contentType: mediaType,
        ),
      );

    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RiverSideApiException('清水河畔图片上传失败(HTTP ${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔图片上传返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final head = map['head'] is Map
          ? (map['head'] as Map)
          : const <dynamic, dynamic>{};
      final message = '${head['errInfo'] ?? map['errcode'] ?? '清水河畔图片上传失败'}'
          .trim();
      throw RiverSideApiException(message.isEmpty ? '清水河畔图片上传失败' : message);
    }
    final body = map['body'] is Map
        ? (map['body'] as Map)
        : const <dynamic, dynamic>{};
    final attachments = _normalizeQingAttachmentList(body['attachment']);
    if (attachments.isEmpty) {
      throw const RiverSideApiException('清水河畔图片上传结果为空');
    }
    final att = attachments.first;
    final aid = '${att['id'] ?? att['aid'] ?? ''}'.trim();
    final urlName = '${att['urlName'] ?? att['url'] ?? ''}'.trim();
    if (urlName.isEmpty) {
      throw const RiverSideApiException('清水河畔图片地址为空');
    }
    final resolvedUrl = _resolveQingAbsoluteUrl(urlName);
    if (resolvedUrl.isEmpty) {
      throw const RiverSideApiException('清水河畔图片地址解析失败');
    }
    return _QingComposeUploadImage(
      aid: aid,
      urlName: urlName,
      resolvedUrl: resolvedUrl,
    );
  }

  List<Map<String, dynamic>> _normalizeQingAttachmentList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e is Map ? e.map((k, v) => MapEntry('$k', v)) : null)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }
    if (raw is Map) {
      return <Map<String, dynamic>>[raw.map((k, v) => MapEntry('$k', v))];
    }
    return const <Map<String, dynamic>>[];
  }

  MediaType _guessImageMediaType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  String _normalizeUploadFileName(String fileName, MediaType mediaType) {
    final raw = fileName.trim();
    if (raw.isEmpty) {
      return mediaType.subtype == 'png' ? 'image.png' : 'image.jpg';
    }
    if (raw.contains('.')) return raw;
    return '$raw.${mediaType.subtype == 'png' ? 'png' : 'jpg'}';
  }

  String _resolveQingAbsoluteUrl(String source) {
    final raw = source.trim();
    if (raw.isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    final decoded = raw.replaceAll('&amp;', '&');
    try {
      final base = Uri.parse(RiverServerConfig.instance.qingShuiHePanBaseUrl);
      return base.resolve(decoded).toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> _openEditor() async {
    HapticFeedback.lightImpact();
    final draftKey = _topicDraftKey();
    final canUseRiverDraft =
        _activeRiverCookieHeader()?.trim().isNotEmpty == true;
    Future<RiverMarkdownDraftEntry?> loadCurrentDraft() async {
      if (!canUseRiverDraft) return null;
      final cookie = _activeRiverCookieHeader();
      if (cookie == null || cookie.trim().isEmpty) return null;
      final draft = await widget.dependencies.accountStore.riverSideApiClient
          .fetchComposerDraft(draftKey: draftKey, cookieHeader: cookie);
      if (draft == null) return null;
      if (mounted) {
        _mutateState(() {
          if (_titleController.text.trim().isEmpty &&
              draft.title.trim().isNotEmpty) {
            _titleController.text = draft.title.trim();
          }
          if (_selectedRiverCategoryId == null && draft.categoryId != null) {
            _selectedRiverCategoryId = draft.categoryId;
          }
        });
      }
      return _mapDraftToEditorEntry(draft);
    }

    Future<RiverMarkdownDraftEntry?> saveDraft(
      String markdown,
      int? sequence,
    ) async {
      if (!canUseRiverDraft) return null;
      final cookie = _activeRiverCookieHeader();
      if (cookie == null || cookie.trim().isEmpty) return null;
      final nextSequence = await widget
          .dependencies
          .accountStore
          .riverSideApiClient
          .saveComposerDraft(
            draftKey: draftKey,
            sequence: sequence ?? 0,
            data: <String, dynamic>{
              'reply': markdown,
              'action': 'createTopic',
              'title': _titleController.text.trim(),
              'categoryId': _selectedRiverCategoryId,
              'archetypeId': 'regular',
            },
            cookieHeader: cookie,
          );
      return RiverMarkdownDraftEntry(
        draftKey: draftKey,
        sequence: nextSequence,
        markdown: markdown,
        title: _titleController.text.trim().isEmpty
            ? '发帖草稿'
            : _titleController.text.trim(),
        subtitle: markdown.trim(),
        updatedAt: DateTime.now(),
      );
    }

    final effectiveEmoji = _effectiveComposeEmojiConfig();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return RiverMarkdownEditor(
          title: '正文',
          hintText: '在这里输入内容...',
          submitLabel: '确认',
          initialText: _contentMarkdown,
          emojiUrls: effectiveEmoji.emojiUrls,
          emojiGroups: effectiveEmoji.emojiGroups,
          onSearchMentionUsers: _searchMentionUsersForComposeEditor,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          onUploadImage: _uploadComposeImage,
          onLoadCurrentDraft: canUseRiverDraft ? loadCurrentDraft : null,
          onSaveDraft: canUseRiverDraft ? saveDraft : null,
          onLoadDrafts: canUseRiverDraft
              ? () => _loadComposeDraftsForEditor(draftKey: draftKey)
              : null,
          onDeleteDraft: canUseRiverDraft ? _deleteComposeDraftForEditor : null,
          aiScene: RiverMarkdownAiScene.topicCompose,
          onAiGenerateStream: _generateAiContentStreamForCompose,
          onSubmit: (markdown) async {
            _mutateState(() {
              _contentMarkdown = markdown;
            });
            return true;
          },
        );
      },
    );
  }

  Future<List<RiverMarkdownMentionUser>> _searchMentionUsersForComposeEditor(
    String query,
  ) async {
    final result = <RiverMarkdownMentionUser>[];
    if (_enableRiverCompose) {
      result.addAll(await _searchRiverMentionUsersForCompose(query));
    }
    if (_enableQingCompose) {
      result.addAll(await _searchQingMentionUsersForCompose(query));
    }
    return _dedupeMentionUsers(result);
  }

  Future<List<RiverMarkdownMentionUser>> _searchRiverMentionUsersForCompose(
    String query,
  ) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const <RiverMarkdownMentionUser>[];
    }
    final cookie = _activeRiverCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return const <RiverMarkdownMentionUser>[];
    }
    try {
      final users = await widget.dependencies.accountStore.riverSideApiClient
          .searchUsers(term: keyword, limit: 20, cookieHeader: cookie);
      return users
          .map(
            (user) => RiverMarkdownMentionUser(
              key: 'river_${user.username.toLowerCase()}',
              insertText: user.username,
              displayName: user.displayName,
              username: user.username,
              avatarUrl: user.avatarUrl,
              subtitle: '@${user.username}',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <RiverMarkdownMentionUser>[];
    }
  }

  Future<List<RiverMarkdownMentionUser>> _searchQingMentionUsersForCompose(
    String query,
  ) async {
    final auth = _activeQingAuth();
    if (auth == null) {
      return const <RiverMarkdownMentionUser>[];
    }
    final normalized = query.trim().toLowerCase();
    final result = <RiverMarkdownMentionUser>[];
    final seen = <String>{};

    void pushUser({
      required String key,
      required String name,
      required String username,
      required String avatar,
    }) {
      final display = name.trim();
      final insert = display.isEmpty ? username.trim() : display;
      if (insert.isEmpty) {
        return;
      }
      final unique = key.trim().isNotEmpty
          ? key.trim().toLowerCase()
          : insert.toLowerCase();
      if (seen.contains(unique)) {
        return;
      }
      seen.add(unique);
      result.add(
        RiverMarkdownMentionUser(
          key: unique,
          insertText: insert,
          displayName: display.isEmpty ? insert : display,
          username: username.trim(),
          avatarUrl: avatar,
          subtitle: username.trim().isEmpty ? '' : '@${username.trim()}',
        ),
      );
    }

    try {
      final atListMap = await _callQingApi(
        auth: auth,
        body: const <String, String>{
          'r': 'forum/atuserlist',
          'page': '1',
          'pageSize': '20',
        },
      );
      final listRaw = atListMap['list'];
      if (listRaw is List) {
        for (final raw in listRaw) {
          final item = _toStringDynamicMap(raw);
          if (item.isEmpty) {
            continue;
          }
          final uid = _parseInt(item['uid']) ?? 0;
          final name = _pickStringFromMap(item, const <String>[
            'name',
            'user_nick_name',
            'nickname',
          ]);
          final username = _pickStringFromMap(item, const <String>[
            'user_name',
            'username',
          ]);
          final avatar = _resolveQingAbsoluteUrl(
            _pickStringFromMap(item, const <String>['icon', 'avatar']),
          );
          if (normalized.isNotEmpty) {
            final nameLower = name.toLowerCase();
            final usernameLower = username.toLowerCase();
            if (!nameLower.contains(normalized) &&
                !usernameLower.contains(normalized)) {
              continue;
            }
          }
          pushUser(
            key: uid > 0 ? 'qing_uid_$uid' : 'qing_name_${name.toLowerCase()}',
            name: name,
            username: username,
            avatar: avatar,
          );
        }
      }
    } catch (_) {}

    if (normalized.isNotEmpty) {
      try {
        final map = await _callQingApi(
          auth: auth,
          body: <String, String>{
            'r': 'user/searchuser',
            'keyword': query.trim(),
            'page': '1',
            'pageSize': '20',
          },
        );
        final body = _toStringDynamicMap(map['body']);
        final listRaw = map['list'] ?? body['list'];
        if (listRaw is List) {
          for (final raw in listRaw) {
            final item = _toStringDynamicMap(raw);
            if (item.isEmpty) {
              continue;
            }
            final uid = _parseInt(item['uid']) ?? 0;
            final name = _pickStringFromMap(item, const <String>[
              'name',
              'user_nick_name',
              'nick_name',
              'nickname',
            ]);
            final username = _pickStringFromMap(item, const <String>[
              'user_name',
              'username',
              'userName',
            ]);
            final avatar = _resolveQingAbsoluteUrl(
              _pickStringFromMap(item, const <String>['icon', 'avatar']),
            );
            pushUser(
              key: uid > 0
                  ? 'qing_uid_$uid'
                  : 'qing_name_${name.toLowerCase()}_${username.toLowerCase()}',
              name: name,
              username: username,
              avatar: avatar,
            );
          }
        }
      } catch (_) {}
    }

    return result;
  }

  List<RiverMarkdownMentionUser> _dedupeMentionUsers(
    List<RiverMarkdownMentionUser> source,
  ) {
    final seen = <String>{};
    final result = <RiverMarkdownMentionUser>[];
    for (final item in source) {
      final key = item.key.trim().isEmpty
          ? item.insertText.trim().toLowerCase()
          : item.key.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      result.add(item);
      if (result.length >= 20) {
        break;
      }
    }
    return result;
  }

  _ComposeEmojiConfig _effectiveComposeEmojiConfig() {
    if (_enableRiverCompose && _enableQingCompose) {
      final dualUrls = QingEmojiCatalog.buildDualComposeEmojiUrlMap(
        riverEmojiUrls: _riverEmojiUrls,
      );
      final dualGroups = QingEmojiCatalog.buildDualComposeEmojiGroups(
        riverEmojiGroups: _riverEmojiGroups,
        dualEmojiUrls: dualUrls,
      );
      return _ComposeEmojiConfig(emojiUrls: dualUrls, emojiGroups: dualGroups);
    }
    if (_enableRiverCompose) {
      return _ComposeEmojiConfig(
        emojiUrls: _riverEmojiUrls,
        emojiGroups: _riverEmojiGroups,
      );
    }
    if (_enableQingCompose) {
      return _ComposeEmojiConfig(
        emojiUrls: _qingEmojiUrls,
        emojiGroups: _qingEmojiGroups,
      );
    }
    return const _ComposeEmojiConfig(
      emojiUrls: <String, String>{},
      emojiGroups: <String, List<String>>{},
    );
  }

  Future<void> _openCategoryPicker(AccountProvider provider) async {
    HapticFeedback.selectionClick();
    final categories = provider == AccountProvider.riverSide
        ? _riverCategories
        : _qingCategories;
    final selectedId = provider == AccountProvider.riverSide
        ? _selectedRiverCategoryId
        : _selectedQingBoardId;

    if (categories.isEmpty && !_loadingMeta) {
      if (provider == AccountProvider.riverSide) {
        await _loadMetaData();
      } else {
        final refreshed = await _loadQingCategories(forceRefresh: true);
        if (mounted) {
          _mutateState(() {
            _qingCategories = refreshed;
          });
        }
      }
    }
    if (!mounted) return;
    final source = provider == AccountProvider.riverSide
        ? _riverCategories
        : _qingCategories;
    if (source.isEmpty) {
      _showToast('暂无可选板块', isError: true);
      return;
    }

    final selected = await showModalBottomSheet<RiverSideCategoryOption?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        final payload = provider == AccountProvider.riverSide
            ? _buildRiverPublishPickerPayload(source)
            : _buildQingPublishPickerPayload(_qingCategoryRoots, source);
        return RiverPublishCategoryPickerSheet(
          title: provider == AccountProvider.riverSide
              ? 'RiverSide 板块'
              : '清水河畔板块',
          subtitle: '选择需要发帖的板块',
          icon: provider == AccountProvider.riverSide
              ? Icons.dashboard_rounded
              : Icons.account_tree_rounded,
          payload: payload,
          selectedCategoryId: selectedId,
          onRefresh: () async {
            if (provider == AccountProvider.riverSide) {
              final cookie = _activeRiverCookieHeader();
              final categories = filterRiverSidePublishableCategories(
                await RiverSideCategoryStore.instance.load(
                  apiClient:
                      widget.dependencies.accountStore.riverSideApiClient,
                  username:
                      widget.dependencies.accountStore.activeRiverSideUsername,
                  cookieHeader: cookie,
                  forceRefresh: true,
                ),
              );
              if (mounted) {
                _mutateState(() {
                  _riverCategories = categories;
                });
              }
              return _buildRiverPublishPickerPayload(categories);
            }
            final categories = await _loadQingCategories(forceRefresh: true);
            if (mounted) {
              _mutateState(() {
                _qingCategories = categories;
              });
            }
            return _buildQingPublishPickerPayload(
              _qingCategoryRoots,
              categories,
            );
          },
          onSelected: (category) => Navigator.of(sheetContext).pop(category),
        );
      },
    );
    if (!mounted || selected == null) return;
    _mutateState(() {
      if (provider == AccountProvider.riverSide) {
        _selectedRiverCategoryId = selected.id;
      } else {
        _selectedQingBoardId = selected.id;
      }
    });
  }

  RiverSideCategoryOption? _selectedCategory(AccountProvider provider) {
    return findRiverSideCategoryById(
      id: provider == AccountProvider.riverSide
          ? _selectedRiverCategoryId
          : _selectedQingBoardId,
      categories: provider == AccountProvider.riverSide
          ? _riverCategories
          : _qingCategories,
    );
  }

  String _displayCategoryName(
    RiverSideCategoryOption category,
    AccountProvider provider,
  ) {
    return displayRiverSideCategoryName(
      category: category,
      allCategories: provider == AccountProvider.riverSide
          ? _riverCategories
          : _qingCategories,
    );
  }

  RiverPublishCategoryPickerPayload _buildRiverPublishPickerPayload(
    List<RiverSideCategoryOption> categories,
  ) {
    final groups = buildRiverSideCategoryGroups(categories);
    final tabs = <RiverPublishCategoryPickerTab>[];
    final sectionsByTab = <int, List<RiverPublishCategoryPickerSection>>{};

    for (final group in groups) {
      final tabId = group.parent.id;
      tabs.add(
        RiverPublishCategoryPickerTab(id: tabId, label: group.parent.name),
      );
      final sections = <RiverPublishCategoryPickerSection>[];
      if (group.parent.canCreateTopic) {
        sections.add(
          RiverPublishCategoryPickerSection(
            title: '可发帖板块',
            categories: <RiverSideCategoryOption>[group.parent],
          ),
        );
      }
      if (group.children.isNotEmpty) {
        sections.add(
          RiverPublishCategoryPickerSection(
            title: '板块',
            categories: group.children,
          ),
        );
      }
      sectionsByTab[tabId] = sections;
    }

    return RiverPublishCategoryPickerPayload(
      tabs: tabs,
      sectionsByTab: sectionsByTab,
    );
  }

  RiverPublishCategoryPickerPayload _buildQingPublishPickerPayload(
    List<_QingComposeForumNode> roots,
    List<RiverSideCategoryOption> categories,
  ) {
    final categoryById = <int, RiverSideCategoryOption>{
      for (final item in categories) item.id: item,
    };
    final tabs = <RiverPublishCategoryPickerTab>[];
    final sectionsByTab = <int, List<RiverPublishCategoryPickerSection>>{};

    for (final root in roots) {
      final sections = <RiverPublishCategoryPickerSection>[];
      final quickBoards = <RiverSideCategoryOption>[];
      for (final child in root.children) {
        if (child.children.isEmpty) {
          final boardId = child.boardId;
          final category = boardId == null ? null : categoryById[boardId];
          if (category != null && child.canCreateTopic) {
            quickBoards.add(category);
          }
          continue;
        }
        final boards = <RiverSideCategoryOption>[];
        if (child.canCreateTopic && child.boardId != null) {
          final direct = categoryById[child.boardId!];
          if (direct != null) {
            boards.add(direct);
          }
        }
        for (final node in child.collectPostableDescendants()) {
          final boardId = node.boardId;
          if (boardId == null) {
            continue;
          }
          final category = categoryById[boardId];
          if (category != null &&
              !boards.any((item) => item.id == category.id)) {
            boards.add(category);
          }
        }
        if (boards.isEmpty) {
          continue;
        }
        sections.add(
          RiverPublishCategoryPickerSection(
            title: child.name,
            categories: boards,
          ),
        );
      }
      if (quickBoards.isNotEmpty) {
        sections.insert(
          0,
          RiverPublishCategoryPickerSection(
            title: '快捷板块',
            categories: quickBoards,
          ),
        );
      }
      tabs.add(RiverPublishCategoryPickerTab(id: root.id, label: root.name));
      sectionsByTab[root.id] = sections;
    }

    return RiverPublishCategoryPickerPayload(
      tabs: tabs,
      sectionsByTab: sectionsByTab,
    );
  }

  bool _validateBeforeSubmit({required bool focusTitle}) {
    if (!_enableRiverCompose && !_enableQingCompose) {
      _showToast('请先选择至少一个发帖目标', isError: true);
      return false;
    }
    if (_titleController.text.trim().isEmpty) {
      if (focusTitle) _titleFocusNode.requestFocus();
      _showToast('标题还是要有的', isError: true);
      return false;
    }
    if (_contentMarkdown.trim().isEmpty) {
      _openEditor();
      _showToast('内容不能为空', isError: true);
      return false;
    }
    if (_enableRiverCompose) {
      if (_activeRiverCookieHeader()?.trim().isEmpty != false) {
        _showToast(_ComposeTopicPageState._labelNeedRiverLogin, isError: true);
        return false;
      }
      if (_selectedRiverCategoryId == null) {
        _openCategoryPicker(AccountProvider.riverSide);
        _showToast('请选择 RiverSide 板块', isError: true);
        return false;
      }
    }
    if (_enableQingCompose) {
      if (_activeQingAuth() == null) {
        _showToast(_ComposeTopicPageState._labelNeedQingLogin, isError: true);
        return false;
      }
      if (_selectedQingBoardId == null) {
        _openCategoryPicker(AccountProvider.qingShuiHePan);
        _showToast('请选择清水河畔板块', isError: true);
        return false;
      }
      if (_hasQingUnmappedImages(_contentMarkdown)) {
        _showToast('检测到未同步到清水河畔的图片，请重新插入后再发布', isError: true);
        return false;
      }
    }
    return true;
  }

  bool _hasQingUnmappedImages(String markdown) {
    final imageReg = RegExp(r'!\[[^\]]*\]\(([^)]+)\)', caseSensitive: false);
    for (final match in imageReg.allMatches(markdown)) {
      final rawUrl = (match.group(1) ?? '').trim();
      if (rawUrl.isEmpty) {
        continue;
      }
      final resolved = _resolveQingAbsoluteUrl(rawUrl);
      final mapped =
          _qingUploadedImagesByDisplayUrl[rawUrl] ??
          _qingUploadedImagesByDisplayUrl[resolved];
      if (mapped == null && rawUrl.contains('/uploads/short-url/')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openCrossForumTransfer() async {
    HapticFeedback.lightImpact();
    final canUseRiver = _activeRiverCookieHeader()?.trim().isNotEmpty == true;
    final canUseQing = _activeQingAuth() != null;
    if (!canUseRiver && !canUseQing) {
      _showToast('请先登录至少一个论坛账号', isError: true);
      return;
    }
    if (!canUseRiver || !canUseQing) {
      _showToast('互传需要同时登录 RiverSide 和清水河畔', isError: true);
      return;
    }

    final picked = await _showCrossForumTopicPicker(
      initialSource: _CrossForumTransferSource.riverSide,
    );
    if (picked == null || !mounted) {
      return;
    }
    await _applyCrossForumTransfer(picked);
  }

  Future<_CrossForumTransferPickedTopic?> _showCrossForumTopicPicker({
    required _CrossForumTransferSource initialSource,
  }) async {
    _CrossForumTransferSource source = initialSource;
    List<_CrossForumTransferTopicItem> topics =
        const <_CrossForumTransferTopicItem>[];
    bool loading = true;
    String? error;
    var initialized = false;
    var requestToken = 0;

    Future<void> loadTopics(StateSetter setModalState) async {
      final token = ++requestToken;
      setModalState(() {
        loading = true;
        error = null;
      });
      try {
        final next = source == _CrossForumTransferSource.riverSide
            ? await _fetchRiverOwnTopicsForTransfer()
            : await _fetchQingOwnTopicsForTransfer();
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          topics = next;
          loading = false;
        });
      } on RiverSideApiException catch (e) {
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          error = e.message;
          loading = false;
        });
      } catch (_) {
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          error = '加载帖子失败，请稍后重试';
          loading = false;
        });
      }
    }

    return showModalBottomSheet<_CrossForumTransferPickedTopic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(sheetContext).mounted) {
                  loadTopics(setModalState);
                }
              });
            }

            Widget body;
            if (loading) {
              body = const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            } else if (error != null) {
              body = Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => loadTopics(setModalState),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            } else if (topics.isEmpty) {
              body = const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text('暂无可互传帖子'),
                ),
              );
            } else {
              body = ListView.separated(
                shrinkWrap: true,
                itemCount: topics.length,
                separatorBuilder: (_, unused) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = topics[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        source == _CrossForumTransferSource.riverSide
                            ? Icons.rss_feed_rounded
                            : Icons.water_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      item.title.isEmpty ? '(无标题)' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _CrossForumTransferPickedTopic(
                          source: source,
                          topic: item,
                        ),
                      );
                    },
                  );
                },
              );
            }

            final isRiver = source == _CrossForumTransferSource.riverSide;
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择互传源帖子',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<_CrossForumTransferSource>(
                      segments: const [
                        ButtonSegment<_CrossForumTransferSource>(
                          value: _CrossForumTransferSource.riverSide,
                          icon: Icon(Icons.rss_feed_rounded),
                          label: Text('RiverSide'),
                        ),
                        ButtonSegment<_CrossForumTransferSource>(
                          value: _CrossForumTransferSource.qingShuiHePan,
                          icon: Icon(Icons.water_rounded),
                          label: Text('清水河畔'),
                        ),
                      ],
                      selected: <_CrossForumTransferSource>{source},
                      onSelectionChanged:
                          (Set<_CrossForumTransferSource> next) {
                            if (next.isEmpty) {
                              return;
                            }
                            final selected = next.first;
                            if (selected == source) {
                              return;
                            }
                            setModalState(() {
                              source = selected;
                            });
                            loadTopics(setModalState);
                          },
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(RiverRadius.md),
                      ),
                      child: Text(
                        isRiver
                            ? '将选中的 RiverSide 主贴转换为清水河畔格式并填入编辑器'
                            : '将选中的清水河畔主贴转换为 RiverSide 格式并填入编辑器',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(child: body),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<_CrossForumTransferTopicItem>>
  _fetchRiverOwnTopicsForTransfer() async {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    final cookie = _activeRiverCookieHeader();
    if (username == null || username.trim().isEmpty || cookie == null) {
      throw const RiverSideApiException('请先登录 RiverSide 账号');
    }
    final items = await widget.dependencies.accountStore.riverSideApiClient
        .fetchProfileActivities(
          username,
          kind: RiverSideProfileActivityKind.topics,
          cookieHeader: cookie,
          offset: 0,
        );
    final dedup = <int, _CrossForumTransferTopicItem>{};
    for (final it in items) {
      if (it.topicId <= 0) {
        continue;
      }
      dedup.putIfAbsent(
        it.topicId,
        () => _CrossForumTransferTopicItem(
          topicId: it.topicId,
          boardId: null,
          title: it.title,
          subtitle: it.excerpt.isEmpty ? it.categoryName : it.excerpt,
          createdAt: it.createdAt,
        ),
      );
    }
    final list = dedup.values.toList(growable: false);
    list.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return b.topicId.compareTo(a.topicId);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  Future<List<_CrossForumTransferTopicItem>>
  _fetchQingOwnTopicsForTransfer() async {
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
    final map = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'user/topiclist',
        'type': 'topic',
        'page': '1',
        'pageSize': '50',
        if (auth.userId != null && auth.userId! > 0) 'uid': '${auth.userId}',
      },
    );
    final listRaw = map['list'];
    if (listRaw is! List) {
      return const <_CrossForumTransferTopicItem>[];
    }
    final result = <_CrossForumTransferTopicItem>[];
    for (final raw in listRaw) {
      final item = _toStringDynamicMap(raw);
      final topicId =
          _parseInt(item['topic_id']) ??
          _parseInt(item['id']) ??
          _parseInt(item['tid']) ??
          0;
      if (topicId <= 0) {
        continue;
      }
      final title = _pickStringFromMap(item, const <String>[
        'title',
        'subject',
        'topic_title',
      ]);
      final subtitle = _pickStringFromMap(item, const <String>[
        'subject',
        'summary',
        'content',
      ]);
      final boardId = _parseInt(item['board_id']);
      final createdEpoch =
          _parseInt(item['last_reply_date']) ??
          _parseInt(item['create_date']) ??
          _parseInt(item['dateline']);
      result.add(
        _CrossForumTransferTopicItem(
          topicId: topicId,
          boardId: boardId,
          title: title.isEmpty ? '(无标题)' : title,
          subtitle: subtitle,
          createdAt: _epochToDateForTransfer(createdEpoch),
        ),
      );
    }
    result.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return b.topicId.compareTo(a.topicId);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return result;
  }

  DateTime? _epochToDateForTransfer(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    final isMillis = value > 1000000000000;
    return DateTime.fromMillisecondsSinceEpoch(isMillis ? value : value * 1000);
  }

  Future<void> _applyCrossForumTransfer(
    _CrossForumTransferPickedTopic picked,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      if (picked.source == _CrossForumTransferSource.riverSide) {
        final cookie = _activeRiverCookieHeader();
        if (cookie == null || cookie.trim().isEmpty) {
          throw const RiverSideApiException('请先登录 RiverSide 账号');
        }
        if (_activeQingAuth() == null) {
          throw const RiverSideApiException('请先登录清水河畔账号');
        }
        final detail = await widget.dependencies.accountStore.riverSideApiClient
            .fetchTopicDetail(
              topicId: picked.topic.topicId,
              cookieHeader: cookie,
            );
        var markdown = detail.mainPost.contentMarkdown.trim();
        if (markdown.isEmpty) {
          markdown = picked.topic.subtitle.trim();
        }
        markdown = _normalizeRiverContentForTransfer(markdown);
        final converted = QingEmojiCatalog.convertRiverEmojiTokensToQingCommon(
          markdown,
          dropUnsupported: true,
        );
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _titleController.text = detail.title.trim().isEmpty
              ? picked.topic.title
              : detail.title.trim();
          _contentMarkdown = converted;
          _enableRiverCompose = false;
          _enableQingCompose = true;
          _selectedQingBoardId ??= _pickFirstPublishableBoardId(
            _qingCategories,
          );
        });
        _showToast('已将 RiverSide 帖子转换为清水河畔格式');
        return;
      }

      if (_activeRiverCookieHeader()?.trim().isEmpty != false) {
        throw const RiverSideApiException('请先登录 RiverSide 账号');
      }
      final qing = await _fetchQingTopicForTransfer(
        topicId: picked.topic.topicId,
        boardId: picked.topic.boardId,
      );
      final converted = QingEmojiCatalog.stripQingOnlyEmojiTokensForRiver(
        qing.markdown,
      );
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _titleController.text = qing.title.trim().isEmpty
            ? picked.topic.title
            : qing.title.trim();
        _contentMarkdown = converted;
        _enableRiverCompose = true;
        _enableQingCompose = false;
        _selectedRiverCategoryId ??= _pickFirstPublishableBoardId(
          _riverCategories,
        );
      });
      _showToast('已将清水河畔帖子转换为 RiverSide 格式');
    } on RiverSideApiException catch (e) {
      if (mounted) {
        _showToast(e.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showToast('互传失败，请稍后重试', isError: true);
      }
    } finally {
      if (nav.canPop()) {
        nav.pop();
      }
    }
  }

  int? _pickFirstPublishableBoardId(List<RiverSideCategoryOption> source) {
    for (final item in source) {
      if (item.id > 0 &&
          (item.parentCategoryId != null || source.length == 1)) {
        return item.id;
      }
    }
    for (final item in source) {
      if (item.id > 0) {
        return item.id;
      }
    }
    return null;
  }

  String _normalizeRiverContentForTransfer(String source) {
    return source.replaceAllMapped(
      RegExp(r'upload://([^\s)\]]+)', caseSensitive: false),
      (match) => _resolveForumUrl('upload://${match.group(1) ?? ''}'),
    );
  }

  Future<_QingTransferTopicDetail> _fetchQingTopicForTransfer({
    required int topicId,
    int? boardId,
  }) async {
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
    final map = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'forum/postlist',
        'topicId': '$topicId',
        'page': '1',
        'pageSize': '20',
        'order': '0',
        if (boardId != null && boardId > 0) 'boardId': '$boardId',
      },
    );
    final topic = _toStringDynamicMap(map['topic']);
    final body = _toStringDynamicMap(map['body']);
    final source = topic.isNotEmpty ? topic : body;
    final title = _pickStringFromMap(source, const <String>[
      'title',
      'subject',
      'topic_title',
    ]);
    final markdown = _qingContentToMarkdownForTransfer(
      source['content'] ?? source['contentList'] ?? source['subject'],
    );
    return _QingTransferTopicDetail(
      title: title,
      markdown: markdown,
      boardId: _parseInt(source['board_id']),
    );
  }

  String _qingContentToMarkdownForTransfer(dynamic raw) {
    if (raw is String) {
      return _convertQingBbCodeToMarkdownForTransfer(raw);
    }
    if (raw is Map) {
      final map = _toStringDynamicMap(raw);
      if (map.isEmpty) return '';
      return _qingContentToMarkdownForTransfer(
        map['content'] ?? map['infor'] ?? map['text'] ?? map['subject'],
      );
    }
    if (raw is! List) {
      return '';
    }
    final lines = <String>[];
    for (final item in raw) {
      final map = _toStringDynamicMap(item);
      if (map.isEmpty) continue;
      final type = _parseInt(map['type']) ?? 0;
      final info = _convertQingBbCodeToMarkdownForTransfer(
        '${map['infor'] ?? map['text'] ?? ''}',
      );
      final rawUrl = _pickStringFromMap(map, const <String>[
        'url',
        'originalInfo',
        'infor',
      ]);
      final url = _resolveQingAbsoluteUrl(rawUrl);
      if (type == 1 && url.isNotEmpty) {
        lines.add('![]($url)');
        continue;
      }
      if ((type == 2 || type == 5) && url.isNotEmpty) {
        lines.add(
          _looksLikeImageUrlForTransfer(url) ? '![]($url)' : '[附件]($url)',
        );
        continue;
      }
      if (type == 4 && url.isNotEmpty) {
        final label = info.isEmpty ? url : info;
        lines.add('[${label.trim().isEmpty ? url : label}]($url)');
        continue;
      }
      if (info.trim().isNotEmpty) {
        lines.add(info);
      } else if (url.isNotEmpty) {
        lines.add(url);
      }
    }
    return lines.join('\n\n').trim();
  }

  String _convertQingBbCodeToMarkdownForTransfer(String source) {
    var text = _decodeQingHtmlEntitiesForTransfer(
      source,
    ).replaceAll('\r\n', '\n');
    if (text.trim().isEmpty) {
      return '';
    }
    text = QingEmojiCatalog.replaceBracketTagsWithColonKey(text);
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAllMapped(
      RegExp(r'<img[^>]*src="([^"]+)"[^>]*>', caseSensitive: false),
      (match) {
        final url = _resolveQingAbsoluteUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) return '';
        return '![]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      ),
      (match) {
        final url = _resolveQingAbsoluteUrl((match.group(1) ?? '').trim());
        final label = _cleanQingHtmlTextForTransfer(match.group(2) ?? '');
        return '[${label.isEmpty ? url : label}]($url)';
      },
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text.replaceAllMapped(
      RegExp(r'\[img(?:=[^\]]*)?\]([\s\S]*?)\[/img\]', caseSensitive: false),
      (match) {
        final url = _resolveQingAbsoluteUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) return '';
        return '![]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\[url=([^\]]+)\]([\s\S]*?)\[/url\]', caseSensitive: false),
      (match) {
        final url = _resolveQingAbsoluteUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) return match.group(2) ?? '';
        final label = _cleanQingHtmlTextForTransfer(match.group(2) ?? '');
        return '[${label.isEmpty ? url : label}]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\[url\]([\s\S]*?)\[/url\]', caseSensitive: false),
      (match) {
        final url = _resolveQingAbsoluteUrl((match.group(1) ?? '').trim());
        if (url.isEmpty) return '';
        return _looksLikeImageUrlForTransfer(url)
            ? '![]($url)'
            : '[$url]($url)';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'\[quote(?:=[^\]]*)?\]([\s\S]*?)\[/quote\]',
        caseSensitive: false,
      ),
      (match) {
        final quote = _cleanQingHtmlTextForTransfer(match.group(1) ?? '');
        if (quote.isEmpty) return '';
        return quote.split('\n').map((line) => '> ${line.trim()}').join('\n');
      },
    );
    text = text.replaceAll(
      RegExp(r'\[/?[a-z][^\]]*\]', caseSensitive: false),
      '',
    );
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _decodeQingHtmlEntitiesForTransfer(String source) {
    return source
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  String _cleanQingHtmlTextForTransfer(String source) {
    return _decodeQingHtmlEntitiesForTransfer(
      source.replaceAll(RegExp(r'<[^>]+>'), ''),
    ).trim();
  }

  bool _looksLikeImageUrlForTransfer(String source) {
    final value = source.trim().toLowerCase();
    if (value.isEmpty) return false;
    return RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|svg|heic|heif)(\?.*)?$',
    ).hasMatch(value);
  }

  Future<void> _previewTopic() async {
    HapticFeedback.lightImpact();
    if (!_validateBeforeSubmit(focusTitle: false)) return;
    final labels = <String>[];
    final riverCategory = _selectedCategory(AccountProvider.riverSide);
    final qingCategory = _selectedCategory(AccountProvider.qingShuiHePan);
    if (_enableRiverCompose && riverCategory != null) {
      labels.add(
        'RiverSide · ${_displayCategoryName(riverCategory, AccountProvider.riverSide)}',
      );
    }
    if (_enableQingCompose && qingCategory != null) {
      labels.add(
        '清水河畔 · ${_displayCategoryName(qingCategory, AccountProvider.qingShuiHePan)}',
      );
    }
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => ComposeTopicPreviewPage(
          title: _titleController.text.trim(),
          categoryName: labels.join('  |  '),
          markdown: _contentMarkdown,
          author:
              _activeAccount ??
              widget.dependencies.accountStore.activeQingShuiHePanAccount,
        ),
      ),
    );
  }

  Future<void> _publishTopic() async {
    if (_publishing) return;
    HapticFeedback.heavyImpact();
    if (!_validateBeforeSubmit(focusTitle: true)) return;

    final title = _titleController.text.trim();
    final sourceMarkdown = _contentMarkdown.trim();
    final publishToRiver = _enableRiverCompose;
    final publishToQing = _enableQingCompose;
    final dualCompose = _enableRiverCompose && _enableQingCompose;
    final riverMarkdown = dualCompose
        ? QingEmojiCatalog.stripQingOnlyEmojiTokensForRiver(sourceMarkdown)
        : sourceMarkdown;
    final qingMarkdown = dualCompose
        ? QingEmojiCatalog.convertRiverEmojiTokensToQingCommon(sourceMarkdown)
        : sourceMarkdown;
    final riverCategoryId = _selectedRiverCategoryId;
    final qingBoardId = _selectedQingBoardId;
    final riverCookie = _activeRiverCookieHeader();
    final qingAuth = _activeQingAuth();
    _mutateState(() => _publishing = true);

    try {
      final tasks = <Future<_ComposePublishAttemptResult>>[];
      if (publishToRiver && riverCategoryId != null && riverCookie != null) {
        tasks.add(
          _publishRiverTopic(
            title: title,
            markdown: riverMarkdown,
            categoryId: riverCategoryId,
            cookieHeader: riverCookie,
          ),
        );
      }
      if (publishToQing && qingBoardId != null && qingAuth != null) {
        tasks.add(
          _publishQingTopicAttempt(
            auth: qingAuth,
            boardId: qingBoardId,
            title: title,
            markdown: qingMarkdown,
          ),
        );
      }

      final results = tasks.isEmpty
          ? const <_ComposePublishAttemptResult>[]
          : await Future.wait(tasks);
      final success = results
          .where((item) => item.success)
          .map(
            (item) => _ComposePublishResult(
              provider: item.provider,
              topicId: item.topicId,
              boardId: item.boardId,
            ),
          )
          .toList(growable: false);
      final riverFailure = results
          .where((item) => item.provider == AccountProvider.riverSide)
          .map((item) => item.failureMessage)
          .whereType<String>()
          .firstOrNull;
      final qingFailure = results
          .where((item) => item.provider == AccountProvider.qingShuiHePan)
          .map((item) => item.failureMessage)
          .whereType<String>()
          .firstOrNull;

      if (!mounted) return;
      if (success.isEmpty) {
        if (riverFailure == null && qingFailure == null) {
          _showToast('发布失败，请稍后重试', isError: true);
          return;
        }
        _showPublishFailureToasts(
          riverFailure: riverFailure,
          qingFailure: qingFailure,
        );
        return;
      }

      final hasFailure = riverFailure != null || qingFailure != null;
      if (hasFailure) {
        final succeededProviders = success.map((item) => item.provider).toSet();
        _mutateState(() {
          if (succeededProviders.contains(AccountProvider.riverSide)) {
            _enableRiverCompose = false;
          }
          if (succeededProviders.contains(AccountProvider.qingShuiHePan)) {
            _enableQingCompose = false;
          }
        });

        final successLabels = <String>[];
        if (succeededProviders.contains(AccountProvider.riverSide)) {
          successLabels.add('RiverSide');
        }
        if (succeededProviders.contains(AccountProvider.qingShuiHePan)) {
          successLabels.add('清水河畔');
        }
        if (successLabels.isNotEmpty) {
          _showToast('已发布到${successLabels.join('、')}');
        }
        _showToast('已保留正文并自动切换到失败论坛，可直接修正后重试', isError: true);
        _showPublishFailureToasts(
          riverFailure: riverFailure,
          qingFailure: qingFailure,
        );
        return;
      }

      await _clearComposeContentAfterPublishSuccess();
      _showToast(success.length > 1 ? '已同步发布到两个论坛' : '发布成功！');
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      final jump = success.firstWhere(
        (item) => item.topicId != null && item.topicId! > 0,
        orElse: () => success.first,
      );
      if (jump.topicId == null || jump.topicId! <= 0) {
        Navigator.of(context).pop(true);
        return;
      }
      await Navigator.of(context).push(
        DraggableRoute<void>(
          builder: (_) => TopicDetailPage(
            dependencies: widget.dependencies,
            topicId: jump.topicId!,
            provider: jump.provider,
            qingBoardId: jump.provider == AccountProvider.qingShuiHePan
                ? jump.boardId
                : null,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _mutateState(() => _publishing = false);
      }
    }
  }

  Future<_ComposePublishAttemptResult> _publishRiverTopic({
    required String title,
    required String markdown,
    required int categoryId,
    required String cookieHeader,
  }) async {
    try {
      final result = await widget.dependencies.accountStore.riverSideApiClient
          .createTopic(
            title: title,
            raw: markdown,
            categoryId: categoryId,
            cookieHeader: cookieHeader,
          );
      return _ComposePublishAttemptResult.success(
        provider: AccountProvider.riverSide,
        topicId: result.topicId,
      );
    } on RiverSideApiException catch (error) {
      final message = error.message.trim();
      return _ComposePublishAttemptResult.failure(
        provider: AccountProvider.riverSide,
        failureMessage: message.isEmpty ? '发布失败' : message,
      );
    } catch (_) {
      return const _ComposePublishAttemptResult.failure(
        provider: AccountProvider.riverSide,
        failureMessage: '发布失败',
      );
    }
  }

  Future<_ComposePublishAttemptResult> _publishQingTopicAttempt({
    required QingShuiHePanAuth auth,
    required int boardId,
    required String title,
    required String markdown,
  }) async {
    try {
      final topicId = await _publishQingTopic(
        auth: auth,
        boardId: boardId,
        title: title,
        markdown: markdown,
      );
      return _ComposePublishAttemptResult.success(
        provider: AccountProvider.qingShuiHePan,
        topicId: topicId,
        boardId: boardId,
      );
    } on RiverSideApiException catch (error) {
      final message = error.message.trim();
      return _ComposePublishAttemptResult.failure(
        provider: AccountProvider.qingShuiHePan,
        failureMessage: message.isEmpty ? '发布失败' : message,
      );
    } catch (_) {
      return const _ComposePublishAttemptResult.failure(
        provider: AccountProvider.qingShuiHePan,
        failureMessage: '发布失败',
      );
    }
  }

  Future<int?> _publishQingTopic({
    required QingShuiHePanAuth auth,
    required int boardId,
    required String title,
    required String markdown,
  }) async {
    final normalized = QingEmojiCatalog.normalizeForSubmit(markdown).trim();
    final payloadContent = _buildQingTopicPayloadContent(normalized);
    if (payloadContent.contentList.isEmpty) {
      throw const RiverSideApiException('清水河畔正文不能为空');
    }
    final resolvedTypeId = await _resolveQingTopicTypeId(
      auth: auth,
      boardId: boardId,
    );
    final payload = <String, dynamic>{
      'body': <String, dynamic>{
        'json': <String, dynamic>{
          'isAnonymous': 0,
          'isOnlyAuthor': 0,
          'typeId': resolvedTypeId == null || resolvedTypeId <= 0
              ? ''
              : resolvedTypeId,
          if (payloadContent.aids.isNotEmpty)
            'aid': payloadContent.aids.join(','),
          'fid': boardId,
          'isQuote': 0,
          'title': title,
          'content': jsonEncode(payloadContent.contentList),
          'contentList': payloadContent.contentList,
          'poll': '',
        },
      },
    };
    final resp = await _callQingApi(
      auth: auth,
      body: <String, String>{
        'r': 'forum/topicadmin',
        'act': 'new',
        'json': jsonEncode(payload),
      },
    );
    _qingUploadedImagesByDisplayUrl.clear();
    return _pickQingTopicId(resp);
  }

  Future<int?> _resolveQingTopicTypeId({
    required QingShuiHePanAuth auth,
    required int boardId,
  }) async {
    if (boardId <= 0) {
      return null;
    }
    try {
      final map = await _callQingApi(
        auth: auth,
        body: <String, String>{
          'r': 'forum/topiclist',
          'page': '1',
          'pageSize': '0',
          'boardId': '$boardId',
          'filterType': 'typeid',
          'filterId': '',
          'sortby': 'new',
        },
      );
      final listRaw = map['classificationType_list'];
      if (listRaw is! List) {
        return null;
      }
      for (final raw in listRaw) {
        final node = _toStringDynamicMap(raw);
        if (node.isEmpty) {
          continue;
        }
        final typeId = _parseInt(node['classificationType_id']);
        if (typeId != null && typeId > 0) {
          return typeId;
        }
      }
    } catch (_) {
      // ignore and fallback to empty typeId
    }
    return null;
  }

  _QingComposeTopicPayload _buildQingTopicPayloadContent(String markdown) {
    final source = markdown.trim();
    if (source.isEmpty) {
      return const _QingComposeTopicPayload(
        contentList: <Map<String, dynamic>>[],
        aids: <String>[],
      );
    }
    final contentList = <Map<String, dynamic>>[];
    final aids = <String>{};
    final imageReg = RegExp(r'!\[[^\]]*\]\(([^)]+)\)', caseSensitive: false);
    var cursor = 0;
    for (final match in imageReg.allMatches(source)) {
      final before = source.substring(cursor, match.start).trim();
      if (before.isNotEmpty) {
        contentList.add(<String, dynamic>{'type': 0, 'infor': before});
      }
      final rawUrl = (match.group(1) ?? '').trim();
      final resolved = _resolveQingAbsoluteUrl(rawUrl);
      final uploaded =
          _qingUploadedImagesByDisplayUrl[resolved] ??
          _qingUploadedImagesByDisplayUrl[rawUrl];
      if (uploaded != null) {
        contentList.add(<String, dynamic>{
          'type': 1,
          'infor': uploaded.urlName,
        });
        if (uploaded.aid.trim().isNotEmpty) aids.add(uploaded.aid.trim());
      } else if (rawUrl.isNotEmpty) {
        contentList.add(<String, dynamic>{'type': 1, 'infor': rawUrl});
      }
      cursor = match.end;
    }
    final tail = source.substring(cursor).trim();
    if (tail.isNotEmpty) {
      contentList.add(<String, dynamic>{'type': 0, 'infor': tail});
    }
    return _QingComposeTopicPayload(
      contentList: contentList,
      aids: aids.toList(growable: false),
    );
  }

  int? _pickQingTopicId(Map<String, dynamic> map) {
    final body = _toStringDynamicMap(map['body']);
    final topic = _toStringDynamicMap(body['topic']);
    final candidates = <dynamic>[
      body['topic_id'],
      body['tid'],
      body['id'],
      topic['topic_id'],
      topic['tid'],
      topic['id'],
      map['topic_id'],
      map['tid'],
      map['id'],
    ];
    for (final raw in candidates) {
      final value = _parseInt(raw);
      if (value != null && value > 0) return value;
    }
    return null;
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
          body: _encodeQingForm(<String, String>{
            ...body,
            'accessToken': auth.token,
            'accessSecret': auth.secret,
          }),
        )
        .timeout(const Duration(seconds: 16));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const RiverSideApiException('清水河畔接口返回异常');
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      final head = map['head'] is Map
          ? (map['head'] as Map)
          : const <dynamic, dynamic>{};
      final message = '${head['errInfo'] ?? map['errcode'] ?? '请求失败'}'.trim();
      throw RiverSideApiException(message.isEmpty ? '请求失败' : message);
    }
    return map;
  }

  void _showPublishFailureToasts({String? riverFailure, String? qingFailure}) {
    if (riverFailure != null && riverFailure.trim().isNotEmpty) {
      _showToast('RiverSide 发帖失败：${riverFailure.trim()}', isError: true);
    }
    if (qingFailure != null && qingFailure.trim().isNotEmpty) {
      _showToast('清水河畔发帖失败：${qingFailure.trim()}', isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    toastification.show(
      context: context,
      type: isError ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flatColored,
      alignment: Alignment.topCenter,
      autoCloseDuration: const Duration(seconds: 3),
      showProgressBar: false,
      closeOnClick: true,
      dragToClose: true,
      title: Text(message.trim(), maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }
}

class _RiverComposeMeta {
  const _RiverComposeMeta({
    required this.categories,
    required this.emojiUrls,
    required this.emojiGroups,
  });

  final List<RiverSideCategoryOption> categories;
  final Map<String, String> emojiUrls;
  final Map<String, List<String>> emojiGroups;
}

class _ComposeEmojiConfig {
  const _ComposeEmojiConfig({
    required this.emojiUrls,
    required this.emojiGroups,
  });

  final Map<String, String> emojiUrls;
  final Map<String, List<String>> emojiGroups;
}

class _QingComposeTopicPayload {
  const _QingComposeTopicPayload({
    required this.contentList,
    required this.aids,
  });

  final List<Map<String, dynamic>> contentList;
  final List<String> aids;
}

class _QingComposeCategoryLoadResult {
  const _QingComposeCategoryLoadResult({
    required this.categories,
    required this.roots,
  });

  final List<RiverSideCategoryOption> categories;
  final List<_QingComposeForumNode> roots;
}

class _QingComposeForumNode {
  const _QingComposeForumNode({
    required this.id,
    this.boardId,
    required this.name,
    required this.displayName,
    required this.canCreateTopic,
    this.children = const <_QingComposeForumNode>[],
  });

  final int id;
  final int? boardId;
  final String name;
  final String displayName;
  final bool canCreateTopic;
  final List<_QingComposeForumNode> children;

  bool containsBoard(int targetBoardId) {
    if (boardId == targetBoardId) {
      return true;
    }
    for (final child in children) {
      if (child.containsBoard(targetBoardId)) {
        return true;
      }
    }
    return false;
  }

  List<_QingComposeForumNode> collectPostableDescendants({
    bool includeSelf = false,
  }) {
    final result = <_QingComposeForumNode>[];
    final seen = <int>{};

    void visit(_QingComposeForumNode node, {required bool allowSelf}) {
      if (allowSelf && node.canCreateTopic && node.boardId != null) {
        if (seen.add(node.boardId!)) {
          result.add(node);
        }
      }
      for (final child in node.children) {
        visit(child, allowSelf: true);
      }
    }

    visit(this, allowSelf: includeSelf);
    return result;
  }
}

class _ComposePublishResult {
  const _ComposePublishResult({
    required this.provider,
    required this.topicId,
    this.boardId,
  });

  final AccountProvider provider;
  final int? topicId;
  final int? boardId;
}

class _ComposePublishAttemptResult {
  const _ComposePublishAttemptResult._({
    required this.provider,
    required this.success,
    this.topicId,
    this.boardId,
    this.failureMessage,
  });

  const _ComposePublishAttemptResult.success({
    required AccountProvider provider,
    int? topicId,
    int? boardId,
  }) : this._(
         provider: provider,
         success: true,
         topicId: topicId,
         boardId: boardId,
       );

  const _ComposePublishAttemptResult.failure({
    required AccountProvider provider,
    required String failureMessage,
  }) : this._(
         provider: provider,
         success: false,
         failureMessage: failureMessage,
       );

  final AccountProvider provider;
  final bool success;
  final int? topicId;
  final int? boardId;
  final String? failureMessage;
}

enum _CrossForumTransferSource { riverSide, qingShuiHePan }

class _CrossForumTransferTopicItem {
  const _CrossForumTransferTopicItem({
    required this.topicId,
    required this.boardId,
    required this.title,
    required this.subtitle,
    required this.createdAt,
  });

  final int topicId;
  final int? boardId;
  final String title;
  final String subtitle;
  final DateTime? createdAt;
}

class _CrossForumTransferPickedTopic {
  const _CrossForumTransferPickedTopic({
    required this.source,
    required this.topic,
  });

  final _CrossForumTransferSource source;
  final _CrossForumTransferTopicItem topic;
}

class _QingTransferTopicDetail {
  const _QingTransferTopicDetail({
    required this.title,
    required this.markdown,
    required this.boardId,
  });

  final String title;
  final String markdown;
  final int? boardId;
}

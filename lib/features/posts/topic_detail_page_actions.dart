part of 'topic_detail_page.dart';

extension _TopicDetailPageCommentActions on _TopicDetailPageState {
  Stream<String> _generateAiContentStreamForEditor(
    RiverMarkdownAiRequest request,
  ) {
    final service = RiverAiService(widget.dependencies.settingsController);
    return service.generateStream(
      instruction: request.instruction,
      currentText: request.currentMarkdown,
      referenceText: request.referenceMarkdown,
    );
  }

  Future<void> _openAuthorProfileSheetForPost(
    RiverSideTopicPostDetail post,
  ) async {
    if (_isQingShuiHePanTopic) {
      await _openQingUserProfileSheet(
        authorUserId: post.authorUserId,
        username: post.authorUsername,
        displayName: post.authorDisplayName,
        avatarUrl: post.authorAvatarUrl,
        heroTagAvatar: _topicPostAuthorAvatarHeroTag(post),
        heroTagName: _topicPostAuthorNameHeroTag(post),
      );
      return;
    }
    final avatarHeroTag = _topicPostAuthorAvatarHeroTag(post);
    final nameHeroTag = _topicPostAuthorNameHeroTag(post);
    await showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: post.authorUsername,
      displayName: post.authorDisplayName,
      avatarUrl: post.authorAvatarUrl,
      heroTagAvatar: avatarHeroTag,
      heroTagName: nameHeroTag,
    );
  }

  Future<void> _openQingUserProfileSheetByMentionToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return;
    }
    int? uid;
    String? username;
    if (normalized.startsWith('uid:')) {
      uid = int.tryParse(normalized.substring(4));
    } else {
      username = normalized;
    }
    await _openQingUserProfileSheet(authorUserId: uid, username: username);
  }

  Future<void> _openQingUserProfileSheet({
    int? authorUserId,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? heroTagAvatar,
    String? heroTagName,
  }) async {
    await showQingShuiHePanUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      userId: authorUserId,
      username: (username ?? '').trim(),
      displayName: displayName,
      avatarUrl: avatarUrl,
      heroTagAvatar: heroTagAvatar,
      heroTagName: heroTagName,
    );
  }

  Future<void> _openCrossPostTransferSheet() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    final sourcePost = detail.mainPost;
    if (!_isOwnComment(sourcePost)) {
      _showSimpleToast('仅支持转帖自己发布的主贴');
      return;
    }

    final targetProvider = _isQingShuiHePanTopic
        ? AccountProvider.riverSide
        : AccountProvider.qingShuiHePan;
    final sourceMarkdown = sourcePost.contentMarkdown.trim();
    final normalizedSource = _isQingShuiHePanTopic
        ? sourceMarkdown
        : _normalizeRiverSourceMarkdownForCrossPost(sourceMarkdown);
    final convertedMarkdown = _isQingShuiHePanTopic
        ? QingEmojiCatalog.stripQingOnlyEmojiTokensForRiver(normalizedSource)
        : QingEmojiCatalog.convertRiverEmojiTokensToQingCommon(
            normalizedSource,
            dropUnsupported: true,
          );
    final convertedTitle = detail.title.trim().isEmpty
        ? '(无标题)'
        : detail.title.trim();
    final sheetBackgroundColor = Theme.of(context).colorScheme.surface;

    final previewEmojiUrls = targetProvider == AccountProvider.qingShuiHePan
        ? QingEmojiCatalog.buildEmojiUrlMap()
        : await _loadRiverEmojiUrlsForTransferPreview();
    if (!mounted) {
      return;
    }

    var categories = const <RiverSideCategoryOption>[];
    var selectedCategoryId = targetProvider == AccountProvider.qingShuiHePan
        ? widget.qingBoardId
        : null;
    var qingTypeOptions = const <_QingTopicTypeOption>[];
    int? selectedQingTypeId;
    var loadingCategories = true;
    var loadingQingTypes = false;
    var transfering = false;
    String? loadingError;
    String? loadingQingTypeError;
    var initialized = false;
    var requestToken = 0;
    var qingTypeRequestToken = 0;

    Future<void> loadQingTopicTypes(
      StateSetter setModalState, {
      required int? boardId,
    }) async {
      if (targetProvider != AccountProvider.qingShuiHePan ||
          boardId == null ||
          boardId <= 0) {
        setModalState(() {
          qingTypeOptions = const <_QingTopicTypeOption>[];
          selectedQingTypeId = null;
          loadingQingTypes = false;
          loadingQingTypeError = null;
        });
        return;
      }
      final token = ++qingTypeRequestToken;
      setModalState(() {
        loadingQingTypes = true;
        loadingQingTypeError = null;
      });
      try {
        final types = await _loadQingCrossPostTopicTypes(boardId: boardId);
        if (token != qingTypeRequestToken) {
          return;
        }
        setModalState(() {
          qingTypeOptions = types;
          if (types.isEmpty) {
            selectedQingTypeId = null;
          } else if (!types.any((item) => item.id == selectedQingTypeId)) {
            // 与 river_lite 保持一致：默认选中第一个主题类别，避免发帖时被后端拦截。
            selectedQingTypeId = types.first.id;
          }
          loadingQingTypes = false;
        });
      } on RiverSideApiException catch (e) {
        if (token != qingTypeRequestToken) {
          return;
        }
        setModalState(() {
          qingTypeOptions = const <_QingTopicTypeOption>[];
          selectedQingTypeId = null;
          loadingQingTypes = false;
          loadingQingTypeError = e.message;
        });
      } catch (_) {
        if (token != qingTypeRequestToken) {
          return;
        }
        setModalState(() {
          qingTypeOptions = const <_QingTopicTypeOption>[];
          selectedQingTypeId = null;
          loadingQingTypes = false;
          loadingQingTypeError = '主题类别加载失败，请稍后重试';
        });
      }
    }

    Future<void> loadCategories(StateSetter setModalState) async {
      final token = ++requestToken;
      setModalState(() {
        loadingCategories = true;
        loadingError = null;
      });
      try {
        final loaded = await _loadCrossPostTargetCategories(targetProvider);
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          categories = loaded;
          loadingCategories = false;
          selectedCategoryId ??= _pickFirstPublishableCategoryIdForCrossPost(
            loaded,
          );
        });
        if (targetProvider == AccountProvider.qingShuiHePan) {
          await loadQingTopicTypes(setModalState, boardId: selectedCategoryId);
        }
      } on RiverSideApiException catch (e) {
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          loadingCategories = false;
          loadingError = e.message;
        });
      } catch (_) {
        if (token != requestToken) {
          return;
        }
        setModalState(() {
          loadingCategories = false;
          loadingError = '板块加载失败，请稍后重试';
        });
      }
    }

    final pickedAction = await showModalBottomSheet<_CrossPostAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sheetBackgroundColor,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted) {
                  loadCategories(setModalState);
                }
              });
            }
            final selectedCategory = findRiverSideCategoryById(
              id: selectedCategoryId,
              categories: categories,
            );
            final selectedCategoryText = selectedCategory == null
                ? '选择板块'
                : displayRiverSideCategoryName(
                    category: selectedCategory,
                    allCategories: categories,
                  );
            final targetLabel = targetProvider == AccountProvider.qingShuiHePan
                ? '清水河畔'
                : 'RiverSide';
            final selectedQingTypeName = qingTypeOptions
                .firstWhere(
                  (item) => item.id == selectedQingTypeId,
                  orElse: () => const _QingTopicTypeOption(id: -1, name: ''),
                )
                .name
                .trim();
            final selectedQingTypeText = selectedQingTypeName.isEmpty
                ? '选择主题类别'
                : selectedQingTypeName;

            return _CrossPostTransferSheet(
              targetProvider: targetProvider,
              targetLabel: targetLabel,
              title: convertedTitle,
              markdown: convertedMarkdown,
              previewEmojiUrls: previewEmojiUrls,
              topicId: detail.topicId,
              cookieHeader: _activeCookieHeader(),
              loadingCategories: loadingCategories,
              loadingError: loadingError,
              selectedCategoryText: selectedCategoryText,
              qingTypeEnabled:
                  targetProvider == AccountProvider.qingShuiHePan &&
                  (loadingQingTypes ||
                      loadingQingTypeError != null ||
                      qingTypeOptions.isNotEmpty),
              loadingQingTypes: loadingQingTypes,
              loadingQingTypeError: loadingQingTypeError,
              selectedQingTypeText: selectedQingTypeText,
              transfering: transfering,
              onPickCategory: (loadingCategories || transfering)
                  ? null
                  : () async {
                      final next = await _selectCrossPostCategory(
                        targetProvider: targetProvider,
                        categories: categories,
                        selectedCategoryId: selectedCategoryId,
                      );
                      if (next == null || !mounted || !sheetContext.mounted) {
                        return;
                      }
                      setModalState(() {
                        categories = next.categories;
                        selectedCategoryId = next.selectedCategoryId;
                        qingTypeOptions = const <_QingTopicTypeOption>[];
                        selectedQingTypeId = null;
                        loadingQingTypeError = null;
                      });
                      if (targetProvider == AccountProvider.qingShuiHePan) {
                        await loadQingTopicTypes(
                          setModalState,
                          boardId: selectedCategoryId,
                        );
                      }
                    },
              onPickQingType:
                  (transfering ||
                      loadingCategories ||
                      targetProvider != AccountProvider.qingShuiHePan)
                  ? null
                  : () async {
                      final picked = await _selectQingCrossPostTopicType(
                        options: qingTypeOptions,
                        selectedTypeId: selectedQingTypeId,
                      );
                      if (picked == null || !sheetContext.mounted) {
                        return;
                      }
                      setModalState(() {
                        selectedQingTypeId = picked.id;
                      });
                    },
              onRetryLoadCategories: loadingError == null || transfering
                  ? null
                  : () => loadCategories(setModalState),
              onRetryLoadQingTypes:
                  (loadingQingTypeError == null ||
                      transfering ||
                      loadingCategories ||
                      targetProvider != AccountProvider.qingShuiHePan)
                  ? null
                  : () => loadQingTopicTypes(
                      setModalState,
                      boardId: selectedCategoryId,
                    ),
              onEdit: transfering
                  ? null
                  : () {
                      if (!sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop(
                        _CrossPostAction(
                          type: _CrossPostActionType.edit,
                          provider: targetProvider,
                          categoryId: selectedCategoryId,
                          title: convertedTitle,
                          markdown: convertedMarkdown,
                        ),
                      );
                    },
              onTransfer: (transfering || loadingCategories)
                  ? null
                  : () async {
                      final selectedCategory = findRiverSideCategoryById(
                        id: selectedCategoryId,
                        categories: categories,
                      );
                      if (!_isValidCrossPostCategorySelection(
                        targetProvider: targetProvider,
                        categoryId: selectedCategoryId,
                        category: selectedCategory,
                      )) {
                        _showSimpleToast('请先选择板块');
                        return;
                      }
                      if (targetProvider == AccountProvider.qingShuiHePan &&
                          qingTypeOptions.isNotEmpty &&
                          (selectedQingTypeId == null ||
                              selectedQingTypeId! <= 0)) {
                        _showSimpleToast('请先选择主题类别');
                        return;
                      }
                      setModalState(() {
                        transfering = true;
                      });
                      try {
                        final topicId = await _submitCrossPost(
                          targetProvider: targetProvider,
                          categoryId: selectedCategoryId!,
                          qingTypeId: selectedQingTypeId,
                          title: convertedTitle,
                          markdown: convertedMarkdown,
                        );
                        if (!mounted || !sheetContext.mounted) {
                          return;
                        }
                        Navigator.of(sheetContext).pop(
                          _CrossPostAction(
                            type: _CrossPostActionType.transfer,
                            provider: targetProvider,
                            categoryId: selectedCategoryId,
                            title: convertedTitle,
                            markdown: convertedMarkdown,
                            createdTopicId: topicId,
                          ),
                        );
                      } on RiverSideApiException catch (e) {
                        if (mounted) {
                          _showSimpleToast(e.message);
                        }
                      } catch (_) {
                        if (mounted) {
                          _showSimpleToast('转帖失败，请稍后重试');
                        }
                      } finally {
                        if (sheetContext.mounted) {
                          setModalState(() {
                            transfering = false;
                          });
                        }
                      }
                    },
            );
          },
        );
      },
    );

    if (!mounted || pickedAction == null) {
      return;
    }
    if (pickedAction.type == _CrossPostActionType.edit) {
      await Navigator.of(context).push(
        riverPageRoute<void>(
          builder: (_) => ComposeTopicPage(
            dependencies: widget.dependencies,
            initialTitle: pickedAction.title,
            initialMarkdown: pickedAction.markdown,
            initialEnableRiverCompose:
                pickedAction.provider == AccountProvider.riverSide,
            initialEnableQingCompose:
                pickedAction.provider == AccountProvider.qingShuiHePan,
            initialSelectedRiverCategoryId:
                pickedAction.provider == AccountProvider.riverSide
                ? pickedAction.categoryId
                : null,
            initialSelectedQingBoardId:
                pickedAction.provider == AccountProvider.qingShuiHePan
                ? pickedAction.categoryId
                : null,
          ),
        ),
      );
      return;
    }
    _showSimpleToast('转帖成功');
    final createdId = pickedAction.createdTopicId;
    if (createdId != null && createdId > 0) {
      await Navigator.of(context).push(
        riverPageRoute<void>(
          builder: (_) => TopicDetailPage(
            dependencies: widget.dependencies,
            topicId: createdId,
            provider: pickedAction.provider,
            qingBoardId: pickedAction.provider == AccountProvider.qingShuiHePan
                ? pickedAction.categoryId
                : null,
          ),
        ),
      );
    }
  }

  void _showSimpleToast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showRiverSnackBar(message);
  }

  String _normalizeRiverSourceMarkdownForCrossPost(String source) {
    return source.replaceAllMapped(
      RegExp(r'upload://([^\s)\]]+)', caseSensitive: false),
      (match) => '$riverSideBaseUrl/uploads/short-url/${match.group(1) ?? ''}',
    );
  }

  Future<Map<String, String>> _loadRiverEmojiUrlsForTransferPreview() async {
    final cookie = widget.dependencies.accountStore.riverSideCookieHeaderFor(
      widget.dependencies.accountStore.activeRiverSideUsername ?? '',
    );
    if (cookie == null || cookie.trim().isEmpty) {
      return const <String, String>{};
    }
    try {
      return await widget.dependencies.accountStore.riverSideApiClient
          .fetchEmojiUrlMap(cookieHeader: cookie);
    } catch (_) {
      return const <String, String>{};
    }
  }

  bool _isValidCrossPostCategorySelection({
    required AccountProvider targetProvider,
    required int? categoryId,
    required RiverSideCategoryOption? category,
  }) {
    if (categoryId == null || categoryId <= 0 || category == null) {
      return false;
    }
    if (targetProvider != AccountProvider.qingShuiHePan) {
      return true;
    }
    // 清水河畔转帖需要具体可发帖板块；顶层分组（无 parent）不可直接发帖。
    return category.parentCategoryId != null;
  }

  Future<List<RiverSideCategoryOption>> _loadCrossPostTargetCategories(
    AccountProvider targetProvider,
  ) async {
    if (targetProvider == AccountProvider.riverSide) {
      final username = widget.dependencies.accountStore.activeRiverSideUsername;
      final cookie = widget.dependencies.accountStore.riverSideCookieHeaderFor(
        username ?? '',
      );
      if (username == null || username.trim().isEmpty) {
        throw const RiverSideApiException('请先登录 RiverSide 账号');
      }
      if (cookie == null || cookie.trim().isEmpty) {
        throw const RiverSideApiException('当前 RiverSide 登录态已失效');
      }
      var categories = await RiverSideCategoryStore.instance.load(
        apiClient: widget.dependencies.accountStore.riverSideApiClient,
        username: username,
        cookieHeader: cookie,
      );
      if (categories.isEmpty) {
        categories = await RiverSideCategoryStore.instance.load(
          apiClient: widget.dependencies.accountStore.riverSideApiClient,
          username: username,
          cookieHeader: cookie,
          forceRefresh: true,
        );
      }
      return categories;
    }
    return _loadQingCrossPostCategories();
  }

  Future<_CrossPostCategorySelection?> _selectCrossPostCategory({
    required AccountProvider targetProvider,
    required List<RiverSideCategoryOption> categories,
    required int? selectedCategoryId,
  }) async {
    if (categories.isEmpty) {
      return null;
    }
    final selected = await showModalBottomSheet<RiverSideCategoryOption?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return RiverSideCategoryPickerSheet(
          initialCategories: categories,
          selectedCategoryId: selectedCategoryId,
          allowSelectAll: false,
          onRefreshCategories: ({bool forceRefresh = false}) async {
            return targetProvider == AccountProvider.riverSide
                ? _loadCrossPostTargetCategories(AccountProvider.riverSide)
                : _loadQingCrossPostCategories(forceRefresh: forceRefresh);
          },
          onSelected: (category) {
            if (category != null) {
              Navigator.of(sheetContext).pop(category);
            }
          },
        );
      },
    );
    if (selected == null) {
      return null;
    }
    final refreshed = targetProvider == AccountProvider.riverSide
        ? categories
        : await _loadQingCrossPostCategories();
    return _CrossPostCategorySelection(
      selectedCategoryId: selected.id,
      categories: refreshed.isEmpty ? categories : refreshed,
    );
  }

  int? _pickFirstPublishableCategoryIdForCrossPost(
    List<RiverSideCategoryOption> source,
  ) {
    for (final item in source) {
      if (item.id > 0 && item.parentCategoryId != null) {
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

  Future<List<RiverSideCategoryOption>> _loadQingCrossPostCategories({
    bool forceRefresh = true,
  }) async {
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/_/forum/list';
    final uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        if (auth.userId != null && auth.userId! > 0) 'uid': '${auth.userId}',
        'accessToken': auth.token,
        'accessSecret': auth.secret,
        '_t': forceRefresh
            ? '${DateTime.now().millisecondsSinceEpoch}'
            : '${DateTime.now().millisecondsSinceEpoch ~/ 10000}',
      },
    );
    final response = await http
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': RiverServerConfig.instance.qingShuiHePanBaseUrl,
            if (auth.cookieHeader.trim().isNotEmpty)
              'Cookie': auth.cookieHeader.trim(),
          },
        )
        .timeout(const Duration(seconds: 16));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      return _loadQingCrossPostCategoriesLegacy(auth);
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if (map.containsKey('code')) {
      final code = _asInt(map['code']) ?? -1;
      if (code != 0) {
        return _loadQingCrossPostCategoriesLegacy(auth);
      }
      final parsed = _parseQingForumTreeCategoriesForCrossPost(map['data']);
      if (parsed.isNotEmpty) {
        return _injectQingDeveloperCategoryForCrossPost(parsed);
      }
      return _loadQingCrossPostCategoriesLegacy(auth);
    }
    if ('${map['rs']}' == '0') {
      throw RiverSideApiException('${map['errcode'] ?? '清水河畔板块加载失败'}'.trim());
    }
    return _injectQingDeveloperCategoryForCrossPost(
      _parseQingForumCategoriesForCrossPost(map['list']),
    );
  }

  Future<List<RiverSideCategoryOption>> _loadQingCrossPostCategoriesLegacy(
    QingShuiHePanAuth auth,
  ) async {
    final map = await _callQingApi(
      auth: auth,
      body: const <String, String>{'r': 'forum/forumlist'},
    );
    final parsed = _parseQingForumCategoriesForCrossPost(map['list']);
    return _injectQingDeveloperCategoryForCrossPost(parsed);
  }

  Future<List<_QingTopicTypeOption>> _loadQingCrossPostTopicTypes({
    required int boardId,
  }) async {
    if (boardId <= 0) {
      return const <_QingTopicTypeOption>[];
    }
    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
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
      return const <_QingTopicTypeOption>[];
    }
    final result = <_QingTopicTypeOption>[];
    final seenIds = <int>{};
    for (final raw in listRaw) {
      final node = _asStringDynamicMap(raw);
      if (node.isEmpty) {
        continue;
      }
      final id = _asInt(node['classificationType_id']);
      final name = _pickString(node, const <String>[
        'classificationType_name',
        'name',
      ]);
      if (id == null || id <= 0 || name.isEmpty || seenIds.contains(id)) {
        continue;
      }
      seenIds.add(id);
      result.add(_QingTopicTypeOption(id: id, name: name));
    }
    return result;
  }

  Future<_QingTopicTypeOption?> _selectQingCrossPostTopicType({
    required List<_QingTopicTypeOption> options,
    required int? selectedTypeId,
  }) async {
    if (options.isEmpty) {
      return null;
    }
    return showModalBottomSheet<_QingTopicTypeOption>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final item = options[index];
              final selected = item.id == selectedTypeId;
              return ListTile(
                title: Text(item.name),
                trailing: selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(item),
              );
            },
          ),
        );
      },
    );
  }

  List<RiverSideCategoryOption> _injectQingDeveloperCategoryForCrossPost(
    List<RiverSideCategoryOption> source,
  ) {
    if (!widget.dependencies.settingsController.developerModeEnabled) {
      return source;
    }
    const developerBoardId = 138;
    if (source.any((item) => item.id == developerBoardId)) {
      return source;
    }
    final next = List<RiverSideCategoryOption>.from(source);
    next.add(
      RiverSideCategoryOption(
        id: developerBoardId,
        name: '开发者专区',
        position: next.length + 1,
        parentCategoryId: null,
        description: '',
      ),
    );
    return next;
  }

  List<RiverSideCategoryOption> _parseQingForumTreeCategoriesForCrossPost(
    dynamic dataRaw,
  ) {
    if (dataRaw is! List) {
      return const <RiverSideCategoryOption>[];
    }
    final categories = <RiverSideCategoryOption>[];
    final seenIds = <int>{};
    var position = 0;
    var syntheticParentSeed = 1;

    bool canPostThread(Map<String, dynamic> node) {
      final raw = node['can_post_thread'];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      final text = '$raw'.trim().toLowerCase();
      return text == '1' || text == 'true';
    }

    void addTopLevel({required int id, required String name}) {
      categories.add(
        RiverSideCategoryOption(
          id: id,
          name: name,
          position: position++,
          parentCategoryId: null,
          description: '',
        ),
      );
      seenIds.add(id);
    }

    void walkChildren(
      List<dynamic> children, {
      required int parentId,
      required List<String> path,
    }) {
      for (final rawChild in children) {
        final node = _asStringDynamicMap(rawChild);
        if (node.isEmpty) continue;
        final fid = _asInt(node['fid']);
        final name = _pickString(node, const <String>['name']);
        if (name.isEmpty) continue;

        final nextPath = <String>[...path, name];
        if (fid != null &&
            fid > 0 &&
            canPostThread(node) &&
            !seenIds.contains(fid)) {
          final label = nextPath.length <= 1
              ? name
              : nextPath.sublist(1).join(' / ');
          categories.add(
            RiverSideCategoryOption(
              id: fid,
              name: label,
              position: position++,
              parentCategoryId: parentId,
              description: '',
            ),
          );
          seenIds.add(fid);
        }

        final nestedChildren = node['children'];
        if (nestedChildren is List && nestedChildren.isNotEmpty) {
          walkChildren(nestedChildren, parentId: parentId, path: nextPath);
        }
      }
    }

    for (final rawRoot in dataRaw) {
      final root = _asStringDynamicMap(rawRoot);
      if (root.isEmpty) continue;
      final rootName = _pickString(root, const <String>['name']);
      if (rootName.isEmpty) continue;
      final rootFid = _asInt(root['fid']);

      final canUseRootAsParent =
          rootFid != null && rootFid > 0 && canPostThread(root);
      final parentId = canUseRootAsParent
          ? rootFid
          : -(900000 + syntheticParentSeed++);
      if (!seenIds.contains(parentId)) {
        addTopLevel(id: parentId, name: rootName);
      }

      final children = root['children'];
      if (children is List && children.isNotEmpty) {
        walkChildren(children, parentId: parentId, path: <String>[rootName]);
      }
    }
    return categories;
  }

  List<RiverSideCategoryOption> _parseQingForumCategoriesForCrossPost(
    dynamic listRaw,
  ) {
    if (listRaw is! List) {
      return const <RiverSideCategoryOption>[];
    }
    final categories = <RiverSideCategoryOption>[];
    final seenBoardIds = <int>{};
    var position = 0;
    var syntheticParentSeed = 1;

    for (final rawGroup in listRaw) {
      final group = _asStringDynamicMap(rawGroup);
      if (group.isEmpty) continue;
      final groupName = _pickString(group, const <String>[
        'board_category_name',
        'category_name',
        'name',
      ]);
      final groupIdRaw = _asInt(group['board_category_id']);
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
      if (boardList is! List) continue;
      for (final rawBoard in boardList) {
        final board = _asStringDynamicMap(rawBoard);
        if (board.isEmpty) continue;
        final boardId = _asInt(board['board_id']);
        if (boardId == null || boardId <= 0 || seenBoardIds.contains(boardId)) {
          continue;
        }
        final boardName = _pickString(board, const <String>[
          'board_name',
          'forum_name',
          'name',
        ]);
        if (boardName.isEmpty) continue;
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
    return categories;
  }

  Future<int?> _submitCrossPost({
    required AccountProvider targetProvider,
    required int categoryId,
    int? qingTypeId,
    required String title,
    required String markdown,
  }) async {
    if (targetProvider == AccountProvider.riverSide) {
      final username = widget.dependencies.accountStore.activeRiverSideUsername;
      final cookie = widget.dependencies.accountStore.riverSideCookieHeaderFor(
        username ?? '',
      );
      if (username == null || username.trim().isEmpty) {
        throw const RiverSideApiException('请先登录 RiverSide 账号');
      }
      if (cookie == null || cookie.trim().isEmpty) {
        throw const RiverSideApiException('当前 RiverSide 登录态已失效');
      }
      final result = await widget.dependencies.accountStore.riverSideApiClient
          .createTopic(
            title: title,
            raw: markdown,
            categoryId: categoryId,
            cookieHeader: cookie,
          );
      return result.topicId;
    }

    final auth = _activeQingAuth();
    if (auth == null) {
      throw const RiverSideApiException('请先登录清水河畔账号');
    }
    final normalized = QingEmojiCatalog.normalizeForSubmit(markdown).trim();
    final payloadContent = _buildQingCrossPostPayloadContent(normalized);
    if (payloadContent.contentList.isEmpty) {
      throw const RiverSideApiException('正文不能为空');
    }
    final payload = <String, dynamic>{
      'body': <String, dynamic>{
        'json': <String, dynamic>{
          'isAnonymous': 0,
          'isOnlyAuthor': 0,
          'typeId': qingTypeId == null || qingTypeId <= 0 ? '' : qingTypeId,
          if (payloadContent.aids.isNotEmpty)
            'aid': payloadContent.aids.join(','),
          'fid': categoryId,
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
    return _pickQingCrossPostTopicId(resp);
  }

  _QingReplyPayload _buildQingCrossPostPayloadContent(String markdown) {
    final source = markdown.trim();
    if (source.isEmpty) {
      return const _QingReplyPayload(
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
      final resolved = _resolveQingUrl(rawUrl);
      if (resolved.isNotEmpty) {
        contentList.add(<String, dynamic>{'type': 1, 'infor': resolved});
      } else if (rawUrl.isNotEmpty) {
        contentList.add(<String, dynamic>{'type': 1, 'infor': rawUrl});
      }
      cursor = match.end;
    }
    final tail = source.substring(cursor).trim();
    if (tail.isNotEmpty) {
      contentList.add(<String, dynamic>{'type': 0, 'infor': tail});
    }
    return _QingReplyPayload(
      contentList: contentList,
      aids: aids.toList(growable: false),
    );
  }

  int? _pickQingCrossPostTopicId(Map<String, dynamic> map) {
    final body = _asStringDynamicMap(map['body']);
    final topic = _asStringDynamicMap(body['topic']);
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
      final value = _asInt(raw);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  String _buildReplyPayload({
    required String markdown,
    String? quoteUsername,
    int? quotePostNumber,
    int? quoteTopicId,
    String? quoteContent,
  }) {
    final body = markdown.trim();
    if (body.isEmpty) {
      return '';
    }

    final username = _normalizeMentionUsernameToken(
      quoteUsername?.trim() ?? '',
    );
    final postNumber = quotePostNumber ?? 0;
    final topicId = quoteTopicId ?? 0;
    final content = (quoteContent ?? '').trim();
    if (username.isEmpty ||
        postNumber <= 0 ||
        topicId <= 0 ||
        content.isEmpty) {
      return body;
    }

    return '[quote="$username, post:$postNumber, topic:$topicId"]\n'
        '$content\n'
        '[/quote]\n\n'
        '$body';
  }

  RiverMarkdownDraftEntry _mapDraftToEditorEntry(RiverSideComposerDraft draft) {
    final subtitle = draft.markdown.trim().isNotEmpty
        ? draft.markdown.trim()
        : '无内容';
    return RiverMarkdownDraftEntry(
      draftKey: draft.draftKey,
      sequence: draft.sequence,
      markdown: draft.markdown,
      title: draft.title,
      subtitle: subtitle,
      updatedAt: draft.createdAt,
    );
  }

  String _replyDraftKey({required int topicId, int? replyToPostNumber}) {
    return 'river_reply_${topicId}_${replyToPostNumber ?? 0}';
  }

  String _editDraftKey(int postId) => 'river_edit_$postId';

  Future<List<RiverMarkdownDraftEntry>> _loadTopicDraftsForEditor({
    required bool Function(RiverSideComposerDraft draft) filter,
  }) async {
    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return const <RiverMarkdownDraftEntry>[];
    }
    final drafts = await widget.dependencies.accountStore.riverSideApiClient
        .fetchComposerDrafts(cookieHeader: cookie, offset: 0, limit: 50);
    return drafts
        .where(filter)
        .map(_mapDraftToEditorEntry)
        .toList(growable: false);
  }

  Future<bool> _deleteTopicDraftForEditor(RiverMarkdownDraftEntry draft) async {
    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return false;
    }
    await widget.dependencies.accountStore.riverSideApiClient
        .deleteComposerDraft(
          draftKey: draft.draftKey,
          sequence: draft.sequence,
          cookieHeader: cookie,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showRiverSnackBar('草稿已删除');
    }
    return true;
  }

  Future<String?> _uploadReplyImage(String fileName, List<int> bytes) async {
    final picUiInserted = await _uploadImageViaPicUiIfEnabled(
      fileName: fileName,
      bytes: bytes,
    );
    if (picUiInserted != null) {
      return picUiInserted;
    }

    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      throw const RiverSideApiException(
        _TopicDetailPageState._labelReplyNeedLogin,
      );
    }

    final uploaded = await widget.dependencies.accountStore.riverSideApiClient
        .uploadComposerImage(
          cookieHeader: cookieHeader,
          fileName: fileName,
          bytes: bytes,
        );
    final resolved = uploaded.startsWith('upload://')
        ? uploaded
        : _resolveForumUrl(uploaded);
    return '![]($resolved)';
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
      _showSimpleToast('PicUI 上传失败，已回退论坛上传：$error');
      return null;
    }
  }

  void _appendPublishedReply(RiverSideTopicPostDetail created) {
    final detail = _detail;
    if (detail == null || created.topicId != detail.topicId) {
      return;
    }

    if (created.postNumber <= 1 || detail.mainPost.id == created.id) {
      _detail = detail.copyWith(mainPost: created);
      _loadedPostIds.add(created.id);
      return;
    }

    final nextComments = <RiverSideTopicPostDetail>[..._comments];
    final existingIndex = nextComments.indexWhere(
      (item) => item.id == created.id,
    );
    var added = false;
    if (existingIndex >= 0) {
      nextComments[existingIndex] = created;
    } else {
      added = true;
      nextComments.add(created);
      _loadedPostIds.add(created.id);
    }
    nextComments.sort((a, b) => a.postNumber.compareTo(b.postNumber));

    final nextStream = detail.streamPostIds.contains(created.id)
        ? detail.streamPostIds
        : <int>[...detail.streamPostIds, created.id];

    _comments = nextComments;
    _detail = detail.copyWith(
      replyCount: added ? detail.replyCount + 1 : detail.replyCount,
      streamPostIds: nextStream,
      loadedPostIds: <int>{..._loadedPostIds},
    );
  }

  Future<bool> _submitReply({
    required int topicId,
    required String markdown,
    int? replyToPostNumber,
    String? quoteUsername,
    int? quoteTopicId,
    String? quoteContent,
  }) async {
    if (_isQingShuiHePanTopic) {
      return _submitQingReply(
        topicId: topicId,
        markdown: markdown,
        replyToPostNumber: replyToPostNumber,
      );
    }
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplyNeedLogin);
      return false;
    }

    try {
      final payload = _buildReplyPayload(
        markdown: markdown,
        quoteUsername: quoteUsername,
        quotePostNumber: replyToPostNumber,
        quoteTopicId: quoteTopicId ?? topicId,
        quoteContent: quoteContent,
      );
      final created = await widget.dependencies.accountStore.riverSideApiClient
          .createTopicReply(
            topicId: topicId,
            raw: payload,
            replyToPostNumber: replyToPostNumber,
            cookieHeader: cookieHeader,
          );
      if (!mounted) {
        return false;
      }

      _mutateState(() {
        _appendPublishedReply(created);
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplySuccess);

      if (topicId == (_detail?.topicId ?? -1)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _jumpToPostNumber(
            postNumber: created.postNumber,
            topicId: created.topicId,
          );
        });
      }
      return true;
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
      return false;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('\u56de\u590d\u53d1\u9001\u5931\u8d25');
      return false;
    }
  }

  Future<bool> _submitQingReply({
    required int topicId,
    required String markdown,
    int? replyToPostNumber,
  }) async {
    final auth = _activeQingAuth();
    if (auth == null) {
      ScaffoldMessenger.of(context).showRiverSnackBar(_loginRequiredLabel);
      return false;
    }

    final replyText = QingEmojiCatalog.normalizeForSubmit(markdown).trim();
    final parsed = _buildQingReplyContentAndAids(replyText);
    if (parsed.contentList.isEmpty) {
      return false;
    }
    final replyId = replyToPostNumber == null
        ? 0
        : (_qingReplyIdByPostNumber[replyToPostNumber] ?? 0);
    final payload = <String, dynamic>{
      'body': <String, dynamic>{
        'json': <String, dynamic>{
          'content': jsonEncode(parsed.contentList),
          'contentList': parsed.contentList,
          if (parsed.aids.isNotEmpty) 'aid': parsed.aids.join(','),
          'fid': _qingBoardId ?? widget.qingBoardId ?? 0,
          'isAnonymous': 0,
          'isOnlyAuthor': 0,
          'isQuote': replyId > 0 ? '1' : '0',
          'replyId': '$replyId',
          'tid': '$topicId',
          'typeId': '',
        },
      },
    };

    try {
      await _callQingApi(
        auth: auth,
        body: <String, String>{
          'r': 'forum/topicadmin',
          'act': 'reply',
          'json': jsonEncode(payload),
        },
      );
      if (!mounted) {
        return false;
      }
      _qingUploadedImagesByUrl.clear();
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplySuccess);
      // Keep behavior aligned with RiverSide: return success quickly so editor
      // can close immediately, then refresh list asynchronously.
      unawaited(_refreshQingAfterReplyPosted());
      return true;
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
      return false;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('回复发送失败');
      return false;
    }
  }

  Future<void> _refreshQingAfterReplyPosted() async {
    if (!mounted) {
      return;
    }
    try {
      await _loadInitial();
      if (!mounted) {
        return;
      }
      await _jumpToLatestComment();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('评论刷新失败，请手动下拉刷新');
    }
  }

  _QingReplyPayload _buildQingReplyContentAndAids(String normalizedMarkdown) {
    final source = normalizedMarkdown.trim();
    if (source.isEmpty) {
      return const _QingReplyPayload(
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
      final resolvedUrl = _resolveQingUrl(rawUrl);
      if (resolvedUrl.isNotEmpty) {
        final uploaded =
            _qingUploadedImagesByUrl[resolvedUrl] ??
            _qingUploadedImagesByUrl[rawUrl];
        if (uploaded != null) {
          contentList.add(<String, dynamic>{
            'type': 1,
            'infor': uploaded.urlName,
          });
          if (uploaded.aid.trim().isNotEmpty) {
            aids.add(uploaded.aid.trim());
          }
        } else {
          contentList.add(<String, dynamic>{'type': 1, 'infor': rawUrl});
        }
      }
      cursor = match.end;
    }
    final tail = source.substring(cursor).trim();
    if (tail.isNotEmpty) {
      contentList.add(<String, dynamic>{'type': 0, 'infor': tail});
    }
    return _QingReplyPayload(
      contentList: contentList,
      aids: aids.toList(growable: false),
    );
  }

  Future<String?> _uploadQingReplyImage(
    String fileName,
    List<int> bytes,
  ) async {
    final picUiInserted = await _uploadImageViaPicUiIfEnabled(
      fileName: fileName,
      bytes: bytes,
    );
    if (picUiInserted != null) {
      return picUiInserted;
    }

    final auth = _activeQingAuth();
    if (auth == null) {
      throw RiverSideApiException(_loginRequiredLabel);
    }
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php'
        '?r=forum/sendattachmentex&type=image&module=forum'
        '&accessToken=${Uri.encodeQueryComponent(auth.token)}'
        '&accessSecret=${Uri.encodeQueryComponent(auth.secret)}';
    final mediaType = _guessImageMediaType(fileName);
    final normalizedFileName = _normalizeUploadFileName(fileName, mediaType);
    Map<String, dynamic> map;
    try {
      map = await _uploadQingImageWithField(
        endpoint: endpoint,
        fieldName: 'uploadFile[]',
        fileName: normalizedFileName,
        bytes: bytes,
        mediaType: mediaType,
      );
    } on RiverSideApiException catch (error) {
      // Some deployments only accept `uploadFile` (without brackets).
      final msg = error.message.toLowerCase();
      if (!(msg.contains('结果为空') ||
          msg.contains('返回异常') ||
          msg.contains('格式') ||
          msg.contains('uploadfile'))) {
        rethrow;
      }
      map = await _uploadQingImageWithField(
        endpoint: endpoint,
        fieldName: 'uploadFile',
        fileName: normalizedFileName,
        bytes: bytes,
        mediaType: mediaType,
      );
    }

    if ('${map['rs']}' == '0') {
      final head = map['head'] is Map
          ? (map['head'] as Map)
          : const <dynamic, dynamic>{};
      final message =
          '${head['errInfo'] ?? head['errCode'] ?? map['errcode'] ?? '图片上传失败'}'
              .trim();
      throw RiverSideApiException(message.isEmpty ? '图片上传失败' : message);
    }
    final body = map['body'] is Map
        ? (map['body'] as Map)
        : const <dynamic, dynamic>{};
    final attachments = _normalizeQingAttachmentList(
      _pickQingAttachmentRaw(body),
    );
    if (attachments.isEmpty) {
      throw RiverSideApiException(
        '图片上传结果为空: ${jsonEncode(body).substring(0, math.min(300, jsonEncode(body).length))}',
      );
    }
    final att = attachments.first;
    final aid = '${att['id'] ?? att['aid'] ?? ''}'.trim();
    final urlName =
        '${att['urlName'] ?? att['url'] ?? att['attachmentUrl'] ?? ''}'.trim();
    if (urlName.isEmpty) {
      throw const RiverSideApiException('图片地址为空');
    }
    final resolvedUrl = _resolveQingAttachmentUrl(urlName);
    if (resolvedUrl.isEmpty) {
      throw const RiverSideApiException('图片地址解析失败');
    }
    final record = _QingReplyUploadImage(
      aid: aid,
      urlName: urlName,
      resolvedUrl: resolvedUrl,
    );
    _qingUploadedImagesByUrl[urlName] = record;
    _qingUploadedImagesByUrl[resolvedUrl] = record;
    return '![]($resolvedUrl)';
  }

  Future<Map<String, dynamic>> _uploadQingImageWithField({
    required String endpoint,
    required String fieldName,
    required String fileName,
    required List<int> bytes,
    required MediaType mediaType,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers['Accept'] = 'application/json, text/plain, */*'
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: fileName,
          contentType: mediaType,
        ),
      );
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RiverSideApiException(
        '图片上传失败(HTTP ${response.statusCode}): ${response.body}',
      );
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw RiverSideApiException(
        '图片上传返回异常: ${text.substring(0, math.min(200, text.length))}',
      );
    }
    return decoded.map((k, v) => MapEntry('$k', v));
  }

  dynamic _pickQingAttachmentRaw(Map<dynamic, dynamic> body) {
    if (body['attachment'] != null) {
      return body['attachment'];
    }
    final externInfo = body['externInfo'];
    if (externInfo is Map && externInfo['attachment'] != null) {
      return externInfo['attachment'];
    }
    return null;
  }

  MediaType _guessImageMediaType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.gif')) {
      return MediaType('image', 'gif');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return MediaType('image', 'heic');
    }
    return MediaType('image', 'jpeg');
  }

  String _normalizeUploadFileName(String fileName, MediaType mediaType) {
    final raw = fileName.trim();
    if (raw.isEmpty) {
      return 'image.${mediaType.subtype == 'png' ? 'png' : 'jpg'}';
    }
    if (raw.contains('.')) {
      return raw;
    }
    if (mediaType.subtype == 'png') {
      return '$raw.png';
    }
    if (mediaType.subtype == 'gif') {
      return '$raw.gif';
    }
    if (mediaType.subtype == 'webp') {
      return '$raw.webp';
    }
    if (mediaType.subtype == 'heic') {
      return '$raw.heic';
    }
    return '$raw.jpg';
  }

  List<Map<String, dynamic>> _normalizeQingAttachmentList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e is Map ? e.map((k, v) => MapEntry('$k', v)) : null)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }
    if (raw is Map) {
      final list = <Map<String, dynamic>>[];
      for (final value in raw.values) {
        if (value is Map) {
          list.add(value.map((k, v) => MapEntry('$k', v)));
        }
      }
      if (list.isNotEmpty) {
        return list;
      }
      return <Map<String, dynamic>>[raw.map((k, v) => MapEntry('$k', v))];
    }
    return const <Map<String, dynamic>>[];
  }

  String _resolveQingAttachmentUrl(String source) {
    final raw = source.trim();
    if (raw.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) {
      return raw;
    }
    final decoded = raw.replaceAll('&amp;', '&');
    try {
      final base = Uri.parse(RiverServerConfig.instance.qingShuiHePanBaseUrl);
      return base.resolve(decoded).toString();
    } catch (_) {
      return '';
    }
  }

  Future<List<RiverMarkdownMentionUser>> _searchMentionUsersForEditor(
    String query,
  ) async {
    if (_isQingShuiHePanTopic) {
      return _searchQingMentionUsersForEditor(query);
    }
    return _searchRiverMentionUsersForEditor(query);
  }

  Future<List<RiverMarkdownMentionUser>> _searchRiverMentionUsersForEditor(
    String query,
  ) async {
    final normalized = query.trim().toLowerCase();
    final local = _collectRiverMentionUsersFromTopic();
    List<RiverMarkdownMentionUser> filteredLocal;
    if (normalized.isEmpty) {
      filteredLocal = local.take(20).toList(growable: false);
    } else {
      filteredLocal = local
          .where((item) {
            final username = item.username.toLowerCase();
            final display = item.displayName.toLowerCase();
            return username.contains(normalized) ||
                display.contains(normalized);
          })
          .take(20)
          .toList(growable: false);
    }

    if (normalized.isEmpty) {
      return filteredLocal;
    }
    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return filteredLocal;
    }
    try {
      final remote = await widget.dependencies.accountStore.riverSideApiClient
          .searchUsers(term: query.trim(), limit: 20, cookieHeader: cookie);
      final merged = <RiverMarkdownMentionUser>[
        for (final user in remote)
          RiverMarkdownMentionUser(
            key: 'river_${user.username.toLowerCase()}',
            insertText: user.username,
            displayName: user.displayName,
            username: user.username,
            avatarUrl: user.avatarUrl,
            subtitle: '@${user.username}',
          ),
        ...filteredLocal,
      ];
      return _dedupeMentionUsers(merged);
    } catch (_) {
      return filteredLocal;
    }
  }

  List<RiverMarkdownMentionUser> _collectRiverMentionUsersFromTopic() {
    final seen = <String>{};
    final result = <RiverMarkdownMentionUser>[];

    void push(RiverSideTopicPostDetail post) {
      final username = post.authorUsername.trim();
      if (username.isEmpty) {
        return;
      }
      final key = username.toLowerCase();
      if (seen.contains(key)) {
        return;
      }
      seen.add(key);
      final display = post.authorDisplayName.trim();
      result.add(
        RiverMarkdownMentionUser(
          key: 'river_$key',
          insertText: username,
          displayName: display.isEmpty ? username : display,
          username: username,
          avatarUrl: post.authorAvatarUrl,
          subtitle: '@$username',
        ),
      );
    }

    final detail = _detail;
    if (detail != null) {
      push(detail.mainPost);
    }
    for (final post in _comments) {
      push(post);
      if (result.length >= 24) {
        break;
      }
    }
    return result;
  }

  Future<List<RiverMarkdownMentionUser>> _searchQingMentionUsersForEditor(
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
          final item = _asStringDynamicMap(raw);
          if (item.isEmpty) {
            continue;
          }
          final uid = _asInt(item['uid']) ?? 0;
          final name = _pickString(item, const <String>[
            'name',
            'user_nick_name',
            'nickname',
          ]);
          final username = _pickString(item, const <String>[
            'user_name',
            'username',
          ]);
          final avatar = _resolveQingUrl(
            _pickString(item, const <String>['icon', 'avatar', 'userAvatar']),
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
        final searchMap = await _callQingApi(
          auth: auth,
          body: <String, String>{
            'r': 'user/searchuser',
            'keyword': query.trim(),
            'page': '1',
            'pageSize': '20',
          },
        );
        final bodyMap = _asStringDynamicMap(searchMap['body']);
        final listRaw = searchMap['list'] ?? bodyMap['list'];
        if (listRaw is List) {
          for (final raw in listRaw) {
            final item = _asStringDynamicMap(raw);
            if (item.isEmpty) {
              continue;
            }
            final uid = _asInt(item['uid']) ?? 0;
            final name = _pickString(item, const <String>[
              'name',
              'user_nick_name',
              'nick_name',
              'nickname',
            ]);
            final username = _pickString(item, const <String>[
              'user_name',
              'username',
              'userName',
            ]);
            final avatar = _resolveQingUrl(
              _pickString(item, const <String>['icon', 'avatar', 'userAvatar']),
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

    return _dedupeMentionUsers(result);
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

  Future<void> _openReplyComposer({
    required int topicId,
    int? replyToPostNumber,
    String? quoteUsername,
    int? quoteTopicId,
    String? quoteContent,
    String? aiReferenceText,
  }) async {
    if (_isQingShuiHePanTopic) {
      _qingUploadedImagesByUrl.clear();
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return RiverMarkdownEditor(
            title: _TopicDetailPageState._labelReplyEditorTitle,
            submitLabel: _TopicDetailPageState._labelReply,
            initialText: '',
            emojiUrls: _emojiUrls,
            emojiGroups: _emojiGroups,
            onSearchMentionUsers: _searchMentionUsersForEditor,
            emojiInsertFormatter: QingEmojiCatalog.tokenFromKey,
            aiScene: RiverMarkdownAiScene.topicReply,
            aiReplyReferenceText: (aiReferenceText ?? '').trim().isNotEmpty
                ? aiReferenceText
                : quoteContent,
            onAiGenerateStream: _generateAiContentStreamForEditor,
            maxHeight: MediaQuery.sizeOf(context).height * 0.74,
            onUploadImage: _uploadQingReplyImage,
            onSubmit: (markdown) {
              return _submitQingReply(
                topicId: topicId,
                markdown: markdown,
                replyToPostNumber: replyToPostNumber,
              );
            },
          );
        },
      );
      return;
    }

    final draftKey = _replyDraftKey(
      topicId: topicId,
      replyToPostNumber: replyToPostNumber,
    );

    Future<RiverMarkdownDraftEntry?> loadCurrentDraft() async {
      final cookie = _activeCookieHeader();
      if (cookie == null || cookie.trim().isEmpty) {
        return null;
      }
      final draft = await widget.dependencies.accountStore.riverSideApiClient
          .fetchComposerDraft(draftKey: draftKey, cookieHeader: cookie);
      if (draft == null) {
        return null;
      }
      return _mapDraftToEditorEntry(draft);
    }

    Future<RiverMarkdownDraftEntry?> saveDraft(
      String markdown,
      int? sequence,
    ) async {
      final cookie = _activeCookieHeader();
      if (cookie == null || cookie.trim().isEmpty) {
        return null;
      }
      final nextSequence = await widget
          .dependencies
          .accountStore
          .riverSideApiClient
          .saveComposerDraft(
            draftKey: draftKey,
            sequence: sequence ?? 0,
            data: <String, dynamic>{
              'reply': markdown,
              'action': 'reply',
              'topicId': topicId,
              'postId': replyToPostNumber,
              'metaData': null,
              'archetypeId': 'regular',
            },
            cookieHeader: cookie,
          );
      return RiverMarkdownDraftEntry(
        draftKey: draftKey,
        sequence: nextSequence,
        markdown: markdown,
        title: '回复草稿',
        subtitle: markdown.trim(),
        updatedAt: DateTime.now(),
      );
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return RiverMarkdownEditor(
          title: _TopicDetailPageState._labelReplyEditorTitle,
          submitLabel: _TopicDetailPageState._labelReply,
          initialText: '',
          emojiUrls: _emojiUrls,
          emojiGroups: _emojiGroups,
          onSearchMentionUsers: _searchMentionUsersForEditor,
          aiScene: RiverMarkdownAiScene.topicReply,
          aiReplyReferenceText: (aiReferenceText ?? '').trim().isNotEmpty
              ? aiReferenceText
              : quoteContent,
          onAiGenerateStream: _generateAiContentStreamForEditor,
          maxHeight: MediaQuery.sizeOf(context).height * 0.74,
          onUploadImage: _uploadReplyImage,
          onLoadCurrentDraft: loadCurrentDraft,
          onSaveDraft: saveDraft,
          onLoadDrafts: () => _loadTopicDraftsForEditor(
            filter: (draft) {
              if (draft.action == 'reply' && draft.topicId == topicId) {
                return true;
              }
              return draft.draftKey == draftKey;
            },
          ),
          onDeleteDraft: _deleteTopicDraftForEditor,
          onSubmit: (markdown) {
            return _submitReply(
              topicId: topicId,
              markdown: markdown,
              replyToPostNumber: replyToPostNumber,
              quoteUsername: quoteUsername,
              quoteTopicId: quoteTopicId,
              quoteContent: quoteContent,
            );
          },
        );
      },
    );
  }

  bool _isOwnComment(RiverSideTopicPostDetail post) {
    if (_isQingShuiHePanTopic) {
      final active =
          widget.dependencies.accountStore.activeQingShuiHePanAccount;
      if (active == null) {
        return false;
      }
      final activeUserId = active.userId;
      if (activeUserId != null &&
          post.authorUserId != null &&
          activeUserId > 0 &&
          post.authorUserId! > 0) {
        return activeUserId == post.authorUserId;
      }
      final activeUsername = active.username.trim().toLowerCase();
      final activeDisplay = active.displayName.trim().toLowerCase();
      final authorUsername = post.authorUsername.trim().toLowerCase();
      final authorDisplay = post.authorDisplayName.trim().toLowerCase();
      return (activeUsername.isNotEmpty && activeUsername == authorUsername) ||
          (activeDisplay.isNotEmpty && activeDisplay == authorDisplay);
    }
    final active = widget.dependencies.accountStore.activeRiverSideUsername;
    if (active == null || active.trim().isEmpty) {
      return false;
    }
    return active.toLowerCase() == post.authorUsername.toLowerCase();
  }

  Future<void> _copyCommentContent(RiverSideTopicPostDetail post) async {
    final pureContent = _stripQuotedMarkdown(post.contentMarkdown);
    await Clipboard.setData(ClipboardData(text: pureContent));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showRiverSnackBar('\u5df2\u590d\u5236\u5230\u526a\u8d34\u677f');
  }

  void _replacePostInState(RiverSideTopicPostDetail updated) {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    if (detail.mainPost.id == updated.id) {
      _detail = detail.copyWith(mainPost: updated);
      return;
    }

    final index = _comments.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      return;
    }
    final next = <RiverSideTopicPostDetail>[..._comments];
    next[index] = updated;
    next.sort((a, b) => a.postNumber.compareTo(b.postNumber));
    _comments = next;
  }

  void _removePostFromState(RiverSideTopicPostDetail post) {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final nextComments = _comments.where((item) => item.id != post.id).toList();
    _comments = nextComments;
    _loadedPostIds.remove(post.id);
    _detail = detail.copyWith(
      replyCount: detail.replyCount > 0 ? detail.replyCount - 1 : 0,
      streamPostIds: detail.streamPostIds.where((id) => id != post.id).toList(),
      loadedPostIds: <int>{..._loadedPostIds},
    );
  }

  Future<bool> _submitEditComment({
    required RiverSideTopicPostDetail sourcePost,
    required String originalRaw,
    required String nextRaw,
  }) async {
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplyNeedLogin);
      return false;
    }

    try {
      final edited = await widget.dependencies.accountStore.riverSideApiClient
          .editPost(
            postId: sourcePost.id,
            topicId: sourcePost.topicId,
            raw: nextRaw,
            originalRaw: originalRaw,
            cookieHeader: cookieHeader,
          );
      if (!mounted) {
        return false;
      }
      _mutateState(() {
        _replacePostInState(edited);
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelEditCommentSuccess);
      return true;
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
      return false;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('\u7f16\u8f91\u8bc4\u8bba\u5931\u8d25');
      return false;
    }
  }

  Future<void> _openEditCommentComposer(RiverSideTopicPostDetail post) async {
    if (_isQingShuiHePanTopic) {
      return;
    }
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplyNeedLogin);
      return;
    }

    RiverSideTopicPostDetail original = post;
    try {
      original = await widget.dependencies.accountStore.riverSideApiClient
          .fetchPostById(postId: post.id, cookieHeader: cookieHeader);
    } catch (_) {}
    if (!mounted) {
      return;
    }

    final originalRaw = original.contentMarkdown;
    final draftKey = _editDraftKey(post.id);

    Future<RiverMarkdownDraftEntry?> loadCurrentDraft() async {
      final draft = await widget.dependencies.accountStore.riverSideApiClient
          .fetchComposerDraft(draftKey: draftKey, cookieHeader: cookieHeader);
      if (draft == null) {
        return null;
      }
      return _mapDraftToEditorEntry(draft);
    }

    Future<RiverMarkdownDraftEntry?> saveDraft(
      String markdown,
      int? sequence,
    ) async {
      final nextSequence = await widget
          .dependencies
          .accountStore
          .riverSideApiClient
          .saveComposerDraft(
            draftKey: draftKey,
            sequence: sequence ?? 0,
            data: <String, dynamic>{
              'reply': markdown,
              'action': 'edit',
              'topicId': post.topicId,
              'postId': post.id,
              'original_text': originalRaw,
              'metaData': null,
            },
            cookieHeader: cookieHeader,
          );
      return RiverMarkdownDraftEntry(
        draftKey: draftKey,
        sequence: nextSequence,
        markdown: markdown,
        title: '编辑评论草稿',
        subtitle: markdown.trim(),
        updatedAt: DateTime.now(),
      );
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return RiverMarkdownEditor(
          title: _TopicDetailPageState._labelEditCommentTitle,
          submitLabel: _TopicDetailPageState._labelSave,
          closeOnSubmitSuccess: false,
          initialText: originalRaw,
          emojiUrls: _emojiUrls,
          emojiGroups: _emojiGroups,
          onSearchMentionUsers: _searchMentionUsersForEditor,
          aiScene: RiverMarkdownAiScene.editComment,
          onAiGenerateStream: _generateAiContentStreamForEditor,
          maxHeight: MediaQuery.sizeOf(context).height * 0.74,
          onUploadImage: _uploadReplyImage,
          onLoadCurrentDraft: loadCurrentDraft,
          onSaveDraft: saveDraft,
          onLoadDrafts: () => _loadTopicDraftsForEditor(
            filter: (draft) =>
                draft.action == 'edit' || draft.draftKey == draftKey,
          ),
          onDeleteDraft: _deleteTopicDraftForEditor,
          onSubmit: (markdown) async {
            final ok = await _submitEditComment(
              sourcePost: original,
              originalRaw: originalRaw,
              nextRaw: markdown,
            );
            if (ok && sheetContext.mounted) {
              Navigator.of(sheetContext).pop(true);
            }
            return ok;
          },
        );
      },
    );
  }

  Future<void> _deleteComment(RiverSideTopicPostDetail post) async {
    if (_isQingShuiHePanTopic) {
      return;
    }
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplyNeedLogin);
      return;
    }

    final confirmed = await showRiverConfirmDialog(
      context: context,
      title: _TopicDetailPageState._labelDeleteCommentTitle,
      message: _TopicDetailPageState._labelDeleteCommentHint,
      cancelText: _TopicDetailPageState._labelCancel,
      confirmText: _TopicDetailPageState._labelDelete,
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.dependencies.accountStore.riverSideApiClient.deletePost(
        postId: post.id,
        topicId: post.topicId,
        postNumber: post.postNumber,
        cookieHeader: cookieHeader,
      );
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _removePostFromState(post);
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelDeleteCommentSuccess);
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('\u5220\u9664\u8bc4\u8bba\u5931\u8d25');
    }
  }

  Future<void> _deleteMainPost(RiverSideTopicPostDetail post) async {
    if (_isQingShuiHePanTopic) {
      return;
    }
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReplyNeedLogin);
      return;
    }

    final confirmed = await showRiverConfirmDialog(
      context: context,
      title: _TopicDetailPageState._labelDeleteMainPostTitle,
      message: _TopicDetailPageState._labelDeleteMainPostHint,
      cancelText: _TopicDetailPageState._labelCancel,
      confirmText: _TopicDetailPageState._labelDelete,
      icon: Icons.delete_forever_rounded,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.dependencies.accountStore.riverSideApiClient.deletePost(
        postId: post.id,
        topicId: post.topicId,
        postNumber: post.postNumber,
        cookieHeader: cookieHeader,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelDeleteMainPostSuccess);
      Navigator.of(context).pop(true);
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('\u5220\u9664\u4e3b\u8d34\u5931\u8d25');
    }
  }

  Future<void> _showCommentActions(RiverSideTopicPostDetail post) async {
    final own = !_isQingShuiHePanTopic && _isOwnComment(post);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text(
                  _TopicDetailPageState._labelActionCopyContent,
                ),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
              if (own)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text(
                    _TopicDetailPageState._labelActionEditComment,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              if (own)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text(
                    _TopicDetailPageState._labelActionDeleteComment,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'copy':
        await _copyCommentContent(post);
        break;
      case 'edit':
        await _openEditCommentComposer(post);
        break;
      case 'delete':
        await _deleteComment(post);
        break;
    }
  }
}

class _QingReplyPayload {
  const _QingReplyPayload({required this.contentList, required this.aids});

  final List<Map<String, dynamic>> contentList;
  final List<String> aids;
}

class _QingTopicTypeOption {
  const _QingTopicTypeOption({required this.id, required this.name});

  final int id;
  final String name;
}

enum _CrossPostActionType { edit, transfer }

class _CrossPostAction {
  const _CrossPostAction({
    required this.type,
    required this.provider,
    required this.categoryId,
    required this.title,
    required this.markdown,
    this.createdTopicId,
  });

  final _CrossPostActionType type;
  final AccountProvider provider;
  final int? categoryId;
  final String title;
  final String markdown;
  final int? createdTopicId;
}

class _CrossPostCategorySelection {
  const _CrossPostCategorySelection({
    required this.selectedCategoryId,
    required this.categories,
  });

  final int selectedCategoryId;
  final List<RiverSideCategoryOption> categories;
}

class _CrossPostTransferSheet extends StatelessWidget {
  const _CrossPostTransferSheet({
    required this.targetProvider,
    required this.targetLabel,
    required this.title,
    required this.markdown,
    required this.previewEmojiUrls,
    required this.topicId,
    required this.cookieHeader,
    required this.loadingCategories,
    required this.loadingError,
    required this.selectedCategoryText,
    required this.qingTypeEnabled,
    required this.loadingQingTypes,
    required this.loadingQingTypeError,
    required this.selectedQingTypeText,
    required this.transfering,
    required this.onPickCategory,
    required this.onPickQingType,
    required this.onRetryLoadCategories,
    required this.onRetryLoadQingTypes,
    required this.onEdit,
    required this.onTransfer,
  });

  final AccountProvider targetProvider;
  final String targetLabel;
  final String title;
  final String markdown;
  final Map<String, String> previewEmojiUrls;
  final int topicId;
  final String? cookieHeader;
  final bool loadingCategories;
  final String? loadingError;
  final String selectedCategoryText;
  final bool qingTypeEnabled;
  final bool loadingQingTypes;
  final String? loadingQingTypeError;
  final String selectedQingTypeText;
  final bool transfering;
  final VoidCallback? onPickCategory;
  final VoidCallback? onPickQingType;
  final VoidCallback? onRetryLoadCategories;
  final VoidCallback? onRetryLoadQingTypes;
  final VoidCallback? onEdit;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    targetProvider == AccountProvider.qingShuiHePan
                        ? 'assets/images/hp.png'
                        : 'assets/images/rs.png',
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '转帖到$targetLabel',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.28,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: _PostContent(
                        markdown: markdown,
                        topicId: topicId,
                        cookieHeader: cookieHeader,
                        emojiUrls: previewEmojiUrls,
                        onQuoteTap: (_) {},
                        onMentionTap: (_) {},
                        onTopicLinkTap: (_) {},
                        enableImageHero: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPickCategory,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    if (loadingCategories)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.dashboard_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loadingError ??
                            (loadingCategories
                                ? '加载板块中...'
                                : selectedCategoryText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (qingTypeEnabled) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPickQingType,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (loadingQingTypes)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.label_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loadingQingTypeError ??
                              (loadingQingTypes
                                  ? '加载主题类别中...'
                                  : selectedQingTypeText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (loadingError != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetryLoadCategories,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试加载板块'),
              ),
            ],
            if (loadingQingTypeError != null && qingTypeEnabled) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onRetryLoadQingTypes,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试加载主题类别'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTransfer,
                    icon: transfering
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(transfering ? '转帖中' : '转帖'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

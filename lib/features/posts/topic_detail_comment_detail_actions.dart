part of 'topic_detail_page.dart';

extension _CommentDetailPageActions on _CommentDetailPageState {
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

  Future<List<RiverMarkdownMentionUser>> _searchMentionUsersForEditor(
    String query,
  ) async {
    final normalized = query.trim().toLowerCase();
    final local = _collectRiverMentionUsersFromCommentDetail();
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

  List<RiverMarkdownMentionUser> _collectRiverMentionUsersFromCommentDetail() {
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

    push(_rootPost);
    for (final post in _replies) {
      push(post);
      if (result.length >= 24) {
        break;
      }
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

  List<_ReactionOption> _availableReactionOptionsForComment() {
    if (_validReactions.isEmpty) {
      return _defaultReactionOptions;
    }
    return _reactionOptionsFromIds(_validReactions);
  }

  Future<void> _onReactPressed(RiverSideTopicPostDetail post) async {
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_TopicDetailPageState._labelReactionNotReady);
      return;
    }

    final selected = await showModalBottomSheet<_ReactionOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ReactionPickerSheet(
          postId: post.id,
          options: _availableReactionOptionsForComment(),
          currentReactionId: post.currentUserReaction?.id,
          onSelected: (option) {
            _mutateState(() {
              _pendingReactionHeroByPostId[post.id] = option.id;
            });
            Navigator.of(sheetContext).pop(option);
          },
        );
      },
    );
    if (!mounted || selected == null) {
      return;
    }

    await _togglePostReaction(
      post: post,
      reactionId: selected.id,
      cookieHeader: cookieHeader,
    );
  }

  Future<void> _togglePostReaction({
    required RiverSideTopicPostDetail post,
    required String reactionId,
    required String cookieHeader,
  }) async {
    _mutateState(() {
      _reactingPostIds.add(post.id);
    });

    try {
      final state = await widget.dependencies.accountStore.riverSideApiClient
          .togglePostReaction(
            postId: post.id,
            reactionId: reactionId,
            cookieHeader: cookieHeader,
          );
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _applyPostReactionState(state);
        _hasMutations = true;
      });
    } on RiverSideApiException catch (error) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _pendingReactionHeroByPostId.remove(post.id);
      });
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _pendingReactionHeroByPostId.remove(post.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar('点赞操作失败');
    } finally {
      _mutateState(() {
        _reactingPostIds.remove(post.id);
      });
    }
  }

  void _applyPostReactionState(RiverSidePostReactionState state) {
    final clearCurrent = state.currentUserReaction == null;
    if (_rootPost.id == state.postId) {
      _rootPost = _rootPost.copyWith(
        reactions: state.reactions,
        currentUserReaction: state.currentUserReaction,
        clearCurrentUserReaction: clearCurrent,
        reactionUsersCount: state.reactionUsersCount,
      );
    }

    final index = _replies.indexWhere((post) => post.id == state.postId);
    if (index >= 0) {
      final next = <RiverSideTopicPostDetail>[..._replies];
      final current = next[index];
      next[index] = current.copyWith(
        reactions: state.reactions,
        currentUserReaction: state.currentUserReaction,
        clearCurrentUserReaction: clearCurrent,
        reactionUsersCount: state.reactionUsersCount,
      );
      _replies = next;
    }

    _pendingReactionHeroByPostId.remove(state.postId);
    _reactionPulseTokenByPostId[state.postId] =
        (_reactionPulseTokenByPostId[state.postId] ?? 0) + 1;
  }

  Future<void> _onReactionStatusPressed({
    required RiverSideTopicPostDetail post,
    required String reactionId,
  }) async {
    try {
      final groups = await widget.dependencies.accountStore.riverSideApiClient
          .fetchPostReactionUsers(
            postId: post.id,
            reactionId: reactionId,
            cookieHeader: _activeCookieHeader(),
          );
      if (!mounted) {
        return;
      }

      RiverSidePostReactionUsersGroup? group;
      for (final item in groups) {
        if (item.id == reactionId) {
          group = item;
          break;
        }
      }
      group ??= groups.isEmpty ? null : groups.first;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return _ReactionUsersSheet(
            postId: post.id,
            reactionId: reactionId,
            group: group,
          );
        },
      );
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
      ).showRiverSnackBar(_TopicDetailPageState._labelReactionUsersEmpty);
    }
  }

  Future<void> _openAuthorProfileSheetForPost(
    RiverSideTopicPostDetail post,
  ) async {
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

  Future<void> _openMentionProfileFromContent(String username) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return;
    }
    await showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: normalized,
    );
  }

  Future<void> _openTopicFromContent(int topicId) async {
    if (topicId <= 0 || topicId == _rootPost.topicId) {
      return;
    }
    await Navigator.of(context).push(
      DraggableRoute<void>(
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: topicId,
        ),
      ),
    );
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

  String _replyDraftKey({int? replyToPostNumber}) {
    return 'river_reply_${_rootPost.topicId}_${replyToPostNumber ?? 0}';
  }

  String _editDraftKey(int postId) => 'river_edit_$postId';

  Future<List<RiverMarkdownDraftEntry>> _loadCommentDetailDraftsForEditor({
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

  Future<bool> _deleteCommentDetailDraftForEditor(
    RiverMarkdownDraftEntry draft,
  ) async {
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
        _CommentDetailPageState._labelReplyNeedLogin,
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showRiverSnackBar('PicUI 上传失败，已回退论坛上传：$error');
      }
      return null;
    }
  }

  Future<bool> _submitReply({
    required String markdown,
    int? replyToPostNumber,
    String? quoteUsername,
    int? quoteTopicId,
    String? quoteContent,
  }) async {
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelReplyNeedLogin);
      return false;
    }

    try {
      final payload = _buildReplyPayload(
        markdown: markdown,
        quoteUsername: quoteUsername,
        quotePostNumber: replyToPostNumber,
        quoteTopicId: quoteTopicId ?? _rootPost.topicId,
        quoteContent: quoteContent,
      );
      await widget.dependencies.accountStore.riverSideApiClient
          .createTopicReply(
            topicId: _rootPost.topicId,
            raw: payload,
            replyToPostNumber: replyToPostNumber,
            cookieHeader: cookieHeader,
          );
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelReplySuccess);
      await _loadData();
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
      ).showRiverSnackBar('回复发送失败');
      return false;
    }
  }

  Future<void> _openReplyComposer({
    int? replyToPostNumber,
    String? quoteUsername,
    int? quoteTopicId,
    String? quoteContent,
  }) async {
    final draftKey = _replyDraftKey(replyToPostNumber: replyToPostNumber);

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
              'topicId': _rootPost.topicId,
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
          aiReplyReferenceText: quoteContent,
          onAiGenerateStream: _generateAiContentStreamForEditor,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          onUploadImage: _uploadReplyImage,
          onLoadCurrentDraft: loadCurrentDraft,
          onSaveDraft: saveDraft,
          onLoadDrafts: () => _loadCommentDetailDraftsForEditor(
            filter: (draft) {
              if (draft.action == 'reply' &&
                  draft.topicId == _rootPost.topicId) {
                return true;
              }
              return draft.draftKey == draftKey;
            },
          ),
          onDeleteDraft: _deleteCommentDetailDraftForEditor,
          onSubmit: (markdown) => _submitReply(
            markdown: markdown,
            replyToPostNumber: replyToPostNumber,
            quoteUsername: quoteUsername,
            quoteTopicId: quoteTopicId,
            quoteContent: quoteContent,
          ),
        );
      },
    );
  }

  bool _isOwnComment(RiverSideTopicPostDetail post) {
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
    ).showRiverSnackBar('已复制到剪贴板');
  }

  void _replacePostInState(RiverSideTopicPostDetail updated) {
    if (_rootPost.id == updated.id) {
      _rootPost = updated;
      return;
    }

    final index = _replies.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      return;
    }
    final next = <RiverSideTopicPostDetail>[..._replies];
    next[index] = updated;
    next.sort((a, b) => a.postNumber.compareTo(b.postNumber));
    _replies = next;
  }

  void _removePostFromState(RiverSideTopicPostDetail post) {
    _replies = _replies.where((item) => item.id != post.id).toList();
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
      ).showRiverSnackBar(_CommentDetailPageState._labelReplyNeedLogin);
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
        _hasMutations = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelEditCommentSuccess);
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
      ).showRiverSnackBar('编辑评论失败');
      return false;
    }
  }

  Future<void> _openEditCommentComposer(RiverSideTopicPostDetail post) async {
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelReplyNeedLogin);
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
          title: _CommentDetailPageState._labelEditCommentTitle,
          submitLabel: _CommentDetailPageState._labelSave,
          closeOnSubmitSuccess: false,
          initialText: originalRaw,
          emojiUrls: _emojiUrls,
          emojiGroups: _emojiGroups,
          onSearchMentionUsers: _searchMentionUsersForEditor,
          aiScene: RiverMarkdownAiScene.editComment,
          onAiGenerateStream: _generateAiContentStreamForEditor,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          onUploadImage: _uploadReplyImage,
          onLoadCurrentDraft: loadCurrentDraft,
          onSaveDraft: saveDraft,
          onLoadDrafts: () => _loadCommentDetailDraftsForEditor(
            filter: (draft) =>
                draft.action == 'edit' || draft.draftKey == draftKey,
          ),
          onDeleteDraft: _deleteCommentDetailDraftForEditor,
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
    final cookieHeader = _activeCookieHeader();
    if (cookieHeader == null || cookieHeader.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelReplyNeedLogin);
      return;
    }

    final confirmed = await showRiverConfirmDialog(
      context: context,
      title: _CommentDetailPageState._labelDeleteCommentTitle,
      message: _CommentDetailPageState._labelDeleteCommentHint,
      cancelText: _CommentDetailPageState._labelCancel,
      confirmText: _CommentDetailPageState._labelDelete,
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
      if (post.id == _rootPost.id) {
        Navigator.of(context).pop(true);
        return;
      }
      _mutateState(() {
        _removePostFromState(post);
        _hasMutations = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showRiverSnackBar(_CommentDetailPageState._labelDeleteCommentSuccess);
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
      ).showRiverSnackBar('删除评论失败');
    }
  }

  Future<void> _showCommentActions(RiverSideTopicPostDetail post) async {
    final own = _isOwnComment(post);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.42;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surfaceContainerLow.withValues(
                      alpha: 0.92,
                    ),
                    theme.colorScheme.surface,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(RiverRadius.full),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                          ),
                          child: Icon(
                            Icons.mode_comment_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '评论操作',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                own ? '复制、编辑或删除这条评论' : '复制这条评论内容',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Column(
                      children: [
                        _TopicMoreActionTile(
                          icon: Icons.content_copy_outlined,
                          title:
                              _CommentDetailPageState._labelActionCopyContent,
                          subtitle: '复制当前评论的正文内容',
                          onTap: () => Navigator.of(sheetContext).pop('copy'),
                        ),
                        if (own) ...[
                          const SizedBox(height: 8),
                          _TopicMoreActionTile(
                            icon: Icons.edit_outlined,
                            title:
                                _CommentDetailPageState._labelActionEditComment,
                            subtitle: '重新编辑这条评论',
                            onTap: () => Navigator.of(sheetContext).pop('edit'),
                          ),
                          const SizedBox(height: 8),
                          _TopicMoreActionTile(
                            icon: Icons.delete_outline,
                            title:
                                _CommentDetailPageState._labelActionDeleteComment,
                            subtitle: '从当前评论串中删除这条评论',
                            onTap: () =>
                                Navigator.of(sheetContext).pop('delete'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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

  Future<void> _showQuoteBottomSheet(_QuoteBlock quote) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.62;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surfaceContainerLow.withValues(
                      alpha: 0.92,
                    ),
                    theme.colorScheme.surface,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(RiverRadius.full),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 0, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primaryContainer,
                            ),
                            child: Icon(
                              Icons.format_quote_rounded,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _CommentDetailPageState._labelQuoteTitle,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '查看完整引用内容',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow
                              .withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(RiverRadius.lg),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.30,
                            ),
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: _MarkdownContent(
                              markdown: quote.contentMarkdown,
                              cookieHeader: _activeCookieHeader(),
                              emojiUrls: _emojiUrls,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

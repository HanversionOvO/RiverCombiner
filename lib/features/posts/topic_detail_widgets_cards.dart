part of 'topic_detail_page.dart';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing case final Widget trailingWidget) trailingWidget,
        ],
      ),
    );
  }
}

class _MainPostCard extends StatefulWidget {
  const _MainPostCard({
    super.key,
    required this.detail,
    required this.cookieHeader,
    required this.emojiUrls,
    required this.onQuoteTap,
    required this.onMentionTap,
    required this.onTopicLinkTap,
    required this.isReacting,
    required this.onReactPressed,
    required this.onReplyPressed,
    required this.onReactionStatusPressed,
    required this.onAuthorTap,
    required this.showOwnerActions,
    this.showTransferAction = false,
    this.onEditPressed,
    this.onDeletePressed,
    this.onTransferPressed,
    this.transferTargetProvider = AccountProvider.qingShuiHePan,
    this.authorAvatarHeroTag,
    this.authorNameHeroTag,
    this.bodyRevealAnimation,
    this.pendingHeroReactionId,
    this.reactionPulseToken = 0,
    required this.onAiSummaryPressed,
    this.aiSummaryLoading = false,
    this.showAiSummaryMarquee = false,
    this.showAiSummaryAction = true,
    this.showReplyAction = true,
    this.isJumpHighlighted = false,
    this.jumpHighlightToken = 0,
    this.submittingPollKeys = const <String>{},
    this.showAliasFirst = false,
    this.autoCollapseBody = true,
    required this.onPollVote,
    required this.onPollClear,
  });

  final RiverSideTopicDetail detail;
  final String? cookieHeader;
  final Map<String, String> emojiUrls;
  final ValueChanged<_QuoteBlock> onQuoteTap;
  final ValueChanged<String> onMentionTap;
  final ValueChanged<int> onTopicLinkTap;
  final bool isReacting;
  final ValueChanged<RiverSideTopicPostDetail> onReactPressed;
  final ValueChanged<RiverSideTopicPostDetail> onReplyPressed;
  final void Function(RiverSideTopicPostDetail post, String reactionId)
  onReactionStatusPressed;
  final ValueChanged<RiverSideTopicPostDetail> onAuthorTap;
  final bool showOwnerActions;
  final bool showTransferAction;
  final VoidCallback? onEditPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onTransferPressed;
  final AccountProvider transferTargetProvider;
  final String? authorAvatarHeroTag;
  final String? authorNameHeroTag;
  final Animation<double>? bodyRevealAnimation;
  final String? pendingHeroReactionId;
  final int reactionPulseToken;
  final VoidCallback onAiSummaryPressed;
  final bool aiSummaryLoading;
  final bool showAiSummaryMarquee;
  final bool showAiSummaryAction;
  final bool showReplyAction;
  final bool isJumpHighlighted;
  final int jumpHighlightToken;
  final Set<String> submittingPollKeys;
  final bool showAliasFirst;
  final bool autoCollapseBody;
  final Future<bool> Function(RiverSideTopicPoll poll, List<String> optionIds)
  onPollVote;
  final Future<bool> Function(RiverSideTopicPoll poll) onPollClear;

  @override
  State<_MainPostCard> createState() => _MainPostCardState();
}

class _MainPostCardState extends State<_MainPostCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final post = widget.detail.mainPost;
    final bodySection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: 0.88,
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _MetaItem(
                icon: Icons.schedule_outlined,
                text: _formatDateTime(post.createdAt),
                color: colors.onSurfaceVariant,
              ),
              _MetaItem(
                icon: Icons.edit_note,
                text: '编辑 ${post.editCount}',
                color: colors.onSurfaceVariant,
              ),
              _MetaItem(
                icon: Icons.visibility_outlined,
                text: '浏览 ${widget.detail.viewCount}',
                color: colors.onSurfaceVariant,
              ),
              _MetaItem(
                icon: Icons.thumb_up_alt_outlined,
                text: '点赞 ${post.likeCount}',
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurface,
                height: 1.7,
              ) ??
              const TextStyle(),
          child: _CollapsibleMainPostBody(
            key: ValueKey<String>(
              'main-post-body-${post.id}-${post.editCount}-${post.contentMarkdown.hashCode}',
            ),
            autoCollapse: widget.autoCollapseBody,
            child: _PostContent(
              markdown: post.contentMarkdown,
              cookedHtml: post.contentCookedHtml,
              topicId: post.topicId,
              cookieHeader: widget.cookieHeader,
              emojiUrls: widget.emojiUrls,
              onQuoteTap: widget.onQuoteTap,
              onMentionTap: widget.onMentionTap,
              onTopicLinkTap: widget.onTopicLinkTap,
            ),
          ),
        ),
        if (post.polls.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
            child: _TopicPollSection(
              postId: post.id,
              polls: post.polls,
              canVote: post.canVotePoll,
              submittingPollKeys: widget.submittingPollKeys,
              onSubmit: widget.onPollVote,
              onClear: widget.onPollClear,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Divider(
          height: 1,
          thickness: 1,
          color: colors.outlineVariant.withValues(alpha: 0.24),
        ),
        const SizedBox(height: 14),
        _PostReactionBar(
          post: post,
          reacting: widget.isReacting,
          onReactPressed: () => widget.onReactPressed(post),
          onReplyPressed: () => widget.onReplyPressed(post),
          onReactionStatusPressed: (reactionId) {
            widget.onReactionStatusPressed(post, reactionId);
          },
          pendingHeroReactionId: widget.pendingHeroReactionId,
          pulseToken: widget.reactionPulseToken,
          showReplyAction: widget.showReplyAction,
          leadingAction: widget.showAiSummaryAction
              ? RiverAiActionButton(
                  onPressed: widget.onAiSummaryPressed,
                  loading: widget.aiSummaryLoading,
                  idleText: 'AI总结',
                  loadingText: 'AI总结中...',
                )
              : null,
        ),
      ],
    );
    final revealAnimation = widget.bodyRevealAnimation;
    final revealedBody = revealAnimation == null
        ? bodySection
        : FadeTransition(
            opacity: revealAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(revealAnimation),
              child: bodySection,
            ),
          );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.985, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: _JumpHighlightWrapper(
        highlighted: widget.isJumpHighlighted,
        token: widget.jumpHighlightToken,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _AiMarqueeBorder(
            enabled: widget.showAiSummaryMarquee,
            borderRadius: BorderRadius.circular(26),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.26),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostAuthorHeader(
                      post: post,
                      onTap: () => widget.onAuthorTap(post),
                      heroTagAvatar:
                          widget.authorAvatarHeroTag ??
                          _topicPostAuthorAvatarHeroTag(post),
                      heroTagName:
                          widget.authorNameHeroTag ??
                          _topicPostAuthorNameHeroTag(post),
                      showAliasFirst: widget.showAliasFirst,
                      trailing: widget.showOwnerActions
                          ? _MainPostInlineActions(
                              onEditPressed: widget.onEditPressed,
                              onDeletePressed: widget.onDeletePressed,
                              onTransferPressed: widget.onTransferPressed,
                              transferTargetProvider:
                                  widget.transferTargetProvider,
                            )
                          : (widget.showTransferAction
                                ? _MainPostInlineActions(
                                    onTransferPressed:
                                        widget.onTransferPressed,
                                    transferTargetProvider:
                                        widget.transferTargetProvider,
                                  )
                                : null),
                    ),
                    const SizedBox(height: 16),
                    revealedBody,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _CollapsibleMainPostBody extends StatefulWidget {
  const _CollapsibleMainPostBody({
    super.key,
    required this.autoCollapse,
    required this.child,
  });

  final bool autoCollapse;
  final Widget child;

  @override
  State<_CollapsibleMainPostBody> createState() => _CollapsibleMainPostBodyState();
}

class _CollapsibleMainPostBodyState extends State<_CollapsibleMainPostBody> {
  static const int _collapsedLines = 12;

  double _contentHeight = 0;
  bool _isCollapsed = false;

  double _collapsedHeight(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final fontSize = style.fontSize ?? 16;
    final lineHeight = style.height ?? 1.7;
    return fontSize * lineHeight * _collapsedLines + 8;
  }

  void _handleMeasuredSize(Size size) {
    if (!mounted) {
      return;
    }
    final nextHeight = size.height;
    final collapsedHeight = _collapsedHeight(context);
    final willCollapse = widget.autoCollapse && nextHeight > collapsedHeight + 4;
    if ((_contentHeight - nextHeight).abs() < 0.5 &&
        _isCollapsed == willCollapse) {
      return;
    }
    setState(() {
      _contentHeight = nextHeight;
      _isCollapsed = willCollapse;
    });
  }

  @override
  void didUpdateWidget(covariant _CollapsibleMainPostBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoCollapse == widget.autoCollapse) {
      return;
    }
    if (!widget.autoCollapse) {
      setState(() {
        _isCollapsed = false;
      });
      return;
    }
    final collapsedHeight = _collapsedHeight(context);
    if (_contentHeight > collapsedHeight + 4) {
      setState(() {
        _isCollapsed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final collapsedHeight = _collapsedHeight(context);
    final isOverflowing = widget.autoCollapse && _contentHeight > collapsedHeight + 4;
    final heightFactor = !isOverflowing || !_isCollapsed || _contentHeight <= 0
        ? 1.0
        : (collapsedHeight / _contentHeight).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: heightFactor,
                  child: _MeasureSize(
                    onChange: _handleMeasuredSize,
                    child: widget.child,
                  ),
                ),
              ),
            ),
            if (isOverflowing && _isCollapsed)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 120,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      IgnorePointer(
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colors.surfaceContainerLow.withValues(
                                  alpha: 0,
                                ),
                                colors.surfaceContainerLow.withValues(
                                  alpha: 0.32,
                                ),
                                colors.surfaceContainerLow.withValues(
                                  alpha: 0.72,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              setState(() {
                                _isCollapsed = false;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.unfold_more_rounded,
                                    size: 18,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '展开全部内容',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (isOverflowing) ...[
          if (!_isCollapsed) ...[
            const SizedBox(height: 12),
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    setState(() {
                      _isCollapsed = true;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.unfold_less_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '收起正文',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (newSize == null || _oldSize == newSize) {
      return;
    }
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(newSize);
    });
  }
}

class _TopicPollSection extends StatefulWidget {
  const _TopicPollSection({
    required this.postId,
    required this.polls,
    required this.canVote,
    required this.submittingPollKeys,
    required this.onSubmit,
    required this.onClear,
  });

  final int postId;
  final List<RiverSideTopicPoll> polls;
  final bool canVote;
  final Set<String> submittingPollKeys;
  final Future<bool> Function(RiverSideTopicPoll poll, List<String> optionIds)
  onSubmit;
  final Future<bool> Function(RiverSideTopicPoll poll) onClear;

  @override
  State<_TopicPollSection> createState() => _TopicPollSectionState();
}

class _TopicPollSectionState extends State<_TopicPollSection> {
  final Map<String, Set<String>> _selectedOptionIdsByPollName =
      <String, Set<String>>{};

  bool _isMultipleChoicePoll(RiverSideTopicPoll poll) {
    final type = poll.type.trim().toLowerCase();
    return type == 'multiple' || type == 'number' || type == 'ranked';
  }

  bool _isSubmitting(RiverSideTopicPoll poll) {
    return widget.submittingPollKeys.contains(
      '${widget.postId}:${poll.name.trim()}',
    );
  }

  Set<String> _selectionForPoll(RiverSideTopicPoll poll) {
    return _selectedOptionIdsByPollName[poll.name] ?? <String>{};
  }

  bool _hasLocalSelection(RiverSideTopicPoll poll) {
    return _selectedOptionIdsByPollName.containsKey(poll.name);
  }

  String _optionText(String html) {
    if (html.trim().isEmpty) {
      return '未命名选项';
    }
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  int _fallbackVoteTotal(RiverSideTopicPoll poll) {
    var total = 0;
    for (final option in poll.options) {
      total += option.votes;
    }
    return total;
  }

  Set<String> _votedOptionIdsFromPoll(RiverSideTopicPoll poll) {
    return poll.options
        .where((item) => item.selected)
        .map((item) => item.id)
        .toSet();
  }

  Future<void> _submitPoll(RiverSideTopicPoll poll) async {
    final selected = _selectionForPoll(poll);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showRiverSnackBar('请先选择投票选项');
      return;
    }
    final success = await widget.onSubmit(
      poll,
      selected.toList(growable: false),
    );
    if (!mounted || !success) {
      return;
    }
    setState(() {
      _selectedOptionIdsByPollName.remove(poll.name);
    });
  }

  Future<void> _clearPoll(RiverSideTopicPoll poll) async {
    final success = await widget.onClear(poll);
    if (!mounted || !success) {
      return;
    }
    setState(() {
      _selectedOptionIdsByPollName.remove(poll.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.polls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widget.polls.length; index++) ...[
          () {
            final poll = widget.polls[index];
            final localSelected = _selectionForPoll(poll);
            final votedOptionIds = _votedOptionIdsFromPoll(poll);
            final selectedForAction = _hasLocalSelection(poll)
                ? localSelected
                : votedOptionIds;
            final onClear =
                votedOptionIds.isNotEmpty && !_hasLocalSelection(poll)
                ? () => _clearPoll(poll)
                : null;
            return _TopicPollCard(
              poll: poll,
              canVote: widget.canVote && poll.canVote,
              selected: selectedForAction,
              submitting: _isSubmitting(poll),
              optionTextBuilder: _optionText,
              fallbackVoteTotalBuilder: _fallbackVoteTotal,
              multipleChoiceResolver: _isMultipleChoicePoll,
              onSelectionChanged: (next) {
                setState(() {
                  _selectedOptionIdsByPollName[poll.name] = next;
                });
              },
              onSubmit: () => _submitPoll(poll),
              onClear: onClear,
            );
          }(),
          if (index != widget.polls.length - 1)
            SizedBox(height: theme.visualDensity.vertical * 2 + 10),
        ],
      ],
    );
  }
}

class _TopicPollCard extends StatelessWidget {
  const _TopicPollCard({
    required this.poll,
    required this.canVote,
    required this.selected,
    required this.submitting,
    required this.optionTextBuilder,
    required this.fallbackVoteTotalBuilder,
    required this.multipleChoiceResolver,
    required this.onSelectionChanged,
    required this.onSubmit,
    this.onClear,
  });

  final RiverSideTopicPoll poll;
  final bool canVote;
  final Set<String> selected;
  final bool submitting;
  final String Function(String html) optionTextBuilder;
  final int Function(RiverSideTopicPoll poll) fallbackVoteTotalBuilder;
  final bool Function(RiverSideTopicPoll poll) multipleChoiceResolver;
  final ValueChanged<Set<String>> onSelectionChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final multipleChoice = multipleChoiceResolver(poll);
    final voterTotal =
        (poll.voters > 0 ? poll.voters : fallbackVoteTotalBuilder(poll)).clamp(
          1,
          1 << 30,
        );
    final pollTitle = poll.title.trim().isEmpty ? '投票' : poll.title.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.poll_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pollTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${poll.voters} 人参与',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final option in poll.options) ...[
            _TopicPollOptionTile(
              option: option,
              optionText: optionTextBuilder(option.html),
              selected: selected.contains(option.id) || option.selected,
              multipleChoice: multipleChoice,
              canVote: canVote && poll.isOpen,
              voterTotal: voterTotal,
              showVoters: poll.public,
              onTap: () {
                if (!(canVote && poll.isOpen) || submitting) {
                  return;
                }
                final next = <String>{...selected};
                if (multipleChoice) {
                  if (!next.add(option.id)) {
                    next.remove(option.id);
                  }
                } else {
                  if (next.contains(option.id)) {
                    next.clear();
                  } else {
                    next
                      ..clear()
                      ..add(option.id);
                  }
                }
                onSelectionChanged(next);
              },
            ),
            if (option != poll.options.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  canVote && poll.isOpen
                      ? (multipleChoice ? '可多选' : '单选')
                      : (poll.isOpen ? '暂不可投票' : '投票已结束'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: canVote && poll.isOpen && !submitting
                    ? onSubmit
                    : null,
                icon: submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.how_to_vote_rounded, size: 16),
                label: Text(submitting ? '提交中' : '提交投票'),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: canVote && poll.isOpen && !submitting
                      ? onClear
                      : null,
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('撤销'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicPollOptionTile extends StatelessWidget {
  const _TopicPollOptionTile({
    required this.option,
    required this.optionText,
    required this.selected,
    required this.multipleChoice,
    required this.canVote,
    required this.voterTotal,
    required this.showVoters,
    required this.onTap,
  });

  final RiverSideTopicPollOption option;
  final String optionText;
  final bool selected;
  final bool multipleChoice;
  final bool canVote;
  final int voterTotal;
  final bool showVoters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = (option.votes / voterTotal).clamp(0.0, 1.0);

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.38)
          : colors.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canVote ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    multipleChoice
                        ? (selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded)
                        : (selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded),
                    size: 18,
                    color: selected
                        ? colors.primary
                        : colors.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      optionText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${option.votes}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: ratio,
                  backgroundColor: colors.outlineVariant.withValues(
                    alpha: 0.25,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    selected
                        ? colors.primary
                        : colors.primary.withValues(alpha: 0.58),
                  ),
                ),
              ),
              if (showVoters && option.voters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: option.voters
                      .map((voter) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundImage: voter.avatarUrl.isEmpty
                                    ? null
                                    : NetworkImage(voter.avatarUrl),
                                child: voter.avatarUrl.isEmpty
                                    ? const Icon(Icons.person, size: 10)
                                    : null,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                voter.displayName,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AiMarqueeBorder extends StatefulWidget {
  const _AiMarqueeBorder({
    required this.enabled,
    required this.borderRadius,
    required this.child,
  });

  final bool enabled;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_AiMarqueeBorder> createState() => _AiMarqueeBorderState();
}

class _AiMarqueeBorderState extends State<_AiMarqueeBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AiMarqueeBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      _controller.repeat();
      return;
    }
    if (oldWidget.enabled && !widget.enabled) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isDark = theme.brightness == Brightness.dark;
        return Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AiMarqueeBorderPainter(
                    progress: _controller.value,
                    borderRadius: widget.borderRadius,
                    darkMode: isDark,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AiMarqueeBorderPainter extends CustomPainter {
  _AiMarqueeBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.darkMode,
  });

  final double progress;
  final BorderRadius borderRadius;
  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(1.2);
    final alpha = darkMode ? 1.0 : 0.86;
    final sweep = SweepGradient(
      colors: [
        Colors.transparent,
        const Color(0xFF4CC9F0).withValues(alpha: 0.35 * alpha),
        const Color(0xFF3A86FF).withValues(alpha: 0.75 * alpha),
        const Color(0xFF7B2FF7).withValues(alpha: 0.92 * alpha),
        const Color(0xFFF72585).withValues(alpha: 0.86 * alpha),
        const Color(0xFFFF9E00).withValues(alpha: 0.62 * alpha),
        Colors.transparent,
        Colors.transparent,
      ],
      stops: const [0.0, 0.06, 0.13, 0.20, 0.27, 0.34, 0.42, 1.0],
      transform: GradientRotation(progress * math.pi * 2),
    );
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.2)
      ..shader = sweep.createShader(rect);
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = sweep.createShader(rect);
    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, corePaint);
  }

  @override
  bool shouldRepaint(covariant _AiMarqueeBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.darkMode != darkMode;
  }
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({
    super.key,
    required this.post,
    required this.cookieHeader,
    required this.emojiUrls,
    required this.onQuoteTap,
    required this.onMentionTap,
    required this.onTopicLinkTap,
    required this.isReacting,
    required this.onReactPressed,
    required this.onReplyPressed,
    required this.heroTag,
    this.onTap,
    this.onLongPress,
    required this.onReactionStatusPressed,
    required this.onAuthorTap,
    this.pendingHeroReactionId,
    this.reactionPulseToken = 0,
    this.isJumpHighlighted = false,
    this.jumpHighlightToken = 0,
    this.showAliasFirst = false,
  });

  final RiverSideTopicPostDetail post;
  final String? cookieHeader;
  final Map<String, String> emojiUrls;
  final ValueChanged<_QuoteBlock> onQuoteTap;
  final ValueChanged<String> onMentionTap;
  final ValueChanged<int> onTopicLinkTap;
  final bool isReacting;
  final ValueChanged<RiverSideTopicPostDetail> onReactPressed;
  final ValueChanged<RiverSideTopicPostDetail> onReplyPressed;
  final String heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(RiverSideTopicPostDetail post, String reactionId)
  onReactionStatusPressed;
  final ValueChanged<RiverSideTopicPostDetail> onAuthorTap;
  final String? pendingHeroReactionId;
  final int reactionPulseToken;
  final bool isJumpHighlighted;
  final int jumpHighlightToken;
  final bool showAliasFirst;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.post.isSystemActionPost) {
      return _SystemActionPostCard(
        post: widget.post,
        heroTag: widget.heroTag,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        highlighted: widget.isJumpHighlighted,
        highlightToken: widget.jumpHighlightToken,
      );
    }
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasReactionStatus = widget.post.reactions.any(
      (item) => item.count > 0,
    );

    return Hero(
      tag: widget.heroTag,
      flightShuttleBuilder: _commentCardHeroShuttleBuilder,
      transitionOnUserGestures: true,
      child: HeroMode(
        enabled: false,
        child: _JumpHighlightWrapper(
          highlighted: widget.isJumpHighlighted,
          token: widget.jumpHighlightToken,
          borderRadius: BorderRadius.circular(18),
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostAuthorHeader(
                      post: widget.post,
                      onTap: () => widget.onAuthorTap(widget.post),
                      heroTagAvatar: _topicPostAuthorAvatarHeroTag(widget.post),
                      heroTagName: _topicPostAuthorNameHeroTag(widget.post),
                      enableHero: false,
                      showAliasFirst: widget.showAliasFirst,
                      trailing: _CommentInlineActions(
                        reacting: widget.isReacting,
                        onReplyPressed: () =>
                            widget.onReplyPressed(widget.post),
                        onReactPressed: () =>
                            widget.onReactPressed(widget.post),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _MetaItem(
                          icon: Icons.schedule_outlined,
                          text: _formatDateTime(widget.post.createdAt),
                          color: subtitleColor,
                        ),
                        _MetaItem(
                          icon: Icons.thumb_up_alt_outlined,
                          text: '点赞 ${widget.post.likeCount}',
                          color: subtitleColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PostContent(
                      markdown: widget.post.contentMarkdown,
                      cookedHtml: widget.post.contentCookedHtml,
                      topicId: widget.post.topicId,
                      cookieHeader: widget.cookieHeader,
                      emojiUrls: widget.emojiUrls,
                      onQuoteTap: widget.onQuoteTap,
                      onMentionTap: widget.onMentionTap,
                      onTopicLinkTap: widget.onTopicLinkTap,
                      enableImageHero: false,
                      enableTextSelection: false,
                      replyToPostNumber: widget.post.replyToPostNumber,
                      replyToUsername: widget.post.replyToUsername,
                    ),
                    if (hasReactionStatus) ...[
                      const SizedBox(height: 10),
                      _PostReactionBar(
                        post: widget.post,
                        reacting: widget.isReacting,
                        onReactPressed: () =>
                            widget.onReactPressed(widget.post),
                        onReplyPressed: () =>
                            widget.onReplyPressed(widget.post),
                        onReactionStatusPressed: (reactionId) {
                          widget.onReactionStatusPressed(
                            widget.post,
                            reactionId,
                          );
                        },
                        pendingHeroReactionId: widget.pendingHeroReactionId,
                        pulseToken: widget.reactionPulseToken,
                        enableReactionHero: false,
                        showPrimaryActions: false,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemActionPostCard extends StatelessWidget {
  const _SystemActionPostCard({
    required this.post,
    this.heroTag,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.highlightToken = 0,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
  });

  final RiverSideTopicPostDetail post;
  final String? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;
  final int highlightToken;
  final EdgeInsetsGeometry margin;

  IconData _iconForActionCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.contains('pinned')) {
      return Icons.push_pin_rounded;
    }
    if (normalized.contains('closed')) {
      return Icons.lock_rounded;
    }
    if (normalized.contains('archived')) {
      return Icons.inventory_2_rounded;
    }
    if (normalized.contains('visible') || normalized.contains('unlisted')) {
      return Icons.visibility_off_rounded;
    }
    return Icons.info_outline_rounded;
  }

  Color _accentColor(ThemeData theme, String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.contains('closed')) {
      return theme.colorScheme.error;
    }
    if (normalized.contains('pinned')) {
      return theme.colorScheme.primary;
    }
    if (normalized.contains('visible') || normalized.contains('unlisted')) {
      return theme.colorScheme.tertiary;
    }
    return theme.colorScheme.secondary;
  }

  String _actionText() {
    final action = post.actionDescription.trim();
    if (action.isNotEmpty) {
      return action;
    }
    final content = post.contentMarkdown.trim();
    if (content.isNotEmpty) {
      return content;
    }
    return '系统动态';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurfaceVariant;
    final accent = _accentColor(theme, post.actionCode);
    final username = _normalizeMentionUsernameToken(post.authorUsername.trim());
    final actorPrimary = riverSidePrimaryLabel(
      username: username,
      displayName: post.authorDisplayName,
    );
    final actorSecondary = riverSideSecondaryLabel(
      username: username,
      displayName: post.authorDisplayName,
    );

    Widget card = Card(
      margin: margin,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForActionCode(post.actionCode),
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _actionText(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _MetaItem(
                          icon: Icons.schedule_outlined,
                          text: _formatDateTime(post.createdAt),
                          color: subtitleColor,
                        ),
                        if (actorPrimary.isNotEmpty)
                          Text(
                            actorPrimary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subtitleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (actorSecondary.isNotEmpty)
                          Text(
                            actorSecondary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subtitleColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (highlighted) {
      card = _JumpHighlightWrapper(
        highlighted: true,
        token: highlightToken,
        borderRadius: BorderRadius.circular(18),
        child: card,
      );
    }

    if (heroTag == null || heroTag!.isEmpty) {
      return card;
    }
    return Hero(
      tag: heroTag!,
      flightShuttleBuilder: _commentCardHeroShuttleBuilder,
      transitionOnUserGestures: true,
      child: HeroMode(enabled: false, child: card),
    );
  }
}

class _JumpHighlightWrapper extends StatelessWidget {
  const _JumpHighlightWrapper({
    required this.highlighted,
    required this.token,
    required this.borderRadius,
    required this.child,
  });

  final bool highlighted;
  final int token;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!highlighted) {
      return child;
    }
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('jump-highlight-$token'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2200),
      curve: Curves.linear,
      builder: (context, value, content) {
        final pulse = math.sin(value * math.pi * 3).clamp(0.0, 1.0);
        final envelope = (1 - value * 0.35).clamp(0.72, 1.0);
        final glowAlpha = pulse * envelope;
        final scale = 1 + 0.014 * glowAlpha;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: 0.22 * glowAlpha,
                  ),
                  blurRadius: 18 * glowAlpha + 2,
                  spreadRadius: 1.5 * glowAlpha,
                ),
              ],
            ),
            child: content,
          ),
        );
      },
      child: child,
    );
  }
}

class _CommentDetailPostCard extends StatelessWidget {
  const _CommentDetailPostCard({
    required this.post,
    required this.cookieHeader,
    required this.emojiUrls,
    required this.onQuoteTap,
    required this.onMentionTap,
    required this.onTopicLinkTap,
    required this.onReplyPressed,
    required this.onReactPressed,
    required this.onReactionStatusPressed,
    required this.reacting,
    required this.onAuthorTap,
    this.onLongPress,
    this.heroTag,
    this.pendingHeroReactionId,
    this.reactionPulseToken = 0,
  });

  final RiverSideTopicPostDetail post;
  final String? cookieHeader;
  final Map<String, String> emojiUrls;
  final ValueChanged<_QuoteBlock> onQuoteTap;
  final ValueChanged<String> onMentionTap;
  final ValueChanged<int> onTopicLinkTap;
  final ValueChanged<RiverSideTopicPostDetail> onReplyPressed;
  final ValueChanged<RiverSideTopicPostDetail> onReactPressed;
  final void Function(RiverSideTopicPostDetail post, String reactionId)
  onReactionStatusPressed;
  final bool reacting;
  final ValueChanged<RiverSideTopicPostDetail> onAuthorTap;
  final VoidCallback? onLongPress;
  final String? heroTag;
  final String? pendingHeroReactionId;
  final int reactionPulseToken;

  @override
  Widget build(BuildContext context) {
    if (post.isSystemActionPost) {
      return _SystemActionPostCard(
        post: post,
        heroTag: heroTag,
        onLongPress: onLongPress,
        margin: const EdgeInsets.only(bottom: 12),
      );
    }
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasReactionStatus = post.reactions.any((item) => item.count > 0);
    final disableInnerHero = heroTag != null && heroTag!.isNotEmpty;

    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PostAuthorHeader(
                post: post,
                onTap: () => onAuthorTap(post),
                heroTagAvatar: _topicPostAuthorAvatarHeroTag(post),
                heroTagName: _topicPostAuthorNameHeroTag(post),
                enableHero: !disableInnerHero,
                trailing: _CommentInlineActions(
                  reacting: reacting,
                  onReplyPressed: () => onReplyPressed(post),
                  onReactPressed: () => onReactPressed(post),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _MetaItem(
                    icon: Icons.schedule_outlined,
                    text: _formatDateTime(post.createdAt),
                    color: subtitleColor,
                  ),
                  _MetaItem(
                    icon: Icons.thumb_up_alt_outlined,
                    text: '点赞 ${post.likeCount}',
                    color: subtitleColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _PostContent(
                markdown: post.contentMarkdown,
                cookedHtml: post.contentCookedHtml,
                topicId: post.topicId,
                cookieHeader: cookieHeader,
                emojiUrls: emojiUrls,
                onQuoteTap: onQuoteTap,
                onMentionTap: onMentionTap,
                onTopicLinkTap: onTopicLinkTap,
                enableImageHero: false,
                enableTextSelection: false,
                replyToPostNumber: post.replyToPostNumber,
                replyToUsername: post.replyToUsername,
              ),
              if (hasReactionStatus) ...[
                const SizedBox(height: 10),
                _PostReactionBar(
                  post: post,
                  reacting: reacting,
                  onReactPressed: () => onReactPressed(post),
                  onReplyPressed: () => onReplyPressed(post),
                  onReactionStatusPressed: (reactionId) {
                    onReactionStatusPressed(post, reactionId);
                  },
                  pendingHeroReactionId: pendingHeroReactionId,
                  pulseToken: reactionPulseToken,
                  enableReactionHero: !disableInnerHero,
                  showPrimaryActions: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (heroTag == null || heroTag!.isEmpty) {
      return card;
    }
    return Hero(
      tag: heroTag!,
      flightShuttleBuilder: _commentCardHeroShuttleBuilder,
      transitionOnUserGestures: true,
      child: HeroMode(enabled: false, child: card),
    );
  }
}

class _PostReactionBar extends StatelessWidget {
  const _PostReactionBar({
    required this.post,
    required this.reacting,
    required this.onReactPressed,
    required this.onReplyPressed,
    required this.onReactionStatusPressed,
    this.pendingHeroReactionId,
    this.pulseToken = 0,
    this.enableReactionHero = true,
    this.showPrimaryActions = true,
    this.showReplyAction = true,
    this.leadingAction,
  });

  final RiverSideTopicPostDetail post;
  final bool reacting;
  final VoidCallback onReactPressed;
  final VoidCallback onReplyPressed;
  final ValueChanged<String> onReactionStatusPressed;
  final String? pendingHeroReactionId;
  final int pulseToken;
  final bool enableReactionHero;
  final bool showPrimaryActions;
  final bool showReplyAction;
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reactions = post.reactions.where((item) => item.count > 0).toList();
    final pendingId = pendingHeroReactionId;
    final hasPending =
        pendingId != null &&
        pendingId.isNotEmpty &&
        reactions.every((item) => item.id != pendingId);
    final actionBg = theme.colorScheme.surfaceContainerHighest;
    final actionBorder = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.55,
    );
    final actionFg = theme.colorScheme.onSurfaceVariant;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (leadingAction case final Widget actionWidget) actionWidget,
        if (showPrimaryActions) ...[
          if (showReplyAction)
            _ActionPillButton(
              onPressed: onReplyPressed,
              backgroundColor: actionBg,
              borderColor: actionBorder,
              foregroundColor: actionFg,
              icon: const Icon(Icons.reply_outlined, size: 18),
              label: _TopicDetailPageState._labelReply,
            ),
          _ActionPillButton(
            onPressed: reacting ? null : onReactPressed,
            backgroundColor: reacting
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                : actionBg,
            borderColor: reacting ? theme.colorScheme.primary : actionBorder,
            foregroundColor: reacting ? theme.colorScheme.primary : actionFg,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: reacting
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.add_reaction_outlined,
                      key: ValueKey('ready'),
                      size: 18,
                    ),
            ),
            label: _TopicDetailPageState._labelReact,
          ),
        ],
        if (hasPending)
          _ReactionStateChip(
            postId: post.id,
            reactionId: pendingId,
            countText: '...',
            selected: false,
            isPending: true,
            pulseToken: pulseToken,
            enableHero: enableReactionHero,
            onPressed: null,
          ),
        ...reactions.map((reaction) {
          final selected = post.currentUserReaction?.id == reaction.id;
          return _ReactionStateChip(
            postId: post.id,
            reactionId: reaction.id,
            countText: '${reaction.count}',
            selected: selected,
            pulseToken: pulseToken,
            enableHero: enableReactionHero,
            onPressed: () => onReactionStatusPressed(reaction.id),
          );
        }),
      ],
    );
  }
}

class _ReactionStateChip extends StatelessWidget {
  const _ReactionStateChip({
    required this.postId,
    required this.reactionId,
    required this.countText,
    required this.selected,
    required this.pulseToken,
    required this.onPressed,
    this.enableHero = true,
    this.isPending = false,
  });

  final int postId;
  final String reactionId;
  final String countText;
  final bool selected;
  final int pulseToken;
  final VoidCallback? onPressed;
  final bool enableHero;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = ActionChip(
      avatar: Text(
        _reactionEmoji(reactionId),
        style: const TextStyle(fontSize: 14),
      ),
      label: Text(countText),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: selected ? theme.colorScheme.primary : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      backgroundColor: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
      ),
      onPressed: onPressed,
    );

    final animatedChip = TweenAnimationBuilder<double>(
      key: ValueKey<String>(
        'reaction-chip-$postId-$reactionId-$selected-$isPending-$pulseToken',
      ),
      tween: Tween<double>(begin: selected ? 0.88 : 1, end: 1),
      duration: Duration(milliseconds: selected ? 280 : 180),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(
          opacity: isPending ? value.clamp(0.72, 1) : 1,
          child: child,
        ),
      ),
      child: chip,
    );

    final child = Material(color: Colors.transparent, child: animatedChip);
    if (!enableHero) {
      return child;
    }
    return Hero(
      tag: _reactionHeroTag(postId: postId, reactionId: reactionId),
      transitionOnUserGestures: true,
      child: child,
    );
  }
}

class _CommentInlineActions extends StatelessWidget {
  const _CommentInlineActions({
    required this.reacting,
    this.onReplyPressed,
    this.onReactPressed,
  });

  final bool reacting;
  final VoidCallback? onReplyPressed;
  final VoidCallback? onReactPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.68,
    );
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    final fg = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CommentInlineActionButton(
          tooltip: _TopicDetailPageState._labelReply,
          icon: const Icon(Icons.reply_outlined, size: 17),
          onPressed: onReplyPressed,
          backgroundColor: bg,
          borderColor: border,
          foregroundColor: fg,
        ),
        const SizedBox(width: 6),
        _CommentInlineActionButton(
          tooltip: _TopicDetailPageState._labelReact,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: reacting
                ? const SizedBox(
                    key: ValueKey('comment-like-loading'),
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.add_reaction_outlined,
                    key: ValueKey('comment-like-ready'),
                    size: 17,
                  ),
          ),
          onPressed: reacting ? null : onReactPressed,
          backgroundColor: reacting
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.62)
              : bg,
          borderColor: reacting ? theme.colorScheme.primary : border,
          foregroundColor: reacting ? theme.colorScheme.primary : fg,
        ),
      ],
    );
  }
}

class _MainPostInlineActions extends StatelessWidget {
  const _MainPostInlineActions({
    this.onEditPressed,
    this.onDeletePressed,
    this.onTransferPressed,
    this.transferTargetProvider = AccountProvider.qingShuiHePan,
  });

  final VoidCallback? onEditPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onTransferPressed;
  final AccountProvider transferTargetProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.68,
    );
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    final fg = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CommentInlineActionButton(
          tooltip: transferTargetProvider == AccountProvider.qingShuiHePan
              ? '转帖到清水河畔'
              : '转帖到 RiverSide',
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.asset(
                  transferTargetProvider == AccountProvider.qingShuiHePan
                      ? 'assets/images/hp.png'
                      : 'assets/images/rs.png',
                  width: 14,
                  height: 14,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.swap_horiz_rounded, size: 14),
            ],
          ),
          onPressed: onTransferPressed,
          backgroundColor: bg,
          borderColor: border,
          foregroundColor: fg,
        ),
        if (onEditPressed != null || onDeletePressed != null) ...[
          const SizedBox(width: 6),
        ],
        if (onEditPressed != null)
          _CommentInlineActionButton(
            tooltip: _TopicDetailPageState._labelActionEditMainPost,
            icon: const Icon(Icons.edit_outlined, size: 17),
            onPressed: onEditPressed,
            backgroundColor: bg,
            borderColor: border,
            foregroundColor: fg,
          ),
        if (onDeletePressed != null) ...[
          if (onEditPressed != null) const SizedBox(width: 6),
          _CommentInlineActionButton(
            tooltip: _TopicDetailPageState._labelActionDeleteMainPost,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            onPressed: onDeletePressed,
            backgroundColor: bg,
            borderColor: border,
            foregroundColor: fg,
          ),
        ],
      ],
    );
  }
}

class _CommentInlineActionButton extends StatelessWidget {
  const _CommentInlineActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: disabled
            ? backgroundColor.withValues(alpha: 0.45)
            : backgroundColor.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: disabled ? borderColor.withValues(alpha: 0.35) : borderColor,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: IconTheme.merge(
              data: IconThemeData(
                size: 17,
                color: disabled
                    ? foregroundColor.withValues(alpha: 0.55)
                    : foregroundColor,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPillButton extends StatelessWidget {
  const _ActionPillButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Material(
      color: disabled
          ? backgroundColor.withValues(alpha: 0.45)
          : backgroundColor.withValues(alpha: 0.9),
      shape: StadiumBorder(
        side: BorderSide(
          color: disabled ? borderColor.withValues(alpha: 0.35) : borderColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(
                  size: 18,
                  color: disabled
                      ? foregroundColor.withValues(alpha: 0.55)
                      : foregroundColor,
                ),
                child: icon,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: disabled
                      ? foregroundColor.withValues(alpha: 0.55)
                      : foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

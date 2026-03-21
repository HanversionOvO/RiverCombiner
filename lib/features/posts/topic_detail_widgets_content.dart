part of 'topic_detail_page.dart';

class _PostContent extends StatelessWidget {
  const _PostContent({
    required this.markdown,
    this.cookedHtml = '',
    required this.topicId,
    required this.cookieHeader,
    required this.emojiUrls,
    required this.onQuoteTap,
    this.onMentionTap,
    this.onTopicLinkTap,
    this.enableImageHero = true,
    this.enableTextSelection = true,
    this.replyToPostNumber,
    this.replyToUsername,
  });

  final String markdown;
  final String cookedHtml;
  final int topicId;
  final String? cookieHeader;
  final Map<String, String> emojiUrls;
  final ValueChanged<_QuoteBlock> onQuoteTap;
  final ValueChanged<String>? onMentionTap;
  final ValueChanged<int>? onTopicLinkTap;
  final bool enableImageHero;
  final bool enableTextSelection;
  final int? replyToPostNumber;
  final String? replyToUsername;

  @override
  Widget build(BuildContext context) {
    final trimmedCookedHtml = cookedHtml.trim();
    if (_shouldPreferCookedHtmlRendering(
      markdown: markdown,
      cookedHtml: trimmedCookedHtml,
      replyToPostNumber: replyToPostNumber,
    )) {
      return _MarkdownContent(
        markdown: markdown,
        cookedHtmlOverride: trimmedCookedHtml,
        preferCookedHtml: true,
        cookieHeader: cookieHeader,
        emojiUrls: emojiUrls,
        onMentionTap: onMentionTap,
        onTopicLinkTap: onTopicLinkTap,
        enableImageHero: enableImageHero,
        enableTextSelection: enableTextSelection,
      );
    }

    final blocks = _parsePostContentBlocks(markdown, topicId);
    final hasQuoteBlock = blocks.any((block) => block is _QuoteBlock);
    final replyPostNumber = replyToPostNumber ?? 0;
    final canInjectReplyHint = replyPostNumber > 0 && !hasQuoteBlock;
    final mergedBlocks = <_PostContentBlock>[
      if (canInjectReplyHint)
        _QuoteBlock(
          ref: _QuoteRef(
            username: (replyToUsername ?? '').trim().isEmpty
                ? _TopicDetailPageState._labelUnknownUser
                : _normalizeMentionUsernameToken(
                    (replyToUsername ?? '').trim(),
                  ),
            topicId: topicId,
            postNumber: replyPostNumber,
          ),
          contentMarkdown: '',
        ),
      ...blocks,
    ];

    if (mergedBlocks.isEmpty) {
      return const _MarkdownContent(
        markdown: _TopicDetailPageState._labelEmpty,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < mergedBlocks.length; i++) ...[
          if (mergedBlocks[i] is _MarkdownBlock)
            _MarkdownContent(
              markdown: (mergedBlocks[i] as _MarkdownBlock).markdown,
              cookieHeader: cookieHeader,
              emojiUrls: emojiUrls,
              onMentionTap: onMentionTap,
              onTopicLinkTap: onTopicLinkTap,
              enableImageHero: enableImageHero,
              enableTextSelection: enableTextSelection,
            )
          else
            _QuotePreviewCard(
              quote: mergedBlocks[i] as _QuoteBlock,
              onTap: () => onQuoteTap(mergedBlocks[i] as _QuoteBlock),
            ),
          if (i != mergedBlocks.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _QuotePreviewCard extends StatelessWidget {
  const _QuotePreviewCard({required this.quote, required this.onTap});

  final _QuoteBlock quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasFloorRef = quote.ref.postNumber > 0;
    final preview = _toPlainPreview(quote.contentMarkdown);
    final inlineStyle = quote.inlineStyle;
    final contentTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize:
          (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) *
          (inlineStyle?.fontScale ?? 1),
      color:
          inlineStyle?.foregroundColor ??
          Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final styledPreview = inlineStyle == null
        ? null
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color:
                  inlineStyle.backgroundColor ??
                  Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              preview.isEmpty ? '查看引用内容' : preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: contentTextStyle,
            ),
          );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.reply_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasFloorRef
                          ? '回复 @${_normalizeMentionUsernameToken(quote.ref.username)} 的 #${quote.ref.postNumber}'
                          : '引用内容',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (styledPreview != null)
                      styledPreview
                    else
                      Text(
                        preview.isEmpty
                            ? (hasFloorRef
                                  ? '查看被回复内容'
                                  : '查看引用内容')
                            : preview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkdownContent extends StatelessWidget {
  const _MarkdownContent({
    required this.markdown,
    this.cookedHtmlOverride = '',
    this.preferCookedHtml = false,
    this.cookieHeader,
    this.emojiUrls = const <String, String>{},
    this.onMentionTap,
    this.onTopicLinkTap,
    this.enableImageHero = true,
    this.enableTextSelection = true,
  });

  final String markdown;
  final String cookedHtmlOverride;
  final bool preferCookedHtml;
  final String? cookieHeader;
  final Map<String, String> emojiUrls;
  final ValueChanged<String>? onMentionTap;
  final ValueChanged<int>? onTopicLinkTap;
  final bool enableImageHero;
  final bool enableTextSelection;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    if (preferCookedHtml && cookedHtmlOverride.trim().isNotEmpty) {
      final content = _buildCookedHtmlBody(
        context,
        cookedHtmlOverride.trim(),
        baseStyle,
      );
      if (!enableTextSelection) {
        return content;
      }
      return _CustomMarkdownSelectionArea(child: content);
    }
    final data = markdown.trim().isEmpty
        ? _TopicDetailPageState._labelEmpty
        : markdown;
    final chunks = _splitMarkdownRenderChunks(data);
    if (chunks.isNotEmpty &&
        chunks.any(
          (chunk) =>
              chunk is _MarkdownVideoChunk || chunk is _MarkdownLinkChunk,
        )) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < chunks.length; i++) ...[
            if (chunks[i] case final _MarkdownTextChunk textChunk)
              _buildMarkdownBody(context, textChunk.markdown)
            else if (chunks[i] case final _MarkdownVideoChunk videoChunk)
              _InlineVideoSourceCard(video: videoChunk.video)
            else if (chunks[i] case final _MarkdownLinkChunk linkChunk)
              _ExternalLinkBookmarkCard(
                url: linkChunk.url,
                label: linkChunk.label,
                onTap: () {
                  unawaited(_openLink(linkChunk.url));
                },
              ),
            if (i != chunks.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
      if (!enableTextSelection) {
        return content;
      }
      return _CustomMarkdownSelectionArea(child: content);
    }
    final content = _buildMarkdownBody(context, data);
    if (!enableTextSelection) {
      return content;
    }
    return _CustomMarkdownSelectionArea(child: content);
  }

  Widget _buildMarkdownBody(BuildContext context, String data) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final baseStyle = textTheme.bodyMedium;
    if (_containsInlineHtmlTag(data)) {
      return _buildHtmlMarkdownBody(context, data, baseStyle);
    }

    final headers = _buildImageHeaders(cookieHeader);
    final galleryItems = _buildMarkdownGalleryItems(
      markdown: data,
      headers: headers,
    );
    final isDark = theme.brightness == Brightness.dark;
    final quoteBg = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.10),
      theme.colorScheme.surfaceContainerLow,
    );
    final quoteBorder = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.62 : 0.44,
    );
    final tableBorder = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.65 : 0.88,
    );
    final tableBg = theme.colorScheme.surfaceContainerLow;
    final tableHeadBg = theme.colorScheme.surfaceContainerHighest;
    var imageBuilderIndex = 0;
    final inlineSyntaxes = <md.InlineSyntax>[
      if (emojiUrls.isNotEmpty) _EmojiInlineSyntax(emojiUrls),
      if (onMentionTap != null) _MentionInlineSyntax(),
    ];
    final builders = <String, MarkdownElementBuilder>{
      if (emojiUrls.isNotEmpty) 'emoji': _EmojiBuilder(headers: headers),
      if (onMentionTap != null)
        'mention': _MentionBuilder(onTap: onMentionTap!),
      'a': _TopicAwareLinkBuilder(
        onTapMention: onMentionTap,
        onTapTopicLink: onTopicLinkTap,
        onTapExternalLink: _openLink,
      ),
    };
    return MarkdownBody(
      data: data,
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: inlineSyntaxes,
      builders: builders,
      imageBuilder: (uri, title, alt) {
        final resolvedUrl = _resolveForumUrl('$uri');
        if (!_isSafeRenderableImageUrl(resolvedUrl)) {
          // Guard unknown/broken image markdown (e.g. empty src). Render as
          // plain fallback text to avoid image provider crash.
          return Text(
            '[图片]',
            style: baseStyle?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        final imageIndex = imageBuilderIndex++;
        final fallbackHeroTag = _buildMarkdownHeroTag(
          markdown: data,
          index: imageIndex,
          imageUrl: resolvedUrl,
        );
        final viewerItems = galleryItems.isNotEmpty
            ? galleryItems
            : <RiverImageViewerItem>[
                RiverImageViewerItem(
                  url: resolvedUrl,
                  headers: headers,
                  heroTag: fallbackHeroTag,
                ),
              ];
        final initialIndex = galleryItems.isNotEmpty
            ? _resolveGalleryInitialIndex(
                items: galleryItems,
                url: resolvedUrl,
                preferredIndex: imageIndex,
              )
            : 0;

        return _MarkdownImage(
          url: resolvedUrl,
          headers: headers,
          viewerItems: viewerItems,
          initialIndex: initialIndex,
          heroTag: viewerItems[initialIndex].heroTag,
          enableHero: enableImageHero,
        );
      },
      onTapLink: (_, href, _) {},
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: baseStyle,
        blockquote: baseStyle?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
        ),
        tableHead: (baseStyle ?? textTheme.bodyMedium)?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        tableBody: (baseStyle ?? textTheme.bodyMedium)?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.5,
        ),
        tableHeadAlign: TextAlign.left,
        tableCellsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        tableCellsDecoration: BoxDecoration(
          color: tableBg,
          border: Border.all(color: tableBorder),
        ),
        tableHeadCellsDecoration: BoxDecoration(
          color: tableHeadBg,
          border: Border.all(color: tableBorder),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        blockquoteDecoration: BoxDecoration(
          color: quoteBg,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: quoteBorder, width: 3)),
        ),
      ),
    );
  }

  Widget _buildHtmlMarkdownBody(
    BuildContext context,
    String data,
    TextStyle? baseStyle,
  ) {
    final rawHtml = md.markdownToHtml(
      data,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final html = _normalizeMentionAnchorsInHtml(rawHtml);
    return _buildCookedHtmlBody(context, html, baseStyle);
  }

  Widget _buildCookedHtmlBody(
    BuildContext context,
    String html,
    TextStyle? baseStyle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final quoteBg = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.10),
      theme.colorScheme.surfaceContainerLow,
    );
    final quoteBorder = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.62 : 0.44,
    );
    final tableBorder = theme.colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.65 : 0.88,
    );
    final tableBg = theme.colorScheme.surfaceContainerLow;
    final detailsBg = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.06),
      theme.colorScheme.surfaceContainerLow,
    );
    final headers = _buildImageHeaders(cookieHeader);
    return HtmlWidget(
      html,
      baseUrl: Uri.tryParse(riverSideBaseUrl),
      renderMode: RenderMode.column,
      textStyle: baseStyle,
      customWidgetBuilder: (element) {
        final tag = (element.localName ?? '').toLowerCase();
        if (tag == 'table') {
          return _HtmlTableBlock(element: element);
        }
        if (tag != 'a') {
          return null;
        }
        if (!_isStandaloneHtmlAnchor(element)) {
          return null;
        }
        final href = (element.attributes['href'] ?? '').trim();
        if (href.isEmpty) {
          return null;
        }
        final resolved = _resolveForumUrl(href);
        if (_tryParseMentionUsernameFromUrl(resolved) != null ||
            _tryParseTopicIdFromUrl(resolved) != null) {
          return null;
        }
        final label = element.text.trim();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _ExternalLinkBookmarkCard(
            url: resolved,
            label: label,
            onTap: () {
              unawaited(_openLink(resolved));
            },
          ),
        );
      },
      customStylesBuilder: (element) {
        final tag = (element.localName ?? '').toLowerCase();
        if (tag == 'blockquote') {
          return <String, String>{
            'margin': '0',
            'padding': '10px 12px',
            'border-left': '3px solid ${_toCssColor(quoteBorder)}',
            'background-color': _toCssColor(quoteBg),
            'border-radius': '12px',
          };
        }
        if (tag == 'table') {
          return <String, String>{
            'width': '100%',
            'border-collapse': 'collapse',
            'background-color': _toCssColor(tableBg),
            'border': '1px solid ${_toCssColor(tableBorder)}',
            'color': _toCssColor(theme.colorScheme.onSurface),
            'border-radius': '12px',
            'overflow': 'hidden',
            'margin': '0',
          };
        }
        if (tag == 'tr') {
          return <String, String>{
            'background-color': _toCssColor(tableBg),
            'color': _toCssColor(theme.colorScheme.onSurface),
          };
        }
        if (tag == 'th') {
          return <String, String>{
            'padding': '10px 12px',
            'font-weight': '700',
            'text-align': 'left',
            'background-color': _toCssColor(
              theme.colorScheme.surfaceContainerHighest,
            ),
            'color': _toCssColor(theme.colorScheme.onSurface),
            'border': '1px solid ${_toCssColor(tableBorder)}',
          };
        }
        if (tag == 'td') {
          return <String, String>{
            'padding': '10px 12px',
            'background-color': _toCssColor(tableBg),
            'color': _toCssColor(theme.colorScheme.onSurface),
            'border': '1px solid ${_toCssColor(tableBorder)}',
          };
        }
        if (tag == 'details') {
          return <String, String>{
            'display': 'block',
            'margin': '0',
            'padding': '10px 12px',
            'background-color': _toCssColor(detailsBg),
            'border': '1px solid ${_toCssColor(tableBorder)}',
            'border-radius': '12px',
          };
        }
        if (tag == 'summary') {
          return <String, String>{
            'font-weight': '700',
            'margin': '0 0 8px 0',
          };
        }
        return null;
      },
      onTapUrl: (url) {
        final resolved = _resolveForumUrl(url);
        final mentionUsername = _tryParseMentionUsernameFromUrl(resolved);
        if (mentionUsername != null && onMentionTap != null) {
          onMentionTap!(mentionUsername);
          return true;
        }
        final topicId = _tryParseTopicIdFromUrl(resolved);
        if (topicId != null && onTopicLinkTap != null) {
          onTopicLinkTap!(topicId);
          return true;
        }
        unawaited(_openLink(resolved));
        return true;
      },
      onTapImage: (imageMetadata) {
        final viewerItems = <RiverImageViewerItem>[];
        var sourceIndex = 0;
        for (final source in imageMetadata.sources) {
          final resolved = _resolveForumUrl(source.url.trim());
          final uri = Uri.tryParse(resolved);
          final scheme = uri?.scheme.toLowerCase();
          if (scheme != 'http' && scheme != 'https') {
            continue;
          }
          if (!_isSafeRenderableImageUrl(resolved)) {
            continue;
          }
          final effectiveHeaders = _headersForImageUrl(resolved, headers);
          viewerItems.add(
            RiverImageViewerItem(
              url: resolved,
              headers: effectiveHeaders,
              heroTag:
                  'topic_html_image_${html.hashCode}_${sourceIndex}_${resolved.hashCode}',
              imageProvider: CachedNetworkImageProvider(
                resolved,
                headers: effectiveHeaders,
              ),
            ),
          );
          sourceIndex++;
        }
        if (viewerItems.isEmpty) {
          return;
        }
        unawaited(RiverImageViewerPage.open(context, items: viewerItems));
      },
    );
  }

  String _normalizeMentionAnchorsInHtml(String html) {
    if (html.trim().isEmpty) {
      return html;
    }
    final anchorPattern = RegExp(
      r'<a([^>]*\bhref\s*=\s*"([^"]+)"[^>]*)>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    return html.replaceAllMapped(anchorPattern, (match) {
      final full = match.group(0) ?? '';
      final attrs = match.group(1) ?? '';
      final href = (match.group(2) ?? '').trim();
      final innerHtml = match.group(3) ?? '';
      if (href.isEmpty) {
        return full;
      }
      final resolved = _resolveForumUrl(href);
      final mentionUsername = _tryParseMentionUsernameFromUrl(resolved);
      if (mentionUsername == null) {
        return full;
      }
      final mentionToken = mentionUsername.startsWith('uid:')
          ? mentionUsername
          : _normalizeMentionUsernameToken(mentionUsername);
      final fallbackLabel = mentionToken.startsWith('uid:')
          ? '@用户'
          : '@$mentionToken';
      final plainLabel = _decodeHtmlEntities(
        innerHtml.replaceAll(RegExp(r'<[^>]*>'), ''),
      ).trim();
      final normalizedLabel = _normalizeMentionDisplayLabel(
        label: plainLabel,
        fallbackLabel: fallbackLabel,
      );
      if (normalizedLabel == plainLabel) {
        return full;
      }
      return '<a$attrs>${htmlEscape.convert(normalizedLabel)}</a>';
    });
  }

  String _toCssColor(Color color) {
    final alpha = (color.a * 255).round() / 255;
    return 'rgba(${color.r}, ${color.g}, ${color.b}, ${alpha.toStringAsFixed(3)})';
  }

  bool _containsInlineHtmlTag(String source) {
    if (source.trim().isEmpty) {
      return false;
    }
    final tagRegex = RegExp(r'<[^>\n]+>');
    final htmlTagRegex = RegExp(
      r'^</?[a-z][a-z0-9-]*(\s[^>]*)?/?>$',
      caseSensitive: false,
    );
    for (final match in tagRegex.allMatches(source)) {
      final token = (match.group(0) ?? '').trim();
      if (token.isEmpty) {
        continue;
      }
      final lower = token.toLowerCase();
      if (lower.startsWith('<http') ||
          lower.startsWith('<https') ||
          lower.startsWith('<mailto:')) {
        continue;
      }
      if (htmlTagRegex.hasMatch(token)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openLink(String? href) async {
    final raw = href?.trim();
    if (raw == null || raw.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

}

bool _shouldPreferCookedHtmlRendering({
  required String markdown,
  required String cookedHtml,
  required int? replyToPostNumber,
}) {
  if (cookedHtml.trim().isEmpty) {
    return false;
  }
  if ((replyToPostNumber ?? 0) > 0) {
    return false;
  }
  if (RegExp(
    r'\[quote(?:="[^"]*")?\][\s\S]*?\[/quote\]',
    caseSensitive: false,
  ).hasMatch(markdown)) {
    return false;
  }
  final lower = cookedHtml.toLowerCase();
  return lower.contains('<table') ||
      lower.contains('class="md-table"') ||
      lower.contains('<details') ||
      lower.contains('<summary') ||
      lower.contains('class="onebox"');
}

class _CustomMarkdownSelectionArea extends StatelessWidget {
  const _CustomMarkdownSelectionArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        ContextMenuButtonItem? copyItem;
        for (final item in selectableRegionState.contextMenuButtonItems) {
          if (item.type == ContextMenuButtonType.copy) {
            copyItem = item;
            break;
          }
        }
        if (copyItem == null || copyItem.onPressed == null) {
          return const SizedBox.shrink();
        }
        final anchors = selectableRegionState.contextMenuAnchors;
        return CustomSingleChildLayout(
          delegate: TextSelectionToolbarLayoutDelegate(
            anchorAbove: anchors.primaryAnchor,
            anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
          ),
          child: _SelectionCopyToolbarButton(
            label: '复制内容',
            onPressed: copyItem.onPressed!,
          ),
        );
      },
      child: child,
    );
  }
}

class _SelectionCopyToolbarButton extends StatelessWidget {
  const _SelectionCopyToolbarButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.content_copy_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineVideoSourceCard extends StatefulWidget {
  const _InlineVideoSourceCard({required this.video});

  final _VideoSourceDescriptor video;

  @override
  State<_InlineVideoSourceCard> createState() => _InlineVideoSourceCardState();
}

class _HtmlTableBlock extends StatelessWidget {
  const _HtmlTableBlock({required this.element});

  final dynamic element;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = _extractRows(element);
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxColumns = rows
        .map((row) => row.length)
        .fold<int>(0, (current, next) => math.max(current, next));
    if (maxColumns <= 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
                verticalInside: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (final row in rows)
                  TableRow(
                    children: [
                      for (var index = 0; index < maxColumns; index++)
                        _HtmlTableCell(
                          text: index < row.length ? row[index].text : '',
                          isHeader: index < row.length && row[index].isHeader,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<List<_HtmlTableCellData>> _extractRows(dynamic tableElement) {
    final directRows = _parseRowList(tableElement.children);
    if (directRows.isNotEmpty) {
      return directRows;
    }

    final rows = <List<_HtmlTableCellData>>[];
    for (final child in tableElement.children) {
      rows.addAll(_parseRowList(child.children));
    }
    return rows;
  }

  List<List<_HtmlTableCellData>> _parseRowList(dynamic elements) {
    final rows = <List<_HtmlTableCellData>>[];
    for (final rowElement in elements) {
      if ((rowElement.localName ?? '').toLowerCase() != 'tr') {
        continue;
      }
      final cells = <_HtmlTableCellData>[];
      for (final cell in rowElement.children) {
        final tag = (cell.localName ?? '').toLowerCase();
        if (tag != 'th' && tag != 'td') {
          continue;
        }
        final text = _decodeHtmlEntities('${cell.text ?? ''}').trim();
        cells.add(
          _HtmlTableCellData(
            text: text,
            isHeader: tag == 'th',
          ),
        );
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }
    return rows;
  }
}

class _HtmlTableCell extends StatelessWidget {
  const _HtmlTableCell({
    required this.text,
    required this.isHeader,
  });

  final String text;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isHeader
          ? colors.surfaceContainerHighest
          : colors.surfaceContainerLow,
      child: Text(
        text,
        style: (isHeader
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.bodyMedium)
            ?.copyWith(color: colors.onSurface),
      ),
    );
  }
}

class _HtmlTableCellData {
  const _HtmlTableCellData({
    required this.text,
    required this.isHeader,
  });

  final String text;
  final bool isHeader;
}

class _InlineVideoSourceCardState extends State<_InlineVideoSourceCard> {
  WebViewController? _controller;
  bool _loading = false;
  double _aspectRatio = 16 / 9;

  Future<void> _activatePlayer() async {
    if (_controller != null) {
      return;
    }
    final controller = WebViewController();
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setBackgroundColor(Colors.black);
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) {
            return;
          }
          setState(() => _loading = false);
          if (widget.video.directVideo) {
            _requestDirectVideoMeta(controller);
          }
        },
      ),
    );
    if (widget.video.directVideo) {
      await controller.addJavaScriptChannel(
        'RiverVideoMeta',
        onMessageReceived: (message) {
          _applyVideoMeta(message.message);
        },
      );
    }
    setState(() {
      _loading = true;
      _controller = controller;
    });
    if (widget.video.directVideo) {
      final html =
          '<!doctype html><html><head><meta name="viewport" '
          'content="width=device-width, initial-scale=1.0, maximum-scale=1.0"></head>'
          '<body style="margin:0;background:#000;overflow:hidden;">'
          '<video id="rv_video" controls playsinline webkit-playsinline '
          'style="width:100%;height:100%;object-fit:contain;background:#000;" '
          'src="${widget.video.embedUrl}"></video>'
          '<script>'
          'const v=document.getElementById("rv_video");'
          'function sendMeta(){'
          'if(!v)return;'
          'const w=v.videoWidth||0;const h=v.videoHeight||0;'
          'if(w>0&&h>0&&window.RiverVideoMeta){RiverVideoMeta.postMessage(w+","+h);}'
          '}'
          'v.addEventListener("loadedmetadata",sendMeta);'
          'v.addEventListener("resize",sendMeta);'
          'setTimeout(sendMeta, 120);'
          'setTimeout(sendMeta, 600);'
          '</script>'
          '</body></html>';
      await controller.loadHtmlString(html);
      return;
    }
    final uri = Uri.tryParse(widget.video.embedUrl);
    if (uri != null) {
      await controller.loadRequest(uri);
      return;
    }
    await controller.loadHtmlString(
      '<!doctype html><html><body style="margin:0;background:#000;"></body></html>',
    );
  }

  Future<void> _requestDirectVideoMeta(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        '(() => {'
        'const v=document.getElementById("rv_video")||document.querySelector("video");'
        'if(!v){return "";}'
        'const w=v.videoWidth||0;const h=v.videoHeight||0;'
        'return (w>0&&h>0)?(w+","+h):"";'
        '})()',
      );
      _applyVideoMeta('$result');
    } catch (_) {
      // Ignore: metadata may not be available on some devices at this moment.
    }
  }

  void _applyVideoMeta(String raw) {
    final clean = raw.replaceAll('"', '').trim();
    if (clean.isEmpty) {
      return;
    }
    final parts = clean.split(',');
    if (parts.length != 2) {
      return;
    }
    final width = double.tryParse(parts[0].trim()) ?? 0;
    final height = double.tryParse(parts[1].trim()) ?? 0;
    if (width <= 0 || height <= 0) {
      return;
    }
    final ratio = (width / height).clamp(9 / 16, 21 / 9);
    if (!mounted || (ratio - _aspectRatio).abs() < 0.005) {
      return;
    }
    setState(() {
      _aspectRatio = ratio;
    });
  }

  Future<void> _openSource() async {
    await launchUrl(
      Uri.parse(widget.video.sourceUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: widget.video.directVideo ? _aspectRatio : 16 / 9,
            child: _controller == null
                ? Material(
                    color: Colors.black,
                    child: InkWell(
                      onTap: _activatePlayer,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击播放 ${widget.video.providerLabel}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: WebViewWidget(controller: _controller!),
                      ),
                      if (_loading)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.video.providerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '外部打开',
                  onPressed: _openSource,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

part of 'topic_detail_page.dart';

const String _assetEmojiScheme = 'asset://';

bool _isAssetEmojiUrl(String source) =>
    source.trim().toLowerCase().startsWith(_assetEmojiScheme);

String _assetPathFromEmojiUrl(String source) =>
    source.trim().substring(_assetEmojiScheme.length);

String _normalizeForumEmojiLookupKey(String raw) {
  final key = raw.trim();
  if (key.isEmpty) {
    return '';
  }
  final shorthand = RegExp(
    r'^([as])(\d+)$',
    caseSensitive: false,
  ).firstMatch(key);
  if (shorthand == null) {
    return key;
  }
  final prefix = (shorthand.group(1) ?? '').toLowerCase();
  final id = (shorthand.group(2) ?? '').trim();
  if (prefix.isEmpty || id.isEmpty) {
    return key;
  }
  return '${prefix}_$id';
}

abstract class _PostContentBlock {
  const _PostContentBlock();
}

class _MarkdownBlock extends _PostContentBlock {
  const _MarkdownBlock(this.markdown);

  final String markdown;
}

class _QuoteBlock extends _PostContentBlock {
  const _QuoteBlock({
    required this.ref,
    required this.contentMarkdown,
    this.inlineStyle,
  });

  final _QuoteRef ref;
  final String contentMarkdown;
  final _QuoteInlineStyle? inlineStyle;
}

class _QuoteInlineStyle {
  const _QuoteInlineStyle({
    this.fontScale = 1,
    this.foregroundColor,
    this.backgroundColor,
  });

  final double fontScale;
  final Color? foregroundColor;
  final Color? backgroundColor;
}

class _QuoteRef {
  const _QuoteRef({
    required this.username,
    required this.topicId,
    required this.postNumber,
  });

  final String username;
  final int topicId;
  final int postNumber;
}

List<_PostContentBlock> _parsePostContentBlocks(String source, int topicId) {
  final content = source.trim();
  if (content.isEmpty) {
    return const <_PostContentBlock>[];
  }

  final matches = RegExp(
    r'\[quote(?:="([^"]*)")?\]([\s\S]*?)\[/quote\]',
    caseSensitive: false,
  ).allMatches(content);

  if (matches.isEmpty) {
    return <_PostContentBlock>[_MarkdownBlock(content)];
  }

  final blocks = <_PostContentBlock>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      final markdown = content.substring(cursor, match.start).trim();
      if (markdown.isNotEmpty) {
        blocks.add(_MarkdownBlock(markdown));
      }
    }

    final header = (match.group(1) ?? '').trim();
    final quoted = (match.group(2) ?? '').trim();
    final parsedQuote = _parseQuoteContent(quoted);
    blocks.add(
      _QuoteBlock(
        ref: _parseQuoteRef(header, topicId),
        contentMarkdown: parsedQuote.markdown,
        inlineStyle: parsedQuote.inlineStyle,
      ),
    );
    cursor = match.end;
  }

  if (cursor < content.length) {
    final markdown = content.substring(cursor).trim();
    if (markdown.isNotEmpty) {
      blocks.add(_MarkdownBlock(markdown));
    }
  }

  return blocks;
}

class _ParsedQuoteContent {
  const _ParsedQuoteContent({required this.markdown, this.inlineStyle});

  final String markdown;
  final _QuoteInlineStyle? inlineStyle;
}

class _QingStructuredQuote {
  const _QingStructuredQuote({
    required this.username,
    required this.bodyMarkdown,
    required this.blockMarkdown,
  });

  final String username;
  final String bodyMarkdown;
  final String blockMarkdown;
}

_ParsedQuoteContent _parseQuoteContent(String source) {
  final raw = source.trim();
  if (raw.isEmpty) {
    return const _ParsedQuoteContent(markdown: '');
  }
  final cleaned = raw
      .replaceAll(
        RegExp(
          r'\[/?(?:size|color|bgcolor)(?:=[^\]]*)?\]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  final style = _extractQuoteInlineStyle(raw);
  return _ParsedQuoteContent(
    markdown: cleaned.isEmpty ? raw : cleaned,
    inlineStyle: style,
  );
}

_QuoteInlineStyle? _extractQuoteInlineStyle(String source) {
  final sizeMatch = RegExp(
    r'\[size=(\d+)\]',
    caseSensitive: false,
  ).firstMatch(source);
  final sizePercent = int.tryParse((sizeMatch?.group(1) ?? '').trim());
  final scale = sizePercent == null
      ? 1.0
      : (sizePercent / 100).clamp(0.8, 2.6).toDouble();

  final colorMatch = RegExp(
    r'\[color=([^\]]+)\]',
    caseSensitive: false,
  ).firstMatch(source);
  final bgMatch = RegExp(
    r'\[bgcolor=([^\]]+)\]',
    caseSensitive: false,
  ).firstMatch(source);
  final fg = _parseBbcodeColor((colorMatch?.group(1) ?? '').trim());
  final bg = _parseBbcodeColor((bgMatch?.group(1) ?? '').trim());

  if ((scale - 1).abs() < 0.01 && fg == null && bg == null) {
    return null;
  }
  return _QuoteInlineStyle(
    fontScale: scale,
    foregroundColor: fg,
    backgroundColor: bg,
  );
}

Color? _parseBbcodeColor(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  switch (value) {
    case 'red':
      return Colors.red;
    case 'yellow':
      return Colors.yellow;
    case 'orange':
      return Colors.orange;
    case 'blue':
      return Colors.blue;
    case 'green':
      return Colors.green;
    case 'black':
      return Colors.black;
    case 'white':
      return Colors.white;
    case 'grey':
    case 'gray':
      return Colors.grey;
    case 'purple':
      return Colors.purple;
    case 'pink':
      return Colors.pink;
    default:
      final hex = value.startsWith('#') ? value.substring(1) : value;
      if (hex.length == 6) {
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed == null) {
          return null;
        }
        return Color(0xFF000000 | parsed);
      }
      if (hex.length == 8) {
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed == null) {
          return null;
        }
        return Color(parsed);
      }
      return null;
  }
}

_QuoteRef _parseQuoteRef(String header, int fallbackTopicId) {
  var username = _TopicDetailPageState._labelUnknownUser;
  final parts = header.split(',');
  if (parts.isNotEmpty) {
    final first = parts.first.trim();
    if (first.isNotEmpty && !first.contains(':')) {
      username = _normalizeMentionUsernameToken(first);
    }
  }

  final postNumber =
      _firstInt(RegExp(r'post:\s*(\d+)', caseSensitive: false), header) ?? 0;
  final topicId =
      _firstInt(RegExp(r'topic:\s*(\d+)', caseSensitive: false), header) ??
      fallbackTopicId;

  return _QuoteRef(
    username: username,
    topicId: topicId,
    postNumber: postNumber,
  );
}

int? _firstInt(RegExp pattern, String source) {
  final match = pattern.firstMatch(source);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

String _toPlainPreview(String markdown) {
  return markdown
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .replaceAll(RegExp(r'[`*_>#-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripQuotedMarkdown(String markdown) {
  final source = markdown.trim();
  if (source.isEmpty) {
    return source;
  }
  var stripped = source;
  stripped = stripped.replaceAll(
    RegExp(r'\[quote(?:="[^"]*")?\][\s\S]*?\[/quote\]', caseSensitive: false),
    '',
  );
  stripped = stripped.replaceAll(
    RegExp(
      r'<aside\b[^>]*class="[^"]*\bquote\b[^"]*"[^>]*>[\s\S]*?</aside>',
      caseSensitive: false,
    ),
    '',
  );
  stripped = stripped.replaceAll(
    RegExp(
      r'^(?:[^\n]{0,120}:\s*\n)?(?:>\s?.*(?:\n|$))+',
      caseSensitive: false,
    ),
    '',
  );
  return stripped.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

class _EmojiInlineSyntax extends md.InlineSyntax {
  _EmojiInlineSyntax(this.emojiUrls) : super(r':([a-zA-Z0-9_+\-]+):');

  final Map<String, String> emojiUrls;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final key = (match.group(1) ?? '').trim();
    if (key.isEmpty) {
      // Consume unknown token safely to avoid parser retry on same range.
      parser.addNode(md.Text(match.group(0) ?? ':'));
      return true;
    }
    final normalizedKey = _normalizeForumEmojiLookupKey(key);
    final url =
        emojiUrls[normalizedKey] ??
        emojiUrls[normalizedKey.toLowerCase()] ??
        emojiUrls[key] ??
        emojiUrls[key.toLowerCase()];
    if (url == null || url.isEmpty) {
      // Keep unknown emoji token as plain text, but consume current match.
      parser.addNode(md.Text(match.group(0) ?? ':$key:'));
      return true;
    }

    final element = md.Element.text('emoji', normalizedKey);
    element.attributes['data-url'] = url;
    parser.addNode(element);
    return true;
  }
}

class _MentionInlineSyntax extends md.InlineSyntax {
  _MentionInlineSyntax()
    : super(r'(?<![\w/`])@([^\s@`<>()\[\]{}]{1,32})');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final username = _trimTrailingMentionPunctuation(
      (match.group(1) ?? '').trim(),
    );
    if (username.isEmpty) {
      return false;
    }
    final element = md.Element.text('mention', '@$username');
    element.attributes['data-username'] = username;
    parser.addNode(element);
    return true;
  }
}

String _trimTrailingMentionPunctuation(String source) {
  var value = source.trim();
  while (value.isNotEmpty &&
      RegExp(r'[!?,.;:)\]}>，。！？；：、]+$').hasMatch(value)) {
    value = value.substring(0, value.length - 1).trimRight();
  }
  return value;
}

class _MentionBuilder extends MarkdownElementBuilder {
  _MentionBuilder({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final username = _normalizeMentionUsernameToken(
      (element.attributes['data-username'] ?? '').trim(),
    );
    if (username.isEmpty) {
      return Text(element.textContent, style: preferredStyle);
    }
    return _InlinePillLink(
      icon: Icons.alternate_email_rounded,
      label: '@$username',
      onTap: () => onTap(username),
    );
  }
}

class _TopicAwareLinkBuilder extends MarkdownElementBuilder {
  _TopicAwareLinkBuilder({
    this.onTapMention,
    this.onTapTopicLink,
    required this.onTapExternalLink,
  });

  final ValueChanged<String>? onTapMention;
  final ValueChanged<int>? onTapTopicLink;
  final ValueChanged<String?> onTapExternalLink;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) {
      return Text(element.textContent, style: preferredStyle);
    }
    final resolved = _resolveForumUrl(href);

    final mentionUsername = _tryParseMentionUsernameFromUrl(resolved);
    if (mentionUsername != null && onTapMention != null) {
      final mentionToken = mentionUsername.startsWith('uid:')
          ? mentionUsername
          : _normalizeMentionUsernameToken(mentionUsername);
      final label = element.textContent.trim();
      final fallbackMentionLabel = mentionToken.startsWith('uid:')
          ? '@用户'
          : '@$mentionToken';
      final shown = _normalizeMentionDisplayLabel(
        label: label,
        fallbackLabel: fallbackMentionLabel,
      );
      return _InlinePillLink(
        icon: Icons.alternate_email_rounded,
        label: shown,
        onTap: () => onTapMention!(mentionToken),
      );
    }

    final topicId = _tryParseTopicIdFromUrl(resolved);
    if (topicId != null && onTapTopicLink != null) {
      final label = element.textContent.trim();
      return _InlinePillLink(
        icon: Icons.article_outlined,
        label: label.isEmpty ? '帖子 #$topicId' : label,
        onTap: () => onTapTopicLink!(topicId),
      );
    }

    final label = element.textContent.trim();
    return _InlineExternalLinkText(
      label: label.isEmpty ? resolved : label,
      onTap: () => onTapExternalLink(resolved),
      preferredStyle: preferredStyle,
    );
  }
}

class _InlinePillLink extends StatelessWidget {
  const _InlinePillLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isStandaloneHtmlAnchor(dynamic element) {
  final parent = element?.parent;
  if (parent == null) {
    return false;
  }
  final parentName = '${parent.localName ?? ''}'.toLowerCase();
  if (parentName != 'p' && parentName != 'li' && parentName != 'div') {
    return false;
  }
  final children = parent.children;
  if (children is! List || children.length != 1) {
    return false;
  }
  return identical(children.first, element);
}

class _InlineExternalLinkText extends StatelessWidget {
  const _InlineExternalLinkText({
    required this.label,
    required this.onTap,
    this.preferredStyle,
  });

  final String label;
  final VoidCallback onTap;
  final TextStyle? preferredStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: preferredStyle?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ExternalLinkBookmarkCard extends StatefulWidget {
  const _ExternalLinkBookmarkCard({
    required this.url,
    required this.onTap,
    this.label = '',
  });

  final String url;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ExternalLinkBookmarkCard> createState() =>
      _ExternalLinkBookmarkCardState();
}

class _ExternalLinkBookmarkCardState extends State<_ExternalLinkBookmarkCard> {
  late Future<_LinkPreviewMetadata?> _future;

  @override
  void initState() {
    super.initState();
    _future = _LinkPreviewCache.load(widget.url);
  }

  @override
  void didUpdateWidget(covariant _ExternalLinkBookmarkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _LinkPreviewCache.load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LinkPreviewMetadata?>(
      future: _future,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        return _buildCard(context, metadata: metadata);
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required _LinkPreviewMetadata? metadata,
  }) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(widget.url);
    final host = (metadata?.host ?? uri?.host ?? widget.url).trim();
    final label = widget.label.trim();
    final title = _firstNonEmpty(<String>[
      metadata?.title ?? '',
      (label.isNotEmpty && label != widget.url) ? label : '',
      host,
      widget.url,
    ]);
    final description = _firstNonEmpty(<String>[
      metadata?.description ?? '',
      metadata?.siteName ?? '',
      widget.url,
    ]);
    final imageUrl = (metadata?.imageUrl ?? '').trim();
    final imageUri = Uri.tryParse(imageUrl);
    final hasImage =
        imageUri != null &&
        (imageUri.scheme.toLowerCase() == 'http' ||
            imageUri.scheme.toLowerCase() == 'https');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.54),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const SizedBox(width: 78, height: 78),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkPreviewMetadata {
  const _LinkPreviewMetadata({
    required this.host,
    this.title = '',
    this.description = '',
    this.imageUrl = '',
    this.siteName = '',
  });

  final String host;
  final String title;
  final String description;
  final String imageUrl;
  final String siteName;
}

class _LinkPreviewCache {
  _LinkPreviewCache._();

  static const int _maxEntries = 96;
  static final Map<String, _LinkPreviewMetadata?> _cache =
      <String, _LinkPreviewMetadata?>{};
  static final Map<String, Future<_LinkPreviewMetadata?>> _inflight =
      <String, Future<_LinkPreviewMetadata?>>{};
  static final List<String> _order = <String>[];

  static Future<_LinkPreviewMetadata?> load(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return Future<_LinkPreviewMetadata?>.value(null);
    }
    if (_cache.containsKey(url)) {
      return Future<_LinkPreviewMetadata?>.value(_cache[url]);
    }
    final pending = _inflight[url];
    if (pending != null) {
      return pending;
    }
    final task = _fetch(url).then(
      (value) {
        _put(url, value);
        _inflight.remove(url);
        return value;
      },
      onError: (_) {
        _put(url, null);
        _inflight.remove(url);
        return null;
      },
    );
    _inflight[url] = task;
    return task;
  }

  static void _put(String url, _LinkPreviewMetadata? value) {
    if (_cache.containsKey(url)) {
      _order.remove(url);
    }
    _cache[url] = value;
    _order.add(url);
    while (_order.length > _maxEntries) {
      final removed = _order.removeAt(0);
      _cache.remove(removed);
    }
  }

  static Future<_LinkPreviewMetadata?> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final host = uri.host.trim();
    if (host.isEmpty) {
      return null;
    }

    try {
      final response = await http
          .get(
            uri,
            headers: const <String, String>{
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return _LinkPreviewMetadata(host: host);
      }
      var html = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (html.length > 240000) {
        html = html.substring(0, 240000);
      }
      final attrsList = _extractMetaAttributes(html);
      final title = _firstNonEmpty(<String>[
        _metaByProperty(attrsList, 'og:title'),
        _metaByName(attrsList, 'twitter:title'),
        _extractHtmlTitle(html),
      ]);
      final description = _firstNonEmpty(<String>[
        _metaByProperty(attrsList, 'og:description'),
        _metaByName(attrsList, 'description'),
        _metaByName(attrsList, 'twitter:description'),
      ]);
      final siteName = _firstNonEmpty(<String>[
        _metaByProperty(attrsList, 'og:site_name'),
        _metaByName(attrsList, 'application-name'),
      ]);
      final imageRaw = _firstNonEmpty(<String>[
        _metaByProperty(attrsList, 'og:image'),
        _metaByName(attrsList, 'twitter:image'),
      ]);
      final imageUrl = _resolveLinkPreviewImage(uri, imageRaw);
      return _LinkPreviewMetadata(
        host: host,
        title: _normalizePreviewText(title),
        description: _normalizePreviewText(description),
        imageUrl: imageUrl,
        siteName: _normalizePreviewText(siteName),
      );
    } catch (_) {
      return _LinkPreviewMetadata(host: host);
    }
  }
}

List<Map<String, String>> _extractMetaAttributes(String html) {
  final tags = RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html);
  final result = <Map<String, String>>[];
  for (final match in tags) {
    final tag = (match.group(0) ?? '').trim();
    if (tag.isEmpty) {
      continue;
    }
    result.add(_parseHtmlAttributes(tag));
  }
  return result;
}

Map<String, String> _parseHtmlAttributes(String tag) {
  final attrs = <String, String>{};
  final pattern = RegExp(
    '([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(tag)) {
    final key = (match.group(1) ?? '').trim().toLowerCase();
    final value = _decodeHtmlEntities(
      (match.group(3) ?? match.group(4) ?? match.group(5) ?? '').trim(),
    );
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    attrs[key] = value;
  }
  return attrs;
}

String _metaByProperty(List<Map<String, String>> attrsList, String property) {
  final target = property.toLowerCase();
  for (final attrs in attrsList) {
    if ((attrs['property'] ?? '').toLowerCase() == target) {
      return attrs['content'] ?? '';
    }
  }
  return '';
}

String _metaByName(List<Map<String, String>> attrsList, String name) {
  final target = name.toLowerCase();
  for (final attrs in attrsList) {
    if ((attrs['name'] ?? '').toLowerCase() == target) {
      return attrs['content'] ?? '';
    }
  }
  return '';
}

String _extractHtmlTitle(String html) {
  final match = RegExp(
    r'<title\b[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) {
    return '';
  }
  return _decodeHtmlEntities(match.group(1) ?? '');
}

String _decodeHtmlEntities(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  return raw
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

String _normalizePreviewText(String raw) {
  return raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _resolveLinkPreviewImage(Uri pageUri, String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return value;
  }
  if (value.startsWith('//')) {
    return '${pageUri.scheme}:$value';
  }
  final resolved = pageUri.resolve(value);
  return resolved.toString();
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String? _tryParseMentionUsernameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty && isRiverSideHost(host)) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    final parts = segments.toList(growable: false);
    if (parts.length < 2 || parts.first != 'u') {
      return null;
    }
    final username = parts[1].split('.').first.trim();
    final normalized = _normalizeMentionUsernameToken(username);
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
  if (host.isNotEmpty && _isQingShuiHePanHost(host)) {
    final uid =
        uri.queryParameters['uid'] ??
        uri.queryParameters['user_id'] ??
        uri.queryParameters['userid'];
    final normalizedUid = int.tryParse((uid ?? '').trim());
    if (normalizedUid != null && normalizedUid > 0) {
      return 'uid:$normalizedUid';
    }
    final username =
        uri.queryParameters['username'] ??
        uri.queryParameters['user_name'] ??
        uri.queryParameters['name'];
    final normalizedUsername = _normalizeMentionUsernameToken(
      (username ?? '').trim(),
    );
    if (normalizedUsername.isNotEmpty) {
      return normalizedUsername;
    }
    final path = uri.path.toLowerCase();
    final uidFromPath = RegExp(r'uid(?:=|/|-)(\d+)').firstMatch(path);
    if (uidFromPath != null) {
      final parsed = int.tryParse(uidFromPath.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return 'uid:$parsed';
      }
    }
  }
  return null;
}

String _normalizeMentionUsernameToken(String source) {
  var token = source.trim();
  if (token.isEmpty || token.startsWith('uid:')) {
    return token;
  }
  while (token.startsWith('@')) {
    token = token.substring(1).trimLeft();
  }
  return token;
}

String _normalizeMentionDisplayLabel({
  required String label,
  required String fallbackLabel,
}) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return fallbackLabel;
  }
  if (!trimmed.startsWith('@')) {
    return fallbackLabel;
  }
  final token = _normalizeMentionUsernameToken(trimmed);
  if (token.isEmpty) {
    return fallbackLabel;
  }
  return '@$token';
}

int? _tryParseTopicIdFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty && isRiverSideHost(host)) {
    final parts = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.first != 't') {
      return null;
    }
    for (var i = parts.length - 1; i >= 1; i--) {
      final parsed = int.tryParse(parts[i]);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }
  if (host.isNotEmpty && _isQingShuiHePanHost(host)) {
    final tid =
        uri.queryParameters['tid'] ??
        uri.queryParameters['topic_id'] ??
        uri.queryParameters['topicId'];
    final fromQuery = int.tryParse((tid ?? '').trim());
    if (fromQuery != null && fromQuery > 0) {
      return fromQuery;
    }
    final match = RegExp(r'(?:tid=|topic/|thread-)(\d+)').firstMatch(url);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }
  return null;
}

bool _isQingShuiHePanHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  final forumHost = Uri.parse(
    RiverServerConfig.instance.qingShuiHePanBaseUrl,
  ).host.toLowerCase();
  if (forumHost.isEmpty) {
    return false;
  }
  return normalized == forumHost || normalized.endsWith('.$forumHost');
}

class _EmojiBuilder extends MarkdownElementBuilder {
  _EmojiBuilder({required this.headers});

  final Map<String, String>? headers;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final url = (element.attributes['data-url'] ?? '').trim();
    if (url.isEmpty) {
      return Text(':${element.textContent}:', style: preferredStyle);
    }
    final fallback = Text(':${element.textContent}:', style: preferredStyle);
    final child = _isAssetEmojiUrl(url)
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Image.asset(
              _assetPathFromEmojiUrl(url),
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CachedNetworkImage(
              imageUrl: _resolveForumUrl(url),
              httpHeaders: headers,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (context, imageUrl, error) => fallback,
            ),
          );
    return Text.rich(
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: child),
      style: parentStyle ?? preferredStyle,
    );
  }
}

Map<String, String>? _buildImageHeaders(String? cookieHeader) {
  final cookie = cookieHeader?.trim();
  if (cookie == null || cookie.isEmpty) {
    return <String, String>{'Referer': riverSideBaseUrl};
  }
  return <String, String>{'Cookie': cookie, 'Referer': riverSideBaseUrl};
}

Map<String, String>? _headersForImageUrl(
  String url,
  Map<String, String>? headers,
) {
  if (headers == null || headers.isEmpty) {
    return headers;
  }
  final uri = Uri.tryParse(url);
  final host = (uri?.host ?? '').trim().toLowerCase();
  if (host.isEmpty || isRiverSideHost(host)) {
    return headers;
  }
  return null;
}

bool _isRiverSideImageUrl(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').trim().toLowerCase();
  if (host.isEmpty) {
    return false;
  }
  final forumHost = Uri.parse(riverSideBaseUrl).host.toLowerCase();
  return host == forumHost || host.endsWith('.$forumHost');
}

Map<String, String>? _stripCookieHeader(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) {
    return headers;
  }
  final next = <String, String>{};
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'cookie') {
      return;
    }
    next[key] = value;
  });
  return next.isEmpty ? null : next;
}

String _buildImageCacheKey(String url, Map<String, String>? headers) {
  final cookie = (headers?['Cookie'] ?? '').trim();
  if (cookie.isEmpty) {
    return url;
  }
  return '$url#auth';
}

bool _isSafeRenderableImageUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty) {
    return false;
  }
  if (_isAssetEmojiUrl(raw)) {
    final assetPath = _assetPathFromEmojiUrl(raw).trim();
    return assetPath.isNotEmpty;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return false;
  }
  if (!uri.hasScheme) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'data';
}

List<RiverImageViewerItem> _buildMarkdownGalleryItems({
  required String markdown,
  required Map<String, String>? headers,
}) {
  final rawUrls = _extractMarkdownImageUrls(markdown);
  if (rawUrls.isEmpty) {
    return const <RiverImageViewerItem>[];
  }

  final items = <RiverImageViewerItem>[];
  for (var i = 0; i < rawUrls.length; i++) {
    final resolved = _resolveForumUrl(rawUrls[i]);
    if (resolved.isEmpty) {
      continue;
    }
    items.add(
      RiverImageViewerItem(
        url: resolved,
        headers: _headersForImageUrl(resolved, headers),
        heroTag: _buildMarkdownHeroTag(
          markdown: markdown,
          index: i,
          imageUrl: resolved,
        ),
      ),
    );
  }
  return items;
}

int _resolveGalleryInitialIndex({
  required List<RiverImageViewerItem> items,
  required String url,
  required int preferredIndex,
}) {
  if (items.isEmpty) {
    return 0;
  }
  if (preferredIndex >= 0 &&
      preferredIndex < items.length &&
      items[preferredIndex].url == url) {
    return preferredIndex;
  }

  for (var i = preferredIndex; i < items.length; i++) {
    if (items[i].url == url) {
      return i;
    }
  }
  for (var i = 0; i < preferredIndex && i < items.length; i++) {
    if (items[i].url == url) {
      return i;
    }
  }
  if (preferredIndex < 0) {
    return 0;
  }
  if (preferredIndex >= items.length) {
    return items.length - 1;
  }
  return preferredIndex;
}

String _buildMarkdownHeroTag({
  required String markdown,
  required int index,
  required String imageUrl,
}) {
  return 'topic-md-gallery-${markdown.hashCode}-$index-${imageUrl.hashCode}';
}

List<String> _extractMarkdownImageUrls(String markdown) {
  if (markdown.trim().isEmpty) {
    return const <String>[];
  }

  final urls = <String>[];
  final pattern = RegExp(
    r'''!\[[^\]]*\]\(([^)]+)\)|<img[^>]+src\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(markdown)) {
    var raw = (match.group(1) ?? match.group(2) ?? '').trim();
    if (raw.isEmpty) {
      continue;
    }

    if (raw.startsWith('<') && raw.endsWith('>') && raw.length > 2) {
      raw = raw.substring(1, raw.length - 1).trim();
    }
    final spaceIndex = raw.indexOf(RegExp(r'\s'));
    if (spaceIndex > 0) {
      raw = raw.substring(0, spaceIndex).trim();
    }
    if (raw.isEmpty) {
      continue;
    }
    urls.add(raw);
  }

  return urls;
}

abstract class _MarkdownRenderChunk {
  const _MarkdownRenderChunk();
}

class _MarkdownTextChunk extends _MarkdownRenderChunk {
  const _MarkdownTextChunk(this.markdown);

  final String markdown;
}

class _MarkdownVideoChunk extends _MarkdownRenderChunk {
  const _MarkdownVideoChunk(this.video);

  final _VideoSourceDescriptor video;
}

class _MarkdownLinkChunk extends _MarkdownRenderChunk {
  const _MarkdownLinkChunk({required this.url, this.label = ''});

  final String url;
  final String label;
}

class _VideoSourceDescriptor {
  const _VideoSourceDescriptor({
    required this.sourceUrl,
    required this.embedUrl,
    required this.providerLabel,
    required this.directVideo,
  });

  final String sourceUrl;
  final String embedUrl;
  final String providerLabel;
  final bool directVideo;
}

List<_MarkdownRenderChunk> _splitMarkdownRenderChunks(String markdown) {
  final source = markdown.trim();
  if (source.isEmpty) {
    return const <_MarkdownRenderChunk>[];
  }

  final chunks = <_MarkdownRenderChunk>[];
  final buffer = StringBuffer();
  final lines = source.split('\n');

  void flushTextBuffer() {
    final text = buffer.toString().trim();
    if (text.isNotEmpty) {
      chunks.add(_MarkdownTextChunk(text));
    }
    buffer.clear();
  }

  for (final line in lines) {
    final trimmed = line.trim();
    final markdownLink = _parseStandaloneMarkdownLink(trimmed);
    if (markdownLink != null) {
      final resolved = _resolveForumUrl(markdownLink.url);
      if (!_isInternalForumLink(resolved)) {
        flushTextBuffer();
        chunks.add(
          _MarkdownLinkChunk(url: resolved, label: markdownLink.label),
        );
        continue;
      }
    }

    final standaloneUrl = _parseStandaloneUrlLine(trimmed);
    if (standaloneUrl != null) {
      final split = _splitUrlAndTrailing(standaloneUrl);
      final resolvedUrl = _resolveForumUrl(split.item1);
      final descriptor = _parseVideoSourceDescriptor(resolvedUrl);
      if (descriptor != null) {
        flushTextBuffer();
        chunks.add(_MarkdownVideoChunk(descriptor));
        if (split.item2.isNotEmpty) {
          buffer.writeln(split.item2);
        }
        continue;
      }
      if (!_isInternalForumLink(resolvedUrl)) {
        flushTextBuffer();
        chunks.add(_MarkdownLinkChunk(url: resolvedUrl));
        if (split.item2.isNotEmpty) {
          buffer.writeln(split.item2);
        }
        continue;
      }
    }

    buffer.writeln(line);
  }

  flushTextBuffer();
  if (chunks.isEmpty) {
    return <_MarkdownRenderChunk>[_MarkdownTextChunk(source)];
  }
  return chunks;
}

({String label, String url})? _parseStandaloneMarkdownLink(String line) {
  final value = line.trim();
  if (value.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'^\[([^\]\n]+)\]\((<?https?:\/\/[^)\s>]+>?)\)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  final label = (match.group(1) ?? '').trim();
  var url = (match.group(2) ?? '').trim();
  if (url.startsWith('<') && url.endsWith('>') && url.length > 2) {
    url = url.substring(1, url.length - 1).trim();
  }
  if (url.isEmpty) {
    return null;
  }
  return (label: label, url: url);
}

String? _parseStandaloneUrlLine(String line) {
  var value = line.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('<') && value.endsWith('>') && value.length > 2) {
    value = value.substring(1, value.length - 1).trim();
  }
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    return null;
  }
  final lower = value.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  return value;
}

bool _isInternalForumLink(String url) {
  return _tryParseMentionUsernameFromUrl(url) != null ||
      _tryParseTopicIdFromUrl(url) != null;
}

({String item1, String item2}) _splitUrlAndTrailing(String rawUrl) {
  var url = rawUrl;
  var trailing = '';
  while (url.isNotEmpty &&
      RegExp(r'[),.!?;:]$').hasMatch(url) &&
      !RegExp(r'[\w/]$').hasMatch(url)) {
    trailing = '${url[url.length - 1]}$trailing';
    url = url.substring(0, url.length - 1);
  }
  return (item1: url, item2: trailing);
}

_VideoSourceDescriptor? _parseVideoSourceDescriptor(String resolvedUrl) {
  if (resolvedUrl.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(resolvedUrl);
  if (uri == null) {
    return null;
  }

  final host = uri.host.toLowerCase();
  final youtubeId = _extractYoutubeVideoId(uri);
  if (youtubeId != null) {
    return _VideoSourceDescriptor(
      sourceUrl: resolvedUrl,
      embedUrl:
          'https://www.youtube.com/embed/$youtubeId?playsinline=1&autoplay=0&rel=0&modestbranding=1',
      providerLabel: 'YouTube',
      directVideo: false,
    );
  }

  final bilibiliBv = _extractBilibiliBvId(uri);
  if (bilibiliBv != null) {
    return _VideoSourceDescriptor(
      sourceUrl: resolvedUrl,
      embedUrl:
          'https://player.bilibili.com/player.html?bvid=$bilibiliBv&high_quality=1&autoplay=0',
      providerLabel: 'Bilibili',
      directVideo: false,
    );
  }

  if (host.contains('b23.tv')) {
    return _VideoSourceDescriptor(
      sourceUrl: resolvedUrl,
      embedUrl: resolvedUrl,
      providerLabel: 'Bilibili',
      directVideo: false,
    );
  }

  final path = uri.path.toLowerCase();
  const directSuffixes = <String>['.mp4', '.m4v', '.mov', '.webm', '.m3u8'];
  if (directSuffixes.any(path.endsWith)) {
    return _VideoSourceDescriptor(
      sourceUrl: resolvedUrl,
      embedUrl: resolvedUrl,
      providerLabel: '视频',
      directVideo: true,
    );
  }

  return null;
}

String? _extractYoutubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.contains('youtu.be')) {
    final parts = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (parts.isEmpty) {
      return null;
    }
    return parts.first;
  }
  if (!host.contains('youtube.com')) {
    return null;
  }
  final v = uri.queryParameters['v']?.trim();
  if (v != null && v.isNotEmpty) {
    return v;
  }
  final parts = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (parts.isEmpty) {
    return null;
  }
  final list = parts.toList(growable: false);
  if (list.first == 'shorts' || list.first == 'embed') {
    if (list.length >= 2) {
      return list[1];
    }
  }
  return null;
}

String? _extractBilibiliBvId(Uri uri) {
  final host = uri.host.toLowerCase();
  if (!host.contains('bilibili.com') && !host.contains('b23.tv')) {
    return null;
  }
  final queryBv = uri.queryParameters['bvid']?.trim();
  if (queryBv != null && queryBv.isNotEmpty) {
    return queryBv;
  }
  final joinedPath = '/${uri.pathSegments.join('/')}';
  final match = RegExp(r'BV[0-9A-Za-z]+').firstMatch(joinedPath);
  if (match == null) {
    return null;
  }
  return match.group(0);
}

String _resolveForumUrl(String source) {
  final raw = source.trim();
  if (raw.isEmpty) {
    return raw;
  }

  if (raw.startsWith('upload://')) {
    final short = raw.substring('upload://'.length);
    return '$riverSideBaseUrl/uploads/short-url/$short';
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return raw;
  }
  if (uri.hasScheme) {
    return raw;
  }
  if (raw.startsWith('//')) {
    return 'https:$raw';
  }
  if (raw.startsWith('/')) {
    return '$riverSideBaseUrl$raw';
  }
  return '$riverSideBaseUrl/$raw';
}

Color _onlineStateColor(bool? isOnline, BuildContext context) {
  if (isOnline == null) {
    return Theme.of(context).colorScheme.outline;
  }
  return isOnline ? Colors.green : Theme.of(context).colorScheme.outline;
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '--';
  }

  final local = value.toLocal();
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

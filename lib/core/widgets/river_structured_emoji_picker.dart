import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:river/core/theme/river_design_tokens.dart';
import 'package:flutter/services.dart';

const String _riverAssetEmojiScheme = 'asset://';

bool _isRiverAssetEmojiUrl(String source) =>
    source.trim().toLowerCase().startsWith(_riverAssetEmojiScheme);

String _riverAssetPathFromEmojiUrl(String source) =>
    source.trim().substring(_riverAssetEmojiScheme.length);

class RiverEmojiPicker extends StatefulWidget {
  const RiverEmojiPicker({
    super.key,
    required this.emojiUrls,
    required this.emojiGroups,
    required this.onSelected,
    this.title = '选择表情',
    this.embedded = false,
    this.resolveUrl,
    this.headersForUrl,
  });

  final Map<String, String> emojiUrls;
  final Map<String, List<String>> emojiGroups;
  final ValueChanged<String> onSelected;
  final String title;
  final bool embedded;
  final String Function(String raw)? resolveUrl;
  final Map<String, String>? Function(String resolvedUrl)? headersForUrl;

  @override
  State<RiverEmojiPicker> createState() => _RiverEmojiPickerState();
}

class _RiverPickerCategoryItem {
  const _RiverPickerCategoryItem({
    required this.pickerCategory,
    required this.title,
    required this.coverKey,
    required this.emojis,
  });

  final Category pickerCategory;
  final String title;
  final String coverKey;
  final List<Emoji> emojis;
}

class _RiverEmojiPickerState extends State<RiverEmojiPicker> {
  static const List<Category> _availablePickerCategories = <Category>[
    Category.SMILEYS,
    Category.ANIMALS,
    Category.FOODS,
    Category.ACTIVITIES,
    Category.TRAVEL,
    Category.OBJECTS,
    Category.SYMBOLS,
    Category.FLAGS,
  ];

  late List<_RiverPickerCategoryItem> _categories;

  @override
  void initState() {
    super.initState();
    _categories = _buildCategories();
  }

  @override
  void didUpdateWidget(covariant RiverEmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emojiUrls == widget.emojiUrls &&
        oldWidget.emojiGroups == widget.emojiGroups) {
      return;
    }
    _categories = _buildCategories();
  }

  List<_RiverPickerCategoryItem> _buildCategories() {
    final categories = <_RiverPickerCategoryItem>[];
    var categoryCursor = 0;

    widget.emojiGroups.forEach((groupName, keys) {
      final title = groupName.trim().isEmpty ? '自定义表情' : groupName.trim();
      final valid = keys
          .where(widget.emojiUrls.containsKey)
          .map((key) => Emoji(key, '$title | $key'))
          .toList(growable: false);
      if (valid.isEmpty) {
        return;
      }
      categories.add(
        _RiverPickerCategoryItem(
          pickerCategory:
              _availablePickerCategories[categoryCursor %
                  _availablePickerCategories.length],
          title: title,
          coverKey: valid.first.emoji,
          emojis: valid,
        ),
      );
      categoryCursor++;
    });

    if (categories.isEmpty && widget.emojiUrls.isNotEmpty) {
      final keys = widget.emojiUrls.keys.toList()..sort();
      categories.add(
        _RiverPickerCategoryItem(
          pickerCategory: Category.SMILEYS,
          title: '全部',
          coverKey: keys.first,
          emojis: keys
              .map((key) => Emoji(key, '全部 | $key'))
              .toList(growable: false),
        ),
      );
    }
    return categories;
  }

  List<CategoryEmoji> _buildEmojiSet(Locale _) {
    return _categories
        .map((item) => CategoryEmoji(item.pickerCategory, item.emojis))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (_categories.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(widget.embedded ? 24 : 30),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.18),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '暂无表情',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
            colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(widget.embedded ? 24 : 30),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: widget.embedded ? 0.08 : 0.12,
            ),
            blurRadius: widget.embedded ? 20 : 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (!widget.embedded) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(RiverRadius.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    final key = emoji.emoji.trim();
                    if (key.isEmpty) {
                      return;
                    }
                    widget.onSelected(key);
                  },
                  config: Config(
                    height: constraints.maxHeight,
                    locale: const Locale('zh', 'CN'),
                    checkPlatformCompatibility: false,
                    emojiSet: _buildEmojiSet,
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 30,
                      backgroundColor: Colors.transparent,
                      verticalSpacing: 8,
                      horizontalSpacing: 8,
                      gridPadding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      noRecents: const SizedBox.shrink(),
                      loadingIndicator: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      recentTabBehavior: RecentTabBehavior.NONE,
                      extraTab: CategoryExtraTab.NONE,
                      tabBarHeight: 56,
                      backgroundColor: Colors.transparent,
                      indicatorColor: colorScheme.primary,
                      iconColor: colorScheme.onSurfaceVariant,
                      iconColorSelected: colorScheme.primary,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                    searchViewConfig: const SearchViewConfig(hintText: '搜索表情'),
                  ),
                  customWidget: (config, state, showSearchBar) {
                    return _RiverEmojiPickerView(
                      config: config,
                      state: state,
                      categoryItems: _categories,
                      emojiUrls: widget.emojiUrls,
                      resolveUrl: widget.resolveUrl,
                      headersForUrl: widget.headersForUrl,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.58;
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _RiverEmojiPickerView extends StatefulWidget {
  const _RiverEmojiPickerView({
    required this.config,
    required this.state,
    required this.categoryItems,
    required this.emojiUrls,
    required this.resolveUrl,
    required this.headersForUrl,
  });

  final Config config;
  final EmojiViewState state;
  final List<_RiverPickerCategoryItem> categoryItems;
  final Map<String, String> emojiUrls;
  final String Function(String raw)? resolveUrl;
  final Map<String, String>? Function(String resolvedUrl)? headersForUrl;

  @override
  State<_RiverEmojiPickerView> createState() => _RiverEmojiPickerViewState();
}

class _RiverEmojiPickerViewState extends State<_RiverEmojiPickerView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final initialIndex = _resolveInitialIndex();
    _tabController = TabController(
      length: widget.categoryItems.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _pageController = PageController(initialPage: initialIndex);
    widget.state.categoryNavigationNotifier.addListener(_onCategoryNavigation);
  }

  @override
  void didUpdateWidget(covariant _RiverEmojiPickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryItems.length == widget.categoryItems.length) {
      return;
    }
    widget.state.categoryNavigationNotifier.removeListener(
      _onCategoryNavigation,
    );
    _tabController.dispose();
    _pageController.dispose();
    final initialIndex = _resolveInitialIndex();
    _tabController = TabController(
      length: widget.categoryItems.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _pageController = PageController(initialPage: initialIndex);
    widget.state.categoryNavigationNotifier.addListener(_onCategoryNavigation);
  }

  @override
  void dispose() {
    widget.state.categoryNavigationNotifier.removeListener(
      _onCategoryNavigation,
    );
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  int _resolveInitialIndex() {
    final targetCategory =
        widget.state.currentCategory ??
        widget.config.categoryViewConfig.initCategory;
    final index = widget.categoryItems.indexWhere(
      (item) => item.pickerCategory == targetCategory,
    );
    return index >= 0 ? index : 0;
  }

  void _onCategoryNavigation() {
    final targetCategory = widget.state.categoryNavigationNotifier.value;
    if (targetCategory == null) {
      return;
    }
    final index = widget.categoryItems.indexWhere(
      (item) => item.pickerCategory == targetCategory,
    );
    if (index < 0) {
      return;
    }
    if ((_pageController.page?.round() ?? _tabController.index) == index) {
      return;
    }
    _pageController.jumpToPage(index);
  }

  String _resolveUrl(String raw) {
    final resolver = widget.resolveUrl;
    return resolver == null ? raw : resolver(raw);
  }

  Widget _buildEmojiThumb({
    required String key,
    required double size,
    required Widget fallback,
  }) {
    final source = (widget.emojiUrls[key] ?? '').trim();
    if (source.isEmpty) {
      return fallback;
    }
    if (_isRiverAssetEmojiUrl(source)) {
      final assetPath = _riverAssetPathFromEmojiUrl(source);
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    final resolved = _resolveUrl(source);
    return CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: widget.headersForUrl?.call(resolved),
      width: size,
      height: size,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, imageUrl) => fallback,
      errorWidget: (context, imageUrl, error) => fallback,
    );
  }

  void _handlePageChanged(int index) {
    _tabController.animateTo(
      index,
      duration: widget.config.categoryViewConfig.tabIndicatorAnimDuration,
    );
    if (index >= 0 && index < widget.categoryItems.length) {
      widget.state.onCategoryChanged?.call(
        widget.categoryItems[index].pickerCategory,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.categoryItems.length,
            onPageChanged: _handlePageChanged,
            itemBuilder: (context, index) {
              final item = widget.categoryItems[index];
              return LayoutBuilder(
                builder: (context, constraints) {
                  final totalSpacing =
                      (widget.config.emojiViewConfig.columns - 1) *
                      widget.config.emojiViewConfig.horizontalSpacing;
                  final cellSize =
                      (constraints.maxWidth -
                          widget.config.emojiViewConfig.gridPadding.horizontal -
                          totalSpacing) /
                      widget.config.emojiViewConfig.columns;
                  return GridView.builder(
                    padding: widget.config.emojiViewConfig.gridPadding,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: widget.config.emojiViewConfig.columns,
                      mainAxisSpacing:
                          widget.config.emojiViewConfig.verticalSpacing,
                      crossAxisSpacing:
                          widget.config.emojiViewConfig.horizontalSpacing,
                      childAspectRatio: 1,
                    ),
                    itemCount: item.emojis.length,
                    itemBuilder: (context, emojiIndex) {
                      final emoji = item.emojis[emojiIndex];
                      return InkWell(
                        borderRadius: BorderRadius.circular(RiverRadius.lg),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.state.onEmojiSelected(
                            item.pickerCategory,
                            emoji,
                          );
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.76),
                            borderRadius: BorderRadius.circular(RiverRadius.lg),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.16,
                              ),
                            ),
                          ),
                          child: Center(
                            child: _buildEmojiThumb(
                              key: emoji.emoji,
                              size: cellSize * 0.62,
                              fallback: Icon(
                                Icons.broken_image_rounded,
                                size: 18,
                                color: colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(RiverRadius.lg),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 3),
              indicator: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(RiverRadius.lg),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              tabs: [
                for (final item in widget.categoryItems)
                  Tooltip(
                    message: item.title,
                    child: SizedBox(
                      width: 42,
                      child: Tab(
                        child: _buildEmojiThumb(
                          key: item.coverKey,
                          size: 22,
                          fallback: Icon(
                            Icons.tag_faces_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              onTap: (index) {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/features/compose/compose_topic_page.dart';
import 'package:river/features/mine/mine_page.dart';
import 'package:river/features/notifications/notifications_page.dart';
import 'package:river/features/posts/posts_page.dart';
import 'package:river/features/search/search_page.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  static const Duration _postsTabDoubleTapWindow = Duration(milliseconds: 320);
  static const int _nativeSearchTabIndex = 4;

  int _selectedTabIndex = 0;
  int _notificationsUnreadCount = 0;
  double _postsSecondFloorProgress = 0;
  DateTime? _lastPostsTabTapAt;
  final PostsPageController _postsPageController = PostsPageController();
  final SearchPageController _searchPageController = SearchPageController();
  bool _nativeSearchTabBarEnabled = false;
  bool _nativeSearchTabBarSyncing = false;

  late final PostsPage _postsPage = PostsPage(
    dependencies: widget.dependencies,
    controller: _postsPageController,
    onSecondFloorVisibilityChanged: _onPostsSecondFloorVisibilityChanged,
    onSecondFloorProgressChanged: _onPostsSecondFloorProgressChanged,
  );
  late final NotificationsPage _notificationsPage = NotificationsPage(
    dependencies: widget.dependencies,
    onUnreadCountChanged: _onUnreadCountChanged,
  );
  late final SearchPage _searchPage = SearchPage(
    dependencies: widget.dependencies,
    initialMode: SearchPageInitialMode.posts,
    showEntryActionIcon: false,
    controller: _searchPageController,
  );
  late final MinePage _minePage = MinePage(dependencies: widget.dependencies);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_syncNativeSearchTabBarMode());
    });
  }

  Future<void> _syncNativeSearchTabBarMode() async {
    if (_nativeSearchTabBarSyncing) {
      return;
    }
    _nativeSearchTabBarSyncing = true;
    try {
      final shouldEnable = _shouldUseExperimentalNativeSearchTabBar(context);
      final theme = Theme.of(context);
      final tint = _colorToArgb(theme.colorScheme.primary);
      final unselectedItemTint = _colorToArgb(
        theme.colorScheme.onSurfaceVariant,
      );
      if (shouldEnable && !_nativeSearchTabBarEnabled) {
        await IOS26NativeSearchTabBar.enable(
          tabs: <NativeTabConfig>[
            NativeTabConfig(
              title: '帖子',
              sfSymbol: 'bubble.left.and.bubble.right',
            ),
            NativeTabConfig(title: '发帖', sfSymbol: 'square.and.pencil'),
            NativeTabConfig(
              title: '通知',
              sfSymbol: 'bell',
              badgeCount: _notificationsUnreadCount > 99
                  ? 99
                  : _notificationsUnreadCount,
            ),
            NativeTabConfig(title: '我的', sfSymbol: 'person'),
            NativeTabConfig(
              title: '搜索',
              sfSymbol: 'magnifyingglass',
              isSearchTab: true,
            ),
          ],
          selectedIndex: _selectedTabIndex.clamp(0, _nativeSearchTabIndex),
          tint: tint,
          unselectedItemTint: unselectedItemTint,
          onTabSelected: _onNativeSearchTabSelected,
          onSearchQueryChanged:
              _searchPageController.onNativeSearchQueryChanged,
          onSearchSubmitted: (query) {
            unawaited(_searchPageController.onNativeSearchSubmitted(query));
          },
          onSearchCancelled: _searchPageController.onNativeSearchCancelled,
        );
        _nativeSearchTabBarEnabled = true;
        return;
      }
      if (shouldEnable && _nativeSearchTabBarEnabled) {
        await IOS26NativeSearchTabBar.setStyle(
          tint: tint,
          unselectedItemTint: unselectedItemTint,
        );
        await IOS26NativeSearchTabBar.setBadgeCounts(<int?>[
          null,
          null,
          _notificationsUnreadCount > 0
              ? (_notificationsUnreadCount > 99
                    ? 99
                    : _notificationsUnreadCount)
              : null,
          null,
          null,
        ]);
        await IOS26NativeSearchTabBar.setSelectedIndex(
          _selectedTabIndex.clamp(0, _nativeSearchTabIndex),
        );
        return;
      }
      if (!shouldEnable && _nativeSearchTabBarEnabled) {
        await IOS26NativeSearchTabBar.disable();
        _nativeSearchTabBarEnabled = false;
      }
    } catch (error) {
      debugPrint('[HomeShell] native search tab bar switch failed: $error');
    } finally {
      _nativeSearchTabBarSyncing = false;
    }
  }

  void _onNativeSearchTabSelected(int index) {
    if (!mounted) {
      return;
    }
    if (index < 0 || index > _nativeSearchTabIndex) {
      return;
    }
    _handleDestinationSelected(index, triggerHaptic: false);
  }

  void _onUnreadCountChanged(int value) {
    if (!mounted || value == _notificationsUnreadCount) {
      return;
    }
    setState(() {
      _notificationsUnreadCount = value;
    });
    if (_nativeSearchTabBarEnabled) {
      unawaited(
        IOS26NativeSearchTabBar.setBadgeCounts(<int?>[
          null,
          null,
          value > 0 ? (value > 99 ? 99 : value) : null,
          null,
          null,
        ]),
      );
    }
  }

  void _onPostsSecondFloorVisibilityChanged(bool visible) {
    if (!mounted) {
      return;
    }
    if (!visible && _postsSecondFloorProgress != 0) {
      setState(() {
        _postsSecondFloorProgress = 0;
      });
    }
  }

  void _onPostsSecondFloorProgressChanged(double progress) {
    final next = progress.clamp(0.0, 1.0);
    if (!mounted || (_postsSecondFloorProgress - next).abs() < 0.001) {
      return;
    }
    setState(() {
      _postsSecondFloorProgress = next;
    });
  }

  void _handleDestinationSelected(int index, {bool triggerHaptic = true}) {
    if (triggerHaptic) {
      HapticFeedback.selectionClick();
    }
    if (index == 0) {
      if (_selectedTabIndex == 0) {
        final now = DateTime.now();
        final lastTapAt = _lastPostsTabTapAt;
        if (lastTapAt != null &&
            now.difference(lastTapAt) <= _postsTabDoubleTapWindow) {
          _lastPostsTabTapAt = null;
          unawaited(_postsPageController.scrollToTopAndRefresh());
          return;
        }
        _lastPostsTabTapAt = now;
        return;
      }
      _lastPostsTabTapAt = DateTime.now();
    } else {
      _lastPostsTabTapAt = null;
    }

    if (index == _selectedTabIndex) {
      return;
    }
    setState(() {
      _selectedTabIndex = index;
    });
    if (_nativeSearchTabBarEnabled) {
      unawaited(IOS26NativeSearchTabBar.setSelectedIndex(index));
    }
  }

  void _onMaterialDestinationSelected(int index) {
    _handleDestinationSelected(index);
  }

  void _onIPhoneDestinationSelected(int index) {
    _handleDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final isIPhone = _isIPhoneDevice(context);
    final pages = _buildPages(isIPhone: isIPhone);
    final safeSelectedTabIndex = _selectedTabIndex.clamp(0, pages.length - 1);
    final secondFloorProgress = safeSelectedTabIndex == 0
        ? _postsSecondFloorProgress
        : 0.0;

    if (isIPhone) {
      if (_shouldUseExperimentalNativeSearchTabBar(context)) {
        return Scaffold(
          body: IndexedStack(index: safeSelectedTabIndex, children: pages),
        );
      }
      return _buildIPhoneShell(
        context: context,
        pages: pages,
        selectedIndex: safeSelectedTabIndex,
        secondFloorProgress: secondFloorProgress,
      );
    }

    final bottomOpacity = (1 - secondFloorProgress).clamp(0.0, 1.0);
    final bottomSizeFactor = (1 - secondFloorProgress).clamp(0.0, 1.0);
    return Scaffold(
      body: IndexedStack(index: safeSelectedTabIndex, children: pages),
      bottomNavigationBar: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: bottomSizeFactor,
          child: Opacity(
            opacity: bottomOpacity,
            child: IgnorePointer(
              ignoring: secondFloorProgress > 0.001,
              child: _buildMaterialTabBar(),
            ),
          ),
        ),
      ),
    );
  }

  bool _isIPhoneDevice(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    return MediaQuery.sizeOf(context).shortestSide < 600;
  }

  bool _shouldUseExperimentalNativeSearchTabBar(BuildContext context) {
    if (!_isIPhoneDevice(context)) {
      return false;
    }
    return PlatformInfo.isIOS26OrHigher();
  }

  int _colorToArgb(Color color) {
    return ((color.a * 255).round() & 0xff) << 24 |
        ((color.r * 255).round() & 0xff) << 16 |
        ((color.g * 255).round() & 0xff) << 8 |
        ((color.b * 255).round() & 0xff);
  }

  List<Widget> _buildPages({required bool isIPhone}) {
    final hasSearchDestination = isIPhone && PlatformInfo.isIOS26OrHigher();
    final composeBottomInset = hasSearchDestination ? 78.0 : 0.0;
    return <Widget>[
      _postsPage,
      ComposeTopicPage(
        dependencies: widget.dependencies,
        bottomToolbarExtraInset: composeBottomInset,
      ),
      _notificationsPage,
      _minePage,
      if (hasSearchDestination) _searchPage,
    ];
  }

  Widget _buildIPhoneShell({
    required BuildContext context,
    required List<Widget> pages,
    required int selectedIndex,
    required double secondFloorProgress,
  }) {
    final bottomOpacity = (1 - secondFloorProgress).clamp(0.0, 1.0);
    final bottomSizeFactor = (1 - secondFloorProgress).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IndexedStack(index: selectedIndex, children: pages),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: bottomSizeFactor,
                child: Opacity(
                  opacity: bottomOpacity,
                  child: IgnorePointer(
                    ignoring: secondFloorProgress > 0.001,
                    child: _buildIPhoneTabBar(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AdaptiveNavigationDestination> _iPhoneDestinations({
    required bool hasSearchDestination,
  }) {
    return <AdaptiveNavigationDestination>[
      const AdaptiveNavigationDestination(
        icon: 'bubble.left.and.bubble.right',
        selectedIcon: 'bubble.left.and.bubble.right.fill',
        label: '\u5e16\u5b50',
      ),
      const AdaptiveNavigationDestination(
        icon: 'square.and.pencil',
        selectedIcon: 'square.and.pencil',
        label: '\u53d1\u5e16',
      ),
      AdaptiveNavigationDestination(
        icon: 'bell',
        selectedIcon: 'bell.fill',
        label: '\u901a\u77e5',
        badgeCount: _notificationsUnreadCount > 99
            ? 99
            : _notificationsUnreadCount,
      ),
      const AdaptiveNavigationDestination(
        icon: 'person',
        selectedIcon: 'person.fill',
        label: '\u6211\u7684',
      ),
      if (hasSearchDestination)
        const AdaptiveNavigationDestination(
          icon: 'magnifyingglass',
          selectedIcon: 'magnifyingglass',
          label: '\u641c\u7d22',
          isSearch: true,
        ),
    ];
  }

  Widget _buildIPhoneTabBar(BuildContext context) {
    final hasSearchDestination = PlatformInfo.isIOS26OrHigher();
    final destinations = _iPhoneDestinations(
      hasSearchDestination: hasSearchDestination,
    );
    final selectedDestinationIndex = _selectedTabIndex.clamp(
      0,
      destinations.length - 1,
    );

    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26NativeTabBar(
        destinations: destinations,
        selectedIndex: selectedDestinationIndex,
        onTap: _onIPhoneDestinationSelected,
        tint: CupertinoTheme.of(context).primaryColor,
        minimizeBehavior: TabBarMinimizeBehavior.automatic,
      );
    }

    return CupertinoTabBar(
      currentIndex: selectedDestinationIndex,
      onTap: _onIPhoneDestinationSelected,
      items: destinations
          .map((destination) {
            final icon = destination.icon is String
                ? CupertinoIcons.circle
                : destination.icon as IconData;
            final selectedIcon = destination.selectedIcon is String
                ? CupertinoIcons.circle_fill
                : destination.selectedIcon as IconData?;
            return BottomNavigationBarItem(
              icon: Icon(icon),
              activeIcon: Icon(selectedIcon ?? icon),
              label: destination.label,
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildMaterialTabBar() {
    final currentIndex = _selectedTabIndex.clamp(0, 3);
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: _onMaterialDestinationSelected,
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: currentIndex == 0,
            outlinedIcon: Icons.forum_outlined,
            filledIcon: Icons.forum,
            motionStyle: _NavIconMotionStyle.posts,
          ),
          label: '\u5e16\u5b50',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: currentIndex == 1,
            outlinedIcon: Icons.edit_note_outlined,
            filledIcon: Icons.edit_note,
            motionStyle: _NavIconMotionStyle.compose,
          ),
          label: '\u53d1\u5e16',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: currentIndex == 2,
            outlinedIcon: Icons.notifications_none_outlined,
            filledIcon: Icons.notifications,
            badgeCount: _notificationsUnreadCount,
            motionStyle: _NavIconMotionStyle.notifications,
          ),
          label: '\u901a\u77e5',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: currentIndex == 3,
            outlinedIcon: Icons.person_outline,
            filledIcon: Icons.person,
            motionStyle: _NavIconMotionStyle.mine,
          ),
          label: '\u6211\u7684',
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_nativeSearchTabBarEnabled) {
      unawaited(IOS26NativeSearchTabBar.disable());
      _nativeSearchTabBarEnabled = false;
    }
    super.dispose();
  }
}

enum _NavIconMotionStyle { posts, compose, notifications, mine }

class _AnimatedBottomNavIcon extends StatefulWidget {
  const _AnimatedBottomNavIcon({
    required this.selected,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.motionStyle,
    this.badgeCount = 0,
  });

  final bool selected;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final _NavIconMotionStyle motionStyle;
  final int badgeCount;

  @override
  State<_AnimatedBottomNavIcon> createState() => _AnimatedBottomNavIconState();
}

class _AnimatedBottomNavIconState extends State<_AnimatedBottomNavIcon>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void didUpdateWidget(covariant _AnimatedBottomNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _controller
        ..stop()
        ..reset()
        ..forward();
      return;
    }
    if (oldWidget.selected && !widget.selected) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = widget.selected
            ? (_controller.isAnimating
                  ? Curves.easeOutCubic.transform(_controller.value)
                  : 1.0)
            : 0.0;
        final motion = _motionForStyle(widget.motionStyle, p);

        final outlineOpacity = widget.selected ? (1 - p) : 1.0;
        final filledOpacity = widget.selected ? p : 0.0;
        final outlineScale = widget.selected ? (1 - 0.12 * p) : 1.0;
        final filledScale = widget.selected
            ? (0.72 + 0.28 * Curves.easeOutBack.transform(p))
            : 0.78;
        final filledRotate = widget.selected ? motion.iconRotate : 0.0;

        Widget icon = Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: outlineOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: outlineScale,
                child: Icon(widget.outlinedIcon),
              ),
            ),
            Opacity(
              opacity: filledOpacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: filledRotate,
                child: Transform.scale(
                  scale: filledScale,
                  child: Icon(widget.filledIcon),
                ),
              ),
            ),
          ],
        );

        if (widget.badgeCount > 0) {
          icon = Badge.count(
            count: widget.badgeCount > 99 ? 99 : widget.badgeCount,
            child: icon,
          );
        }

        return Transform.translate(
          offset: Offset(motion.offsetX, motion.offsetY),
          child: Transform.scale(
            scale: widget.selected ? motion.scale : 1,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [icon],
            ),
          ),
        );
      },
    );
  }

  _NavMotionMetrics _motionForStyle(_NavIconMotionStyle style, double p) {
    switch (style) {
      case _NavIconMotionStyle.posts:
        return _NavMotionMetrics(
          offsetX: -2.6 * (1 - p),
          offsetY: 2.2 * (1 - p) - 1.7 * math.sin(math.pi * p),
          scale: 1 + 0.07 * math.sin(math.pi * p),
          iconRotate: -0.12 * (1 - p),
        );
      case _NavIconMotionStyle.compose:
        return _NavMotionMetrics(
          offsetX: 2.2 * (1 - p),
          offsetY: 3.6 * (1 - p) - 2.5 * math.sin(math.pi * p),
          scale: 1 + 0.12 * math.sin(math.pi * p),
          iconRotate:
              -0.3 * (1 - p) + 0.08 * math.sin(math.pi * 2.2 * p) * (1 - p),
        );
      case _NavIconMotionStyle.notifications:
        return _NavMotionMetrics(
          offsetX: 0.0,
          offsetY: -0.8 * math.sin(math.pi * p),
          scale: 1 + 0.06 * math.sin(math.pi * p),
          iconRotate: math.sin(math.pi * 6 * p) * 0.2 * (1 - p),
        );
      case _NavIconMotionStyle.mine:
        return _NavMotionMetrics(
          offsetX: 0.0,
          offsetY: 1.4 * (1 - p) - 0.9 * math.sin(math.pi * p),
          scale: 1 + 0.05 * math.sin(math.pi * 0.92 * p),
          iconRotate: -0.06 * (1 - p),
        );
    }
  }
}

class _NavMotionMetrics {
  const _NavMotionMetrics({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.iconRotate,
  });

  final double offsetX;
  final double offsetY;
  final double scale;
  final double iconRotate;
}

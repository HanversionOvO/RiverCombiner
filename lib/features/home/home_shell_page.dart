import 'dart:async';
import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/features/compose/compose_topic_page.dart';
import 'package:river/features/mine/mine_page.dart';
import 'package:river/features/notifications/notifications_page.dart';
import 'package:river/features/posts/posts_page.dart';
import 'package:river/features/search/search_page.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';

enum HomeQuickAction { compose, search, latestCreated, latestReplied, hot }

class HomeShellController {
  _HomeShellPageState? _state;
  HomeQuickAction? _pendingAction;

  void _attach(_HomeShellPageState state) {
    _state = state;
    final pending = _pendingAction;
    _pendingAction = null;
    if (pending != null) {
      unawaited(state._performQuickAction(pending));
    }
  }

  void _detach(_HomeShellPageState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void performQuickAction(HomeQuickAction action) {
    final state = _state;
    if (state == null) {
      _pendingAction = action;
      return;
    }
    unawaited(state._performQuickAction(action));
  }
}

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key, required this.dependencies, this.controller});

  final AppDependencies dependencies;
  final HomeShellController? controller;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  static const Duration _postsTabDoubleTapWindow = Duration(milliseconds: 320);
  static const int _iPhoneSearchDestinationIndex = 1;

  int _selectedTabIndex = 0;
  int _notificationsUnreadCount = 0;
  double _postsSecondFloorProgress = 0;
  DateTime? _lastPostsTabTapAt;
  AccountProvider _notificationsForumProvider = AccountProvider.riverSide;
  final PostsPageController _postsPageController = PostsPageController();

  late final PostsPage _postsPage = PostsPage(
    dependencies: widget.dependencies,
    controller: _postsPageController,
    onForumProviderChanged: _onPostsForumProviderChanged,
    onSecondFloorVisibilityChanged: _onPostsSecondFloorVisibilityChanged,
    onSecondFloorProgressChanged: _onPostsSecondFloorProgressChanged,
  );
  late final MinePage _minePage = MinePage(dependencies: widget.dependencies);

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant HomeShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller?._detach(this);
    widget.controller?._attach(this);
  }

  void _onUnreadCountChanged(int value) {
    if (!mounted || value == _notificationsUnreadCount) {
      return;
    }
    setState(() {
      _notificationsUnreadCount = value;
    });
  }

  void _onPostsForumProviderChanged(AccountProvider provider) {
    if (!mounted || _notificationsForumProvider == provider) {
      return;
    }
    setState(() {
      _notificationsForumProvider = provider;
    });
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
    _handleDestinationSelectedInternal(
      index,
      triggerHaptic: triggerHaptic,
      hasIPhoneSearchDestination: false,
    );
  }

  Future<void> _openSearchPageFromBottomTab() async {
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => SearchPage(
          dependencies: widget.dependencies,
          initialMode: SearchPageInitialMode.posts,
          showEntryActionIcon: false,
        ),
      ),
    );
  }

  int _toAppTabIndex(
    int destinationIndex, {
    required bool hasIPhoneSearchDestination,
  }) {
    if (!hasIPhoneSearchDestination) {
      return destinationIndex;
    }
    if (destinationIndex > _iPhoneSearchDestinationIndex) {
      return destinationIndex - 1;
    }
    return destinationIndex;
  }

  int _toDestinationIndex(
    int appTabIndex, {
    required bool hasIPhoneSearchDestination,
  }) {
    if (!hasIPhoneSearchDestination) {
      return appTabIndex;
    }
    if (appTabIndex >= _iPhoneSearchDestinationIndex) {
      return appTabIndex + 1;
    }
    return appTabIndex;
  }

  void _handleDestinationSelectedInternal(
    int rawIndex, {
    required bool hasIPhoneSearchDestination,
    bool triggerHaptic = true,
  }) {
    if (triggerHaptic) {
      HapticFeedback.selectionClick();
    }
    if (hasIPhoneSearchDestination &&
        rawIndex == _iPhoneSearchDestinationIndex) {
      unawaited(_openSearchPageFromBottomTab());
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final index = _toAppTabIndex(
      rawIndex,
      hasIPhoneSearchDestination: hasIPhoneSearchDestination,
    );

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
  }

  void _onMaterialDestinationSelected(int index) {
    _handleDestinationSelectedInternal(
      index,
      hasIPhoneSearchDestination: false,
    );
  }

  void _onIPhoneDestinationSelected(int index) {
    _handleDestinationSelectedInternal(
      index,
      hasIPhoneSearchDestination: PlatformInfo.isIOS26OrHigher(),
    );
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
      extendBody: true,
      body: _buildMaterialBodyWithSoftEdgeBlur(
        secondFloorProgress: secondFloorProgress,
        child: IndexedStack(index: safeSelectedTabIndex, children: pages),
      ),
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

  List<Widget> _buildPages({required bool isIPhone}) {
    final composeBottomInset = isIPhone && PlatformInfo.isIOS26OrHigher()
        ? 78.0
        : 0.0;
    return <Widget>[
      _postsPage,
      ComposeTopicPage(
        dependencies: widget.dependencies,
        bottomToolbarExtraInset: composeBottomInset,
      ),
      NotificationsPage(
        dependencies: widget.dependencies,
        forumProvider: _notificationsForumProvider,
        onUnreadCountChanged: _onUnreadCountChanged,
      ),
      _minePage,
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
      if (hasSearchDestination)
        const AdaptiveNavigationDestination(
          icon: 'magnifyingglass',
          selectedIcon: 'magnifyingglass',
          label: '\u641c\u7d22',
          isSearch: true,
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
    ];
  }

  Widget _buildIPhoneTabBar(BuildContext context) {
    final hasSearchDestination = PlatformInfo.isIOS26OrHigher();
    final destinations = _iPhoneDestinations(
      hasSearchDestination: hasSearchDestination,
    );
    final selectedDestinationIndex = _toDestinationIndex(
      _selectedTabIndex,
      hasIPhoneSearchDestination: hasSearchDestination,
    ).clamp(0, destinations.length - 1);

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
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
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

  Widget _buildMaterialBodyWithSoftEdgeBlur({
    required Widget child,
    required double secondFloorProgress,
  }) {
    final visibility = (1 - secondFloorProgress).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final navHeight = theme.navigationBarTheme.height ?? 80;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tintBandHeight = navHeight + bottomInset + 42;
    return SoftEdgeBlur(
      edges: <EdgeBlur>[
        EdgeBlur(
          type: EdgeType.bottomEdge,
          size: 130 * visibility,
          sigma: 30 * visibility,
          tintColor: scaffoldColor.withValues(alpha: 0.8 * visibility),
          controlPoints: <ControlPoint>[
            ControlPoint(position: 0.4, type: ControlPointType.visible),
            ControlPoint(position: 1, type: ControlPointType.transparent),
          ],
        ),
      ],
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: child),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: tintBandHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const <double>[0, 0.55, 1],
                    colors: <Color>[
                      scaffoldColor.withValues(alpha: 0),
                      scaffoldColor.withValues(alpha: 0.64 * visibility),
                      scaffoldColor.withValues(alpha: 0.96 * visibility),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> _performQuickAction(HomeQuickAction action) async {
    switch (action) {
      case HomeQuickAction.compose:
        _handleDestinationSelected(1, triggerHaptic: false);
        return;
      case HomeQuickAction.search:
        _handleDestinationSelected(0, triggerHaptic: false);
        await _openSearchPageFromBottomTab();
        return;
      case HomeQuickAction.latestCreated:
        _handleDestinationSelected(0, triggerHaptic: false);
        await _postsPageController.openFeed(RiverSideTopicFeed.latestCreated);
        return;
      case HomeQuickAction.latestReplied:
        _handleDestinationSelected(0, triggerHaptic: false);
        await _postsPageController.openFeed(RiverSideTopicFeed.latestReplied);
        return;
      case HomeQuickAction.hot:
        _handleDestinationSelected(0, triggerHaptic: false);
        await _postsPageController.openFeed(RiverSideTopicFeed.hot);
        return;
    }
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

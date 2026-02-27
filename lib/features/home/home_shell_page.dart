import 'dart:async';
import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/features/compose/compose_topic_page.dart';
import 'package:river/features/mine/mine_page.dart';
import 'package:river/features/notifications/notifications_page.dart';
import 'package:river/features/posts/posts_page.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  static const Duration _postsTabDoubleTapWindow = Duration(milliseconds: 320);

  int _selectedTabIndex = 0;
  int _notificationsUnreadCount = 0;
  double _postsSecondFloorProgress = 0;
  DateTime? _lastPostsTabTapAt;
  final PostsPageController _postsPageController = PostsPageController();

  late final List<Widget> _pages = <Widget>[
    PostsPage(
      dependencies: widget.dependencies,
      controller: _postsPageController,
      onSecondFloorVisibilityChanged: _onPostsSecondFloorVisibilityChanged,
      onSecondFloorProgressChanged: _onPostsSecondFloorProgressChanged,
    ),
    ComposeTopicPage(dependencies: widget.dependencies),
    NotificationsPage(
      dependencies: widget.dependencies,
      onUnreadCountChanged: _onUnreadCountChanged,
    ),
    MinePage(dependencies: widget.dependencies),
  ];

  void _onUnreadCountChanged(int value) {
    if (!mounted || value == _notificationsUnreadCount) {
      return;
    }
    setState(() {
      _notificationsUnreadCount = value;
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

  void _onDestinationSelected(int index) {
    HapticFeedback.selectionClick();
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

  @override
  Widget build(BuildContext context) {
    final isIPhone = _isIPhoneDevice(context);
    final secondFloorProgress = _selectedTabIndex == 0
        ? _postsSecondFloorProgress
        : 0.0;

    if (isIPhone) {
      return _buildIPhoneAdaptiveScaffold(context, secondFloorProgress);
    }

    final bottomOpacity = (1 - secondFloorProgress).clamp(0.0, 1.0);
    final bottomSizeFactor = (1 - secondFloorProgress).clamp(0.0, 1.0);
    return Scaffold(
      body: IndexedStack(index: _selectedTabIndex, children: _pages),
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

  Widget _buildIPhoneAdaptiveScaffold(
    BuildContext context,
    double secondFloorProgress,
  ) {
    final shouldHideBottomBar = secondFloorProgress > 0.001;

    return AdaptiveScaffold(
      enableBlur: true,
      minimizeBehavior: TabBarMinimizeBehavior.automatic,
      body: IndexedStack(
        index: _selectedTabIndex,
        children: <Widget>[
          _pages[0],
          _buildIPhoneComposePage(_pages[1], context),
          _pages[2],
          _pages[3],
        ],
      ),
      bottomNavigationBar: shouldHideBottomBar ? null : _buildIPhoneTabBar(),
    );
  }

  Widget _buildIPhoneComposePage(Widget page, BuildContext context) {
    final shouldReserveBottomSpace = PlatformInfo.isIOS26OrHigher();
    if (!shouldReserveBottomSpace) {
      return page;
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: _iPhoneNativeTabBarReservedHeight(context),
      ),
      child: page,
    );
  }

  double _iPhoneNativeTabBarReservedHeight(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return bottomInset + 56;
  }

  AdaptiveBottomNavigationBar _buildIPhoneTabBar() {
    return AdaptiveBottomNavigationBar(
      useNativeBottomBar: true,
      selectedIndex: _selectedTabIndex,
      onTap: _onDestinationSelected,
      items: <AdaptiveNavigationDestination>[
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
      ],
    );
  }

  Widget _buildMaterialTabBar() {
    return NavigationBar(
      selectedIndex: _selectedTabIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: _selectedTabIndex == 0,
            outlinedIcon: Icons.forum_outlined,
            filledIcon: Icons.forum,
            motionStyle: _NavIconMotionStyle.posts,
          ),
          label: '\u5e16\u5b50',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: _selectedTabIndex == 1,
            outlinedIcon: Icons.edit_note_outlined,
            filledIcon: Icons.edit_note,
            motionStyle: _NavIconMotionStyle.compose,
          ),
          label: '\u53d1\u5e16',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: _selectedTabIndex == 2,
            outlinedIcon: Icons.notifications_none_outlined,
            filledIcon: Icons.notifications,
            badgeCount: _notificationsUnreadCount,
            motionStyle: _NavIconMotionStyle.notifications,
          ),
          label: '\u901a\u77e5',
        ),
        NavigationDestination(
          icon: _AnimatedBottomNavIcon(
            selected: _selectedTabIndex == 3,
            outlinedIcon: Icons.person_outline,
            filledIcon: Icons.person,
            motionStyle: _NavIconMotionStyle.mine,
          ),
          label: '\u6211\u7684',
        ),
      ],
    );
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

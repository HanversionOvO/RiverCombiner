import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
// ignore: implementation_imports
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_native_toolbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MineSettingsToolbarAction {
  const MineSettingsToolbarAction({
    this.iosSymbol,
    this.icon,
    this.title,
    required this.onPressed,
    this.tooltip,
    this.spacerAfter = ToolbarSpacerType.none,
  }) : assert(
         iosSymbol != null || icon != null || title != null,
         'At least one of iosSymbol, icon, or title must be provided.',
       );

  final String? iosSymbol;
  final IconData? icon;
  final String? title;
  final VoidCallback? onPressed;
  final String? tooltip;
  final ToolbarSpacerType spacerAfter;

  AdaptiveAppBarAction toAdaptiveAction() {
    return AdaptiveAppBarAction(
      iosSymbol: iosSymbol,
      icon: icon,
      title: title,
      onPressed: onPressed ?? () {},
      spacerAfter: spacerAfter,
    );
  }

  Widget toMaterialAction(BuildContext context) {
    if (title != null && title!.isNotEmpty) {
      return TextButton(onPressed: onPressed, child: Text(title!));
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.more_horiz_rounded),
    );
  }
}

class MineSettingsPageScaffold extends StatelessWidget {
  const MineSettingsPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.heroTagPrefix,
    this.actions,
    this.backgroundColor,
    this.wrapBodyWithSafeArea = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget body;
  final String? heroTagPrefix;
  final List<MineSettingsToolbarAction>? actions;
  final Color? backgroundColor;
  final bool wrapBodyWithSafeArea;

  @override
  Widget build(BuildContext context) {
    final resolvedActions = actions ?? const <MineSettingsToolbarAction>[];
    final adaptiveActions = resolvedActions
        .where((action) => action.onPressed != null)
        .map((action) => action.toAdaptiveAction())
        .toList(growable: false);
    Widget resolvedBody = body;
    if (wrapBodyWithSafeArea) {
      resolvedBody = SafeArea(top: false, child: resolvedBody);
    }
    if (backgroundColor != null) {
      resolvedBody = ColoredBox(color: backgroundColor!, child: resolvedBody);
    }

    if (_isIPhoneDevice(context)) {
      final topToolbarPlaceholder = MediaQuery.paddingOf(context).top + 44;
      return AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: title,
          useNativeToolbar: true,
          actions: adaptiveActions,
        ),
        body: _wrapIOSBodyWithTopPlaceholder(
          resolvedBody,
          topToolbarPlaceholder,
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: MineSettingsAppBar(
        title: title,
        subtitle: subtitle,
        icon: icon,
        heroTagPrefix: heroTagPrefix,
        actions: resolvedActions
            .map((action) => action.toMaterialAction(context))
            .toList(growable: false),
      ),
      body: resolvedBody,
    );
  }

  Widget _wrapIOSBodyWithTopPlaceholder(Widget body, double placeholderHeight) {
    final topPlaceholder = SizedBox(height: placeholderHeight);
    if (body is ListView && body.childrenDelegate is SliverChildListDelegate) {
      final delegate = body.childrenDelegate as SliverChildListDelegate;
      return ListView(
        key: body.key,
        scrollDirection: body.scrollDirection,
        reverse: body.reverse,
        controller: body.controller,
        primary: body.primary,
        physics: body.physics,
        shrinkWrap: body.shrinkWrap,
        padding: body.padding,
        itemExtent: body.itemExtent,
        prototypeItem: body.prototypeItem,
        cacheExtent: body.cacheExtent,
        semanticChildCount: body.semanticChildCount,
        dragStartBehavior: body.dragStartBehavior,
        keyboardDismissBehavior: body.keyboardDismissBehavior,
        restorationId: body.restorationId,
        clipBehavior: body.clipBehavior,
        hitTestBehavior: body.hitTestBehavior,
        children: <Widget>[topPlaceholder, ...delegate.children],
      );
    }

    if (body is CustomScrollView) {
      return CustomScrollView(
        key: body.key,
        scrollDirection: body.scrollDirection,
        reverse: body.reverse,
        controller: body.controller,
        primary: body.primary,
        physics: body.physics,
        shrinkWrap: body.shrinkWrap,
        center: body.center,
        anchor: body.anchor,
        cacheExtent: body.cacheExtent,
        semanticChildCount: body.semanticChildCount,
        dragStartBehavior: body.dragStartBehavior,
        keyboardDismissBehavior: body.keyboardDismissBehavior,
        restorationId: body.restorationId,
        clipBehavior: body.clipBehavior,
        hitTestBehavior: body.hitTestBehavior,
        slivers: <Widget>[
          SliverToBoxAdapter(child: topPlaceholder),
          ...body.slivers,
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: placeholderHeight),
      child: body,
    );
  }
}

class MineSettingsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MineSettingsAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.heroTagPrefix,
    this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? heroTagPrefix;
  final List<Widget>? actions;

  @override
  Size get preferredSize {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (!isIOS) {
      return const Size.fromHeight(74);
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return const Size.fromHeight(88);
    }
    final view = views.first;
    final topPadding = view.viewPadding.top / view.devicePixelRatio;
    return Size.fromHeight(topPadding + 44);
  }

  @override
  Widget build(BuildContext context) {
    if (_isIPhone(context)) {
      return _buildIPhoneNativeToolbar(context);
    }

    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 6,
      leadingWidth: 54,
      leading: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: _buildBackButton(context),
      ),
      title: Row(
        children: [
          _maybeHero(
            tag: _tag('icon'),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _maybeHero(
                  tag: _tag('title'),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
                _maybeHero(
                  tag: _tag('subtitle'),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
      flexibleSpace: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.95, end: 1.0),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.36 * value,
                  ),
                  theme.colorScheme.surface.withValues(alpha: 0.88),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.28,
                  ),
                ),
              ),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: child,
              ),
            ),
          );
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildIPhoneNativeToolbar(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        IOS26NativeToolbar(
          title: title,
          onLeadingTap: () => Navigator.of(context).maybePop(),
          height: 44,
        ),
        if (actions != null && actions!.isNotEmpty)
          Positioned(
            top: safeTop,
            right: 6,
            height: 44,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
          ),
      ],
    );
  }

  String? _tag(String suffix) {
    if (heroTagPrefix == null || heroTagPrefix!.isEmpty) {
      return null;
    }
    return '${heroTagPrefix!}__$suffix';
  }

  Widget _maybeHero({required String? tag, required Widget child}) {
    if (tag == null) {
      return child;
    }
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder:
          (_, animation, direction, fromHeroContext, toHeroContext) {
            final fromHero = fromHeroContext.widget as Hero;
            final toHero = toHeroContext.widget as Hero;
            final heroChild = direction == HeroFlightDirection.push
                ? toHero.child
                : fromHero.child;
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: heroChild,
              ),
            );
          },
      child: child,
    );
  }

  Widget _buildBackButton(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface.withValues(alpha: 0.90),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  bool _isIPhone(BuildContext context) {
    return _isIPhoneDevice(context);
  }
}

bool _isIPhoneDevice(BuildContext context) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }
  return MediaQuery.sizeOf(context).shortestSide < 600;
}

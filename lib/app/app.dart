import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/platform/app_icon_switcher.dart';
import 'package:river/core/platform/riverside_cookie_bridge.dart';
import 'package:river/core/update/app_update_checker.dart';
import 'package:river/features/home/home_shell_page.dart';
import 'package:river/features/login/login_page.dart';
import 'package:river/core/widgets/river_home_widget_service.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';

class RiverApp extends StatefulWidget {
  const RiverApp({super.key});

  @override
  State<RiverApp> createState() => _RiverAppState();
}

class _RiverAppState extends State<RiverApp> {
  static const String _shortcutCompose = 'river.quick.compose';
  static const String _shortcutSearch = 'river.quick.search';
  static const String _shortcutLatestCreated = 'river.quick.latest_created';
  static const String _shortcutLatestReplied = 'river.quick.latest_replied';

  late final AppDependencies _dependencies;
  late final RiverHomeWidgetService _homeWidgetService;
  final QuickActions _quickActions = const QuickActions();
  final HomeShellController _homeShellController = HomeShellController();
  final GlobalKey<NavigatorState> _appNavigatorKey =
      GlobalKey<NavigatorState>();
  final DateTime _launchStartedAt = DateTime.now();
  static const Duration _minLaunchDisplay = Duration(milliseconds: 1250);
  bool _initialized = false;
  bool _didAutoCheckUpdate = false;
  StreamSubscription<Uri?>? _homeWidgetClickSubscription;
  Timer? _homeWidgetSyncDebounceTimer;

  @override
  void initState() {
    super.initState();
    _dependencies = AppDependencies(
      settingsController: AppSettingsController(),
      accountStore: AccountStore(
        riverSideApiClient: RiverSideApiClient(),
        riverSideCookieBridge: RiverSideCookieBridge(),
      ),
      updateChecker: AppUpdateChecker(),
    );
    _homeWidgetService = RiverHomeWidgetService(
      apiClient: _dependencies.accountStore.riverSideApiClient,
      accountStore: _dependencies.accountStore,
      settingsController: _dependencies.settingsController,
    );
    _dependencies.accountStore.addListener(_scheduleHomeWidgetSync);
    _dependencies.settingsController.addListener(_scheduleHomeWidgetSync);

    _initializeQuickActions();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _dependencies.settingsController.initialize();
    unawaited(
      AppIconSwitcher.switchToPreset(
        _dependencies.settingsController.iconPreset,
      ),
    );
    if (mounted && !_initialized) {
      setState(() {});
    }
    await _dependencies.accountStore.initialize();
    _dependencies.postsStartupPreloadStore.start(
      accountStore: _dependencies.accountStore,
    );
    await _dependencies.updateChecker.initialize();
    final elapsed = DateTime.now().difference(_launchStartedAt);
    if (elapsed < _minLaunchDisplay) {
      await Future<void>.delayed(_minLaunchDisplay - elapsed);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _initialized = true;
    });
    unawaited(_initializeHomeWidgetBridge());
    _scheduleAutoUpdateCheck();
    unawaited(_dependencies.accountStore.syncActiveRiverSideCookieToWebView());
  }

  Future<void> _initializeQuickActions() async {
    try {
      _quickActions.initialize((type) {
        final action = _mapQuickAction(type);
        if (action == null) {
          return;
        }
        _homeShellController.performQuickAction(action);
      });
      await _quickActions.setShortcutItems(_buildQuickShortcutItems());
    } catch (error) {
      debugPrint('[QuickActions] initialize failed: $error');
    }
  }

  List<ShortcutItem> _buildQuickShortcutItems() {
    final composeIcon = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ic_shortcut_compose',
      TargetPlatform.iOS => 'quick_compose',
      _ => null,
    };
    final searchIcon = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ic_shortcut_search',
      TargetPlatform.iOS => 'quick_search',
      _ => null,
    };
    final latestCreatedIcon = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ic_shortcut_latest_created',
      TargetPlatform.iOS => 'quick_latest_created',
      _ => null,
    };
    final latestRepliedIcon = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ic_shortcut_latest_replied',
      TargetPlatform.iOS => 'quick_latest_replied',
      _ => null,
    };

    return <ShortcutItem>[
      ShortcutItem(
        type: _shortcutCompose,
        localizedTitle: '发个帖子',
        localizedSubtitle: '快速发布新内容',
        icon: composeIcon,
      ),
      ShortcutItem(
        type: _shortcutSearch,
        localizedTitle: '搜索',
        localizedSubtitle: '查找帖子和用户',
        icon: searchIcon,
      ),
      ShortcutItem(
        type: _shortcutLatestCreated,
        localizedTitle: '最新发表',
        localizedSubtitle: '查看新发布帖子',
        icon: latestCreatedIcon,
      ),
      ShortcutItem(
        type: _shortcutLatestReplied,
        localizedTitle: '最新回复',
        localizedSubtitle: '查看最新活跃回复',
        icon: latestRepliedIcon,
      ),
    ];
  }

  HomeQuickAction? _mapQuickAction(String? type) {
    switch (type) {
      case _shortcutCompose:
        return HomeQuickAction.compose;
      case _shortcutSearch:
        return HomeQuickAction.search;
      case _shortcutLatestCreated:
        return HomeQuickAction.latestCreated;
      case _shortcutLatestReplied:
        return HomeQuickAction.latestReplied;
      default:
        return null;
    }
  }

  void _scheduleHomeWidgetSync() {
    _homeWidgetSyncDebounceTimer?.cancel();
    _homeWidgetSyncDebounceTimer = Timer(const Duration(milliseconds: 680), () {
      unawaited(_homeWidgetService.syncLatestTopic());
    });
  }

  Future<void> _initializeHomeWidgetBridge() async {
    try {
      await _homeWidgetService.initialize();
      _homeWidgetClickSubscription?.cancel();
      _homeWidgetClickSubscription = HomeWidget.widgetClicked.listen(
        _handleHomeWidgetLaunchUri,
        onError: (Object error) {
          debugPrint('[HomeWidget] widgetClicked stream error: $error');
        },
      );
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      await _handleHomeWidgetLaunchUri(initialUri);
      await _homeWidgetService.syncLatestTopic();
    } catch (error) {
      debugPrint('[HomeWidget] initialize failed: $error');
    }
  }

  Future<void> _handleHomeWidgetLaunchUri(Uri? uri) async {
    final request = _homeWidgetService.parseLaunchUri(uri);
    if (request == null) {
      return;
    }
    switch (request.type) {
      case RiverHomeWidgetLaunchType.openApp:
        return;
      case RiverHomeWidgetLaunchType.openFeed:
        final feed = request.feed;
        if (feed == null) {
          return;
        }
        switch (feed) {
          case RiverSideTopicFeed.latestCreated:
            _homeShellController.performQuickAction(
              HomeQuickAction.latestCreated,
            );
            return;
          case RiverSideTopicFeed.latestReplied:
            _homeShellController.performQuickAction(
              HomeQuickAction.latestReplied,
            );
            return;
          case RiverSideTopicFeed.hot:
            _homeShellController.performQuickAction(HomeQuickAction.hot);
            return;
        }
      case RiverHomeWidgetLaunchType.openTopic:
        final topicId = request.topicId;
        final context = _appNavigatorKey.currentContext;
        if (topicId == null || topicId <= 0 || context == null) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        await Navigator.of(context).push(
          riverPageRoute<void>(
            builder: (_) =>
                TopicDetailPage(dependencies: _dependencies, topicId: topicId),
          ),
        );
        return;
    }
  }

  void _scheduleAutoUpdateCheck() {
    if (_didAutoCheckUpdate) {
      return;
    }
    _didAutoCheckUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final result = await _dependencies.updateChecker.checkForUpdates();
      if (!mounted || !result.hasUpdate) {
        return;
      }
      final dialogContext = _appNavigatorKey.currentContext;
      if (dialogContext == null) {
        return;
      }
      if (!dialogContext.mounted) {
        return;
      }
      await showRiverUpdateDialog(
        context: dialogContext,
        result: result,
        fromManualAction: false,
      );
    });
  }

  @override
  void dispose() {
    _homeWidgetClickSubscription?.cancel();
    _homeWidgetSyncDebounceTimer?.cancel();
    _dependencies.accountStore.removeListener(_scheduleHomeWidgetSync);
    _dependencies.settingsController.removeListener(_scheduleHomeWidgetSync);
    _dependencies.settingsController.dispose();
    _dependencies.accountStore.dispose();
    _dependencies.updateChecker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dependencies.settingsController,
      builder: (context, _) {
        final settings = _dependencies.settingsController;
        return MaterialApp(
          title: 'River Login',
          debugShowCheckedModeBanner: false,
          navigatorKey: _appNavigatorKey,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const <Locale>[
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: const _RiverScrollBehavior(),
          builder: (context, child) {
            final data = MediaQuery.of(context);
            final mediaQueryChild = MediaQuery(
              data: data.copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: _AppRootSnackbarHost(
                child: child ?? const SizedBox.shrink(),
              ),
            );
            if (defaultTargetPlatform != TargetPlatform.android) {
              return mediaQueryChild;
            }
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _androidOverlayStyleForBrightness(
                Theme.of(context).brightness,
              ),
              child: mediaQueryChild,
            );
          },
          theme: _buildTheme(brightness: Brightness.light),
          darkTheme: _buildTheme(brightness: Brightness.dark),
          themeMode: settings.themeMode,
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 1180),
            switchInCurve: Curves.linear,
            switchOutCurve: Curves.linear,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  ...(currentChild == null
                      ? const <Widget>[]
                      : <Widget>[currentChild]),
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final keyValue = child.key is ValueKey<String>
                  ? (child.key as ValueKey<String>).value
                  : '';
              final isStartup = keyValue == 'app_startup';
              if (isStartup) {
                return _StartupTunnelExitTransition(
                  animation: animation,
                  exiting: _initialized,
                  child: child,
                );
              }
              return _HomeTunnelEnterTransition(
                animation: animation,
                child: child,
              );
            },
            child: _initialized
                ? KeyedSubtree(
                    key: const ValueKey<String>('app_home_ready'),
                    child: _buildResolvedHome(),
                  )
                : _RiverStartupScreen(
                    key: ValueKey<String>('app_startup'),
                    iconPreset: settings.iconPreset,
                  ),
          ),
        );
      },
    );
  }

  SystemUiOverlayStyle _androidOverlayStyleForBrightness(
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  ThemeData _buildTheme({required Brightness brightness}) {
    final settings = _dependencies.settingsController;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: settings.themeSeedColor,
      brightness: brightness,
    );
    final cornerRadius = _cornerRadiusForPreset(settings.cornerPreset);
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: settings.compactDensity
          ? VisualDensity.compact
          : VisualDensity.standard,
      splashFactory: settings.reduceMotion
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      pageTransitionsTheme: settings.reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
              },
            )
          : null,
    );

    final textTheme = _applyFontWeightPreset(
      base.textTheme.apply(fontFamily: settings.fontFamilyName),
      settings.fontWeightPreset,
    );
    final primaryTextTheme = _applyFontWeightPreset(
      base.primaryTextTheme.apply(fontFamily: settings.fontFamilyName),
      settings.fontWeightPreset,
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
      ),
    );
  }

  double _cornerRadiusForPreset(AppCornerPreset preset) {
    switch (preset) {
      case AppCornerPreset.compact:
        return 10;
      case AppCornerPreset.standard:
        return 14;
      case AppCornerPreset.relaxed:
        return 20;
    }
  }

  TextTheme _applyFontWeightPreset(
    TextTheme theme,
    AppFontWeightPreset preset,
  ) {
    final delta = switch (preset) {
      AppFontWeightPreset.regular => -1,
      AppFontWeightPreset.medium => 0,
      AppFontWeightPreset.bold => 1,
    };
    if (delta == 0) {
      return theme;
    }
    return theme.copyWith(
      displayLarge: _shiftTextStyleWeight(theme.displayLarge, delta),
      displayMedium: _shiftTextStyleWeight(theme.displayMedium, delta),
      displaySmall: _shiftTextStyleWeight(theme.displaySmall, delta),
      headlineLarge: _shiftTextStyleWeight(theme.headlineLarge, delta),
      headlineMedium: _shiftTextStyleWeight(theme.headlineMedium, delta),
      headlineSmall: _shiftTextStyleWeight(theme.headlineSmall, delta),
      titleLarge: _shiftTextStyleWeight(theme.titleLarge, delta),
      titleMedium: _shiftTextStyleWeight(theme.titleMedium, delta),
      titleSmall: _shiftTextStyleWeight(theme.titleSmall, delta),
      bodyLarge: _shiftTextStyleWeight(theme.bodyLarge, delta),
      bodyMedium: _shiftTextStyleWeight(theme.bodyMedium, delta),
      bodySmall: _shiftTextStyleWeight(theme.bodySmall, delta),
      labelLarge: _shiftTextStyleWeight(theme.labelLarge, delta),
      labelMedium: _shiftTextStyleWeight(theme.labelMedium, delta),
      labelSmall: _shiftTextStyleWeight(theme.labelSmall, delta),
    );
  }

  TextStyle? _shiftTextStyleWeight(TextStyle? style, int delta) {
    if (style == null) {
      return null;
    }
    return style.copyWith(
      fontWeight: _shiftFontWeight(style.fontWeight ?? FontWeight.w400, delta),
    );
  }

  FontWeight _shiftFontWeight(FontWeight source, int delta) {
    const all = <FontWeight>[
      FontWeight.w100,
      FontWeight.w200,
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ];
    var index = all.indexOf(source);
    if (index < 0) {
      index = 3;
    }
    final next = (index + delta).clamp(0, all.length - 1);
    return all[next];
  }

  Widget _buildResolvedHome() {
    if (_dependencies.accountStore.hasAnyAccount ||
        _dependencies.accountStore.isGuestBrowsing) {
      return HomeShellPage(
        dependencies: _dependencies,
        controller: _homeShellController,
      );
    }

    return LoginPage(dependencies: _dependencies);
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class _RiverScrollBehavior extends MaterialScrollBehavior {
  const _RiverScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _AppRootSnackbarHost extends StatelessWidget {
  const _AppRootSnackbarHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: child);
  }
}

class _StartupTunnelExitTransition extends StatelessWidget {
  const _StartupTunnelExitTransition({
    required this.animation,
    required this.exiting,
    required this.child,
  });

  final Animation<double> animation;
  final bool exiting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!exiting) {
      return FadeTransition(opacity: animation, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 在 AnimatedSwitcher 的退出阶段，animation.value 从 1 变到 0
        final t = (1 - animation.value).clamp(0.0, 1.0);

        // 使用三次曲线让动画更加柔和自然
        final curved = Curves.easeInOutCubic.transform(t);

        // 取消了原来夸张的 3 倍放大，改为仅放大 10% (1.0 -> 1.1)
        // 营造一种启动页轻轻“向前推开”并消散的灵动感
        final scale = 1.0 + (0.1 * curved);

        // 平滑淡出
        final opacity = (1 - t).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: child, // 移除了之前的深色遮罩(veilAlpha)和光环爆发动画
          ),
        );
      },
    );
  }
}

class _HomeTunnelEnterTransition extends StatelessWidget {
  const _HomeTunnelEnterTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);
        // 进入曲线
        final curved = Curves.easeOutCubic.transform(t);

        // 微微从下方 20 像素处浮现
        final dy = (1 - curved) * 20.0;
        // 柔和渐显
        final opacity = Curves.easeOut.transform(t);

        // 移除了旧版本中的高斯模糊(Blur)和缩放，采用纯粹的透明度+位移
        // 这样不仅性能更好，也更符合扁平极简的调性
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
    );
  }
}

class _RiverStartupScreen extends StatefulWidget {
  const _RiverStartupScreen({super.key, required this.iconPreset});

  final AppAppIconPreset iconPreset;

  @override
  State<_RiverStartupScreen> createState() => _RiverStartupScreenState();
}

class _RiverStartupScreenState extends State<_RiverStartupScreen>
    with TickerProviderStateMixin {
  late final AnimationController _rippleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);

  late final AnimationController _loadingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _rippleController.dispose();
    _floatController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  _StartupPalette _resolvePalette(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (isDark) {
      return _StartupPalette(
        bgTop: const Color(0xFF0F1712),
        bgBottom: const Color(0xFF1A2A1E),
        accentPrimary: const Color(0xFF66BB6A),
        accentSecondary: const Color(0xFF81C784).withValues(alpha: 0.15),
        textColor: const Color(0xFFE8F0EA),
        subTextColor: const Color(0xFF9EB0A5),
        logoBg: const Color(0xFF25382A),
      );
    }
    return _StartupPalette(
      bgTop: const Color(0xFFF4F9F5),
      bgBottom: const Color(0xFFDFF0E3),
      accentPrimary: const Color(0xFF81C784),
      accentSecondary: const Color(0xFFC8E6C9).withValues(alpha: 0.4),
      textColor: const Color(0xFF2D3B31),
      subTextColor: const Color(0xFF758A7A),
      logoBg: const Color(0xFFFFFFFF),
    );
  }

  String _iconAssetForPreset(AppAppIconPreset preset) {
    return switch (preset) {
      AppAppIconPreset.origin => 'assets/images/app_icons/origin.png',
      AppAppIconPreset.quality => 'assets/images/app_icons/quality.png',
      AppAppIconPreset.pixel => 'assets/images/app_icons/pixel.png',
      AppAppIconPreset.cloud => 'assets/images/app_icons/cloud.png',
      AppAppIconPreset.neon => 'assets/images/app_icons/neon.png',
      AppAppIconPreset.vaporwave => 'assets/images/app_icons/vaporwave.png',
      AppAppIconPreset.china => 'assets/images/app_icons/china.png',
      AppAppIconPreset.chengdu => 'assets/images/app_icons/chengdu.png',
      AppAppIconPreset.animation => 'assets/images/app_icons/animation.png',
      AppAppIconPreset.sweet => 'assets/images/app_icons/sweet.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _resolvePalette(theme);
    final startupIconAsset = _iconAssetForPreset(widget.iconPreset);

    return Scaffold(
      backgroundColor: palette.bgTop,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.bgTop, palette.bgBottom],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 扁平化水波纹动效
                        AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: const Size(240, 240),
                              painter: _FlatRipplePainter(
                                progress: _rippleController.value,
                                color: palette.accentPrimary,
                              ),
                            );
                          },
                        ),
                        // 呼吸悬浮 Logo
                        AnimatedBuilder(
                          animation: _floatController,
                          builder: (context, child) {
                            final dy =
                                math.sin(_floatController.value * math.pi) * 6;
                            return Transform.translate(
                              offset: Offset(0, dy),
                              child: child,
                            );
                          },
                          child: Container(
                            width: 108,
                            height: 108,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: palette.logoBg,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: palette.accentSecondary,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                startupIconAsset,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return ColoredBox(
                                    color: palette.accentPrimary,
                                    child: const Icon(
                                      Icons.waves_rounded,
                                      color: Colors.white,
                                      size: 42,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '聚河畔',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.textColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '连接 RiverSide 与 清水河畔',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.subTextColor,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _FluidLoadingIndicator(
                    animation: _loadingController,
                    color: palette.accentPrimary,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 32,
              child: Text(
                '即将进入河畔',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.subTextColor.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupPalette {
  const _StartupPalette({
    required this.bgTop,
    required this.bgBottom,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.textColor,
    required this.subTextColor,
    required this.logoBg,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color textColor;
  final Color subTextColor;
  final Color logoBg;
}

class _FlatRipplePainter extends CustomPainter {
  const _FlatRipplePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      // 计算错开的进度，让波纹有层次感
      double currentProgress = (progress + (i * 0.33)) % 1.0;
      // 使用曲线让动画显得更有弹性 (EaseOut)
      double curvedProgress = Curves.easeOutCubic.transform(currentProgress);

      double radius = 40 + (maxRadius - 40) * curvedProgress;
      // 随着范围扩大，透明度逐渐降为 0
      double opacity = (1.0 - curvedProgress).clamp(0.0, 1.0) * 0.15;

      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlatRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _FluidLoadingIndicator extends StatelessWidget {
  const _FluidLoadingIndicator({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (index) {
            // 为每个胶囊计算相位差
            final offset = (progress - index * 0.2).abs();
            final normalized = (1 - (offset * 2).clamp(0.0, 1.0));
            // 胶囊高度变化
            final height = 6.0 + normalized * 8.0;
            // 胶囊透明度变化
            final opacity = 0.4 + normalized * 0.6;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: height,
              decoration: BoxDecoration(
                color: color.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}

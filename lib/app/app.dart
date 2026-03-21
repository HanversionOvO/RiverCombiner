import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:draggable_route/draggable_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/mini_apps/river_mini_app_floating_store.dart';
import 'package:river/core/mini_apps/river_mini_app_host_store.dart';
import 'package:river/core/mini_apps/river_mini_app_suspension_store.dart';
import 'package:river/core/navigation/river_route_observer.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/platform/app_icon_switcher.dart';
import 'package:river/core/platform/riverside_cookie_bridge.dart';
import 'package:river/core/update/app_update_checker.dart';
import 'package:river/features/home/home_shell_page.dart';
import 'package:river/features/login/login_page.dart';
import 'package:river/features/mini_apps/mini_app_webview_page.dart';
import 'package:river/core/widgets/river_home_widget_service.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:river/core/realtime/riverside_realtime_inbox_service.dart';
import 'package:river/features/notifications/chat_detail_page.dart';

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
    final sharedPreferencesFuture = SharedPreferences.getInstance();
    final settingsFuture = _dependencies.settingsController.initialize(
      sharedPreferencesFuture: sharedPreferencesFuture,
    );
    final accountFuture = _dependencies.accountStore.initialize(
      sharedPreferencesFuture: sharedPreferencesFuture,
    );
    final topicFootprintFuture = _dependencies.topicFootprintStore.initialize(
      sharedPreferencesFuture: sharedPreferencesFuture,
    );

    await settingsFuture;
    unawaited(
      AppIconSwitcher.switchToPreset(
        _dependencies.settingsController.iconPreset,
      ),
    );
    if (mounted && !_initialized) {
      setState(() {});
    }
    await accountFuture;
    await topicFootprintFuture;
    _dependencies.postsStartupPreloadStore.start(
      accountStore: _dependencies.accountStore,
    );
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
          DraggableRoute<void>(
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

  Future<void> _handleInAppMessageTap(
    RiverSideInAppMessageBanner banner,
  ) async {
    final context = _appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    switch (banner.kind) {
      case RiverSideInAppMessageKind.notification:
        final notification = banner.notification;
        if (notification == null ||
            notification.topicId == null ||
            notification.topicId! <= 0) {
          _homeShellController.performQuickAction(
            HomeQuickAction.notifications,
          );
          return;
        }
        final title = notification.title.trim().isEmpty
            ? '帖子详情'
            : notification.title.trim();
        final authorName = notification.username.trim().isEmpty
            ? '未知用户'
            : notification.username.trim();
        await Navigator.of(context).push(
          DraggableRoute<void>(
            builder: (_) => TopicDetailPage(
              dependencies: _dependencies,
              topicId: notification.topicId!,
              provider: AccountProvider.riverSide,
              initialPostNumberOnOpen:
                  (notification.postNumber != null &&
                      notification.postNumber! > 1)
                  ? notification.postNumber
                  : null,
              preview: TopicDetailPreview(
                title: title,
                authorDisplayName: authorName,
                authorUsername: authorName,
                authorAvatarUrl: notification.avatarUrl,
                titleHeroTag:
                    'realtime_notification_topic_title_${notification.id}',
                authorAvatarHeroTag:
                    'realtime_notification_topic_avatar_${notification.id}',
                authorNameHeroTag:
                    'realtime_notification_topic_name_${notification.id}',
              ),
            ),
          ),
        );
        return;
      case RiverSideInAppMessageKind.channelMessage:
      case RiverSideInAppMessageKind.directMessage:
        final channel = banner.channel;
        if (channel == null) {
          _homeShellController.performQuickAction(
            HomeQuickAction.notifications,
          );
          return;
        }
        await Navigator.of(context).push(
          riverPageRoute<void>(
            builder: (_) =>
                ChatDetailPage(dependencies: _dependencies, channel: channel),
          ),
        );
        return;
    }
  }

  @override
  void dispose() {
    _homeWidgetClickSubscription?.cancel();
    _homeWidgetSyncDebounceTimer?.cancel();
    _dependencies.accountStore.removeListener(_scheduleHomeWidgetSync);
    _dependencies.settingsController.removeListener(_scheduleHomeWidgetSync);
    _dependencies.riverSideRealtimeInboxService.dispose();
    _dependencies.settingsController.dispose();
    _dependencies.accountStore.dispose();
    _dependencies.miniAppHostStore.dispose();
    _dependencies.miniAppFloatingStore.dispose();
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
          navigatorObservers: <NavigatorObserver>[riverRouteObserver],
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
                disableAnimations: settings.reduceMotion,
              ),
              child: _AppRootSnackbarHost(
                dependencies: _dependencies,
                hostStore: _dependencies.miniAppHostStore,
                floatingStore: _dependencies.miniAppFloatingStore,
                onOpenFloatingMiniApp: _openMiniAppFromFloatingEntry,
                onCloseFloatingMiniApp: _closeFloatingMiniApp,
                onTapInAppMessage: _handleInAppMessageTap,
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
          themeAnimationDuration: settings.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          themeAnimationCurve: settings.reduceMotion
              ? Curves.linear
              : Curves.easeOutCubic,
          home: AnimatedSwitcher(
            duration: settings.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 1180),
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
              if (settings.reduceMotion) {
                return child;
              }
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
    final isCompact = settings.compactDensity;
    final isReduceMotion = settings.reduceMotion;
    final cornerRadius = _cornerRadiusForPreset(settings.cornerPreset);
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: isCompact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      splashFactory: isReduceMotion
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      pageTransitionsTheme: isReduceMotion
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
      settings.fontWeightScale,
    );
    final primaryTextTheme = _applyFontWeightPreset(
      base.primaryTextTheme.apply(fontFamily: settings.fontFamilyName),
      settings.fontWeightScale,
    );
    final weightedTextTheme = _applyFontVariationPreset(
      textTheme,
      settings.fontWeightScale,
    );
    final weightedPrimaryTextTheme = _applyFontVariationPreset(
      primaryTextTheme,
      settings.fontWeightScale,
    );

    return base.copyWith(
      textTheme: weightedTextTheme,
      primaryTextTheme: weightedPrimaryTextTheme,
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: isCompact ? 50 : 56,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
      ),
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
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 14,
          vertical: isCompact ? 10 : 14,
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
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cornerRadius + 8),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 2),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 2),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 8),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        height: isCompact ? 64 : 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius + 4),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        visualDensity: isCompact
            ? VisualDensity.compact
            : VisualDensity.standard,
        dense: isCompact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 2 : 6,
        ),
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

  TextTheme _applyFontWeightPreset(TextTheme theme, double scale) {
    final delta = ((scale - 1.0) * 10).round().clamp(-3, 3);
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

  TextTheme _applyFontVariationPreset(TextTheme theme, double scale) {
    final axisWeight = (500 * scale).clamp(320.0, 780.0);
    final variations = <FontVariation>[FontVariation('wght', axisWeight)];
    TextStyle? apply(TextStyle? style) {
      if (style == null) {
        return null;
      }
      return style.copyWith(fontVariations: variations);
    }

    return theme.copyWith(
      displayLarge: apply(theme.displayLarge),
      displayMedium: apply(theme.displayMedium),
      displaySmall: apply(theme.displaySmall),
      headlineLarge: apply(theme.headlineLarge),
      headlineMedium: apply(theme.headlineMedium),
      headlineSmall: apply(theme.headlineSmall),
      titleLarge: apply(theme.titleLarge),
      titleMedium: apply(theme.titleMedium),
      titleSmall: apply(theme.titleSmall),
      bodyLarge: apply(theme.bodyLarge),
      bodyMedium: apply(theme.bodyMedium),
      bodySmall: apply(theme.bodySmall),
      labelLarge: apply(theme.labelLarge),
      labelMedium: apply(theme.labelMedium),
      labelSmall: apply(theme.labelSmall),
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

  void _openMiniAppFromFloatingEntry(RiverMiniAppFloatingEntry entry) {
    _dependencies.miniAppFloatingStore.removeById(entry.miniApp.id);
    _dependencies.miniAppHostStore.activate(entry.miniApp.id);
  }

  void _closeFloatingMiniApp(String appId) {
    _dependencies.miniAppFloatingStore.removeById(appId);
    RiverMiniAppSuspensionStore.clearById(appId);
    _dependencies.miniAppHostStore.close(appId);
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
  const _AppRootSnackbarHost({
    required this.dependencies,
    required this.hostStore,
    required this.child,
    required this.floatingStore,
    required this.onOpenFloatingMiniApp,
    required this.onCloseFloatingMiniApp,
    required this.onTapInAppMessage,
  });

  final AppDependencies dependencies;
  final RiverMiniAppHostStore hostStore;
  final Widget child;
  final RiverMiniAppFloatingStore floatingStore;
  final ValueChanged<RiverMiniAppFloatingEntry> onOpenFloatingMiniApp;
  final ValueChanged<String> onCloseFloatingMiniApp;
  final Future<void> Function(RiverSideInAppMessageBanner banner)
  onTapInAppMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          child,
          _MiniAppHostOverlay(dependencies: dependencies, hostStore: hostStore),
          _MiniAppFloatingDock(
            store: floatingStore,
            onOpen: onOpenFloatingMiniApp,
            onClose: onCloseFloatingMiniApp,
          ),
          _RiverInAppBannerHost(
            service: dependencies.riverSideRealtimeInboxService,
            onTapBanner: onTapInAppMessage,
          ),
        ],
      ),
    );
  }
}

class _RiverInAppBannerHost extends StatefulWidget {
  const _RiverInAppBannerHost({
    required this.service,
    required this.onTapBanner,
  });

  final RiverSideRealtimeInboxService service;
  final Future<void> Function(RiverSideInAppMessageBanner banner) onTapBanner;

  @override
  State<_RiverInAppBannerHost> createState() => _RiverInAppBannerHostState();
}

class _RiverInAppBannerHostState extends State<_RiverInAppBannerHost>
    with SingleTickerProviderStateMixin {
  static const Duration _bannerVisibleDuration = Duration(seconds: 5);
  static const double _dismissDragThreshold = 72;

  StreamSubscription<RiverSideInAppMessageBanner>? _subscription;
  RiverSideInAppMessageBanner? _currentBanner;
  Timer? _hideTimer;
  late final AnimationController _visibilityController;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;
  int _bannerVersion = 0;
  double _dragOffsetY = 0;

  @override
  void initState() {
    super.initState();
    _visibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _opacityAnimation = CurvedAnimation(
      parent: _visibilityController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(
        parent: _visibilityController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInOutCubic,
      ),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.16), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _visibilityController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _subscription = widget.service.bannerStream.listen(_showBanner);
  }

  @override
  void didUpdateWidget(covariant _RiverInAppBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service == widget.service) {
      return;
    }
    _subscription?.cancel();
    _subscription = widget.service.bannerStream.listen(_showBanner);
  }

  void _showBanner(RiverSideInAppMessageBanner banner) {
    _hideTimer?.cancel();
    _bannerVersion += 1;
    HapticFeedback.lightImpact();
    setState(() {
      _currentBanner = banner;
      _dragOffsetY = 0;
    });
    _visibilityController.forward(from: 0);
    _scheduleAutoDismiss();
  }

  Future<void> _dismissBanner() async {
    final banner = _currentBanner;
    if (!mounted || banner == null) {
      return;
    }
    _hideTimer?.cancel();
    final version = ++_bannerVersion;
    if (_visibilityController.status != AnimationStatus.dismissed) {
      await _visibilityController.reverse();
    }
    if (!mounted || _bannerVersion != version) {
      return;
    }
    setState(() {
      _currentBanner = null;
      _dragOffsetY = 0;
    });
  }

  void _scheduleAutoDismiss() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_bannerVisibleDuration, () {
      unawaited(_dismissBanner());
    });
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final nextOffset = (_dragOffsetY + details.delta.dy).clamp(-140.0, 0.0);
    if (nextOffset == _dragOffsetY) {
      return;
    }
    setState(() {
      _dragOffsetY = nextOffset;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final shouldDismiss =
        _dragOffsetY <= -_dismissDragThreshold ||
        details.primaryVelocity != null && details.primaryVelocity! < -320;
    if (shouldDismiss) {
      unawaited(_dismissBanner());
      return;
    }
    setState(() {
      _dragOffsetY = 0;
    });
    _scheduleAutoDismiss();
  }

  Future<void> _handleTap() async {
    final banner = _currentBanner;
    if (banner == null) {
      return;
    }
    await _dismissBanner();
    await widget.onTapBanner(banner);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subscription?.cancel();
    _visibilityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _currentBanner;
    if (banner == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final accent = switch (banner.kind) {
      RiverSideInAppMessageKind.notification => theme.colorScheme.primary,
      RiverSideInAppMessageKind.channelMessage => theme.colorScheme.tertiary,
      RiverSideInAppMessageKind.directMessage => theme.colorScheme.secondary,
    };
    final icon = switch (banner.kind) {
      RiverSideInAppMessageKind.notification => Icons.notifications_rounded,
      RiverSideInAppMessageKind.channelMessage => Icons.forum_rounded,
      RiverSideInAppMessageKind.directMessage => Icons.mail_rounded,
    };
    final label = switch (banner.kind) {
      RiverSideInAppMessageKind.notification => '新通知',
      RiverSideInAppMessageKind.channelMessage => '频道消息',
      RiverSideInAppMessageKind.directMessage => '私信消息',
    };
    final dragProgress = (-_dragOffsetY / _dismissDragThreshold).clamp(
      0.0,
      1.0,
    );
    return Positioned(
      top: topInset + 8,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          ignoring:
              _currentBanner == null ||
              _visibilityController.status == AnimationStatus.dismissed,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                alignment: Alignment.topCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(0, _dragOffsetY, 0),
                  child: Opacity(
                    opacity: 1 - dragProgress * 0.28,
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _handleVerticalDragStart,
                        onVerticalDragUpdate: _handleVerticalDragUpdate,
                        onVerticalDragEnd: _handleVerticalDragEnd,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: _handleTap,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.16),
                                  blurRadius: 30,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: <Color>[
                                        Color.alphaBlend(
                                          accent.withValues(alpha: 0.12),
                                          theme.colorScheme.surface.withValues(
                                            alpha: 0.96,
                                          ),
                                        ),
                                        theme.colorScheme.surface.withValues(
                                          alpha: 0.9,
                                        ),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.22),
                                    ),
                                  ),
                                  child: Stack(
                                    children: <Widget>[
                                      Positioned(
                                        left: -12,
                                        top: -18,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 104,
                                            height: 104,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: <Color>[
                                                  accent.withValues(
                                                    alpha: 0.18,
                                                  ),
                                                  accent.withValues(alpha: 0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          16,
                                          16,
                                          18,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Container(
                                              width: 46,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: <Color>[
                                                    accent.withValues(
                                                      alpha: 0.9,
                                                    ),
                                                    accent.withValues(
                                                      alpha: 0.62,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Icon(
                                                icon,
                                                color:
                                                    theme.colorScheme.onPrimary,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Row(
                                                    children: <Widget>[
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: accent
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                999,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          label,
                                                          style: theme
                                                              .textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                                color: accent,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    0.1,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          banner.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: theme
                                                              .textTheme
                                                              .titleSmall
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                letterSpacing:
                                                                    -0.12,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    banner.message,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          height: 1.4,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 8,
                                        child: IgnorePointer(
                                          child: Center(
                                            child: Container(
                                              width: 34,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.22),
                                                borderRadius:
                                                    BorderRadius.circular(999),
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
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAppHostOverlay extends StatelessWidget {
  const _MiniAppHostOverlay({
    required this.dependencies,
    required this.hostStore,
  });

  final AppDependencies dependencies;
  final RiverMiniAppHostStore hostStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hostStore,
      builder: (context, _) {
        final sessions = hostStore.sessions;
        if (sessions.isEmpty) {
          return const SizedBox.shrink();
        }
        final activeId = hostStore.activeSessionId;
        final orderedSessions = <RiverMiniAppHostSession>[
          ...sessions.where((session) => session.id != activeId),
          ...sessions.where((session) => session.id == activeId),
        ];
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final session in orderedSessions)
              _MiniAppHostAnimatedLayer(
                key: ValueKey<String>(
                  'mini_host_layer_${session.id}_${session.generation}',
                ),
                active: session.id == activeId,
                child: Navigator(
                  key: ValueKey<String>(
                    'mini_host_nav_${session.id}_${session.generation}',
                  ),
                  onGenerateRoute: (_) {
                    return MaterialPageRoute<void>(
                      settings: RouteSettings(name: 'mini_host_${session.id}'),
                      builder: (_) => MiniAppWebViewPage(
                        dependencies: dependencies,
                        miniApp: session.miniApp,
                        launchRoute: session.launchRoute,
                        launchParams: session.launchParams,
                        launchAction: session.launchAction,
                        launchSource: session.launchSource,
                        onSuspendRequested: () => hostStore.suspend(session.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniAppHostAnimatedLayer extends StatefulWidget {
  const _MiniAppHostAnimatedLayer({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_MiniAppHostAnimatedLayer> createState() =>
      _MiniAppHostAnimatedLayerState();
}

class _MiniAppHostAnimatedLayerState extends State<_MiniAppHostAnimatedLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _fade = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    if (widget.active) {
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) {
          unawaited(_controller.forward());
        }
      });
    } else {
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant _MiniAppHostAnimatedLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _controller.forward(from: 0);
    } else if (oldWidget.active && !widget.active) {
      _controller.reverse(from: _controller.value <= 0 ? 1 : _controller.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.active,
      child: ExcludeSemantics(
        excluding: !widget.active,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(position: _slide, child: widget.child),
        ),
      ),
    );
  }
}

class _MiniAppFloatingDock extends StatefulWidget {
  const _MiniAppFloatingDock({
    required this.store,
    required this.onOpen,
    required this.onClose,
  });

  final RiverMiniAppFloatingStore store;
  final ValueChanged<RiverMiniAppFloatingEntry> onOpen;
  final ValueChanged<String> onClose;

  @override
  State<_MiniAppFloatingDock> createState() => _MiniAppFloatingDockState();
}

class _MiniAppFloatingDockState extends State<_MiniAppFloatingDock> {
  bool _snapToRight = true;
  double _topRatio = 0.18;
  double? _dragTop;
  double? _dragLeft;
  bool _isDragging = false;
  bool _dragOverDismissZone = false;
  bool _closingAllFloating = false;
  bool _panelOpen = false;
  bool _panelVisible = false;
  bool _didDrag = false;
  Timer? _panelHideTimer;

  Duration _panelHideDelay() {
    final count = widget.store.entries.length;
    final ms = (280 + count * 30).clamp(300, 560);
    return Duration(milliseconds: ms);
  }

  void _openPanel() {
    _panelHideTimer?.cancel();
    setState(() {
      _panelVisible = true;
      _panelOpen = true;
    });
  }

  void _closePanel({bool immediate = false}) {
    _panelHideTimer?.cancel();
    if (!_panelVisible) {
      return;
    }
    setState(() {
      _panelOpen = false;
      if (immediate) {
        _panelVisible = false;
      }
    });
    if (immediate) {
      return;
    }
    _panelHideTimer = Timer(_panelHideDelay(), () {
      if (!mounted || _panelOpen) {
        return;
      }
      setState(() {
        _panelVisible = false;
      });
    });
  }

  Future<void> _closeAllFloatingApps(List<String> appIds) async {
    if (appIds.isEmpty || _closingAllFloating) {
      return;
    }
    setState(() {
      _closingAllFloating = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 190));
    if (!mounted) {
      return;
    }
    for (final appId in appIds) {
      widget.onClose(appId);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _closingAllFloating = false;
    });
  }

  @override
  void dispose() {
    _panelHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final entries = widget.store.entries;
        if (entries.isEmpty) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final mediaPadding = MediaQuery.paddingOf(context);
            const verticalMargin = 12.0;
            const dockHeight = 52.0;
            const dockWidth = 66.0;
            final minTop = mediaPadding.top + verticalMargin;
            final maxTop =
                constraints.maxHeight -
                mediaPadding.bottom -
                dockHeight -
                verticalMargin;
            if (maxTop <= minTop) {
              return const SizedBox.shrink();
            }

            final resolvedTop =
                (_dragTop ?? (minTop + (maxTop - minTop) * _topRatio)).clamp(
                  minTop,
                  maxTop,
                );
            const minLeft = 0.0;
            final maxLeft = constraints.maxWidth - dockWidth;
            final resolvedLeft =
                (_dragLeft ?? (_snapToRight ? maxLeft : minLeft)).clamp(
                  minLeft,
                  maxLeft,
                );
            final isDragging =
                _isDragging || _dragLeft != null || _dragTop != null;
            final snapDuration = Duration(milliseconds: isDragging ? 0 : 260);
            final anchorX = _snapToRight
                ? (resolvedLeft + 8.0)
                : (resolvedLeft + dockWidth - 8.0);
            final anchorY = resolvedTop + dockHeight / 2;
            final dismissZoneRadius = 128.0;
            const dismissZoneRight = 0.0;
            const dismissZoneBottom = 0.0;
            final dismissCorner = Offset(
              constraints.maxWidth - dismissZoneRight,
              constraints.maxHeight - dismissZoneBottom,
            );

            bool isPointInsideDismissZone(Offset point) {
              final dx = dismissCorner.dx - point.dx;
              final dy = dismissCorner.dy - point.dy;
              if (dx < 0 ||
                  dy < 0 ||
                  dx > dismissZoneRadius ||
                  dy > dismissZoneRadius) {
                return false;
              }
              return dx * dx + dy * dy <= dismissZoneRadius * dismissZoneRadius;
            }

            if (_panelVisible && entries.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _panelOpen = false;
                    _panelVisible = false;
                    _dragOverDismissZone = false;
                  });
                }
              });
            }

            return SizedBox.expand(
              child: Stack(
                children: [
                  if (_panelVisible)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_panelOpen,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closePanel,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            opacity: _panelOpen ? 1 : 0,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.34),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_panelVisible)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_panelOpen,
                        child: _MiniAppFloatingPanel(
                          entries: entries,
                          expanded: _panelOpen,
                          dockedRight: _snapToRight,
                          anchor: Offset(anchorX, anchorY),
                          onOpen: (entry) {
                            _closePanel();
                            widget.onOpen(entry);
                          },
                          onClose: (appId) {
                            widget.onClose(appId);
                          },
                        ),
                      ),
                    ),
                  Positioned(
                    right: dismissZoneRight,
                    bottom: dismissZoneBottom,
                    child: _MiniAppDismissZone(
                      visible: isDragging,
                      active: _dragOverDismissZone,
                      radius: dismissZoneRadius,
                    ),
                  ),
                  AnimatedPositioned(
                    duration: snapDuration,
                    curve: Curves.easeOutCubic,
                    left: resolvedLeft,
                    top: resolvedTop,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_didDrag) {
                          _didDrag = false;
                          return;
                        }
                        if (_panelOpen) {
                          _closePanel();
                        } else {
                          _openPanel();
                        }
                      },
                      onPanStart: (_) {
                        setState(() {
                          _didDrag = false;
                          _isDragging = true;
                          _dragOverDismissZone = false;
                          _closingAllFloating = false;
                          _dragTop = resolvedTop;
                          _dragLeft = resolvedLeft;
                        });
                        _closePanel(immediate: true);
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          if (details.delta.distanceSquared > 0.8) {
                            _didDrag = true;
                          }
                          _dragTop =
                              (_dragTop ?? resolvedTop) + details.delta.dy;
                          _dragTop = _dragTop!.clamp(minTop, maxTop);
                          _dragLeft =
                              (_dragLeft ?? resolvedLeft) + details.delta.dx;
                          _dragLeft = _dragLeft!.clamp(minLeft, maxLeft);
                          final center = Offset(
                            _dragLeft! + dockWidth / 2,
                            _dragTop! + dockHeight / 2,
                          );
                          _dragOverDismissZone = isPointInsideDismissZone(
                            center,
                          );
                        });
                      },
                      onPanEnd: (_) {
                        final shouldCloseAll = _dragOverDismissZone;
                        final center =
                            (_dragLeft ?? resolvedLeft) + dockWidth / 2;
                        final appIds = entries
                            .map((item) => item.miniApp.id)
                            .where((id) => id.trim().isNotEmpty)
                            .toList(growable: false);
                        setState(() {
                          _snapToRight = center > constraints.maxWidth / 2;
                          final top = (_dragTop ?? resolvedTop).clamp(
                            minTop,
                            maxTop,
                          );
                          _topRatio = (top - minTop) / (maxTop - minTop);
                          _dragTop = null;
                          _dragLeft = null;
                          _isDragging = false;
                          _dragOverDismissZone = false;
                        });
                        if (shouldCloseAll) {
                          unawaited(_closeAllFloatingApps(appIds));
                        }
                      },
                      onPanCancel: () {
                        setState(() {
                          _dragTop = null;
                          _dragLeft = null;
                          _isDragging = false;
                          _dragOverDismissZone = false;
                        });
                      },
                      child: _MiniAppFloatingHandle(
                        dockedRight: _snapToRight,
                        dragging: isDragging,
                        dimmed: _dragOverDismissZone,
                        closingAll: _closingAllFloating,
                        count: entries.length,
                        opened: _panelOpen,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniAppFloatingHandle extends StatelessWidget {
  const _MiniAppFloatingHandle({
    required this.dockedRight,
    required this.dragging,
    required this.dimmed,
    required this.closingAll,
    required this.count,
    required this.opened,
  });

  final bool dockedRight;
  final bool dragging;
  final bool dimmed;
  final bool closingAll;
  final int count;
  final bool opened;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edgeRadius = dragging ? 26.0 : (dockedRight ? 0.0 : 26.0);
    final farRadius = dragging ? 26.0 : (dockedRight ? 26.0 : 0.0);
    final targetOpacity = closingAll ? 0.10 : (dimmed ? 0.44 : 1.0);
    return AnimatedScale(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeInOutCubic,
      scale: closingAll ? 0.86 : 1,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        opacity: targetOpacity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 66,
          height: 52,
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(farRadius),
              bottomLeft: Radius.circular(farRadius),
              topRight: Radius.circular(edgeRadius),
              bottomRight: Radius.circular(edgeRadius),
            ),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.86,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: opened
                    ? Container(
                        key: const ValueKey<String>('mini_app_handle_close'),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    : ClipOval(
                        key: const ValueKey<String>('mini_app_handle_logo'),
                        child: Image.asset(
                          'assets/images/miniapp.jpg',
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.widgets_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  opacity: opened ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: opened,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.96,
                          ),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAppDismissZone extends StatelessWidget {
  const _MiniAppDismissZone({
    required this.visible,
    required this.active,
    required this.radius,
  });

  final bool visible;
  final bool active;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = active
        ? theme.colorScheme.error.withValues(alpha: 0.90)
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92);
    final fg = active
        ? theme.colorScheme.onError
        : theme.colorScheme.onSurfaceVariant;
    final label = active ? '松开关闭' : '关闭所有';
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0.18, 0.18),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            scale: active ? 1.04 : 1,
            child: SizedBox(
              width: radius,
              height: radius,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(radius),
                  ),
                  border: Border.all(
                    color: active
                        ? theme.colorScheme.onError.withValues(alpha: 0.28)
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.22,
                          ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 14,
                    top: 14,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Align(
                    alignment: const Alignment(-0.28, -0.28),
                    child: SizedBox(
                      width: radius * 0.55,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active
                                ? Icons.delete_forever_rounded
                                : Icons.delete_outline_rounded,
                            size: 18,
                            color: fg,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style:
                                theme.textTheme.labelSmall?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ) ??
                                TextStyle(
                                  color: fg,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAppFloatingPanel extends StatelessWidget {
  const _MiniAppFloatingPanel({
    required this.entries,
    required this.expanded,
    required this.dockedRight,
    required this.anchor,
    required this.onOpen,
    required this.onClose,
  });

  final List<RiverMiniAppFloatingEntry> entries;
  final bool expanded;
  final bool dockedRight;
  final Offset anchor;
  final ValueChanged<RiverMiniAppFloatingEntry> onOpen;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final inward = dockedRight ? -1.0 : 1.0;
    final count = entries.length;
    final step = count <= 1 ? 0.0 : 1.0 / (count - 1);
    const actionSize = 60.0;
    const openCurve = Cubic(0.2, 0.0, 0.0, 1.0);
    const closeCurve = Cubic(0.4, 0.0, 1.0, 1.0);
    const openScaleCurve = Cubic(0.16, 1.0, 0.2, 1.0);
    const closeScaleCurve = Cubic(0.4, 0.0, 0.84, 0.18);
    const desiredSpacing = 66.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableTop = math.max(0.0, anchor.dy - 28.0);
        final availableBottom = math.max(
          0.0,
          constraints.maxHeight - anchor.dy - 28.0,
        );
        final verticalLimit = math.max(
          52.0,
          math.min(availableTop, availableBottom),
        );

        var radius = 96.0 + (count - 1) * 12.0;
        radius = radius.clamp(92.0, 176.0);

        var angleRange = count <= 1
            ? 0.0
            : (((count - 1) * desiredSpacing) / radius) * 180 / math.pi;
        angleRange = angleRange.clamp(44.0, 128.0);

        final halfRad = (angleRange / 2) * math.pi / 180.0;
        final sinHalf = math.max(0.25, math.sin(halfRad).abs());
        final maxAllowedRadius = (verticalLimit / sinHalf).clamp(72.0, 176.0);
        radius = math.min(radius, maxAllowedRadius);

        return Stack(
          children: [
            for (var i = 0; i < entries.length; i++)
              TweenAnimationBuilder<double>(
                key: ValueKey<String>('mini_app_fan_${entries[i].miniApp.id}'),
                tween: Tween<double>(
                  begin: expanded ? 0 : 1,
                  end: expanded ? 1 : 0,
                ),
                duration: Duration(milliseconds: 240 + (i * 20)),
                curve: Curves.linear,
                builder: (context, value, _) {
                  final start = (i * 0.06).clamp(0.0, 0.45);
                  final itemRaw = ((value - start) / (1 - start)).clamp(
                    0.0,
                    1.0,
                  );
                  final arcT =
                      (expanded
                              ? openCurve.transform(itemRaw)
                              : closeCurve.transform(itemRaw))
                          .clamp(0.0, 1.0);
                  final popT =
                      (expanded
                              ? openScaleCurve.transform(itemRaw)
                              : closeScaleCurve.transform(itemRaw))
                          .clamp(0.0, 1.0);
                  final normalized = count <= 1 ? 0.0 : (-0.5 + step * i);
                  final targetRad =
                      (normalized * angleRange) * (math.pi / 180.0);
                  final currentRad = targetRad * arcT;
                  final currentRadius = radius * popT;
                  final dx = inward * math.cos(currentRad) * currentRadius;
                  final dy = math.sin(currentRad) * currentRadius;
                  final left = anchor.dx + dx - actionSize / 2;
                  final top = anchor.dy + dy - actionSize / 2;
                  final rotate = (1 - popT) * 0.32 * inward;
                  return Positioned(
                    left: left,
                    top: top,
                    child: Opacity(
                      opacity: popT,
                      child: Transform.rotate(
                        angle: rotate,
                        child: Transform.scale(
                          scale: 0.76 + (0.24 * popT),
                          child: _MiniAppFloatingItemButton(
                            entry: entries[i],
                            onOpen: () => onOpen(entries[i]),
                            onClose: () => onClose(entries[i].miniApp.id),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _MiniAppFloatingItemButton extends StatelessWidget {
  const _MiniAppFloatingItemButton({
    required this.entry,
    required this.onOpen,
    required this.onClose,
  });

  final RiverMiniAppFloatingEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconProvider = _miniAppFloatingIconProvider(entry.miniApp.iconUrl);
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkResponse(
                onTap: onOpen,
                containedInkWell: true,
                highlightShape: BoxShape.circle,
                splashColor: theme.colorScheme.primary.withValues(alpha: 0.14),
                highlightColor: theme.colorScheme.primary.withValues(
                  alpha: 0.08,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface.withValues(alpha: 0.94),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.24,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHigh
                            .withValues(alpha: 0.90),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          width: 0.8,
                        ),
                      ),
                      child: ClipOval(
                        child: iconProvider == null
                            ? Center(
                                child: Icon(
                                  Icons.extension_rounded,
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : Image(
                                image: iconProvider,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 22,
                  height: 22,
                  padding: const EdgeInsets.all(2.6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface.withValues(alpha: 0.94),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.36,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.close_rounded,
                      size: 9,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

ImageProvider<Object>? _miniAppFloatingIconProvider(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return NetworkImage(value);
  }
  return null;
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
                    '好的河畔，没有围栏',
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
                '@MikannQAQ',
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/mini_apps/river_mini_app_platform_client.dart';
import 'package:river/core/platform/app_icon_switcher.dart';
import 'package:river/core/platform/riverside_cookie_bridge.dart';
import 'package:river/core/push/river_jpush_service.dart';
import 'package:river/core/push/river_push_registration_reporter.dart';
import 'package:river/core/update/app_update_checker.dart';
import 'package:river/features/home/home_shell_page.dart';
import 'package:river/features/login/login_page.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';

class RiverApp extends StatefulWidget {
  const RiverApp({super.key});

  @override
  State<RiverApp> createState() => _RiverAppState();
}

class _RiverAppState extends State<RiverApp> {
  late final AppDependencies _dependencies;
  late final RiverJPushService _jPushService;
  late final RiverPushRegistrationReporter _pushRegistrationReporter;
  final GlobalKey<NavigatorState> _appNavigatorKey =
      GlobalKey<NavigatorState>();
  final DateTime _launchStartedAt = DateTime.now();
  static const Duration _minLaunchDisplay = Duration(milliseconds: 1250);
  bool _initialized = false;
  bool _didAutoCheckUpdate = false;
  StreamSubscription<Map<String, dynamic>>? _jPushOpenSubscription;
  Timer? _pushSyncDebounceTimer;
  String? _lastPushReportSignature;

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
    _jPushService = RiverJPushService();
    _pushRegistrationReporter = RiverPushRegistrationReporter();
    _dependencies.accountStore.addListener(_schedulePushIdentitySync);
    _dependencies.settingsController.addListener(_schedulePushIdentitySync);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _dependencies.settingsController.initialize();
    unawaited(
      AppIconSwitcher.switchToPreset(
        _dependencies.settingsController.iconPreset,
      ),
    );
    await _dependencies.accountStore.initialize();
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
    unawaited(_initializePush());
    _scheduleAutoUpdateCheck();
    unawaited(_dependencies.accountStore.syncActiveRiverSideCookieToWebView());
  }

  Future<void> _initializePush() async {
    try {
      await _jPushService.initialize();
      _jPushOpenSubscription = _jPushService.onNotificationOpened.listen(
        _handleJPushOpenEvent,
        onError: (Object error) {
          debugPrint('[JPush] onNotificationOpened error: $error');
        },
      );
      final rid = _jPushService.registrationId.value;
      if (rid != null && rid.isNotEmpty) {
        debugPrint('[JPush] registrationId=$rid');
      }
      _jPushService.registrationId.addListener(_schedulePushIdentitySync);
      _schedulePushIdentitySync();
    } catch (error) {
      debugPrint('[JPush] initialize failed: $error');
    }
  }

  Future<void> _handleJPushOpenEvent(Map<String, dynamic> event) async {
    debugPrint('[JPush] onOpenNotification: $event');
    final context = _appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }

    final payload = _flattenPushPayload(event);
    final topicId = _extractInt(payload, const <String>[
      'topicId',
      'topic_id',
      'tid',
    ]);
    if (topicId != null && topicId > 0) {
      final provider = _extractProvider(payload);
      final qingBoardId = _extractInt(payload, const <String>[
        'boardId',
        'board_id',
        'fid',
      ]);
      await Navigator.of(context).push(
        riverPageRoute<void>(
          builder: (_) => TopicDetailPage(
            dependencies: _dependencies,
            topicId: topicId,
            provider: provider,
            qingBoardId: provider == AccountProvider.qingShuiHePan
                ? qingBoardId
                : null,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已打开推送消息')),
    );
  }

  void _schedulePushIdentitySync() {
    _pushSyncDebounceTimer?.cancel();
    _pushSyncDebounceTimer = Timer(const Duration(milliseconds: 360), () {
      unawaited(_syncPushIdentity());
    });
  }

  Future<void> _syncPushIdentity() async {
    final rid = _jPushService.registrationId.value?.trim() ?? '';
    if (rid.isEmpty) {
      return;
    }

    final riverUsername = _dependencies.accountStore.activeRiverSideUsername;
    final qingUsername = _dependencies.accountStore.activeQingShuiHePanUsername;
    final guest = _dependencies.accountStore.isGuestBrowsing;

    final alias = _buildJPushAlias(
      riverUsername: riverUsername,
      qingUsername: qingUsername,
      isGuest: guest,
    );
    final tags = <String>[
      if (riverUsername != null && riverUsername.isNotEmpty) 'riverside',
      if (qingUsername != null && qingUsername.isNotEmpty) 'qingshuihepan',
      if (guest) 'guest',
      'river_app',
    ];

    await _jPushService.bindAlias(alias);
    await _jPushService.bindTags(tags);

    final endpointUrl = _resolvePushRegisterEndpointUrl();
    if (endpointUrl == null || endpointUrl.isEmpty) {
      return;
    }
    final signature =
        '$endpointUrl|$rid|$riverUsername|$qingUsername|${guest ? 1 : 0}';
    if (_lastPushReportSignature == signature) {
      return;
    }

    try {
      await _pushRegistrationReporter.report(
        endpointUrl: endpointUrl,
        payload: <String, dynamic>{
          'registrationId': rid,
          'platform': 'android',
          'app': 'river',
          'riverSideUsername': riverUsername,
          'qingShuiHePanUsername': qingUsername,
          'guest': guest,
          'tags': tags,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _lastPushReportSignature = signature;
      debugPrint('[JPush] registration report success');
    } catch (error) {
      debugPrint('[JPush] registration report failed: $error');
    }
  }

  String? _resolvePushRegisterEndpointUrl() {
    final catalogUrl = _dependencies.settingsController.miniAppsManifestUrl
        .trim();
    if (catalogUrl.isEmpty) {
      return null;
    }
    try {
      final baseUrl = RiverMiniAppPlatformClient().resolvePlatformBaseUrl(
        catalogUrl,
      );
      final baseUri = Uri.parse(baseUrl);
      final normalizedBasePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
      final endpointPath =
          normalizedBasePath.isEmpty
          ? '/api/public/push/register'
          : '$normalizedBasePath/api/public/push/register';
      return baseUri.replace(path: endpointPath, query: '').toString();
    } catch (_) {
      // Non-platform catalog link: skip push registration reporting.
      return null;
    }
  }

  String _buildJPushAlias({
    required String? riverUsername,
    required String? qingUsername,
    required bool isGuest,
  }) {
    if (riverUsername != null && riverUsername.isNotEmpty) {
      return 'river_${riverUsername.toLowerCase()}';
    }
    if (qingUsername != null && qingUsername.isNotEmpty) {
      return 'qing_${qingUsername.toLowerCase()}';
    }
    if (isGuest) {
      return 'guest';
    }
    return 'anonymous';
  }

  Map<String, dynamic> _flattenPushPayload(Map<String, dynamic> event) {
    final payload = <String, dynamic>{...event};
    final extras = event['extras'];
    if (extras is Map) {
      payload.addAll(extras.cast<String, dynamic>());
    } else if (extras is String) {
      try {
        final decoded = jsonDecode(extras);
        if (decoded is Map) {
          payload.addAll(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // Ignore invalid extras JSON.
      }
    }
    return payload;
  }

  int? _extractInt(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is int) {
        return value;
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  AccountProvider _extractProvider(Map<String, dynamic> payload) {
    final raw = (payload['provider'] ?? payload['forum'] ?? payload['site'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (raw == 'qingshuihepan' || raw == 'qing' || raw == 'hp') {
      return AccountProvider.qingShuiHePan;
    }
    return AccountProvider.riverSide;
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
    _jPushOpenSubscription?.cancel();
    _pushSyncDebounceTimer?.cancel();
    _jPushService.registrationId.removeListener(_schedulePushIdentitySync);
    unawaited(_jPushService.dispose());
    _dependencies.accountStore.removeListener(_schedulePushIdentitySync);
    _dependencies.settingsController.removeListener(_schedulePushIdentitySync);
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
                : const _RiverStartupScreen(
                    key: ValueKey<String>('app_startup'),
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
      return HomeShellPage(dependencies: _dependencies);
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
        final t = (1 - animation.value).clamp(0.0, 1.0);
        final curved = Curves.easeInOutCubicEmphasized.transform(t);
        final fade = Curves.easeIn.transform((t * 1.08).clamp(0.0, 1.0));
        final scale = 1 + (3.2 * curved);
        final opacity = (1 - fade).clamp(0.0, 1.0);
        final veilAlpha = (0.04 + curved * 0.22).clamp(0.0, 0.28);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: veilAlpha),
                  ),
                ),
                IgnorePointer(
                  child: _TunnelRingBurst(
                    progress: curved,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
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
        final curved = Curves.easeOutQuart.transform(t);
        final reveal = Curves.easeOutCubic.transform(
          ((t - 0.22) / 0.78).clamp(0.0, 1.0),
        );
        final opacity = Curves.easeOut.transform(
          ((t - 0.18) / 0.82).clamp(0.0, 1.0),
        );
        final blur = (1 - reveal) * 9.5;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - curved) * 26),
            child: Transform.scale(
              scale: 0.9 + 0.1 * curved,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TunnelRingBurst extends StatelessWidget {
  const _TunnelRingBurst({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TunnelRingBurstPainter(progress: progress, color: color),
    );
  }
}

class _TunnelRingBurstPainter extends CustomPainter {
  const _TunnelRingBurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.58;
    final ringCount = 10;
    for (var i = 0; i < ringCount; i++) {
      final offset = i / ringCount;
      final local = (progress - offset * 0.08).clamp(0.0, 1.0);
      if (local <= 0.001) {
        continue;
      }
      final radius = maxRadius * local;
      final opacity = (1 - local).clamp(0.0, 1.0) * 0.26;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 + (1 - local) * 1.4
        ..color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TunnelRingBurstPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _RiverStartupScreen extends StatefulWidget {
  const _RiverStartupScreen({super.key});

  @override
  State<_RiverStartupScreen> createState() => _RiverStartupScreenState();
}

class _RiverStartupScreenState extends State<_RiverStartupScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9800),
  )..repeat();
  late final AnimationController _dotsController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 980),
  )..repeat();
  late final AnimationController _logoTiltController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    _orbitController.dispose();
    _dotsController.dispose();
    _logoTiltController.dispose();
    super.dispose();
  }

  _StartupPalette _resolvePalette(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (isDark) {
      return _StartupPalette(
        moodLabel: '冷调',
        bgTop: const Color(0xFF061426),
        bgMid: const Color(0xFF081A2F),
        bgBottom: const Color(0xFF0A1E35),
        accentA: const Color(0xFF3BA4FF),
        accentB: const Color(0xFF6BD4FF),
        accentC: const Color(0xFF728DFF),
        textColor: Colors.white.withValues(alpha: 0.96),
        subTextColor: Colors.white.withValues(alpha: 0.72),
      );
    }
    return _StartupPalette(
      moodLabel: '暖调',
      bgTop: const Color(0xFFFFF4E9),
      bgMid: const Color(0xFFFFF8F2),
      bgBottom: const Color(0xFFFFFFFF),
      accentA: const Color(0xFFFF8A4B),
      accentB: const Color(0xFFFFB26B),
      accentC: const Color(0xFFEF6B8D),
      textColor: const Color(0xFF2A1D16),
      subTextColor: const Color(0xFF7D6355),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _resolvePalette(theme);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.bgTop, palette.bgMid, palette.bgBottom],
          ),
        ),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _orbitController,
              builder: (context, _) {
                final t = _orbitController.value * math.pi * 2;
                return Stack(
                  children: [
                    Positioned(
                      left: 18 + math.sin(t * 1.00) * 12,
                      top: 88 + math.cos(t * 0.66) * 22,
                      child: _LaunchGlowOrb(
                        size: 160,
                        color: palette.accentA.withValues(alpha: 0.15),
                      ),
                    ),
                    Positioned(
                      right: 12 + math.cos(t * 0.93) * 14,
                      top: 220 + math.sin(t * 0.72) * 18,
                      child: _LaunchGlowOrb(
                        size: 184,
                        color: palette.accentB.withValues(alpha: 0.12),
                      ),
                    ),
                    Positioned(
                      left: 44 + math.sin(t * 0.78) * 10,
                      bottom: 140 + math.cos(t * 0.61) * 16,
                      child: _LaunchGlowOrb(
                        size: 116,
                        color: palette.accentC.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                );
              },
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 236,
                    height: 236,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1.06).animate(
                            CurvedAnimation(
                              parent: _pulseController,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                          child: Container(
                            width: 212,
                            height: 212,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: palette.accentA.withValues(alpha: 0.22),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        RotationTransition(
                          turns: Tween<double>(begin: 0, end: 1).animate(
                            CurvedAnimation(
                              parent: _orbitController,
                              curve: Curves.linear,
                            ),
                          ),
                          child: CustomPaint(
                            size: const Size(186, 186),
                            painter: _OrbitDotsPainter(
                              color: palette.accentB.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        RotationTransition(
                          turns: Tween<double>(begin: -0.012, end: 0.012)
                              .animate(
                                CurvedAnimation(
                                  parent: _logoTiltController,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                          child: Container(
                            width: 122,
                            height: 122,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.96),
                                  palette.accentB.withValues(alpha: 0.55),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: palette.accentA.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return ColoredBox(
                                    color: palette.accentA,
                                    child: const Icon(
                                      Icons.waves_rounded,
                                      color: Colors.white,
                                      size: 46,
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
                  const SizedBox(height: 12),
                  Text(
                    '聚河畔',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: palette.textColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${palette.moodLabel}启动 · 连接 RiverSide 与 清水河畔',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.subTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _StartupLoadingDots(
                    animation: _dotsController,
                    color: palette.accentA,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: Text(
                '即将进入河畔时空隧道',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: palette.subTextColor,
                  fontWeight: FontWeight.w600,
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
    required this.moodLabel,
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.accentA,
    required this.accentB,
    required this.accentC,
    required this.textColor,
    required this.subTextColor,
  });

  final String moodLabel;
  final Color bgTop;
  final Color bgMid;
  final Color bgBottom;
  final Color accentA;
  final Color accentB;
  final Color accentC;
  final Color textColor;
  final Color subTextColor;
}

class _LaunchGlowOrb extends StatelessWidget {
  const _LaunchGlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _OrbitDotsPainter extends CustomPainter {
  const _OrbitDotsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final dotPaint = Paint()..color = color;
    for (var i = 0; i < 18; i++) {
      final t = i / 18 * math.pi * 2;
      final x = center.dx + math.cos(t) * radius;
      final y = center.dy + math.sin(t) * radius;
      final dotRadius = i % 3 == 0 ? 2.2 : 1.6;
      dotPaint.color = color.withValues(alpha: i % 2 == 0 ? 0.85 : 0.45);
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitDotsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _StartupLoadingDots extends StatelessWidget {
  const _StartupLoadingDots({required this.animation, required this.color});

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
          children: List<Widget>.generate(4, (index) {
            final offset = (progress - index * 0.18).abs();
            final normalized = (1 - offset.clamp(0.0, 1.0)).clamp(0.0, 1.0);
            final scale = 0.70 + normalized * 0.46;
            final opacity = 0.30 + normalized * 0.70;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 8.6,
                    height: 8.6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

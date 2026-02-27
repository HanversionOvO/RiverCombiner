import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:draggable_route/draggable_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/ai/river_ai_service.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/categories/riverside_category_utils.dart';
import 'package:river/core/categories/riverside_category_store.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/mini_apps/river_mini_app_install_store.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_repository.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_message_bus_models.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/realtime/riverside_message_bus_poller.dart';
import 'package:river/core/widgets/river_confirm_dialog.dart';
import 'package:river/features/mini_apps/mini_app_webview_page.dart';
import 'package:river/features/mine/riverside_profile_sheet.dart';
import 'package:river/features/search/search_page.dart';
import 'package:river/core/widgets/riverside_category_picker_sheet.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/core/widgets/river_snack_bar.dart';

// -----------------------------------------------------------------------------

part 'posts_page_widgets.dart';

ImageProvider<Object>? _miniAppIconProvider(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return NetworkImage(value);
  }
  if (uri != null && uri.scheme == 'file') {
    final file = File.fromUri(uri);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }
  final file = File(value);
  if (file.existsSync()) {
    return FileImage(file);
  }
  return null;
}

// -----------------------------------------------------------------------------
class _SecondFloorWeatherData {
  const _SecondFloorWeatherData({
    required this.province,
    required this.city,
    required this.district,
    required this.weather,
    required this.temperature,
    required this.windDirection,
    required this.windPower,
    required this.humidity,
    required this.reportTime,
  });

  final String province;
  final String city;
  final String district;
  final String weather;
  final int? temperature;
  final String windDirection;
  final String windPower;
  final int? humidity;
  final String reportTime;

  String get locationLabel {
    final region = <String>[
      province.trim(),
      city.trim(),
      district.trim(),
    ].where((item) => item.isNotEmpty).join(' ');
    return region.isEmpty ? '当前定位' : region;
  }
}

// -----------------------------------------------------------------------------
class PostsPageController {
  _PostsPageState? _state;

  void _attach(_PostsPageState state) {
    _state = state;
  }

  void _detach(_PostsPageState state) {
    if (_state == state) {
      _state = null;
    }
  }

  Future<void> scrollToTopAndRefresh() async {
    await _state?._scrollToTopAndRefresh();
  }
}

// -----------------------------------------------------------------------------

class _PostsSecondFloorLayer extends StatefulWidget {
  const _PostsSecondFloorLayer({
    required this.progress,
    required this.feedLabel,
    required this.weatherData,
    required this.loadingWeather,
    required this.weatherError,
    required this.onRefreshWeather,
    required this.onAiSummaryTap,
    required this.aiSummarizing,
    required this.miniApps,
    required this.onlineMiniApps,
    required this.loadingMiniApps,
    required this.miniAppsError,
    required this.onOpenMiniApp,
    required this.onOpenMiniAppSearch,
    required this.onReorderMiniApps,
    required this.onDeleteMiniApp,
    required this.onRefreshMiniApps,
    required this.bottomBarHeight,
    required this.bottomNavigationReserveHeight,
    required this.interactive,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double progress;
  final String feedLabel;
  final _SecondFloorWeatherData? weatherData;
  final bool loadingWeather;
  final String? weatherError;
  final VoidCallback onRefreshWeather;
  final VoidCallback onAiSummaryTap;
  final bool aiSummarizing;
  final List<RiverMiniAppEntry> miniApps;
  final List<RiverMiniAppEntry> onlineMiniApps;
  final bool loadingMiniApps;
  final String? miniAppsError;
  final ValueChanged<RiverMiniAppEntry> onOpenMiniApp;
  final VoidCallback onOpenMiniAppSearch;
  final ValueChanged<List<String>> onReorderMiniApps;
  final ValueChanged<RiverMiniAppEntry> onDeleteMiniApp;
  final VoidCallback onRefreshMiniApps;
  final double bottomBarHeight;
  final double bottomNavigationReserveHeight;
  final bool interactive;
  final Future<void> Function() onClose;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;

  @override
  State<_PostsSecondFloorLayer> createState() => _PostsSecondFloorLayerState();
}

class _PostsSecondFloorLayerState extends State<_PostsSecondFloorLayer>
    with SingleTickerProviderStateMixin {
  late List<RiverMiniAppEntry> _orderedMiniApps;
  late final AnimationController _fxController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7600),
  )..repeat();
  String? _draggingMiniAppId;
  String? _deleteHoverMiniAppId;
  bool _deleteAccepted = false;
  bool _orderDirty = false;

  bool _isLocalDevelopmentMiniApp(RiverMiniAppEntry item) {
    if (item.localEntryFilePath.trim().isEmpty) {
      return false;
    }
    final id = item.id.trim().toLowerCase();
    return item.packageUrl.trim().isEmpty || id.startsWith('local.');
  }

  @override
  void initState() {
    super.initState();
    _orderedMiniApps = List<RiverMiniAppEntry>.from(widget.miniApps);
  }

  @override
  void didUpdateWidget(covariant _PostsSecondFloorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingMiniAppId != null) {
      return;
    }
    if (_sameIds(_orderedMiniApps, widget.miniApps)) {
      return;
    }
    _orderedMiniApps = List<RiverMiniAppEntry>.from(widget.miniApps);
  }

  @override
  void dispose() {
    _fxController.dispose();
    super.dispose();
  }

  String _weatherLottieFor(String weather) {
    final normalized = weather.trim();
    if (normalized.contains('雷')) {
      return 'assets/lottie/weather/meteocons_thunderstorms.json';
    }
    if (normalized.contains('雪')) {
      return 'assets/lottie/weather/meteocons_snow.json';
    }
    if (normalized.contains('雨')) {
      return 'assets/lottie/weather/meteocons_rain.json';
    }
    if (normalized.contains('雾') || normalized.contains('霾')) {
      return 'assets/lottie/weather/meteocons_haze-day.json';
    }
    if (normalized.contains('阴') || normalized.contains('云')) {
      return 'assets/lottie/weather/meteocons_cloudy.json';
    }
    return 'assets/lottie/weather/meteocons_clear-day.json';
  }

  Widget _buildWeatherCard(ThemeData theme) {
    final weather = widget.weatherData;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final panelColor = theme.colorScheme.surfaceContainerLow;
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.28,
    );

    Widget body;
    if (widget.loadingWeather && weather == null) {
      body = Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在获取天气信息...',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else if ((widget.weatherError ?? '').isNotEmpty && weather == null) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.weatherError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新天气',
            onPressed: widget.onRefreshWeather,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
    } else if (weather != null) {
      final weatherAsset = _weatherLottieFor(weather.weather);
      final weatherTitle = weather.temperature == null
          ? weather.weather
          : '${weather.weather}  ${weather.temperature}°C';
      final windText = <String>[
        weather.windDirection.trim(),
        weather.windPower.trim(),
      ].where((item) => item.isNotEmpty).join(' ');
      final humidityText = weather.humidity == null
          ? ''
          : '湿度 ${weather.humidity}%';
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AnimatedBuilder(
              animation: _fxController,
              builder: (context, child) {
                final phase = _fxController.value * math.pi * 2;
                final dy = math.sin(phase) * 2.2;
                return Transform.translate(offset: Offset(0, dy), child: child);
              },
              child: Lottie.asset(
                weatherAsset,
                repeat: true,
                animate: true,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weather.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  weatherTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    windText,
                    humidityText,
                  ].where((item) => item.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  '更新于 ${weather.reportTime}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '刷新天气',
            onPressed: widget.onRefreshWeather,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Icon(
            Icons.cloud_queue_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '暂无天气信息',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新天气',
            onPressed: widget.onRefreshWeather,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: body,
    );
  }

  Widget _buildAiActionButton(ThemeData theme) {
    return AnimatedBuilder(
      animation: _fxController,
      builder: (context, _) {
        final phase = _fxController.value * math.pi * 2;
        final breathe = 0.92 + 0.08 * (math.sin(phase) * 0.5 + 0.5);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.aiSummarizing ? null : widget.onAiSummaryTap,
            borderRadius: BorderRadius.circular(999),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _AiSpectrumPainter(
                        phase: phase,
                        opacity: widget.aiSummarizing ? 0.78 : 1,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: theme.brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.white.withValues(alpha: 0.3),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.52)
                                : Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Transform.scale(
                        scale: breathe,
                        child: widget.aiSummarizing
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'AI思考中',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 15,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'AI一下',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _sameIds(List<RiverMiniAppEntry> a, List<RiverMiniAppEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  RiverMiniAppEntry? _findMiniApp(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    for (final item in _orderedMiniApps) {
      if (item.id == value) {
        return item;
      }
    }
    return null;
  }

  void _startMiniAppDrag(String id) {
    setState(() {
      _draggingMiniAppId = id;
      _deleteHoverMiniAppId = null;
      _deleteAccepted = false;
      _orderDirty = false;
    });
  }

  void _reorderMiniAppDuringDrag({
    required String draggingId,
    required String targetId,
  }) {
    final fromIndex = _orderedMiniApps.indexWhere(
      (item) => item.id == draggingId,
    );
    final toIndex = _orderedMiniApps.indexWhere((item) => item.id == targetId);
    if (fromIndex < 0 || toIndex < 0 || fromIndex == toIndex) {
      return;
    }
    setState(() {
      final item = _orderedMiniApps.removeAt(fromIndex);
      final insertAt = fromIndex < toIndex ? toIndex - 1 : toIndex;
      _orderedMiniApps.insert(insertAt, item);
      _orderDirty = true;
      _deleteHoverMiniAppId = null;
    });
  }

  void _endMiniAppDrag() {
    final shouldPersist = _orderDirty && !_deleteAccepted;
    final ids = _orderedMiniApps.map((item) => item.id).toList(growable: false);
    setState(() {
      _draggingMiniAppId = null;
      _deleteHoverMiniAppId = null;
      _deleteAccepted = false;
      _orderDirty = false;
    });
    if (shouldPersist) {
      widget.onReorderMiniApps(ids);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final t = widget.progress.clamp(0.0, 1.0);
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;
    final panelHeight = (media.size.height * t).clamp(0.0, media.size.height);
    final draggingMiniApp = _findMiniApp(_draggingMiniAppId);
    final draggingHoverDelete =
        draggingMiniApp != null && _deleteHoverMiniAppId == draggingMiniApp.id;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !widget.interactive,
            child: Container(
              color: Colors.black.withValues(alpha: lerpDouble(0.0, 0.34, t)!),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            ignoring: !widget.interactive,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: widget.onDragUpdate,
              onVerticalDragEnd: widget.onDragEnd,
              child: SizedBox(
                width: double.infinity,
                height: panelHeight,
                child: ClipRect(
                  child: Material(
                    color: theme.colorScheme.surface,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.surfaceContainerLowest,
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              topInset + 10,
                              12,
                              12,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '二楼',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  widget.feedLabel,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 104,
                                  child: _buildAiActionButton(theme),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: '搜索小程序',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: widget.onOpenMiniAppSearch,
                                  icon: const Icon(Icons.search_rounded),
                                ),
                                IconButton(
                                  tooltip: '关闭',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: widget.onClose,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              children: [
                                _buildWeatherCard(theme),
                                const SizedBox(height: 16),
                                Text(
                                  '我的小程序',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '长按小程序可排序或删除',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (widget.loadingMiniApps &&
                                    _orderedMiniApps.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    ),
                                  )
                                else if ((widget.miniAppsError ?? '')
                                        .isNotEmpty &&
                                    _orderedMiniApps.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.miniAppsError!,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        OutlinedButton.icon(
                                          onPressed: widget.onRefreshMiniApps,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('重试'),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_orderedMiniApps.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.widgets_outlined,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            widget.onlineMiniApps.isEmpty
                                                ? '暂无可用小程序，请先检查小程序清单地址。'
                                                : '暂无已添加小程序，请点击右上角搜索并添加。',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '刷新',
                                          onPressed: widget.onRefreshMiniApps,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      const spacing = 10.0;
                                      final itemWidth =
                                          (constraints.maxWidth - spacing * 3) /
                                          4;
                                      return Wrap(
                                        spacing: spacing,
                                        runSpacing: spacing,
                                        children: _orderedMiniApps
                                            .map(
                                              (item) => SizedBox(
                                                width: itemWidth,
                                                height: itemWidth * 0.99,
                                                child: DragTarget<_SecondFloorMiniAppDragData>(
                                                  onWillAcceptWithDetails:
                                                      (details) {
                                                        final dragId =
                                                            details.data.id;
                                                        if (dragId == item.id) {
                                                          return false;
                                                        }
                                                        _reorderMiniAppDuringDrag(
                                                          draggingId: dragId,
                                                          targetId: item.id,
                                                        );
                                                        return true;
                                                      },
                                                  builder: (context, candidates, rejected) {
                                                    final active = candidates
                                                        .whereType<
                                                          _SecondFloorMiniAppDragData
                                                        >()
                                                        .any(
                                                          (candidate) =>
                                                              candidate.id !=
                                                              item.id,
                                                        );
                                                    return AnimatedScale(
                                                      scale:
                                                          _draggingMiniAppId ==
                                                              item.id
                                                          ? 0.92
                                                          : 1.0,
                                                      duration: const Duration(
                                                        milliseconds: 180,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          border: Border.all(
                                                            color: active
                                                                ? theme
                                                                      .colorScheme
                                                                      .primary
                                                                : Colors
                                                                      .transparent,
                                                            width: active
                                                                ? 1.4
                                                                : 1,
                                                          ),
                                                        ),
                                                        child:
                                                            LongPressDraggable<
                                                              _SecondFloorMiniAppDragData
                                                            >(
                                                              data:
                                                                  _SecondFloorMiniAppDragData(
                                                                    item.id,
                                                                  ),
                                                              dragAnchorStrategy:
                                                                  pointerDragAnchorStrategy,
                                                              onDragStarted: () =>
                                                                  _startMiniAppDrag(
                                                                    item.id,
                                                                  ),
                                                              onDragEnd: (_) =>
                                                                  _endMiniAppDrag(),
                                                              feedback: Material(
                                                                color: Colors
                                                                    .transparent,
                                                                child: SizedBox(
                                                                  width:
                                                                      itemWidth,
                                                                  height:
                                                                      itemWidth *
                                                                      0.99,
                                                                  child: Transform.scale(
                                                                    scale: 1.04,
                                                                    child: _SecondFloorMiniAppItem(
                                                                      icon: Icons
                                                                          .widgets_outlined,
                                                                      iconUrl: item
                                                                          .iconUrl,
                                                                      label: item
                                                                          .name,
                                                                      tooltip: item
                                                                          .description,
                                                                      isDevelopment:
                                                                          _isLocalDevelopmentMiniApp(
                                                                            item,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              childWhenDragging: Opacity(
                                                                opacity: 0.14,
                                                                child: _SecondFloorMiniAppItem(
                                                                  icon: Icons
                                                                      .widgets_outlined,
                                                                  iconUrl: item
                                                                      .iconUrl,
                                                                  label:
                                                                      item.name,
                                                                  tooltip: item
                                                                      .description,
                                                                  isDevelopment:
                                                                      _isLocalDevelopmentMiniApp(
                                                                        item,
                                                                      ),
                                                                ),
                                                              ),
                                                              child: _SecondFloorMiniAppItem(
                                                                icon: Icons
                                                                    .widgets_outlined,
                                                                iconUrl: item
                                                                    .iconUrl,
                                                                label:
                                                                    item.name,
                                                                tooltip: item
                                                                    .description,
                                                                isDevelopment:
                                                                    _isLocalDevelopmentMiniApp(
                                                                      item,
                                                                    ),
                                                                onTap: () => widget
                                                                    .onOpenMiniApp(
                                                                      item,
                                                                    ),
                                                              ),
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                            child: DragTarget<_SecondFloorMiniAppDragData>(
                              onWillAcceptWithDetails: (details) {
                                if (_draggingMiniAppId == null) {
                                  return false;
                                }
                                setState(() {
                                  _deleteHoverMiniAppId = details.data.id;
                                });
                                return true;
                              },
                              onLeave: (_) {
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _deleteHoverMiniAppId = null;
                                });
                              },
                              onAcceptWithDetails: (details) {
                                final target = _findMiniApp(details.data.id);
                                if (target == null) {
                                  return;
                                }
                                setState(() {
                                  _deleteAccepted = true;
                                  _deleteHoverMiniAppId = details.data.id;
                                  _orderedMiniApps.removeWhere(
                                    (item) => item.id == details.data.id,
                                  );
                                });
                                widget.onDeleteMiniApp(target);
                              },
                              builder: (context, candidates, rejected) {
                                final dragging = draggingMiniApp != null;
                                final deleteAreaHeight =
                                    widget.bottomBarHeight +
                                    bottomInset +
                                    widget.bottomNavigationReserveHeight;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  height: deleteAreaHeight,
                                  decoration: BoxDecoration(
                                    color: dragging
                                        ? (draggingHoverDelete
                                              ? theme.colorScheme.errorContainer
                                                    .withValues(alpha: 0.92)
                                              : theme
                                                    .colorScheme
                                                    .tertiaryContainer
                                                    .withValues(alpha: 0.72))
                                        : Colors.transparent,
                                  ),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        0,
                                      ),
                                      child: SizedBox(
                                        height: widget.bottomBarHeight - 8,
                                        child: Row(
                                          children: [
                                            Icon(
                                              dragging
                                                  ? (draggingHoverDelete
                                                        ? Icons.delete_rounded
                                                        : Icons
                                                              .delete_outline_rounded)
                                                  : Icons.layers_rounded,
                                              size: 18,
                                              color: dragging
                                                  ? (draggingHoverDelete
                                                        ? theme
                                                              .colorScheme
                                                              .onErrorContainer
                                                        : theme
                                                              .colorScheme
                                                              .onTertiaryContainer)
                                                  : theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              dragging
                                                  ? (draggingHoverDelete
                                                        ? '删除 ${draggingMiniApp.name}'
                                                        : '拖动到此删除小程序')
                                                  : '二楼',
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: dragging
                                                        ? (draggingHoverDelete
                                                              ? theme
                                                                    .colorScheme
                                                                    .onErrorContainer
                                                              : theme
                                                                    .colorScheme
                                                                    .onTertiaryContainer)
                                                        : null,
                                                  ),
                                            ),
                                            const Spacer(),
                                            if (!dragging) ...[
                                              Text(
                                                '当前：${widget.feedLabel}',
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(width: 10),
                                              Icon(
                                                Icons.keyboard_arrow_up_rounded,
                                                size: 18,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                '上滑返回',
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ] else ...[
                                              Text(
                                                draggingHoverDelete
                                                    ? '松手删除'
                                                    : '松手取消',
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: draggingHoverDelete
                                                          ? theme
                                                                .colorScheme
                                                                .onErrorContainer
                                                          : theme
                                                                .colorScheme
                                                                .onTertiaryContainer,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
      ],
    );
  }
}

class _AiSpectrumPainter extends CustomPainter {
  const _AiSpectrumPainter({required this.phase, required this.opacity});

  final double phase;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..color = const Color(0xFFFDF9FF).withValues(alpha: 0.92);
    canvas.drawRect(rect, base);

    final dx1 = math.sin(phase) * size.width * 0.22;
    final dx2 = math.cos(phase * 1.14) * size.width * 0.22;
    final dx3 = math.sin(phase * 0.88 + 1.5) * size.width * 0.22;
    const c1 = Color(0xFFFFCEDA);
    const c2 = Color(0xFFCFF9DA);
    const c3 = Color(0xFFCCE0FF);

    final first = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          c1.withValues(alpha: 0.7 * opacity),
          c1.withValues(alpha: 0),
        ],
      ).createShader(rect.shift(Offset(dx1, 0)));
    canvas.drawRect(rect, first);

    final second = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.topRight,
        colors: [
          c2.withValues(alpha: 0.68 * opacity),
          c2.withValues(alpha: 0),
        ],
      ).createShader(rect.shift(Offset(dx2, 0)));
    canvas.drawRect(rect, second);

    final third = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.topLeft,
        colors: [
          c3.withValues(alpha: 0.7 * opacity),
          c3.withValues(alpha: 0),
        ],
      ).createShader(rect.shift(Offset(dx3, 0)));
    canvas.drawRect(rect, third);
  }

  @override
  bool shouldRepaint(covariant _AiSpectrumPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.opacity != opacity;
  }
}

class _SecondFloorMiniAppDragData {
  const _SecondFloorMiniAppDragData(this.id);

  final String id;
}

class _SecondFloorMiniAppItem extends StatelessWidget {
  const _SecondFloorMiniAppItem({
    required this.icon,
    required this.label,
    this.isDevelopment = false,
    this.iconUrl = '',
    this.tooltip = '',
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDevelopment;
  final String iconUrl;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = iconUrl.trim();
    final iconProvider = _miniAppIconProvider(avatarUrl);
    final initials = label.trim().isEmpty ? 'A' : label.trim().substring(0, 1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (iconProvider == null)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else
                      ClipOval(
                        child: Image(
                          image: iconProvider,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, errorObject, stackTraceObject) =>
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      initials,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                        ),
                      ),
                    const SizedBox(height: 7),
                    Tooltip(
                      message: tooltip.trim().isEmpty ? label : tooltip,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDevelopment)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.tertiary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Text(
                      '开发版',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        height: 1.1,
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

class _OnlineMiniAppSearchTile extends StatelessWidget {
  const _OnlineMiniAppSearchTile({
    required this.app,
    required this.installed,
    required this.installing,
    required this.onTapCard,
  });

  final RiverMiniAppEntry app;
  final bool installed;
  final bool installing;
  final VoidCallback onTapCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = app.iconUrl.trim();
    final iconProvider = _miniAppIconProvider(iconUrl);
    final initials = app.name.trim().isEmpty ? 'A' : app.name.trim()[0];
    final status = app.reviewStatus.trim().toUpperCase();
    final statusLabel = switch (status) {
      'APPROVED' || 'ONLINE' => '',
      'REJECTED' => '已拒绝',
      'PENDING' => '审核中',
      _ => '',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTapCard,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              if (iconProvider == null)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.14,
                  ),
                  child: Text(
                    initials,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                ClipOval(
                  child: Image(
                    image: iconProvider,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (context, errorObject, stackTraceObject) =>
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          child: Text(
                            initials,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (statusLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (app.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        app.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (app.version.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '版本 ${app.version}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (installing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onTapCard,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                  ),
                  icon: Icon(
                    installed ? Icons.open_in_new_rounded : Icons.info_outline,
                    size: 16,
                  ),
                  label: Text(installed ? '打开' : '详情'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PostsForumProvider { riverSide, qingShuiHePan }

extension _PostsForumProviderX on _PostsForumProvider {
  String get logoAsset => switch (this) {
    _PostsForumProvider.riverSide => 'assets/images/rs.png',
    _PostsForumProvider.qingShuiHePan => 'assets/images/hp.png',
  };
}

class _MiniAppMetaRow extends StatelessWidget {
  const _MiniAppMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
class PostsPage extends StatefulWidget {
  const PostsPage({
    super.key,
    required this.dependencies,
    this.controller,
    this.onSecondFloorVisibilityChanged,
    this.onSecondFloorProgressChanged,
  });

  final AppDependencies dependencies;
  final PostsPageController? controller;
  final ValueChanged<bool>? onSecondFloorVisibilityChanged;
  final ValueChanged<double>? onSecondFloorProgressChanged;

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> with TickerProviderStateMixin {
  static const String _latestTopicChannel = '/latest';
  static const String _presenceMessageBusChannel =
      '/presence/whos-online/online';
  static const String _presenceStateChannelName = '/whos-online/online';
  static const double _secondFloorBottomBarHeight = 52;
  static const double _secondFloorBottomNavReserveHeight = 64;

  List<RiverSideCategoryOption> _categories = [];
  bool _loadingCategories = false;
  bool _loadingQingCategories = false;

  int? _selectedBoardId;
  String? _selectedBoardName;

  late TabController _tabController;
  final List<RiverSideTopicFeed> _feeds = RiverSideTopicFeed.values;

  int _filterVersion = 0;

  final Map<int, GlobalKey<_TopicListTabState>> _tabKeys = {};
  String? _lastActiveRiverUsername;
  String? _lastActiveQingUsername;
  _PostsForumProvider _forumProvider = _PostsForumProvider.riverSide;
  RiverSideMessageBusPoller? _messageBusPoller;
  bool _hasRealtimeTopicUpdate = false;
  double _headerScrollFactor = 0;
  int _pollingBootstrapSerial = 0;

  final Map<String, _OnlineUserPreview> _knownUserPreviewsByUsername =
      <String, _OnlineUserPreview>{};
  final Map<int, String> _knownOnlineUsernameById = <int, String>{};
  final Set<int> _onlineUserIds = <int>{};
  final Set<String> _onlineUsernames = <String>{};
  int _onlineUsersCount = 0;
  final GlobalKey _onlineUsersPillKey = GlobalKey();
  int? _riverSelectedBoardId;
  String? _riverSelectedBoardName;
  List<RiverSideCategoryOption> _riverCategories =
      const <RiverSideCategoryOption>[];
  int? _qingSelectedBoardId;
  String? _qingSelectedBoardName;
  List<RiverSideCategoryOption> _qingCategories =
      const <RiverSideCategoryOption>[];
  StreamSubscription<int>? _miniAppsChangedSubscription;
  late final AnimationController _secondFloorController;
  double _secondFloorPullDistance = 0;
  bool _secondFloorArmed = false;
  bool _secondFloorVisibleForParent = false;
  bool _secondFloorOpened = false;
  final RiverMiniAppRepository _miniAppRepository = RiverMiniAppRepository();
  final RiverMiniAppInstallStore _miniAppInstallStore =
      RiverMiniAppInstallStore();
  List<RiverMiniAppEntry> _miniApps = const <RiverMiniAppEntry>[];
  List<RiverMiniAppEntry> _onlineMiniApps = const <RiverMiniAppEntry>[];
  final Set<String> _installingMiniAppIds = <String>{};
  bool _loadingMiniApps = false;
  String? _miniAppsError;
  String _lastMiniAppsManifestUrl = '';
  final Map<int, List<RiverSideTopicSummary>> _tabTopicSnapshotsByIndex =
      <int, List<RiverSideTopicSummary>>{};
  _SecondFloorWeatherData? _secondFloorWeatherData;
  bool _loadingSecondFloorWeather = false;
  String? _secondFloorWeatherError;
  Timer? _secondFloorWeatherTimer;
  bool _summarizingTodayForumByAi = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _lastActiveRiverUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    _lastActiveQingUsername =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    _forumProvider = _resolveInitialForumProvider();
    widget.dependencies.accountStore.addListener(_onAccountStoreChanged);
    widget.dependencies.settingsController.addListener(
      _onRefreshBannerSettingsChanged,
    );
    _tabController = TabController(length: _feeds.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _secondFloorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _secondFloorController.addListener(_onSecondFloorProgressChanged);
    _lastMiniAppsManifestUrl =
        widget.dependencies.settingsController.miniAppsManifestUrl;
    _miniAppsChangedSubscription = RiverMiniAppInstallStore.installedAppsChanged
        .listen((_) {
          if (!mounted) {
            return;
          }
          unawaited(_loadInstalledMiniApps());
        });
    _loadCategories();
    _startSecondFloorWeatherRefreshTimer();
    unawaited(_loadSecondFloorWeather(force: true));
    unawaited(_loadInstalledMiniApps());
    unawaited(_loadMiniApps(forceRefresh: false));
    _restartRealtimePolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncHeaderWithCurrentTab();
    });
  }

  @override
  void dispose() {
    _messageBusPoller?.stop();
    widget.dependencies.accountStore.removeListener(_onAccountStoreChanged);
    widget.dependencies.settingsController.removeListener(
      _onRefreshBannerSettingsChanged,
    );
    widget.controller?._detach(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _miniAppsChangedSubscription?.cancel();
    _miniAppsChangedSubscription = null;
    _secondFloorWeatherTimer?.cancel();
    _secondFloorWeatherTimer = null;
    _secondFloorController.removeListener(_onSecondFloorProgressChanged);
    _secondFloorController.dispose();
    if (_secondFloorVisibleForParent) {
      widget.onSecondFloorVisibilityChanged?.call(false);
    }
    super.dispose();
  }

  bool get _showPostsRealtimeRefreshBanner {
    return widget
        .dependencies
        .settingsController
        .showPostsRealtimeRefreshBanner;
  }

  void _onSecondFloorProgressChanged() {
    final progress = _secondFloorController.value.clamp(0.0, 1.0);
    widget.onSecondFloorProgressChanged?.call(progress);
    final visible = progress > 0.01;
    if (visible == _secondFloorVisibleForParent) {
      return;
    }
    _secondFloorVisibleForParent = visible;
    widget.onSecondFloorVisibilityChanged?.call(visible);
  }

  void _onRefreshBannerSettingsChanged() {
    final nextMiniAppsManifestUrl =
        widget.dependencies.settingsController.miniAppsManifestUrl;
    if (nextMiniAppsManifestUrl != _lastMiniAppsManifestUrl) {
      _lastMiniAppsManifestUrl = nextMiniAppsManifestUrl;
      unawaited(_loadMiniApps(forceRefresh: true));
    }
    if (!mounted) {
      return;
    }
    if (!_showPostsRealtimeRefreshBanner && _hasRealtimeTopicUpdate) {
      setState(() {
        _hasRealtimeTopicUpdate = false;
      });
      return;
    }
    setState(() {});
  }

  void _onAccountStoreChanged() {
    final currentRiver =
        widget.dependencies.accountStore.activeRiverSideUsername;
    final currentQing =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (currentRiver == _lastActiveRiverUsername &&
        currentQing == _lastActiveQingUsername) {
      return;
    }
    _lastActiveRiverUsername = currentRiver;
    _lastActiveQingUsername = currentQing;
    _messageBusPoller?.stop();
    _messageBusPoller = null;

    final previousForum = _forumProvider;
    _stashBoardFilterForForum(previousForum);
    if (!_isForumAvailable(_forumProvider)) {
      _forumProvider = _resolveInitialForumProvider();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasRealtimeTopicUpdate = false;
      _filterVersion++;
      _tabTopicSnapshotsByIndex.clear();
      _onlineUserIds.clear();
      _onlineUsernames.clear();
      _knownOnlineUsernameById.clear();
      _onlineUsersCount = 0;
      _knownUserPreviewsByUsername.clear();
      _restoreBoardFilterForForum(_forumProvider);
    });
    unawaited(_loadCategories(forceRefresh: true));
    unawaited(_loadMiniApps(forceRefresh: true));
    unawaited(_scrollToTopAndRefresh());
    _restartRealtimePolling();
  }

  String? _activeCookieHeader() {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(username);
  }

  _PostsForumProvider _resolveInitialForumProvider() {
    final preferred =
        widget.dependencies.settingsController.homeForumPreference ==
            AppHomeForumPreference.qingShuiHePan
        ? _PostsForumProvider.qingShuiHePan
        : _PostsForumProvider.riverSide;
    final fallback = preferred == _PostsForumProvider.riverSide
        ? _PostsForumProvider.qingShuiHePan
        : _PostsForumProvider.riverSide;
    if (_isForumAvailable(preferred)) {
      return preferred;
    }
    if (_isForumAvailable(fallback)) {
      return fallback;
    }
    return preferred;
  }

  bool _isForumAvailable(_PostsForumProvider forum) {
    switch (forum) {
      case _PostsForumProvider.riverSide:
        final username =
            widget.dependencies.accountStore.activeRiverSideUsername;
        return username != null && username.trim().isNotEmpty;
      case _PostsForumProvider.qingShuiHePan:
        final username =
            widget.dependencies.accountStore.activeQingShuiHePanUsername;
        if (username == null || username.trim().isEmpty) {
          return false;
        }
        final auth = widget.dependencies.accountStore.qingShuiHePanAuthFor(
          username,
        );
        return auth != null;
    }
  }

  void _stashBoardFilterForForum(_PostsForumProvider forum) {
    switch (forum) {
      case _PostsForumProvider.riverSide:
        _riverSelectedBoardId = _selectedBoardId;
        _riverSelectedBoardName = _selectedBoardName;
        _riverCategories = List<RiverSideCategoryOption>.from(_categories);
        break;
      case _PostsForumProvider.qingShuiHePan:
        _qingSelectedBoardId = _selectedBoardId;
        _qingSelectedBoardName = _selectedBoardName;
        _qingCategories = List<RiverSideCategoryOption>.from(_categories);
        break;
    }
  }

  void _restoreBoardFilterForForum(_PostsForumProvider forum) {
    switch (forum) {
      case _PostsForumProvider.riverSide:
        _selectedBoardId = _riverSelectedBoardId;
        _selectedBoardName = _riverSelectedBoardName;
        _categories = List<RiverSideCategoryOption>.from(_riverCategories);
        break;
      case _PostsForumProvider.qingShuiHePan:
        _selectedBoardId = _qingSelectedBoardId;
        _selectedBoardName = _qingSelectedBoardName;
        _categories = List<RiverSideCategoryOption>.from(_qingCategories);
        break;
    }
  }

  Future<void> _switchForum(_PostsForumProvider target) async {
    if (_forumProvider == target) {
      return;
    }
    if (!_isForumAvailable(target)) {
      final message = switch (target) {
        _PostsForumProvider.riverSide => '请先登录 RiverSide 账号',
        _PostsForumProvider.qingShuiHePan => '请先登录清水河畔账号',
      };
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar(message);
      return;
    }

    _messageBusPoller?.stop();
    _messageBusPoller = null;
    _stashBoardFilterForForum(_forumProvider);

    setState(() {
      _forumProvider = target;
      _hasRealtimeTopicUpdate = false;
      _filterVersion++;
      _restoreBoardFilterForForum(target);
      _onlineUserIds.clear();
      _onlineUsernames.clear();
      _knownOnlineUsernameById.clear();
      _knownUserPreviewsByUsername.clear();
      _onlineUsersCount = 0;
    });

    await _loadCategories();
    unawaited(_scrollToTopAndRefresh());
    _restartRealtimePolling();
  }

  Future<void> _toggleForum() async {
    final target = _forumProvider == _PostsForumProvider.riverSide
        ? _PostsForumProvider.qingShuiHePan
        : _PostsForumProvider.riverSide;
    await _switchForum(target);
  }

  void _restartRealtimePolling() {
    _messageBusPoller?.stop();
    _messageBusPoller = null;

    if (_forumProvider != _PostsForumProvider.riverSide) {
      return;
    }

    final cookie = _activeCookieHeader();
    if (cookie == null || cookie.trim().isEmpty) {
      return;
    }
    final bootstrapSerial = ++_pollingBootstrapSerial;
    unawaited(
      _bootstrapRealtimePolling(
        bootstrapSerial: bootstrapSerial,
        cookieHeader: cookie,
      ),
    );
  }

  Future<void> _bootstrapRealtimePolling({
    required int bootstrapSerial,
    required String cookieHeader,
  }) async {
    final apiClient = widget.dependencies.accountStore.riverSideApiClient;
    var presenceLastMessageId = -1;

    try {
      final presenceState = await apiClient.fetchPresenceChannelState(
        channelName: _presenceStateChannelName,
        cookieHeader: cookieHeader,
      );
      if (!mounted || bootstrapSerial != _pollingBootstrapSerial) {
        return;
      }
      if (presenceState != null) {
        presenceLastMessageId = presenceState.lastMessageId;
        if (!presenceState.countOnly) {
          _applyPresenceSnapshot(
            presenceState.users,
            count: presenceState.count,
          );
        } else {
          _applyPresenceCountOnly(presenceState.count);
        }
      }
    } catch (_) {
      // Keep poller resilient even if presence bootstrap fails.
    }
    if (!mounted || bootstrapSerial != _pollingBootstrapSerial) {
      return;
    }

    final channelLastIds = <String, int>{
      _latestTopicChannel: -1,
      _presenceMessageBusChannel: presenceLastMessageId,
    };
    final poller = RiverSideMessageBusPoller(
      apiClient: apiClient,
      cookieHeader: cookieHeader,
      channelLastIds: channelLastIds,
      onEvents: (events) {
        if (!mounted || events.isEmpty) {
          return;
        }
        var hasLatestEvent = false;
        for (final event in events) {
          if (event.channel == _latestTopicChannel) {
            hasLatestEvent = true;
            continue;
          }
          if (event.channel == _presenceMessageBusChannel) {
            _consumePresenceEventData(event.data);
          }
        }
        if (!hasLatestEvent || _hasRealtimeTopicUpdate) {
          return;
        }
        if (!_showPostsRealtimeRefreshBanner) {
          return;
        }
        setState(() {
          _hasRealtimeTopicUpdate = true;
        });
      },
    );
    if (bootstrapSerial != _pollingBootstrapSerial) {
      poller.stop();
      return;
    }
    _messageBusPoller = poller;
    poller.start();
  }

  void _applyPresenceCountOnly(int count) {
    final nextCount = count < 0 ? 0 : count;
    if (!mounted) {
      return;
    }
    if (_onlineUsersCount == nextCount &&
        _onlineUserIds.isEmpty &&
        _onlineUsernames.isEmpty) {
      return;
    }
    setState(() {
      _onlineUsersCount = nextCount;
      _onlineUserIds.clear();
      _onlineUsernames.clear();
      _knownOnlineUsernameById.clear();
    });
  }

  void _applyPresenceSnapshot(
    Iterable<RiverSidePresenceUser> users, {
    int? count,
  }) {
    final nextOnlineIds = <int>{};
    final nextOnlineUsernames = <String>{};
    for (final user in users) {
      if (user.id > 0) {
        nextOnlineIds.add(user.id);
      }
      final normalizedUsername = _normalizePresenceUsername(user.username);
      if (normalizedUsername.isNotEmpty) {
        nextOnlineUsernames.add(normalizedUsername);
      }
      if (user.id > 0 && normalizedUsername.isNotEmpty) {
        _knownOnlineUsernameById[user.id] = normalizedUsername;
      }
    }

    final nextCount = _resolvePresenceCount(
      explicitCount: count,
      usernamesCount: nextOnlineUsernames.length,
      idsCount: nextOnlineIds.length,
    );
    if (!mounted) {
      return;
    }
    if (_onlineUsersCount == nextCount &&
        _setEquals(_onlineUserIds, nextOnlineIds) &&
        _setEquals(_onlineUsernames, nextOnlineUsernames)) {
      return;
    }
    setState(() {
      _onlineUserIds
        ..clear()
        ..addAll(nextOnlineIds);
      _onlineUsernames
        ..clear()
        ..addAll(nextOnlineUsernames);
      _onlineUsersCount = nextCount;
    });
  }

  bool _consumePresenceEventData(dynamic rawData) {
    final payload = _decodePresencePayload(rawData);
    if (payload is List) {
      final users = _parsePresenceUsers(payload);
      _applyPresenceSnapshot(users);
      return true;
    }

    if (payload is! Map) {
      return false;
    }
    final data = _toStringDynamicMap(payload);
    if (data.isEmpty) {
      return false;
    }

    final usersRaw = _readListField(data, const <String>['users']);
    if (usersRaw != null) {
      _applyPresenceSnapshot(
        _parsePresenceUsers(usersRaw),
        count: _parseInt(data['count']),
      );
      return true;
    }

    final enteringUsersRaw = _readListField(data, const <String>[
      'entering_users',
      'online_users',
    ]);
    final leavingUserIdsRaw = _readListField(data, const <String>[
      'leaving_user_ids',
    ]);
    final explicitCount = _parseInt(data['count']);

    final nextIds = <int>{..._onlineUserIds};
    final nextUsernames = <String>{..._onlineUsernames};
    var changed = false;

    if (enteringUsersRaw != null) {
      for (final user in _parsePresenceUsers(enteringUsersRaw)) {
        if (user.id > 0) {
          changed = nextIds.add(user.id) || changed;
        }
        final normalized = _normalizePresenceUsername(user.username);
        if (normalized.isNotEmpty) {
          changed = nextUsernames.add(normalized) || changed;
        }
        if (user.id > 0 && normalized.isNotEmpty) {
          _knownOnlineUsernameById[user.id] = normalized;
        }
      }
    }

    if (leavingUserIdsRaw != null) {
      for (final userId in _parsePresenceUserIds(leavingUserIdsRaw)) {
        final removed = nextIds.remove(userId);
        if (!removed) {
          continue;
        }
        changed = true;
        final username = _knownOnlineUsernameById[userId];
        if (username != null) {
          nextUsernames.remove(username);
        }
      }
    }

    final nextCount = _resolvePresenceCount(
      explicitCount: explicitCount,
      usernamesCount: nextUsernames.length,
      idsCount: nextIds.length,
    );
    if (!mounted) {
      return false;
    }
    if (!changed &&
        _onlineUsersCount == nextCount &&
        _setEquals(_onlineUserIds, nextIds) &&
        _setEquals(_onlineUsernames, nextUsernames)) {
      return false;
    }
    setState(() {
      _onlineUserIds
        ..clear()
        ..addAll(nextIds);
      _onlineUsernames
        ..clear()
        ..addAll(nextUsernames);
      _onlineUsersCount = nextCount;
    });
    return true;
  }

  dynamic _decodePresencePayload(dynamic rawData) {
    if (rawData is String) {
      final source = rawData.trim();
      if (source.isEmpty) {
        return null;
      }
      if ((source.startsWith('{') && source.endsWith('}')) ||
          (source.startsWith('[') && source.endsWith(']'))) {
        try {
          return jsonDecode(source);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    return rawData;
  }

  Map<String, dynamic> _toStringDynamicMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      result['${entry.key}'] = entry.value;
    }
    return result;
  }

  List<dynamic>? _readListField(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value;
      }
    }
    return null;
  }

  List<RiverSidePresenceUser> _parsePresenceUsers(List<dynamic> rawUsers) {
    final users = <RiverSidePresenceUser>[];
    for (final rawUser in rawUsers) {
      final map = _toStringDynamicMap(rawUser);
      if (map.isNotEmpty) {
        final id = _parseInt(map['id']) ?? 0;
        final username = (map['username'] ?? '').toString().trim();
        if (id > 0 || username.isNotEmpty) {
          users.add(RiverSidePresenceUser(id: id, username: username));
        }
        continue;
      }

      final id = _parseInt(rawUser);
      if (id != null && id > 0) {
        users.add(RiverSidePresenceUser(id: id, username: ''));
        continue;
      }

      final username = '$rawUser'.trim();
      if (username.isNotEmpty) {
        users.add(RiverSidePresenceUser(id: 0, username: username));
      }
    }
    return users;
  }

  List<int> _parsePresenceUserIds(List<dynamic> rawIds) {
    final ids = <int>[];
    for (final raw in rawIds) {
      final id = _parseInt(raw);
      if (id != null && id > 0) {
        ids.add(id);
      }
    }
    return ids;
  }

  int _resolvePresenceCount({
    required int? explicitCount,
    required int usernamesCount,
    required int idsCount,
  }) {
    if (explicitCount != null && explicitCount >= 0) {
      return explicitCount;
    }
    final fallback = usernamesCount > idsCount ? usernamesCount : idsCount;
    return fallback < 0 ? 0 : fallback;
  }

  int? _parseInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  String _normalizePresenceUsername(String source) {
    return source.trim().toLowerCase();
  }

  bool _setEquals<T>(Set<T> left, Set<T> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final item in left) {
      if (!right.contains(item)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _consumeRealtimeTopicUpdate() async {
    if (_hasRealtimeTopicUpdate && mounted) {
      setState(() {
        _hasRealtimeTopicUpdate = false;
      });
    }
    await _scrollToTopAndRefresh();
  }

  void _dismissRealtimeTopicUpdateHint() {
    if (!_hasRealtimeTopicUpdate || !mounted) {
      return;
    }
    setState(() {
      _hasRealtimeTopicUpdate = false;
    });
  }

  void _startSecondFloorWeatherRefreshTimer() {
    _secondFloorWeatherTimer?.cancel();
    _secondFloorWeatherTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      unawaited(_loadSecondFloorWeather(force: true));
    });
  }

  Future<void> _loadSecondFloorWeather({bool force = false}) async {
    if (_loadingSecondFloorWeather) {
      return;
    }
    if (!force && _secondFloorWeatherData != null) {
      return;
    }
    if (mounted) {
      setState(() {
        _loadingSecondFloorWeather = true;
        _secondFloorWeatherError = null;
      });
    } else {
      _loadingSecondFloorWeather = true;
      _secondFloorWeatherError = null;
    }
    try {
      final response = await http
          .get(
            Uri.parse('https://uapis.cn/api/v1/misc/weather'),
            headers: const <String, String>{
              'Accept': 'application/json, text/plain, */*',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RiverSideApiException('天气加载失败（HTTP ${response.statusCode}）');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const RiverSideApiException('天气数据格式异常');
      }
      final map = decoded.map((key, value) => MapEntry('$key', value));
      final weather = _SecondFloorWeatherData(
        province: '${map['province'] ?? ''}'.trim(),
        city: '${map['city'] ?? ''}'.trim(),
        district: '${map['district'] ?? ''}'.trim(),
        weather: '${map['weather'] ?? ''}'.trim().isEmpty
            ? '未知天气'
            : '${map['weather'] ?? ''}'.trim(),
        temperature: _parseInt(map['temperature']),
        windDirection: '${map['wind_direction'] ?? ''}'.trim(),
        windPower: '${map['wind_power'] ?? ''}'.trim(),
        humidity: _parseInt(map['humidity']),
        reportTime: '${map['report_time'] ?? ''}'.trim(),
      );
      if (!mounted) {
        _secondFloorWeatherData = weather;
        _loadingSecondFloorWeather = false;
        return;
      }
      setState(() {
        _secondFloorWeatherData = weather;
        _loadingSecondFloorWeather = false;
        _secondFloorWeatherError = null;
      });
    } catch (error) {
      if (!mounted) {
        _loadingSecondFloorWeather = false;
        _secondFloorWeatherError = '$error';
        return;
      }
      setState(() {
        _loadingSecondFloorWeather = false;
        _secondFloorWeatherError = '$error';
      });
    }
  }

  bool _isTodayTopic(DateTime? createdAt, DateTime now) {
    if (createdAt == null) {
      return false;
    }
    final local = createdAt.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  String _formatTopicTimeForAi(DateTime? value) {
    if (value == null) {
      return '--:--';
    }
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _buildTodayTopicDigestText(List<RiverSideTopicSummary> topics) {
    final buffer = StringBuffer();
    for (var index = 0; index < topics.length; index++) {
      final topic = topics[index];
      final category = topic.categoryName.trim().isEmpty
          ? '未分类'
          : topic.categoryName.trim();
      final title = topic.title.trim().isEmpty ? '(无标题)' : topic.title.trim();
      final author = topic.authorDisplayName.trim().isEmpty
          ? topic.authorUsername.trim()
          : topic.authorDisplayName.trim();
      final excerpt = topic.excerpt.replaceAll('\n', ' ').trim();
      buffer.writeln(
        '${index + 1}. [$category] $title | 作者:$author | '
        '回复:${topic.replyCount} 浏览:${topic.viewCount} | '
        '时间:${_formatTopicTimeForAi(topic.createdAt)}',
      );
      if (excerpt.isNotEmpty) {
        buffer.writeln('摘要: $excerpt');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  Future<List<RiverSideTopicSummary>> _fetchQingTopicsForAiPage({
    required RiverSideTopicFeed feed,
    required int page,
    required int? boardId,
  }) async {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (username == null || username.trim().isEmpty) {
      return const <RiverSideTopicSummary>[];
    }
    final auth = widget.dependencies.accountStore.qingShuiHePanAuthFor(
      username,
    );
    if (auth == null) {
      return const <RiverSideTopicSummary>[];
    }
    final endpoint =
        '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
    final requestBody = <String, String>{
      'r': 'forum/topiclist',
      'isImageList': '1',
      'sortby': switch (feed) {
        RiverSideTopicFeed.latestCreated => 'new',
        RiverSideTopicFeed.latestReplied => 'all',
        RiverSideTopicFeed.hot => 'marrow',
      },
      'page': '${page + 1}',
      'pageSize': '20',
      'accessToken': auth.token,
      'accessSecret': auth.secret,
    };
    if (boardId != null && boardId > 0) {
      requestBody['boardId'] = '$boardId';
    }

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: const <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: _encodeQingForm(requestBody),
        )
        .timeout(const Duration(seconds: 14));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      return const <RiverSideTopicSummary>[];
    }
    final map = decoded.map((key, value) => MapEntry('$key', value));
    if ('${map['rs']}' == '0') {
      return const <RiverSideTopicSummary>[];
    }
    final listRaw = map['list'];
    if (listRaw is! List) {
      return const <RiverSideTopicSummary>[];
    }
    final topics = <RiverSideTopicSummary>[];
    for (final raw in listRaw) {
      if (raw is! Map) {
        continue;
      }
      final item = raw.map((key, value) => MapEntry('$key', value));
      final topicId = _parseInt(item['topic_id']) ?? _parseInt(item['id']) ?? 0;
      if (topicId <= 0) {
        continue;
      }
      final title = _pickStringFromMap(item, const <String>[
        'title',
        'subject',
      ]);
      final excerpt = _pickStringFromMap(item, const <String>[
        'subject',
        'summary',
        'content',
      ]);
      final boardName = _pickStringFromMap(item, const <String>[
        'board_name',
        'forum_name',
        'type_name',
      ]);
      final displayName = _pickStringFromMap(item, const <String>[
        'user_nick_name',
        'name',
        'userName',
        'username',
      ]);
      final avatar = _pickStringFromMap(item, const <String>[
        'userAvatar',
        'avatar',
        'icon',
      ]);
      final createdRaw =
          _parseInt(item['last_reply_date']) ??
          _parseInt(item['create_date']) ??
          _parseInt(item['dateline']);
      final createdAt = createdRaw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              createdRaw < 10000000000 ? createdRaw * 1000 : createdRaw,
              isUtc: true,
            );
      final usernameRaw = _pickStringFromMap(item, const <String>[
        'user_name',
        'username',
        'userName',
        'author',
      ]);

      topics.add(
        RiverSideTopicSummary(
          id: topicId,
          title: title,
          excerpt: excerpt,
          categoryId: _parseInt(item['board_id']),
          categoryName: boardName,
          replyCount: _parseInt(item['replies']) ?? 0,
          viewCount: _parseInt(item['hits']) ?? 0,
          createdAt: createdAt,
          authorDisplayName: displayName,
          authorUsername: usernameRaw.isEmpty
              ? 'user_${_parseInt(item['user_id']) ?? topicId}'
              : usernameRaw,
          authorUserId: _parseInt(item['user_id']),
          authorAvatarUrl: avatar,
          isHot: (_parseInt(item['hot']) ?? 0) > 0,
          isPinned: (_parseInt(item['top']) ?? 0) > 0,
        ),
      );
    }
    return topics;
  }

  Future<List<RiverSideTopicSummary>> _loadTodayTopicsForAi() async {
    final now = DateTime.now();
    final topicMap = <int, RiverSideTopicSummary>{};
    final currentTabIndex = _tabController.index;
    final snapshot = _tabTopicSnapshotsByIndex[currentTabIndex] ?? const [];
    for (final topic in snapshot) {
      if (_isTodayTopic(topic.createdAt, now)) {
        topicMap[topic.id] = topic;
      }
    }

    const maxPages = 8;
    final feed = _feeds[currentTabIndex];
    if (_forumProvider == _PostsForumProvider.riverSide) {
      final cookie = _activeCookieHeader();
      for (var page = 0; page < maxPages; page++) {
        final pageTopics = await widget
            .dependencies
            .accountStore
            .riverSideApiClient
            .fetchTopicSummaries(
              feed: feed,
              categoryId: _selectedBoardId,
              page: page,
              cookieHeader: cookie,
            );
        if (pageTopics.isEmpty) {
          break;
        }
        var hasToday = false;
        for (final topic in pageTopics) {
          if (_isTodayTopic(topic.createdAt, now)) {
            topicMap[topic.id] = topic;
            hasToday = true;
          }
        }
        if (!hasToday) {
          break;
        }
      }
    } else {
      for (var page = 0; page < maxPages; page++) {
        final pageTopics = await _fetchQingTopicsForAiPage(
          feed: feed,
          page: page,
          boardId: _selectedBoardId,
        );
        if (pageTopics.isEmpty) {
          break;
        }
        var hasToday = false;
        for (final topic in pageTopics) {
          if (_isTodayTopic(topic.createdAt, now)) {
            topicMap[topic.id] = topic;
            hasToday = true;
          }
        }
        if (!hasToday) {
          break;
        }
      }
    }
    final result = topicMap.values.toList(growable: false)
      ..sort((a, b) {
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
    return result;
  }

  Future<void> _showSecondFloorAiSummarySheet() async {
    final theme = Theme.of(context);
    final forumName = _forumProvider == _PostsForumProvider.riverSide
        ? 'RiverSide'
        : '清水河畔';
    final boardName = _selectedBoardName?.trim();
    final sectionLabel = boardName == null || boardName.isEmpty
        ? '全部板块'
        : boardName;
    final instruction =
        '请总结 $forumName 今日（$sectionLabel / ${_feeds[_tabController.index].label}）的帖子内容，'
        '按以下结构输出：\n'
        '1）一句总体氛围判断；\n'
        '2）3-6条重点讨论话题（每条一行）；\n'
        '3）2-3条可跟进建议。';
    final aiService = RiverAiService(widget.dependencies.settingsController);
    final scrollController = ScrollController();
    var started = false;
    var alive = true;
    var loading = true;
    var streaming = false;
    String? error;
    String markdown = '';
    List<RiverSideTopicSummary> topics = const <RiverSideTopicSummary>[];

    Future<void> bootstrap(StateSetter setModalState) async {
      void safeSet(VoidCallback fn) {
        if (!alive) return;
        setModalState(fn);
      }

      try {
        final loadedTopics = await _loadTodayTopicsForAi();
        if (!alive) return;
        if (loadedTopics.isEmpty) {
          safeSet(() {
            loading = false;
            error = '当前论坛今日暂无可总结的内容';
          });
          return;
        }

        safeSet(() {
          topics = loadedTopics;
          loading = false;
          streaming = true;
          markdown = '';
          error = null;
        });

        await for (final chunk in aiService.generateStream(
          instruction: instruction,
          currentText: _buildTodayTopicDigestText(loadedTopics),
        )) {
          if (!alive) {
            return;
          }
          final value = chunk.replaceAll('\r', '');
          for (final rune in value.runes) {
            if (!alive) {
              return;
            }
            safeSet(() {
              markdown += String.fromCharCode(rune);
            });
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (scrollController.hasClients) {
              scrollController.jumpTo(
                scrollController.position.maxScrollExtent,
              );
            }
          }
        }
        safeSet(() {
          streaming = false;
        });
      } catch (e) {
        safeSet(() {
          loading = false;
          streaming = false;
          error = 'AI总结失败：$e';
        });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final maxHeight = media.size.height * 0.86;
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(bootstrap(setModalState));
              });
            }
            final topTopics = topics.take(6).toList(growable: false);
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 17,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'AI 今日论坛摘要',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildAiSummaryMetaChip(label: forumName),
                          _buildAiSummaryMetaChip(label: sectionLabel),
                          _buildAiSummaryMetaChip(
                            label: _feeds[_tabController.index].label,
                          ),
                          _buildAiSummaryMetaChip(
                            label: '今日 ${topics.length} 条',
                          ),
                        ],
                      ),
                    ),
                    if (streaming || loading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              loading ? '正在整理今日帖子...' : 'AI 正在流式生成...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.28),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Builder(
                              builder: (context) {
                                if ((error ?? '').isNotEmpty) {
                                  return Text(
                                    error!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  );
                                }
                                if (markdown.trim().isEmpty) {
                                  return Text(
                                    loading ? '等待 AI 输出...' : '暂无内容',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  );
                                }
                                return MarkdownBody(
                                  data: markdown,
                                  selectable: true,
                                  styleSheet:
                                      MarkdownStyleSheet.fromTheme(
                                        theme,
                                      ).copyWith(
                                        p: theme.textTheme.bodyMedium?.copyWith(
                                          height: 1.55,
                                        ),
                                      ),
                                );
                              },
                            ),
                          ),
                          if (topTopics.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              '今日重点帖子',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final topic in topTopics)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      Navigator.of(sheetContext).pop();
                                      await Navigator.of(context).push(
                                        DraggableRoute<void>(
                                          builder: (_) => TopicDetailPage(
                                            dependencies: widget.dependencies,
                                            topicId: topic.id,
                                            provider:
                                                _forumProvider ==
                                                    _PostsForumProvider
                                                        .riverSide
                                                ? AccountProvider.riverSide
                                                : AccountProvider.qingShuiHePan,
                                            qingBoardId:
                                                _forumProvider ==
                                                    _PostsForumProvider
                                                        .qingShuiHePan
                                                ? topic.categoryId
                                                : null,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            topic.title.trim().isEmpty
                                                ? '(无标题)'
                                                : topic.title.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${topic.authorDisplayName.isEmpty ? topic.authorUsername : topic.authorDisplayName}'
                                            ' · ${topic.categoryName.isEmpty ? '未分类' : topic.categoryName}'
                                            ' · ${_formatTopicTimeForAi(topic.createdAt)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    alive = false;
    scrollController.dispose();
  }

  Widget _buildAiSummaryMetaChip({required String label}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _summarizeTodayForumByAi() async {
    if (_summarizingTodayForumByAi) {
      return;
    }
    if (!widget.dependencies.settingsController.aiConfigured) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('请先在“我的 - AI设置”中完成配置');
      return;
    }
    setState(() {
      _summarizingTodayForumByAi = true;
    });
    try {
      await _showSecondFloorAiSummarySheet();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('AI总结失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _summarizingTodayForumByAi = false;
        });
      }
    }
  }

  Future<List<RiverSideCategoryOption>> _loadCategories({
    bool forceRefresh = false,
  }) async {
    if (_forumProvider == _PostsForumProvider.riverSide) {
      return _loadRiverSideCategories(forceRefresh: forceRefresh);
    }
    return _loadQingShuiHePanCategories(forceRefresh: forceRefresh);
  }

  Future<List<RiverSideCategoryOption>> _loadRiverSideCategories({
    required bool forceRefresh,
  }) async {
    if (_loadingCategories) return _categories;
    _loadingCategories = true;
    try {
      final cookie = _activeCookieHeader();
      final activeUsername =
          widget.dependencies.accountStore.activeRiverSideUsername;
      var categories = await RiverSideCategoryStore.instance.load(
        apiClient: widget.dependencies.accountStore.riverSideApiClient,
        username: activeUsername,
        cookieHeader: cookie,
        forceRefresh: forceRefresh,
      );
      if (!forceRefresh &&
          cookie != null &&
          cookie.trim().isNotEmpty &&
          categories.isEmpty) {
        categories = await RiverSideCategoryStore.instance.load(
          apiClient: widget.dependencies.accountStore.riverSideApiClient,
          username: activeUsername,
          cookieHeader: cookie,
          forceRefresh: true,
        );
      }
      if (mounted) {
        setState(() {
          _riverCategories = List<RiverSideCategoryOption>.from(categories);
          if (_forumProvider == _PostsForumProvider.riverSide) {
            _categories = List<RiverSideCategoryOption>.from(categories);
          }
          if (_selectedBoardId != null) {
            final selected = findRiverSideCategoryById(
              id: _selectedBoardId,
              categories: categories,
            );
            _selectedBoardName = selected == null
                ? null
                : displayRiverSideCategoryName(
                    category: selected,
                    allCategories: categories,
                  );
          }
          _riverSelectedBoardId = _selectedBoardId;
          _riverSelectedBoardName = _selectedBoardName;
        });
      }
      return categories;
    } catch (e) {
      debugPrint('Failed to load boards: $e');
      return _categories;
    } finally {
      _loadingCategories = false;
    }
  }

  Future<List<RiverSideCategoryOption>> _loadQingShuiHePanCategories({
    required bool forceRefresh,
  }) async {
    if (_loadingQingCategories) {
      return _categories;
    }
    _loadingQingCategories = true;
    try {
      final username =
          widget.dependencies.accountStore.activeQingShuiHePanUsername;
      if (username == null || username.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _qingCategories = const <RiverSideCategoryOption>[];
            if (_forumProvider == _PostsForumProvider.qingShuiHePan) {
              _categories = const <RiverSideCategoryOption>[];
            }
          });
        }
        return const <RiverSideCategoryOption>[];
      }
      final auth = widget.dependencies.accountStore.qingShuiHePanAuthFor(
        username,
      );
      if (auth == null) {
        if (mounted) {
          setState(() {
            _qingCategories = const <RiverSideCategoryOption>[];
            if (_forumProvider == _PostsForumProvider.qingShuiHePan) {
              _categories = const <RiverSideCategoryOption>[];
            }
          });
        }
        return const <RiverSideCategoryOption>[];
      }

      if (!forceRefresh && _qingCategories.isNotEmpty) {
        if (mounted && _forumProvider == _PostsForumProvider.qingShuiHePan) {
          setState(() {
            _categories = List<RiverSideCategoryOption>.from(_qingCategories);
          });
        }
        return _qingCategories;
      }

      final endpoint =
          '${RiverServerConfig.instance.qingShuiHePanBaseUrl}/mobcent/app/web/index.php';
      final requestBody = <String, String>{
        'r': 'forum/forumlist',
        'accessToken': auth.token,
        'accessSecret': auth.secret,
      };
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Accept': 'application/json, text/plain, */*',
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: _encodeQingForm(requestBody),
          )
          .timeout(const Duration(seconds: 14));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const RiverSideApiException('清水河畔板块接口返回异常');
      }
      final map = decoded.map((key, value) => MapEntry('$key', value));
      if ('${map['rs']}' == '0') {
        final errcode = '${map['errcode'] ?? ''}'.trim();
        final head = map['head'] is Map
            ? map['head'] as Map
            : const <dynamic, dynamic>{};
        final errInfo = '${head['errInfo'] ?? ''}'.trim();
        final message = errcode.isNotEmpty
            ? errcode
            : (errInfo.isNotEmpty ? errInfo : '清水河畔板块加载失败');
        throw RiverSideApiException(message);
      }
      final listRaw = map['list'];
      if (listRaw is! List) {
        if (mounted) {
          setState(() {
            _qingCategories = const <RiverSideCategoryOption>[];
            if (_forumProvider == _PostsForumProvider.qingShuiHePan) {
              _categories = const <RiverSideCategoryOption>[];
            }
          });
        }
        return const <RiverSideCategoryOption>[];
      }

      final categories = <RiverSideCategoryOption>[];
      final seenBoardIds = <int>{};
      var position = 0;
      var syntheticParentSeed = 1;

      for (final rawGroup in listRaw) {
        final group = _toStringDynamicMap(rawGroup);
        if (group.isEmpty) {
          continue;
        }
        final groupName = _pickStringFromMap(group, const <String>[
          'board_category_name',
          'category_name',
          'name',
        ]);
        final groupIdRaw = _parseInt(group['board_category_id']);
        int? parentId;
        if (groupName.isNotEmpty) {
          final safeGroupId =
              groupIdRaw != null &&
                  groupIdRaw > 0 &&
                  !seenBoardIds.contains(groupIdRaw)
              ? groupIdRaw
              : -(100000 + syntheticParentSeed++);
          parentId = safeGroupId;
          categories.add(
            RiverSideCategoryOption(
              id: safeGroupId,
              name: groupName,
              position: position++,
              parentCategoryId: null,
              description: '',
            ),
          );
        }
        final boardList = group['board_list'];
        if (boardList is! List) {
          continue;
        }
        for (final rawBoard in boardList) {
          final board = _toStringDynamicMap(rawBoard);
          if (board.isEmpty) {
            continue;
          }
          final boardId = _parseInt(board['board_id']);
          if (boardId == null ||
              boardId <= 0 ||
              seenBoardIds.contains(boardId)) {
            continue;
          }
          final boardName = _pickStringFromMap(board, const <String>[
            'board_name',
            'forum_name',
            'name',
          ]);
          if (boardName.isEmpty) {
            continue;
          }
          seenBoardIds.add(boardId);
          categories.add(
            RiverSideCategoryOption(
              id: boardId,
              name: boardName,
              position: position++,
              parentCategoryId: parentId,
              description: '',
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _qingCategories = List<RiverSideCategoryOption>.from(categories);
          if (_forumProvider == _PostsForumProvider.qingShuiHePan) {
            _categories = List<RiverSideCategoryOption>.from(categories);
          }
          if (_selectedBoardId != null) {
            final selected = findRiverSideCategoryById(
              id: _selectedBoardId,
              categories: categories,
            );
            _selectedBoardName = selected == null
                ? null
                : displayRiverSideCategoryName(
                    category: selected,
                    allCategories: categories,
                  );
          }
          _qingSelectedBoardId = _selectedBoardId;
          _qingSelectedBoardName = _selectedBoardName;
        });
      }
      return categories;
    } catch (e) {
      debugPrint('Failed to load qing boards: $e');
      return _categories;
    } finally {
      _loadingQingCategories = false;
    }
  }

  String _pickStringFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = '${map[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _encodeQingForm(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  Future<void> _scrollToTopAndRefresh() async {
    final key = _tabKeys[_tabController.index];
    key?.currentState?.scrollToTopAndRefresh();
  }

  Future<void> _loadInstalledMiniApps() async {
    final installed = await _miniAppInstallStore.loadInstalledApps();
    if (!mounted) {
      return;
    }
    setState(() {
      _miniApps = _mergeInstalledWithCatalog(
        installed: installed,
        catalog: _onlineMiniApps,
      );
    });
  }

  List<RiverMiniAppEntry> _mergeInstalledWithCatalog({
    required List<RiverMiniAppEntry> installed,
    required List<RiverMiniAppEntry> catalog,
  }) {
    if (installed.isEmpty) {
      return const <RiverMiniAppEntry>[];
    }
    if (catalog.isEmpty) {
      return List<RiverMiniAppEntry>.unmodifiable(installed);
    }
    final catalogById = <String, RiverMiniAppEntry>{
      for (final item in catalog) item.id: item,
    };
    final merged =
        installed
            .map((item) {
              final fromCatalog = catalogById[item.id];
              if (fromCatalog == null) {
                return item;
              }
              return fromCatalog.copyWith(
                localEntryFilePath: item.localEntryFilePath,
                installedAtMillis: item.installedAtMillis,
                order: item.order,
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final order = a.order.compareTo(b.order);
            if (order != 0) {
              return order;
            }
            return a.name.compareTo(b.name);
          });
    return List<RiverMiniAppEntry>.unmodifiable(merged);
  }

  Future<void> _loadMiniApps({required bool forceRefresh}) async {
    if (_loadingMiniApps || !mounted) {
      return;
    }
    setState(() {
      _loadingMiniApps = true;
      _miniAppsError = null;
    });
    try {
      final manifest = await _miniAppRepository.load(
        manifestUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
        cookieHeader: _activeCookieHeader(),
        forceRefresh: forceRefresh,
      );
      if (!mounted) {
        return;
      }
      final catalog = List<RiverMiniAppEntry>.unmodifiable(manifest.entries);
      setState(() {
        _onlineMiniApps = catalog;
        _miniApps = _mergeInstalledWithCatalog(
          installed: _miniApps,
          catalog: catalog,
        );
        _loadingMiniApps = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMiniApps = false;
        _miniAppsError = '$error';
      });
    }
  }

  Future<void> _installMiniApp(RiverMiniAppEntry app) async {
    if (_installingMiniAppIds.contains(app.id)) {
      return;
    }
    setState(() {
      _installingMiniAppIds.add(app.id);
    });
    try {
      final installed = await _miniAppInstallStore.install(
        app: app,
        cookieHeader: _activeCookieHeader(),
      );
      if (!mounted) {
        return;
      }
      final next = <String, RiverMiniAppEntry>{
        for (final item in _miniApps) item.id: item,
      };
      next[installed.id] = installed;
      final merged = _mergeInstalledWithCatalog(
        installed: next.values.toList(growable: false),
        catalog: _onlineMiniApps,
      );
      setState(() {
        _miniApps = merged;
      });
      ScaffoldMessenger.of(context).showRiverSnackBar('已添加 ${installed.name}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final raw = '$error';
      final hint =
          raw.toLowerCase().contains('connection closed while receiving data')
          ? '\n请检查小程序服务器是否稳定在线，并重试。'
          : '';
      ScaffoldMessenger.of(context).showRiverSnackBar('添加小程序失败：$raw$hint');
    } finally {
      if (mounted) {
        setState(() {
          _installingMiniAppIds.remove(app.id);
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _openMiniAppSearchSheet() async {
    final theme = Theme.of(context);
    final controller = TextEditingController();
    Timer? debounce;
    var loading = false;
    var query = '';
    var results = <RiverMiniAppEntry>[];
    final localInstallingIds = <String>{};
    BuildContext? sheetContext;

    String resolvePackageName(RiverMiniAppEntry app) {
      if (app.appCode.trim().isNotEmpty) {
        return app.appCode.trim();
      }
      if (app.projectId.trim().isNotEmpty) {
        return app.projectId.trim();
      }
      return app.id.trim();
    }

    String resolveUpdatedAtLabel(RiverMiniAppEntry app) {
      final raw = app.updatedAtRaw.trim();
      if (raw.isEmpty) {
        return '-';
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        return raw;
      }
      final local = parsed.toLocal();
      final mm = local.month.toString().padLeft(2, '0');
      final dd = local.day.toString().padLeft(2, '0');
      final hh = local.hour.toString().padLeft(2, '0');
      final mi = local.minute.toString().padLeft(2, '0');
      return '${local.year}-$mm-$dd $hh:$mi';
    }

    Future<void> openMiniAppDetail(
      RiverMiniAppEntry app,
      StateSetter setModalState,
    ) async {
      final detailTheme = Theme.of(context);
      final packageName = resolvePackageName(app);
      final developerName = app.developerName.trim().isEmpty
          ? '未知'
          : app.developerName.trim();
      final updatedAt = resolveUpdatedAtLabel(app);
      final version = app.version.trim().isEmpty ? '-' : app.version.trim();
      final description = app.description.trim().isEmpty
          ? '暂无描述'
          : app.description.trim();
      final sizeText = app.packageBytes > 0
          ? '${(app.packageBytes / 1024).toStringAsFixed(1)} KB'
          : '-';

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: detailTheme.colorScheme.surface,
        builder: (detailContext) {
          return StatefulBuilder(
            builder: (detailContext, setDetailState) {
              final installed = _miniApps.any((item) => item.id == app.id);
              final installing =
                  _installingMiniAppIds.contains(app.id) ||
                  localInstallingIds.contains(app.id);
              final canAdd = !installed && !installing;

              Future<void> handleAction() async {
                if (installed) {
                  Navigator.of(detailContext).pop();
                  if (sheetContext?.mounted == true) {
                    Navigator.of(sheetContext!).pop();
                  }
                  await _openMiniApp(app);
                  return;
                }
                if (!canAdd || sheetContext?.mounted != true) {
                  return;
                }
                setDetailState(() {});
                setModalState(() {
                  localInstallingIds.add(app.id);
                });
                await _installMiniApp(app);
                if (!mounted) {
                  return;
                }
                if (sheetContext?.mounted == true) {
                  setModalState(() {
                    localInstallingIds.remove(app.id);
                  });
                }
                if (detailContext.mounted) {
                  Navigator.of(detailContext).pop();
                }
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  12 + MediaQuery.paddingOf(detailContext).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.name,
                            style: detailTheme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (installing)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: detailTheme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: detailTheme.colorScheme.outlineVariant
                              .withValues(alpha: 0.32),
                        ),
                      ),
                      child: Column(
                        children: [
                          _MiniAppMetaRow(label: '包名', value: packageName),
                          _MiniAppMetaRow(label: '开发者', value: developerName),
                          _MiniAppMetaRow(label: '版本', value: version),
                          _MiniAppMetaRow(label: '更新时间', value: updatedAt),
                          _MiniAppMetaRow(label: '安装包大小', value: sizeText),
                          _MiniAppMetaRow(label: '描述', value: description),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(detailContext).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: installing ? null : handleAction,
                            icon: Icon(
                              installed
                                  ? Icons.open_in_new_rounded
                                  : Icons.add_rounded,
                            ),
                            label: Text(installed ? '打开小程序' : '添加小程序'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    Future<void> search(StateSetter setModalState, String raw) async {
      final q = raw.trim();
      query = q;
      if (q.isEmpty) {
        if (sheetContext?.mounted != true) {
          return;
        }
        setModalState(() {
          loading = false;
          results = const <RiverMiniAppEntry>[];
        });
        return;
      }
      if (sheetContext?.mounted != true) {
        return;
      }
      setModalState(() => loading = true);
      try {
        final found = await _miniAppRepository.search(
          manifestUrl:
              widget.dependencies.settingsController.miniAppsManifestUrl,
          query: q,
          cookieHeader: _activeCookieHeader(),
        );
        if (!mounted || query != q || sheetContext?.mounted != true) {
          return;
        }
        setModalState(() {
          loading = false;
          results = found;
        });
      } catch (_) {
        if (!mounted || query != q || sheetContext?.mounted != true) {
          return;
        }
        setModalState(() {
          loading = false;
          results = const <RiverMiniAppEntry>[];
        });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: false,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        sheetContext = context;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final installedIds = _miniApps.map((item) => item.id).toSet();
            final recommended =
                _onlineMiniApps
                    .where((item) => item.enabled)
                    .toList(growable: false)
                  ..sort((a, b) {
                    final aInstalled = installedIds.contains(a.id);
                    final bInstalled = installedIds.contains(b.id);
                    if (aInstalled != bInstalled) {
                      return aInstalled ? 1 : -1;
                    }
                    final orderCmp = a.order.compareTo(b.order);
                    if (orderCmp != 0) {
                      return orderCmp;
                    }
                    return a.name.compareTo(b.name);
                  });
            final recommendedApps = recommended.take(6).toList(growable: false);
            final hasSearchText = query.trim().isNotEmpty;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '搜索小程序',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新在线清单',
                        onPressed: () {
                          unawaited(_loadMiniApps(forceRefresh: true));
                        },
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: false,
                    onChanged: (value) {
                      setModalState(() {
                        query = value.trim();
                        if (query.isEmpty) {
                          loading = false;
                          results = const <RiverMiniAppEntry>[];
                        }
                      });
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 280), () {
                        unawaited(search(setModalState, value));
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: '输入关键字搜索并添加',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: !hasSearchText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '推荐小程序',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (recommendedApps.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    '暂无推荐小程序',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              else
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: recommendedApps.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = recommendedApps[index];
                                      final installed = installedIds.contains(
                                        item.id,
                                      );
                                      final installing = localInstallingIds
                                          .contains(item.id);
                                      return _OnlineMiniAppSearchTile(
                                        app: item,
                                        installed: installed,
                                        installing: installing,
                                        onTapCard: () {
                                          unawaited(
                                            openMiniAppDetail(
                                              item,
                                              setModalState,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                            ],
                          )
                        : loading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : results.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '暂无搜索结果',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = results[index];
                              final installed = installedIds.contains(item.id);
                              final installing = localInstallingIds.contains(
                                item.id,
                              );
                              return _OnlineMiniAppSearchTile(
                                app: item,
                                installed: installed,
                                installing: installing,
                                onTapCard: () {
                                  unawaited(
                                    openMiniAppDetail(item, setModalState),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    debounce?.cancel();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      controller.dispose();
    });
  }

  // ignore: unused_element
  Future<void> _openMiniAppManageSheet() async {
    if (_miniApps.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showRiverSnackBar('暂无可管理的小程序');
      return;
    }

    final draft = List<RiverMiniAppEntry>.from(_miniApps);
    var changed = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
            return SizedBox(
              height: maxHeight,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '管理我的小程序',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.apps_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '共 ${draft.length} 个，拖动右侧手柄调整顺序，点击删除按钮移除',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: draft.length,
                      onReorder: (oldIndex, newIndex) {
                        setModalState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final item = draft.removeAt(oldIndex);
                          draft.insert(newIndex, item);
                          changed = true;
                        });
                      },
                      itemBuilder: (context, index) {
                        final item = draft[index];
                        return Container(
                          key: ValueKey('mini_app_manage_${item.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.24),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              8,
                              8,
                              8,
                            ),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.12),
                              child: Text(
                                item.name.trim().isEmpty
                                    ? 'A'
                                    : item.name.trim()[0],
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.description.trim().isEmpty
                                  ? item.id
                                  : item.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  tooltip: '删除',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    final confirmed =
                                        await showRiverConfirmDialog(
                                          context: context,
                                          title: '删除小程序',
                                          message: '确定删除“${item.name}”吗？',
                                          confirmText: '删除',
                                          icon: Icons.delete_outline_rounded,
                                          isDestructive: true,
                                        );
                                    if (!confirmed) {
                                      return;
                                    }
                                    await _miniAppInstallStore
                                        .removeInstalledById(item.id);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    setModalState(() {
                                      draft.removeWhere(
                                        (it) => it.id == item.id,
                                      );
                                      changed = true;
                                    });
                                    if (draft.isEmpty && context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.drag_indicator_rounded,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || !changed) {
      return;
    }
    await _miniAppInstallStore.reorderInstalledByIds(
      draft.map((item) => item.id).toList(growable: false),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _miniApps = List<RiverMiniAppEntry>.unmodifiable(draft);
    });
  }

  Future<void> _reorderMiniAppsFromSecondFloor(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final byId = <String, RiverMiniAppEntry>{
      for (final item in _miniApps) item.id: item,
    };
    final reordered = <RiverMiniAppEntry>[];
    for (final id in ids) {
      final item = byId.remove(id);
      if (item != null) {
        reordered.add(item);
      }
    }
    reordered.addAll(byId.values);
    if (reordered.isEmpty) {
      return;
    }

    await _miniAppInstallStore.reorderInstalledByIds(
      reordered.map((item) => item.id).toList(growable: false),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _miniApps = List<RiverMiniAppEntry>.unmodifiable(reordered);
    });
  }

  Future<void> _deleteMiniAppFromSecondFloor(RiverMiniAppEntry app) async {
    await _miniAppInstallStore.removeInstalledById(app.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _miniApps = List<RiverMiniAppEntry>.unmodifiable(
        _miniApps.where((item) => item.id != app.id),
      );
    });
    ScaffoldMessenger.of(context).showRiverSnackBar('已删除 ${app.name}');
  }

  Future<void> _openMiniApp(RiverMiniAppEntry app) async {
    if (app.requiresAuth) {
      final username = widget.dependencies.accountStore.activeRiverSideUsername;
      final cookie = _activeCookieHeader() ?? '';
      if (username == null || username.isEmpty || cookie.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showRiverSnackBar('该小程序需要先登录 RiverSide 账号');
        return;
      }
    }

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MiniAppWebViewPage(dependencies: widget.dependencies, miniApp: app),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final slide = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0.7, end: 1).animate(fade),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(slide),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    _syncHeaderWithCurrentTab();
  }

  void _syncHeaderWithCurrentTab() {
    final key = _tabKeys[_tabController.index];
    final offset = key?.currentState?.currentScrollOffset ?? 0;
    _onActiveTabScrollOffsetChanged(offset);
  }

  void _setSecondFloorPullDistance(double value) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final triggerDistance = _secondFloorTriggerDistanceForViewport();
    final next = value.clamp(0.0, screenHeight);
    final armed = next >= triggerDistance;
    final changed =
        (_secondFloorPullDistance - next).abs() > 0.1 ||
        _secondFloorArmed != armed;
    if (!changed || !mounted) {
      return;
    }
    setState(() {
      _secondFloorPullDistance = next;
      _secondFloorArmed = armed;
    });
    if (!_secondFloorController.isAnimating) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      final progress = (next / screenHeight).clamp(0.0, 1.0);
      if ((_secondFloorController.value - progress).abs() > 0.001) {
        _secondFloorController.value = progress;
      }
    }
  }

  double _secondFloorTriggerDistanceForViewport() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return screenHeight * 0.5;
  }

  Future<void> _animateSecondFloorTo(
    double target, {
    Curve curve = Curves.easeOutCubic,
    Duration? duration,
  }) async {
    final clampedTarget = target.clamp(0.0, 1.0);
    final distance = (clampedTarget - _secondFloorController.value).abs();
    final computedDuration =
        duration ??
        Duration(
          milliseconds: (220 + (distance * 260)).round().clamp(220, 460),
        );
    await _secondFloorController.animateTo(
      clampedTarget,
      duration: computedDuration,
      curve: curve,
    );
    if (clampedTarget <= 0.0 && _secondFloorController.value != 0.0) {
      _secondFloorController.value = 0.0;
    } else if (clampedTarget >= 1.0 && _secondFloorController.value != 1.0) {
      _secondFloorController.value = 1.0;
    }
  }

  void _resetSecondFloorPullState() {
    if (_secondFloorPullDistance == 0 && !_secondFloorArmed) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _secondFloorPullDistance = 0;
      _secondFloorArmed = false;
    });
  }

  Future<void> _openSecondFloor() async {
    if (mounted && !_secondFloorOpened) {
      setState(() {
        _secondFloorOpened = true;
      });
    } else {
      _secondFloorOpened = true;
    }
    await _animateSecondFloorTo(1);
  }

  Future<void> _closeSecondFloor() async {
    await _animateSecondFloorTo(0);
    if (mounted && _secondFloorOpened) {
      setState(() {
        _secondFloorOpened = false;
      });
    } else {
      _secondFloorOpened = false;
    }
    _resetSecondFloorPullState();
  }

  void _onHeaderDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta.abs() < 0.1) {
      return;
    }
    if (delta > 0) {
      _setSecondFloorPullDistance(_secondFloorPullDistance + delta);
      return;
    }
    if (delta < 0 && _secondFloorPullDistance > 0) {
      _setSecondFloorPullDistance(_secondFloorPullDistance + delta);
    }
  }

  void _onHeaderDragEnd(DragEndDetails details) {
    if (_secondFloorPullDistance <= 0) {
      if (_secondFloorController.value > 0 &&
          _secondFloorController.value < 1) {
        _resetSecondFloorPullState();
        unawaited(
          _animateSecondFloorTo(
            0,
            curve: Curves.easeOutQuart,
            duration: const Duration(milliseconds: 280),
          ),
        );
      }
      return;
    }
    if (_secondFloorArmed) {
      unawaited(_openSecondFloor());
      return;
    }
    _resetSecondFloorPullState();
    unawaited(
      _animateSecondFloorTo(
        0,
        curve: Curves.easeOutQuart,
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _onSecondFloorDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta.abs() < 0.1) {
      return;
    }
    // 上滑关闭：delta < 0 => progress 下降；下滑回弹：delta > 0 => progress 上升
    final screenHeight = MediaQuery.sizeOf(context).height;
    final next = (_secondFloorController.value + (delta / screenHeight)).clamp(
      0.0,
      1.0,
    );
    _secondFloorController.value = next;
  }

  void _onSecondFloorDragEnd(DragEndDetails details) {
    final shouldClose = _secondFloorController.value < 0.62;
    if (shouldClose) {
      unawaited(_closeSecondFloor());
      return;
    }
    unawaited(_animateSecondFloorTo(1));
  }

  void _onActiveTabScrollOffsetChanged(double offset) {
    final next = (offset / 96).clamp(0.0, 1.0);
    if ((_headerScrollFactor - next).abs() < 0.01 || !mounted) {
      return;
    }
    setState(() {
      _headerScrollFactor = next;
    });
  }

  void _onBoardFilterPressed() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => RiverSideCategoryPickerSheet(
        initialCategories: _categories,
        selectedCategoryId: _selectedBoardId,
        allowSelectAll: true,
        onRefreshCategories: ({bool forceRefresh = false}) {
          return _loadCategories(forceRefresh: forceRefresh);
        },
        onSelected: (category) {
          Navigator.pop(context);
          if (_selectedBoardId == category?.id) return;
          setState(() {
            _selectedBoardId = category?.id;
            _selectedBoardName = category == null
                ? null
                : displayRiverSideCategoryName(
                    category: category,
                    allCategories: _categories,
                  );
            if (_forumProvider == _PostsForumProvider.riverSide) {
              _riverSelectedBoardId = _selectedBoardId;
              _riverSelectedBoardName = _selectedBoardName;
            } else {
              _qingSelectedBoardId = _selectedBoardId;
              _qingSelectedBoardName = _selectedBoardName;
            }
            _filterVersion++;
          });
        },
      ),
    );
  }

  Map<int, String> _buildCategoryNameMap() {
    if (_categories.isEmpty) {
      return const <int, String>{};
    }
    return <int, String>{
      for (final category in _categories)
        category.id: displayRiverSideCategoryName(
          category: category,
          allCategories: _categories,
        ),
    };
  }

  void _onTabTopicsSnapshotChanged(
    int tabIndex,
    List<RiverSideTopicSummary> topics,
  ) {
    _tabTopicSnapshotsByIndex[tabIndex] =
        List<RiverSideTopicSummary>.unmodifiable(topics);
    var changed = false;
    for (final topic in topics) {
      final username = topic.authorUsername.trim();
      final normalized = _normalizePresenceUsername(username);
      if (normalized.isEmpty) {
        continue;
      }
      final preview = _OnlineUserPreview(
        username: username,
        displayName: topic.authorDisplayName.trim().isEmpty
            ? username
            : topic.authorDisplayName.trim(),
        avatarUrl: topic.authorAvatarUrl.trim(),
      );
      final previous = _knownUserPreviewsByUsername[normalized];
      if (previous == preview) {
        continue;
      }
      _knownUserPreviewsByUsername[normalized] = preview;
      changed = true;
    }
    if (changed &&
        mounted &&
        _onlineUsernames.any(_knownUserPreviewsByUsername.containsKey)) {
      setState(() {});
    }
  }

  int get _resolvedOnlineUsersCount {
    if (_onlineUsersCount > 0) {
      return _onlineUsersCount;
    }
    final byName = _onlineUsernames.length;
    final byId = _onlineUserIds.length;
    return byName > byId ? byName : byId;
  }

  List<_OnlineUserPreview> _buildOnlineUsersForDisplay() {
    final usernames = _onlineUsernames.toList(growable: false)..sort();
    final users = <_OnlineUserPreview>[];
    for (final normalized in usernames) {
      final known = _knownUserPreviewsByUsername[normalized];
      if (known != null) {
        users.add(known);
      } else {
        users.add(
          _OnlineUserPreview(
            username: normalized,
            displayName: normalized,
            avatarUrl: '',
          ),
        );
      }
    }
    return users;
  }

  Rect _resolveOnlineUsersPillRect(BuildContext context) {
    final pillContext = _onlineUsersPillKey.currentContext;
    final screenSize = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    if (pillContext == null) {
      return Rect.fromLTWH(screenSize.width - 176, topInset + 14, 164, 34);
    }
    final renderObject = pillContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return Rect.fromLTWH(screenSize.width - 176, topInset + 14, 164, 34);
    }
    final globalOffset = renderObject.localToGlobal(Offset.zero);
    return globalOffset & renderObject.size;
  }

  Future<void> _openOnlineUsersPopup() async {
    final users = _buildOnlineUsersForDisplay();
    final onlineCount = _resolvedOnlineUsersCount;
    final anchorRect = _resolveOnlineUsersPillRect(context);
    final selected = await showGeneralDialog<_OnlineUserPreview>(
      context: context,
      barrierLabel: 'online_users',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.04),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final theme = Theme.of(dialogContext);
        final shownUsers = users.take(120).toList(growable: false);
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final topInset = MediaQuery.paddingOf(dialogContext).top;
        final bottomInset = MediaQuery.paddingOf(dialogContext).bottom;
        final popupWidth = (screenSize.width * 0.72).clamp(244.0, 328.0);
        final popupLeft = (anchorRect.right - popupWidth).clamp(
          12.0,
          screenSize.width - popupWidth - 12.0,
        );
        final popupTop = (anchorRect.bottom + 8).clamp(
          topInset + 6,
          screenSize.height - 210,
        );
        final maxHeight = (screenSize.height - popupTop - bottomInset - 12)
            .clamp(156.0, 360.0);
        final arrowLeft = (anchorRect.center.dx - popupLeft - 6).clamp(
          14.0,
          popupWidth - 22,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).maybePop(),
              ),
            ),
            Positioned(
              top: popupTop,
              left: popupLeft,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -6,
                        left: arrowLeft,
                        child: Transform.rotate(
                          angle: 0.785398,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.32),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.32,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.shadow.withValues(
                                alpha: 0.18,
                              ),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tips_and_updates_outlined,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '当前在线',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$onlineCount',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onPrimaryContainer,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: '关闭',
                                    visualDensity: VisualDensity.compact,
                                    splashRadius: 16,
                                    onPressed: () =>
                                        Navigator.of(dialogContext).maybePop(),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                            if (shownUsers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 6, 12, 12),
                                child: Text('暂无在线用户详情'),
                              )
                            else
                              Flexible(
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    2,
                                    8,
                                    12,
                                  ),
                                  shrinkWrap: true,
                                  itemBuilder: (context, index) {
                                    final user = shownUsers[index];
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => Navigator.of(
                                          dialogContext,
                                        ).pop(user),
                                        child: Ink(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              _buildOnlineUserAvatar(
                                                user: user,
                                                radius: 15,
                                              ),
                                              const SizedBox(width: 9),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      user.displayName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                    Text(
                                                      '@${user.username}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 6),
                                  itemCount: shownUsers.length,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuad,
          reverseCurve: Curves.easeInQuad,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }
    await showRiverSideUserProfileSheet(
      context: context,
      dependencies: widget.dependencies,
      username: selected.username,
      displayName: selected.displayName,
      avatarUrl: selected.avatarUrl,
    );
  }

  Future<void> _openSearchPage({
    SearchPageInitialMode initialMode = SearchPageInitialMode.posts,
  }) async {
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => SearchPage(
          dependencies: widget.dependencies,
          initialMode: initialMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final easedHeaderFactor = Curves.easeOutCubic.transform(
      _headerScrollFactor,
    );
    final categoryNameMap = _buildCategoryNameMap();

    return PopScope<void>(
      canPop: !_secondFloorOpened,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_secondFloorOpened || _secondFloorController.value > 0) {
          unawaited(_closeSecondFloor());
        }
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _secondFloorController,
          builder: (context, _) {
            final progress = _secondFloorController.value.clamp(0.0, 1.0);
            final baseShift = lerpDouble(
              0,
              MediaQuery.sizeOf(context).height * 0.78,
              progress,
            )!;
            final showSecondFloor = progress > 0.0001;
            final secondFloorInteractive =
                _secondFloorOpened || progress >= 0.999;

            return Stack(
              children: [
                Transform.translate(
                  offset: Offset(0, baseShift),
                  child: IgnorePointer(
                    ignoring: secondFloorInteractive,
                    child: Column(
                      children: [
                        _buildTopHeader(
                          theme,
                          easedHeaderFactor,
                          secondFloorProgress: progress,
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: _feeds.asMap().entries.map((entry) {
                              final index = entry.key;
                              final feed = entry.value;

                              _tabKeys[index] ??=
                                  GlobalKey<_TopicListTabState>();

                              return _TopicListTab(
                                key: _tabKeys[index],
                                dependencies: widget.dependencies,
                                forumProvider: _forumProvider,
                                feed: feed,
                                boardId: _selectedBoardId,
                                categoryNameMap: categoryNameMap,
                                filterVersion: _filterVersion,
                                showInlineRealtimeHint:
                                    _forumProvider ==
                                        _PostsForumProvider.riverSide &&
                                    _showPostsRealtimeRefreshBanner &&
                                    _hasRealtimeTopicUpdate,
                                onConsumeRealtimeUpdate:
                                    _consumeRealtimeTopicUpdate,
                                onDismissRealtimeUpdate:
                                    _dismissRealtimeTopicUpdateHint,
                                onTopicsSnapshotChanged: (topics) =>
                                    _onTabTopicsSnapshotChanged(index, topics),
                                onScrollOffsetChanged: (offset) {
                                  if (_tabController.index != index) {
                                    return;
                                  }
                                  _onActiveTabScrollOffsetChanged(offset);
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !showSecondFloor,
                  child: _PostsSecondFloorLayer(
                    progress: progress,
                    feedLabel: _feeds[_tabController.index].label,
                    weatherData: _secondFloorWeatherData,
                    loadingWeather: _loadingSecondFloorWeather,
                    weatherError: _secondFloorWeatherError,
                    onRefreshWeather: () {
                      unawaited(_loadSecondFloorWeather(force: true));
                    },
                    onAiSummaryTap: () {
                      unawaited(_summarizeTodayForumByAi());
                    },
                    aiSummarizing: _summarizingTodayForumByAi,
                    miniApps: _miniApps,
                    onlineMiniApps: _onlineMiniApps,
                    loadingMiniApps: _loadingMiniApps,
                    miniAppsError: _miniAppsError,
                    onOpenMiniApp: (app) {
                      unawaited(_openMiniApp(app));
                    },
                    onOpenMiniAppSearch: () {
                      unawaited(
                        _openSearchPage(
                          initialMode: SearchPageInitialMode.miniApps,
                        ),
                      );
                    },
                    onReorderMiniApps: (ids) {
                      unawaited(_reorderMiniAppsFromSecondFloor(ids));
                    },
                    onDeleteMiniApp: (app) {
                      unawaited(_deleteMiniAppFromSecondFloor(app));
                    },
                    onRefreshMiniApps: () {
                      unawaited(_loadMiniApps(forceRefresh: true));
                    },
                    bottomBarHeight: _secondFloorBottomBarHeight,
                    bottomNavigationReserveHeight:
                        _secondFloorBottomNavReserveHeight,
                    interactive: secondFloorInteractive,
                    onClose: _closeSecondFloor,
                    onDragUpdate: _onSecondFloorDragUpdate,
                    onDragEnd: _onSecondFloorDragEnd,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOnlineUsersPill(ThemeData theme) {
    final users = _buildOnlineUsersForDisplay();
    final onlineCount = _resolvedOnlineUsersCount;
    final previewUsers = users.take(3).toList(growable: false);
    final enabled = onlineCount > 0;

    return KeyedSubtree(
      key: _onlineUsersPillKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? _openOnlineUsersPopup : null,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: 0.7,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 24,
                  child: previewUsers.isEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(
                            Icons.group_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (
                              var index = 0;
                              index < previewUsers.length;
                              index++
                            )
                              Positioned(
                                left: index * 12,
                                child: _buildOnlineUserAvatar(
                                  user: previewUsers[index],
                                  radius: 11,
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$onlineCount用户在线',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineUserAvatar({
    required _OnlineUserPreview user,
    required double radius,
  }) {
    final theme = Theme.of(context);
    final displayText = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.username.trim();
    final initials = displayText.isEmpty ? '?' : displayText.substring(0, 1);
    final avatarUrl = user.avatarUrl.trim();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.surface, width: 1.4),
        image: avatarUrl.isEmpty
            ? null
            : DecorationImage(
                image: NetworkImage(avatarUrl),
                fit: BoxFit.cover,
              ),
      ),
      alignment: Alignment.center,
      child: avatarUrl.isEmpty
          ? Text(
              initials,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    );
  }

  Widget _buildTopHeader(
    ThemeData theme,
    double t, {
    required double secondFloorProgress,
  }) {
    final useBottomSearchTab = _shouldUseBottomSearchTab(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final collapse = t.clamp(0.0, 1.0);
    final secondFloorFade = (1 - secondFloorProgress).clamp(0.0, 1.0);
    const titleSize = 21.0;
    final subtitleVisibility = (1.0 - collapse).clamp(0.0, 1.0);
    final borderAlpha = lerpDouble(0.18, 0.26, collapse)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface.withValues(
              alpha: lerpDouble(0.90, 0.96, t)!,
            ),
            theme.colorScheme.surfaceContainerLowest.withValues(
              alpha: lerpDouble(0.82, 0.92, t)!,
            ),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(
              alpha: borderAlpha,
            ),
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: lerpDouble(7, 11, t)!,
            sigmaY: lerpDouble(7, 11, t)!,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: topInset + lerpDouble(9, 8, collapse)!,
              bottom: 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _onHeaderDragUpdate,
                  onVerticalDragEnd: _onHeaderDragEnd,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: SizedBox(
                      height: 52,
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 196),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '帖子',
                                        textAlign: TextAlign.left,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.2,
                                              fontSize: titleSize,
                                            ),
                                      ),
                                      ClipRect(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          heightFactor: subtitleVisibility,
                                          child: Opacity(
                                            opacity: subtitleVisibility,
                                            child: Text(
                                              _feeds[_tabController.index]
                                                  .label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 10),
                                  _buildForumSwitchButton(theme),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_forumProvider ==
                                    _PostsForumProvider.riverSide) ...[
                                  _buildOnlineUsersPill(theme),
                                  const SizedBox(width: 8),
                                ],
                                if (!useBottomSearchTab)
                                  IconButton.filledTonal(
                                    onPressed: _openSearchPage,
                                    tooltip: '搜索',
                                    icon: Hero(
                                      tag: postsSearchHeroTag,
                                      child: const Icon(Icons.search_rounded),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: Opacity(
                    opacity: secondFloorFade,
                    child: IgnorePointer(
                      ignoring: secondFloorFade <= 0.01,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TabBar(
                                controller: _tabController,
                                isScrollable: true,
                                tabAlignment: TabAlignment.start,
                                indicatorColor: theme.colorScheme.primary,
                                labelColor: theme.colorScheme.primary,
                                unselectedLabelColor:
                                    theme.colorScheme.onSurfaceVariant,
                                indicatorSize: TabBarIndicatorSize.label,
                                dividerColor: Colors.transparent,
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                labelPadding: const EdgeInsets.only(right: 24),
                                tabs: _feeds
                                    .map((feed) => Tab(text: feed.label))
                                    .toList(),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 20,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            _buildBoardFilterButton(theme),
                          ],
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
    );
  }

  Widget _buildBoardFilterButton(ThemeData theme) {
    final hasSelection = _selectedBoardId != null;
    final label = _selectedBoardName ?? '\u5168\u90e8\u677f\u5757';

    return Hero(
      tag: 'board_picker_hero',
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            return Material(color: Colors.transparent, child: toContext.widget);
          },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onBoardFilterPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(
              color: hasSelection
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
              borderRadius: BorderRadius.circular(20),
              border: hasSelection
                  ? Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasSelection
                      ? Icons.dashboard_rounded
                      : Icons.dashboard_customize_outlined,
                  size: 16,
                  color: hasSelection
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasSelection
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: hasSelection
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForumSwitchButton(ThemeData theme) {
    final current = _forumProvider;
    final target = current == _PostsForumProvider.riverSide
        ? _PostsForumProvider.qingShuiHePan
        : _PostsForumProvider.riverSide;
    final canSwitch = _isForumAvailable(target);
    final switched = current == _PostsForumProvider.qingShuiHePan;
    final iconColor = theme.colorScheme.onSurfaceVariant;
    final background = theme.colorScheme.surfaceContainerHigh.withValues(
      alpha: canSwitch ? 0.86 : 0.62,
    );

    return Tooltip(
      message: '切换论坛',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleForum,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: switched ? 0.72 : 1,
                  child: _buildForumSwitchLogo(current.logoAsset),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: switched ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sync_alt_rounded,
                      size: 11,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: switched ? 1 : 0.72,
                  child: _buildForumSwitchLogo(target.logoAsset),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForumSwitchLogo(String assetPath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Image.asset(assetPath, width: 14, height: 14, fit: BoxFit.cover),
    );
  }

  bool _shouldUseBottomSearchTab(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    if (MediaQuery.sizeOf(context).shortestSide >= 600) {
      return false;
    }
    return PlatformInfo.isIOS26OrHigher();
  }
}

// -----------------------------------------------------------------------------

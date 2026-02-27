import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:river/app/app_settings_controller.dart';
import 'package:river/core/account/account_store.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_topic_models.dart';

enum RiverHomeWidgetLaunchType { openApp, openFeed, openTopic }

class RiverHomeWidgetLaunchRequest {
  const RiverHomeWidgetLaunchRequest._({
    required this.type,
    this.feed,
    this.topicId,
  });

  const RiverHomeWidgetLaunchRequest.openApp()
    : this._(type: RiverHomeWidgetLaunchType.openApp);

  const RiverHomeWidgetLaunchRequest.openFeed(RiverSideTopicFeed value)
    : this._(type: RiverHomeWidgetLaunchType.openFeed, feed: value);

  const RiverHomeWidgetLaunchRequest.openTopic(int value)
    : this._(type: RiverHomeWidgetLaunchType.openTopic, topicId: value);

  final RiverHomeWidgetLaunchType type;
  final RiverSideTopicFeed? feed;
  final int? topicId;
}

class RiverHomeWidgetService {
  RiverHomeWidgetService({
    required RiverSideApiClient apiClient,
    required AccountStore accountStore,
    required AppSettingsController settingsController,
  }) : _apiClient = apiClient,
       _accountStore = accountStore,
       _settingsController = settingsController;

  static const String androidProviderName = 'RiverHomeWidgetProvider';
  static const String androidQualifiedProviderName =
      'com.example.river.RiverHomeWidgetProvider';
  static const String iOSWidgetName = 'RiverHomeWidget';
  static const String iOSAppGroupId = 'group.com.example.river.homewidget';

  static const String _keyState = 'river_widget_state';
  static const String _keyFeed = 'river_widget_feed';
  static const String _keyFeedLabel = 'river_widget_feed_label';
  static const String _keyTitle = 'river_widget_title';
  static const String _keyExcerpt = 'river_widget_excerpt';
  static const String _keyMeta = 'river_widget_meta';
  static const String _keyReplies = 'river_widget_replies';
  static const String _keyViews = 'river_widget_views';
  static const String _keyTopicId = 'river_widget_topic_id';
  static const String _keyAccent = 'river_widget_accent';

  final RiverSideApiClient _apiClient;
  final AccountStore _accountStore;
  final AppSettingsController _settingsController;

  Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await HomeWidget.setAppGroupId(iOSAppGroupId);
    } catch (_) {
      // iOS widget extension may not be configured in every build environment.
    }
  }

  Future<void> syncLatestTopic() async {
    final feed = _selectedFeed();
    final accent = _settingsController.themeSeedColor.toARGB32().toSigned(32);
    final cookieHeader = _activeRiverSideCookie();

    await _saveSharedBaseData(feed: feed, accentColorArgb: accent);
    try {
      final topics = await _apiClient.fetchTopicSummaries(
        feed: feed,
        page: 0,
        cookieHeader: cookieHeader,
      );
      final topic = topics.isEmpty ? null : topics.first;
      if (topic == null) {
        await _saveEmptyData(feed: feed);
      } else {
        await _saveTopicData(feed: feed, topic: topic);
      }
    } catch (_) {
      await _saveErrorData(feed: feed);
    }

    await HomeWidget.updateWidget(
      name: androidProviderName,
      qualifiedAndroidName: androidQualifiedProviderName,
      iOSName: iOSWidgetName,
    );
  }

  RiverHomeWidgetLaunchRequest? parseLaunchUri(Uri? uri) {
    if (uri == null) {
      return null;
    }
    if (uri.scheme != 'river' || uri.host != 'widget') {
      return null;
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    final first = segments.isEmpty ? '' : segments.first;
    switch (first) {
      case 'topic':
        final id = int.tryParse(
          segments.length > 1 ? segments.elementAt(1) : '',
        );
        if (id != null && id > 0) {
          return RiverHomeWidgetLaunchRequest.openTopic(id);
        }
        return const RiverHomeWidgetLaunchRequest.openApp();
      case 'feed':
        final raw = segments.length > 1
            ? segments.elementAt(1)
            : (uri.queryParameters['feed'] ?? '');
        final feed = _feedFromName(raw);
        if (feed != null) {
          return RiverHomeWidgetLaunchRequest.openFeed(feed);
        }
        return const RiverHomeWidgetLaunchRequest.openApp();
      default:
        return const RiverHomeWidgetLaunchRequest.openApp();
    }
  }

  RiverSideTopicFeed _selectedFeed() {
    switch (_settingsController.homeWidgetFeedPreference) {
      case AppHomeWidgetFeedPreference.latestCreated:
        return RiverSideTopicFeed.latestCreated;
      case AppHomeWidgetFeedPreference.latestReplied:
        return RiverSideTopicFeed.latestReplied;
      case AppHomeWidgetFeedPreference.hot:
        return RiverSideTopicFeed.hot;
    }
  }

  String? _activeRiverSideCookie() {
    final username = _accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) {
      return null;
    }
    return _accountStore.riverSideCookieHeaderFor(username);
  }

  Future<void> _saveSharedBaseData({
    required RiverSideTopicFeed feed,
    required int accentColorArgb,
  }) async {
    await HomeWidget.saveWidgetData<String>(_keyFeed, feed.name);
    await HomeWidget.saveWidgetData<String>(_keyFeedLabel, feed.label);
    await HomeWidget.saveWidgetData<int>(_keyAccent, accentColorArgb);
  }

  Future<void> _saveTopicData({
    required RiverSideTopicFeed feed,
    required RiverSideTopicSummary topic,
  }) async {
    final title = topic.title.trim().isEmpty ? '（无标题）' : topic.title.trim();
    final excerpt = _normalizeExcerpt(topic.excerpt);
    final meta = _buildMeta(topic);

    await HomeWidget.saveWidgetData<String>(_keyState, 'ok');
    await HomeWidget.saveWidgetData<String>(_keyFeed, feed.name);
    await HomeWidget.saveWidgetData<String>(_keyFeedLabel, feed.label);
    await HomeWidget.saveWidgetData<String>(_keyTitle, title);
    await HomeWidget.saveWidgetData<String>(
      _keyExcerpt,
      excerpt.isEmpty ? '打开聚河畔查看完整内容' : excerpt,
    );
    await HomeWidget.saveWidgetData<String>(_keyMeta, meta);
    await HomeWidget.saveWidgetData<int>(_keyReplies, topic.replyCount);
    await HomeWidget.saveWidgetData<int>(_keyViews, topic.viewCount);
    await HomeWidget.saveWidgetData<int>(_keyTopicId, topic.id);
  }

  Future<void> _saveEmptyData({required RiverSideTopicFeed feed}) async {
    await HomeWidget.saveWidgetData<String>(_keyState, 'empty');
    await HomeWidget.saveWidgetData<String>(_keyFeed, feed.name);
    await HomeWidget.saveWidgetData<String>(_keyFeedLabel, feed.label);
    await HomeWidget.saveWidgetData<String>(_keyTitle, '暂无可展示帖子');
    await HomeWidget.saveWidgetData<String>(_keyExcerpt, '打开聚河畔刷新后重试');
    await HomeWidget.saveWidgetData<String>(_keyMeta, '河畔小组件');
    await HomeWidget.saveWidgetData<int>(_keyReplies, 0);
    await HomeWidget.saveWidgetData<int>(_keyViews, 0);
    await HomeWidget.saveWidgetData<int>(_keyTopicId, 0);
  }

  Future<void> _saveErrorData({required RiverSideTopicFeed feed}) async {
    await HomeWidget.saveWidgetData<String>(_keyState, 'error');
    await HomeWidget.saveWidgetData<String>(_keyFeed, feed.name);
    await HomeWidget.saveWidgetData<String>(_keyFeedLabel, feed.label);
    await HomeWidget.saveWidgetData<String>(_keyTitle, '小组件更新失败');
    await HomeWidget.saveWidgetData<String>(_keyExcerpt, '请稍后打开 App 再次同步');
    await HomeWidget.saveWidgetData<String>(_keyMeta, '河畔小组件');
    await HomeWidget.saveWidgetData<int>(_keyReplies, 0);
    await HomeWidget.saveWidgetData<int>(_keyViews, 0);
    await HomeWidget.saveWidgetData<int>(_keyTopicId, 0);
  }

  String _normalizeExcerpt(String source) {
    final compact = source
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    if (compact.length <= 90) {
      return compact;
    }
    return '${compact.substring(0, 90).trimRight()}…';
  }

  String _buildMeta(RiverSideTopicSummary topic) {
    final parts = <String>[
      if (topic.categoryName.trim().isNotEmpty) topic.categoryName.trim(),
      if (topic.authorDisplayName.trim().isNotEmpty) topic.authorDisplayName,
      if (topic.createdAt != null) _formatDate(topic.createdAt!),
    ];
    if (parts.isEmpty) {
      return '聚河畔';
    }
    return parts.join(' · ');
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  RiverSideTopicFeed? _feedFromName(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final value in RiverSideTopicFeed.values) {
      if (value.name.toLowerCase() == normalized) {
        return value;
      }
    }
    return null;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:river/core/config/server_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppFontWeightPreset { regular, medium, bold }

enum AppAppIconPreset {
  origin,
  quality,
  pixel,
  cloud,
  neon,
  vaporwave,
  china,
  chengdu,
  animation,
  sweet,
}

enum AppCornerPreset { compact, standard, relaxed }

enum AppAiProvider { deepseek, openAiCompatible }

enum AppHomeForumPreference { riverSide, qingShuiHePan }

enum AppHomeWidgetFeedPreference { latestCreated, latestReplied, hot }

class AppSettingsController extends ChangeNotifier {
  static const List<String> defaultPostsTabOrder = <String>[
    'latestCreated',
    'latestReplied',
    'favorites',
    'footprints',
    'hot',
  ];

  static const String _themeModeKey = 'app.theme_mode';
  static const String _themeSeedColorKey = 'app.theme_seed_color';
  static const String _fontScaleKey = 'app.font_scale';
  static const String _fontWeightScaleKey = 'app.font_weight_scale';
  static const String _fontWeightPresetKey = 'app.font_weight_preset';
  static const String _fontFamilyNameKey = 'app.font_family_name';
  static const String _legacyFontFamilyPresetKey = 'app.font_family_preset';
  static const String _iconPresetKey = 'app.icon_preset';
  static const String _compactDensityKey = 'app.compact_density';
  static const String _reduceMotionKey = 'app.reduce_motion';
  static const String _cornerPresetKey = 'app.corner_preset';
  static const String _postsRealtimeRefreshBannerKey =
      'app.posts_realtime_refresh_banner';
  static const String _notificationsRealtimeRefreshBannerKey =
      'app.notifications_realtime_refresh_banner';
  static const String _inAppMessagesKey = 'app.in_app_messages';
  static const String _autoCollapseTopicBodyKey = 'app.auto_collapse_topic_body';
  static const String _postsTabOrderKey = 'app.posts_tab_order';
  static const String _topicCommentsRealtimeRefreshBannerKey =
      'app.topic_comments_realtime_refresh_banner';
  static const String _postsSecondFloorGuideKey =
      'app.posts_second_floor_guide';
  static const String _riverSideBaseUrlKey = 'app.riverside_base_url';
  static const String _qingShuiHePanBaseUrlKey = 'app.qingshuihepan_base_url';
  static const String _updateManifestUrlKey = 'app.update_manifest_url';
  static const String _miniAppsManifestUrlKey = 'app.mini_apps_manifest_url';
  static const String _aiProviderKey = 'app.ai_provider';
  static const String _aiBaseUrlKey = 'app.ai_base_url';
  static const String _aiModelKey = 'app.ai_model';
  static const String _aiApiKeyKey = 'app.ai_api_key';
  static const String _aiSystemPromptKey = 'app.ai_system_prompt';
  static const String _aiTemperatureKey = 'app.ai_temperature';
  static const String _developerModeEnabledKey = 'app.developer_mode_enabled';
  static const String _homeForumPreferenceKey = 'app.home_forum_preference';
  static const String _homeWidgetFeedPreferenceKey =
      'app.home_widget_feed_preference';
  static const String _miniAppRemotePreviewEnabledKey =
      'app.mini_app_remote_preview_enabled';
  static const String _picUiEnabledKey = 'app.picui_enabled';
  static const String _picUiApiBaseUrlKey = 'app.picui_api_base_url';
  static const String _picUiApiTokenKey = 'app.picui_api_token';
  static const String _picUiDefaultPermissionKey =
      'app.picui_default_permission';
  static const String _picUiDefaultStrategyIdKey =
      'app.picui_default_strategy_id';
  static const String _picUiDefaultAlbumIdKey = 'app.picui_default_album_id';
  static const String _picUiTempUploadTokenKey = 'app.picui_temp_upload_token';
  static const String _picUiExpiredAtKey = 'app.picui_expired_at';
  static const String _legacyPicGoEnabledKey = 'app.picgo_enabled';
  static const String _legacyPicGoApiBaseUrlKey = 'app.picgo_api_base_url';
  static const String _legacyPicGoApiKeyKey = 'app.picgo_api_key';

  static const Color defaultSeedColor = Color(0xFF12457A);
  static const String defaultFontFamilyName = 'HarmonyOS Sans';
  static const String defaultAiBaseUrl =
      'https://api.deepseek.com/v1/chat/completions';
  static const String defaultAiModel = 'deepseek-chat';
  static const String defaultAiSystemPrompt =
      '你是 River App 的写作助手，请用简洁、自然、友好的中文输出，不要添加多余解释。';
  static const String defaultPicUiApiBaseUrl = 'https://picui.cn';

  ThemeMode _themeMode = ThemeMode.system;
  Color _themeSeedColor = defaultSeedColor;
  double _fontScale = 1.0;
  double _fontWeightScale = 1.0;
  String? _fontFamilyName = defaultFontFamilyName;
  AppAppIconPreset _iconPreset = AppAppIconPreset.origin;
  AppCornerPreset _cornerPreset = AppCornerPreset.standard;
  bool _compactDensity = false;
  bool _reduceMotion = false;
  bool _showPostsRealtimeRefreshBanner = true;
  bool _showNotificationsRealtimeRefreshBanner = true;
  bool _showInAppMessages = true;
  bool _autoCollapseTopicBody = true;
  List<String> _postsTabOrder = List<String>.from(defaultPostsTabOrder);
  bool _showTopicCommentsRealtimeRefreshBanner = true;
  bool _showPostsSecondFloorGuide = true;
  String _riverSideBaseUrl = RiverServerConfig.defaultBaseUrl;
  String _qingShuiHePanBaseUrl = RiverServerConfig.defaultQingShuiHePanBaseUrl;
  String _updateManifestUrl = RiverServerConfig.defaultUpdateManifestUrl;
  String _miniAppsManifestUrl = RiverServerConfig.defaultMiniAppsManifestUrl;
  AppAiProvider _aiProvider = AppAiProvider.deepseek;
  String _aiBaseUrl = defaultAiBaseUrl;
  String _aiModel = defaultAiModel;
  String _aiApiKey = '';
  String _aiSystemPrompt = defaultAiSystemPrompt;
  double _aiTemperature = 0.7;
  bool _developerModeEnabled = false;
  AppHomeForumPreference _homeForumPreference =
      AppHomeForumPreference.riverSide;
  AppHomeWidgetFeedPreference _homeWidgetFeedPreference =
      AppHomeWidgetFeedPreference.latestReplied;
  bool _miniAppRemotePreviewEnabled = false;
  bool _picUiEnabled = false;
  String _picUiApiBaseUrl = defaultPicUiApiBaseUrl;
  String _picUiApiToken = '';
  int _picUiDefaultPermission = 1;
  int? _picUiDefaultStrategyId;
  int? _picUiDefaultAlbumId;
  String _picUiTempUploadToken = '';
  String _picUiExpiredAt = '';

  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;
  Color get themeSeedColor => _themeSeedColor;
  double get fontScale => _fontScale;
  double get fontWeightScale => _fontWeightScale;
  String? get fontFamilyName => _fontFamilyName;
  AppAppIconPreset get iconPreset => _iconPreset;
  AppCornerPreset get cornerPreset => _cornerPreset;
  bool get compactDensity => _compactDensity;
  bool get reduceMotion => _reduceMotion;
  bool get showPostsRealtimeRefreshBanner => _showPostsRealtimeRefreshBanner;
  bool get showNotificationsRealtimeRefreshBanner =>
      _showNotificationsRealtimeRefreshBanner;
  bool get showInAppMessages => _showInAppMessages;
  bool get autoCollapseTopicBody => _autoCollapseTopicBody;
  List<String> get postsTabOrder => List<String>.unmodifiable(_postsTabOrder);
  bool get showTopicCommentsRealtimeRefreshBanner =>
      _showTopicCommentsRealtimeRefreshBanner;
  bool get showPostsSecondFloorGuide => _showPostsSecondFloorGuide;
  String get riverSideBaseUrl => _riverSideBaseUrl;
  String get qingShuiHePanBaseUrl => _qingShuiHePanBaseUrl;
  String get updateManifestUrl => _updateManifestUrl;
  String get miniAppsManifestUrl => _miniAppsManifestUrl;
  AppAiProvider get aiProvider => _aiProvider;
  String get aiBaseUrl => _aiBaseUrl;
  String get aiModel => _aiModel;
  String get aiApiKey => _aiApiKey;
  String get aiSystemPrompt => _aiSystemPrompt;
  double get aiTemperature => _aiTemperature;
  bool get developerModeEnabled => _developerModeEnabled;
  AppHomeForumPreference get homeForumPreference => _homeForumPreference;
  AppHomeWidgetFeedPreference get homeWidgetFeedPreference =>
      _homeWidgetFeedPreference;
  bool get miniAppRemotePreviewEnabled => _miniAppRemotePreviewEnabled;
  bool get picUiEnabled => _picUiEnabled;
  String get picUiApiBaseUrl => _picUiApiBaseUrl;
  String get picUiApiToken => _picUiApiToken;
  int get picUiDefaultPermission => _picUiDefaultPermission;
  int? get picUiDefaultStrategyId => _picUiDefaultStrategyId;
  int? get picUiDefaultAlbumId => _picUiDefaultAlbumId;
  String get picUiTempUploadToken => _picUiTempUploadToken;
  String get picUiExpiredAt => _picUiExpiredAt;
  bool get picUiConfigured =>
      _picUiApiBaseUrl.trim().isNotEmpty && _picUiApiToken.trim().isNotEmpty;
  bool get aiConfigured =>
      _aiBaseUrl.trim().isNotEmpty &&
      _aiModel.trim().isNotEmpty &&
      _aiApiKey.trim().isNotEmpty;

  Future<void> initialize({
    Future<SharedPreferences>? sharedPreferencesFuture,
  }) async {
    _prefs ??= await (sharedPreferencesFuture ?? SharedPreferences.getInstance());

    final themeModeRaw = _prefs?.getString(_themeModeKey);
    if (themeModeRaw != null) {
      for (final mode in ThemeMode.values) {
        if (mode.name == themeModeRaw) {
          _themeMode = mode;
          break;
        }
      }
    }

    final seedColorValue = _prefs?.getInt(_themeSeedColorKey);
    if (seedColorValue != null) {
      _themeSeedColor = Color(seedColorValue);
    }

    final scaleValue = _prefs?.getDouble(_fontScaleKey);
    if (scaleValue != null) {
      _fontScale = _clampFontScale(scaleValue);
    }

    final fontWeightScaleValue = _prefs?.getDouble(_fontWeightScaleKey);
    if (fontWeightScaleValue != null) {
      _fontWeightScale = _clampFontWeightScale(fontWeightScaleValue);
    } else {
      final fontWeightRaw = _prefs?.getString(_fontWeightPresetKey);
      if (fontWeightRaw != null) {
        for (final value in AppFontWeightPreset.values) {
          if (value.name == fontWeightRaw) {
            _fontWeightScale = _legacyPresetToScale(value);
            break;
          }
        }
      }
    }

    final rawFontFamily = _prefs?.getString(_fontFamilyNameKey);
    if (rawFontFamily != null) {
      final trimmed = rawFontFamily.trim();
      _fontFamilyName = trimmed.isEmpty ? null : trimmed;
    } else {
      final legacyPreset = _prefs?.getString(_legacyFontFamilyPresetKey);
      _fontFamilyName =
          _mapLegacyFontPresetToFamily(legacyPreset) ?? defaultFontFamilyName;
    }

    final iconPresetRaw = _normalizeLegacyIconPresetName(
      _prefs?.getString(_iconPresetKey),
    );
    if (iconPresetRaw != null) {
      for (final value in AppAppIconPreset.values) {
        if (value.name == iconPresetRaw) {
          _iconPreset = value;
          break;
        }
      }
    }

    final cornerPresetRaw = _prefs?.getString(_cornerPresetKey);
    if (cornerPresetRaw != null) {
      for (final value in AppCornerPreset.values) {
        if (value.name == cornerPresetRaw) {
          _cornerPreset = value;
          break;
        }
      }
    }

    _compactDensity = _prefs?.getBool(_compactDensityKey) ?? false;
    _reduceMotion = _prefs?.getBool(_reduceMotionKey) ?? false;
    _showPostsRealtimeRefreshBanner =
        _prefs?.getBool(_postsRealtimeRefreshBannerKey) ?? true;
    _showNotificationsRealtimeRefreshBanner =
        _prefs?.getBool(_notificationsRealtimeRefreshBannerKey) ?? true;
    _showInAppMessages =
        _prefs?.getBool(_inAppMessagesKey) ??
        _prefs?.getBool(_notificationsRealtimeRefreshBannerKey) ??
        true;
    _autoCollapseTopicBody =
        _prefs?.getBool(_autoCollapseTopicBodyKey) ?? true;
    _postsTabOrder = _normalizePostsTabOrder(
      _prefs?.getStringList(_postsTabOrderKey),
    );
    _showTopicCommentsRealtimeRefreshBanner =
        _prefs?.getBool(_topicCommentsRealtimeRefreshBannerKey) ?? true;
    _showPostsSecondFloorGuide =
        _prefs?.getBool(_postsSecondFloorGuideKey) ?? true;

    final rawBaseUrl = _prefs?.getString(_riverSideBaseUrlKey);
    if (rawBaseUrl != null && rawBaseUrl.trim().isNotEmpty) {
      try {
        _riverSideBaseUrl = RiverServerConfig.normalizeBaseUrl(rawBaseUrl);
      } catch (_) {
        _riverSideBaseUrl = RiverServerConfig.defaultBaseUrl;
      }
    }

    final rawQingBaseUrl = _prefs?.getString(_qingShuiHePanBaseUrlKey);
    if (rawQingBaseUrl != null && rawQingBaseUrl.trim().isNotEmpty) {
      try {
        _qingShuiHePanBaseUrl = RiverServerConfig.normalizeBaseUrl(
          rawQingBaseUrl,
        );
      } catch (_) {
        _qingShuiHePanBaseUrl = RiverServerConfig.defaultQingShuiHePanBaseUrl;
      }
    }

    final rawUpdateUrl = _prefs?.getString(_updateManifestUrlKey);
    if (rawUpdateUrl != null && rawUpdateUrl.trim().isNotEmpty) {
      try {
        _updateManifestUrl = RiverServerConfig.normalizeUrl(rawUpdateUrl);
      } catch (_) {
        _updateManifestUrl = RiverServerConfig.defaultUpdateManifestUrl;
      }
    }

    final rawMiniAppsUrl = _prefs?.getString(_miniAppsManifestUrlKey);
    if (rawMiniAppsUrl != null && rawMiniAppsUrl.trim().isNotEmpty) {
      try {
        _miniAppsManifestUrl = RiverServerConfig.normalizeUrl(rawMiniAppsUrl);
      } catch (_) {
        _miniAppsManifestUrl = RiverServerConfig.defaultMiniAppsManifestUrl;
      }
    }

    final aiProviderRaw = _prefs?.getString(_aiProviderKey);
    if (aiProviderRaw != null) {
      for (final provider in AppAiProvider.values) {
        if (provider.name == aiProviderRaw) {
          _aiProvider = provider;
          break;
        }
      }
    }

    final aiBaseUrlRaw = _prefs?.getString(_aiBaseUrlKey);
    if (aiBaseUrlRaw != null && aiBaseUrlRaw.trim().isNotEmpty) {
      try {
        _aiBaseUrl = RiverServerConfig.normalizeUrl(aiBaseUrlRaw);
      } catch (_) {
        _aiBaseUrl = defaultAiBaseUrl;
      }
    }

    final aiModelRaw = _prefs?.getString(_aiModelKey);
    if (aiModelRaw != null) {
      final model = aiModelRaw.trim();
      _aiModel = model.isEmpty ? defaultAiModel : model;
    }

    final aiApiKeyRaw = _prefs?.getString(_aiApiKeyKey);
    if (aiApiKeyRaw != null) {
      _aiApiKey = aiApiKeyRaw.trim();
    }

    final aiSystemPromptRaw = _prefs?.getString(_aiSystemPromptKey);
    if (aiSystemPromptRaw != null) {
      final prompt = aiSystemPromptRaw.trim();
      _aiSystemPrompt = prompt.isEmpty ? defaultAiSystemPrompt : prompt;
    }

    final aiTemperatureRaw = _prefs?.getDouble(_aiTemperatureKey);
    if (aiTemperatureRaw != null) {
      _aiTemperature = _clampAiTemperature(aiTemperatureRaw);
    }

    _developerModeEnabled = _prefs?.getBool(_developerModeEnabledKey) ?? false;
    final homeForumRaw = _prefs?.getString(_homeForumPreferenceKey);
    if (homeForumRaw != null) {
      for (final value in AppHomeForumPreference.values) {
        if (value.name == homeForumRaw) {
          _homeForumPreference = value;
          break;
        }
      }
    }
    final homeWidgetFeedRaw = _prefs?.getString(_homeWidgetFeedPreferenceKey);
    if (homeWidgetFeedRaw != null) {
      for (final value in AppHomeWidgetFeedPreference.values) {
        if (value.name == homeWidgetFeedRaw) {
          _homeWidgetFeedPreference = value;
          break;
        }
      }
    }
    _miniAppRemotePreviewEnabled =
        _prefs?.getBool(_miniAppRemotePreviewEnabledKey) ?? false;
    _picUiEnabled =
        _prefs?.getBool(_picUiEnabledKey) ??
        _prefs?.getBool(_legacyPicGoEnabledKey) ??
        false;

    final picUiApiBaseUrlRaw =
        _prefs?.getString(_picUiApiBaseUrlKey) ??
        _prefs?.getString(_legacyPicGoApiBaseUrlKey);
    if (picUiApiBaseUrlRaw != null && picUiApiBaseUrlRaw.trim().isNotEmpty) {
      try {
        _picUiApiBaseUrl = RiverServerConfig.normalizeBaseUrl(
          picUiApiBaseUrlRaw,
        );
      } catch (_) {
        _picUiApiBaseUrl = defaultPicUiApiBaseUrl;
      }
    }

    final picUiApiTokenRaw =
        _prefs?.getString(_picUiApiTokenKey) ??
        _prefs?.getString(_legacyPicGoApiKeyKey);
    if (picUiApiTokenRaw != null) {
      _picUiApiToken = picUiApiTokenRaw.trim();
    }

    final picUiPermissionRaw = _prefs?.getInt(_picUiDefaultPermissionKey);
    if (picUiPermissionRaw != null &&
        (picUiPermissionRaw == 0 || picUiPermissionRaw == 1)) {
      _picUiDefaultPermission = picUiPermissionRaw;
    }
    final picUiStrategyRaw = _prefs?.getInt(_picUiDefaultStrategyIdKey);
    if (picUiStrategyRaw != null && picUiStrategyRaw > 0) {
      _picUiDefaultStrategyId = picUiStrategyRaw;
    }
    final picUiAlbumRaw = _prefs?.getInt(_picUiDefaultAlbumIdKey);
    if (picUiAlbumRaw != null && picUiAlbumRaw > 0) {
      _picUiDefaultAlbumId = picUiAlbumRaw;
    }
    _picUiTempUploadToken = (_prefs?.getString(_picUiTempUploadTokenKey) ?? '')
        .trim();
    _picUiExpiredAt = (_prefs?.getString(_picUiExpiredAtKey) ?? '').trim();

    RiverServerConfig.instance.apply(
      baseUrl: _riverSideBaseUrl,
      qingShuiHePanBaseUrl: _qingShuiHePanBaseUrl,
      updateManifestUrl: _updateManifestUrl,
      miniAppsManifestUrl: _miniAppsManifestUrl,
    );
  }

  void updateThemeMode(ThemeMode value) {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    notifyListeners();
    unawaited(_saveThemeMode());
  }

  void updateThemeSeedColor(Color value) {
    if (_themeSeedColor.toARGB32() == value.toARGB32()) {
      return;
    }
    _themeSeedColor = value;
    notifyListeners();
    unawaited(_saveThemeSeedColor());
  }

  void updateFontScale(double value) {
    final next = _clampFontScale(value);
    if ((_fontScale - next).abs() < 0.001) {
      return;
    }
    _fontScale = next;
    notifyListeners();
    unawaited(_saveFontScale());
  }

  void updateFontWeightScale(double value) {
    final next = _clampFontWeightScale(value);
    if ((_fontWeightScale - next).abs() < 0.001) {
      return;
    }
    _fontWeightScale = next;
    notifyListeners();
    unawaited(_saveFontWeightScale());
  }

  void updateFontWeightPreset(AppFontWeightPreset value) {
    updateFontWeightScale(_legacyPresetToScale(value));
  }

  void updateFontFamilyName(String? value) {
    final next = value?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_fontFamilyName == normalized) {
      return;
    }
    _fontFamilyName = normalized;
    notifyListeners();
    unawaited(_saveFontFamilyName());
  }

  void updateIconPreset(AppAppIconPreset value) {
    if (_iconPreset == value) {
      return;
    }
    _iconPreset = value;
    notifyListeners();
    unawaited(_saveIconPreset());
  }

  void updateCompactDensity(bool value) {
    if (_compactDensity == value) {
      return;
    }
    _compactDensity = value;
    notifyListeners();
    unawaited(_saveCompactDensity());
  }

  void updateReduceMotion(bool value) {
    if (_reduceMotion == value) {
      return;
    }
    _reduceMotion = value;
    notifyListeners();
    unawaited(_saveReduceMotion());
  }

  void updateCornerPreset(AppCornerPreset value) {
    if (_cornerPreset == value) {
      return;
    }
    _cornerPreset = value;
    notifyListeners();
    unawaited(_saveCornerPreset());
  }

  void updateShowPostsRealtimeRefreshBanner(bool value) {
    if (_showPostsRealtimeRefreshBanner == value) {
      return;
    }
    _showPostsRealtimeRefreshBanner = value;
    notifyListeners();
    unawaited(_saveShowPostsRealtimeRefreshBanner());
  }

  void updateShowNotificationsRealtimeRefreshBanner(bool value) {
    if (_showNotificationsRealtimeRefreshBanner == value) {
      return;
    }
    _showNotificationsRealtimeRefreshBanner = value;
    notifyListeners();
    unawaited(_saveShowNotificationsRealtimeRefreshBanner());
  }

  void updateShowInAppMessages(bool value) {
    if (_showInAppMessages == value) {
      return;
    }
    _showInAppMessages = value;
    notifyListeners();
    unawaited(_saveShowInAppMessages());
  }

  void updateAutoCollapseTopicBody(bool value) {
    if (_autoCollapseTopicBody == value) {
      return;
    }
    _autoCollapseTopicBody = value;
    notifyListeners();
    unawaited(_saveAutoCollapseTopicBody());
  }

  void updatePostsTabOrder(List<String> value) {
    final normalized = _normalizePostsTabOrder(value);
    if (listEquals(_postsTabOrder, normalized)) {
      return;
    }
    _postsTabOrder = normalized;
    notifyListeners();
    unawaited(_savePostsTabOrder());
  }

  void updateShowTopicCommentsRealtimeRefreshBanner(bool value) {
    if (_showTopicCommentsRealtimeRefreshBanner == value) {
      return;
    }
    _showTopicCommentsRealtimeRefreshBanner = value;
    notifyListeners();
    unawaited(_saveShowTopicCommentsRealtimeRefreshBanner());
  }

  void markPostsSecondFloorGuideShown() {
    if (!_showPostsSecondFloorGuide) {
      return;
    }
    _showPostsSecondFloorGuide = false;
    notifyListeners();
    unawaited(_saveShowPostsSecondFloorGuide());
  }

  void resetGuideStates() {
    var changed = false;
    if (!_showPostsSecondFloorGuide) {
      _showPostsSecondFloorGuide = true;
      changed = true;
    }
    if (!changed) {
      return;
    }
    notifyListeners();
    unawaited(_saveShowPostsSecondFloorGuide());
  }

  void updateRiverSideBaseUrl(String value) {
    final normalized = RiverServerConfig.normalizeBaseUrl(value);
    if (_riverSideBaseUrl == normalized) {
      return;
    }
    _riverSideBaseUrl = normalized;
    RiverServerConfig.instance.updateBaseUrl(normalized);
    notifyListeners();
    unawaited(_saveRiverSideBaseUrl());
  }

  void updateQingShuiHePanBaseUrl(String value) {
    final normalized = RiverServerConfig.normalizeBaseUrl(value);
    if (_qingShuiHePanBaseUrl == normalized) {
      return;
    }
    _qingShuiHePanBaseUrl = normalized;
    RiverServerConfig.instance.setQingShuiHePanBaseUrl(normalized);
    notifyListeners();
    unawaited(_saveQingShuiHePanBaseUrl());
  }

  void updateUpdateManifestUrl(String value) {
    final normalized = RiverServerConfig.normalizeUrl(value);
    if (_updateManifestUrl == normalized) {
      return;
    }
    _updateManifestUrl = normalized;
    RiverServerConfig.instance.setUpdateManifestUrl(normalized);
    notifyListeners();
    unawaited(_saveUpdateManifestUrl());
  }

  void updateMiniAppsManifestUrl(String value) {
    final normalized = RiverServerConfig.normalizeUrl(value);
    if (_miniAppsManifestUrl == normalized) {
      return;
    }
    _miniAppsManifestUrl = normalized;
    RiverServerConfig.instance.setMiniAppsManifestUrl(normalized);
    notifyListeners();
    unawaited(_saveMiniAppsManifestUrl());
  }

  void updateAiProvider(AppAiProvider value) {
    if (_aiProvider == value) {
      return;
    }
    _aiProvider = value;
    notifyListeners();
    unawaited(_saveAiProvider());
  }

  void updateAiBaseUrl(String value) {
    final normalized = RiverServerConfig.normalizeUrl(value);
    if (_aiBaseUrl == normalized) {
      return;
    }
    _aiBaseUrl = normalized;
    notifyListeners();
    unawaited(_saveAiBaseUrl());
  }

  void updateAiModel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || _aiModel == normalized) {
      return;
    }
    _aiModel = normalized;
    notifyListeners();
    unawaited(_saveAiModel());
  }

  void updateAiApiKey(String value) {
    final normalized = value.trim();
    if (_aiApiKey == normalized) {
      return;
    }
    _aiApiKey = normalized;
    notifyListeners();
    unawaited(_saveAiApiKey());
  }

  void updateAiSystemPrompt(String value) {
    final normalized = value.trim();
    final next = normalized.isEmpty ? defaultAiSystemPrompt : normalized;
    if (_aiSystemPrompt == next) {
      return;
    }
    _aiSystemPrompt = next;
    notifyListeners();
    unawaited(_saveAiSystemPrompt());
  }

  void updateAiTemperature(double value) {
    final next = _clampAiTemperature(value);
    if ((_aiTemperature - next).abs() < 0.001) {
      return;
    }
    _aiTemperature = next;
    notifyListeners();
    unawaited(_saveAiTemperature());
  }

  void updateDeveloperModeEnabled(bool value) {
    if (_developerModeEnabled == value) {
      return;
    }
    _developerModeEnabled = value;
    notifyListeners();
    unawaited(_saveDeveloperModeEnabled());
  }

  void updateHomeForumPreference(AppHomeForumPreference value) {
    if (_homeForumPreference == value) {
      return;
    }
    _homeForumPreference = value;
    notifyListeners();
    unawaited(_saveHomeForumPreference());
  }

  void updateHomeWidgetFeedPreference(AppHomeWidgetFeedPreference value) {
    if (_homeWidgetFeedPreference == value) {
      return;
    }
    _homeWidgetFeedPreference = value;
    notifyListeners();
    unawaited(_saveHomeWidgetFeedPreference());
  }

  void updateMiniAppRemotePreviewEnabled(bool value) {
    if (_miniAppRemotePreviewEnabled == value) {
      return;
    }
    _miniAppRemotePreviewEnabled = value;
    notifyListeners();
    unawaited(_saveMiniAppRemotePreviewEnabled());
  }

  void updatePicUiEnabled(bool value) {
    if (_picUiEnabled == value) {
      return;
    }
    _picUiEnabled = value;
    notifyListeners();
    unawaited(_savePicUiEnabled());
  }

  void updatePicUiApiBaseUrl(String value) {
    final normalized = RiverServerConfig.normalizeBaseUrl(value);
    if (_picUiApiBaseUrl == normalized) {
      return;
    }
    _picUiApiBaseUrl = normalized;
    notifyListeners();
    unawaited(_savePicUiApiBaseUrl());
  }

  void updatePicUiApiToken(String value) {
    final normalized = value.trim();
    if (_picUiApiToken == normalized) {
      return;
    }
    _picUiApiToken = normalized;
    notifyListeners();
    unawaited(_savePicUiApiToken());
  }

  void updatePicUiDefaultPermission(int value) {
    final normalized = value == 0 ? 0 : 1;
    if (_picUiDefaultPermission == normalized) {
      return;
    }
    _picUiDefaultPermission = normalized;
    notifyListeners();
    unawaited(_savePicUiDefaultPermission());
  }

  void updatePicUiDefaultStrategyId(int? value) {
    final normalized = value != null && value > 0 ? value : null;
    if (_picUiDefaultStrategyId == normalized) {
      return;
    }
    _picUiDefaultStrategyId = normalized;
    notifyListeners();
    unawaited(_savePicUiDefaultStrategyId());
  }

  void updatePicUiDefaultAlbumId(int? value) {
    final normalized = value != null && value > 0 ? value : null;
    if (_picUiDefaultAlbumId == normalized) {
      return;
    }
    _picUiDefaultAlbumId = normalized;
    notifyListeners();
    unawaited(_savePicUiDefaultAlbumId());
  }

  void updatePicUiTempUploadToken(String value) {
    final normalized = value.trim();
    if (_picUiTempUploadToken == normalized) {
      return;
    }
    _picUiTempUploadToken = normalized;
    notifyListeners();
    unawaited(_savePicUiTempUploadToken());
  }

  void updatePicUiExpiredAt(String value) {
    final normalized = value.trim();
    if (_picUiExpiredAt == normalized) {
      return;
    }
    _picUiExpiredAt = normalized;
    notifyListeners();
    unawaited(_savePicUiExpiredAt());
  }

  String? _mapLegacyFontPresetToFamily(String? presetName) {
    switch (presetName) {
      case 'system':
        return null;
      case 'sans':
        return 'sans-serif';
      case 'sansThin':
        return 'sans-serif-thin';
      case 'sansLight':
        return 'sans-serif-light';
      case 'sansMedium':
        return 'sans-serif-medium';
      case 'sansBlack':
        return 'sans-serif-black';
      case 'rounded':
        return 'sans-serif-rounded';
      case 'condensed':
        return 'sans-serif-condensed';
      case 'condensedMedium':
        return 'sans-serif-condensed-medium';
      case 'smallCaps':
        return 'sans-serif-smallcaps';
      case 'serif':
        return 'serif';
      case 'monospace':
        return 'monospace';
      default:
        return null;
    }
  }

  String? _normalizeLegacyIconPresetName(String? rawName) {
    if (rawName == null) {
      return null;
    }
    switch (rawName.trim()) {
      case 'classic':
        return AppAppIconPreset.origin.name;
      case 'riverBlue':
        return AppAppIconPreset.quality.name;
      case 'minimal':
        return AppAppIconPreset.pixel.name;
      default:
        return rawName.trim();
    }
  }

  double _clampFontScale(double value) {
    if (value < 0.85) {
      return 0.85;
    }
    if (value > 1.4) {
      return 1.4;
    }
    return value;
  }

  double _clampFontWeightScale(double value) {
    if (value < 0.8) {
      return 0.8;
    }
    if (value > 1.25) {
      return 1.25;
    }
    return value;
  }

  AppFontWeightPreset _scaleToLegacyPreset(double scale) {
    if (scale < 0.94) {
      return AppFontWeightPreset.regular;
    }
    if (scale > 1.10) {
      return AppFontWeightPreset.bold;
    }
    return AppFontWeightPreset.medium;
  }

  double _legacyPresetToScale(AppFontWeightPreset preset) {
    return switch (preset) {
      AppFontWeightPreset.regular => 0.86,
      AppFontWeightPreset.medium => 1.0,
      AppFontWeightPreset.bold => 1.18,
    };
  }

  double _clampAiTemperature(double value) {
    if (value < 0) {
      return 0;
    }
    if (value > 2) {
      return 2;
    }
    return value;
  }

  Future<void> _saveThemeMode() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_themeModeKey, _themeMode.name);
  }

  Future<void> _saveThemeSeedColor() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_themeSeedColorKey, _themeSeedColor.toARGB32());
  }

  Future<void> _saveFontScale() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_fontScaleKey, _fontScale);
  }

  Future<void> _saveFontWeightScale() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_fontWeightScaleKey, _fontWeightScale);
    await _prefs!.setString(
      _fontWeightPresetKey,
      _scaleToLegacyPreset(_fontWeightScale).name,
    );
  }

  Future<void> _saveFontFamilyName() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_fontFamilyNameKey, _fontFamilyName ?? '');
  }

  Future<void> _saveIconPreset() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_iconPresetKey, _iconPreset.name);
  }

  Future<void> _saveCompactDensity() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_compactDensityKey, _compactDensity);
  }

  Future<void> _saveReduceMotion() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_reduceMotionKey, _reduceMotion);
  }

  Future<void> _saveCornerPreset() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_cornerPresetKey, _cornerPreset.name);
  }

  Future<void> _saveShowPostsRealtimeRefreshBanner() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(
      _postsRealtimeRefreshBannerKey,
      _showPostsRealtimeRefreshBanner,
    );
  }

  Future<void> _saveShowNotificationsRealtimeRefreshBanner() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(
      _notificationsRealtimeRefreshBannerKey,
      _showNotificationsRealtimeRefreshBanner,
    );
  }

  Future<void> _saveShowInAppMessages() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_inAppMessagesKey, _showInAppMessages);
  }

  Future<void> _saveAutoCollapseTopicBody() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_autoCollapseTopicBodyKey, _autoCollapseTopicBody);
  }

  Future<void> _savePostsTabOrder() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_postsTabOrderKey, _postsTabOrder);
  }

  Future<void> _saveShowTopicCommentsRealtimeRefreshBanner() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(
      _topicCommentsRealtimeRefreshBannerKey,
      _showTopicCommentsRealtimeRefreshBanner,
    );
  }

  List<String> _normalizePostsTabOrder(List<String>? raw) {
    final remaining = List<String>.from(defaultPostsTabOrder);
    final ordered = <String>[];
    for (final item in raw ?? const <String>[]) {
      final id = item.trim();
      if (id.isEmpty || !remaining.remove(id)) {
        continue;
      }
      ordered.add(id);
    }
    ordered.addAll(remaining);
    return ordered;
  }

  Future<void> _saveShowPostsSecondFloorGuide() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(
      _postsSecondFloorGuideKey,
      _showPostsSecondFloorGuide,
    );
  }

  Future<void> _saveRiverSideBaseUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_riverSideBaseUrlKey, _riverSideBaseUrl);
  }

  Future<void> _saveQingShuiHePanBaseUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_qingShuiHePanBaseUrlKey, _qingShuiHePanBaseUrl);
  }

  Future<void> _saveUpdateManifestUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_updateManifestUrlKey, _updateManifestUrl);
  }

  Future<void> _saveMiniAppsManifestUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_miniAppsManifestUrlKey, _miniAppsManifestUrl);
  }

  Future<void> _saveAiProvider() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_aiProviderKey, _aiProvider.name);
  }

  Future<void> _saveAiBaseUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_aiBaseUrlKey, _aiBaseUrl);
  }

  Future<void> _saveAiModel() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_aiModelKey, _aiModel);
  }

  Future<void> _saveAiApiKey() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_aiApiKeyKey, _aiApiKey);
  }

  Future<void> _saveAiSystemPrompt() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_aiSystemPromptKey, _aiSystemPrompt);
  }

  Future<void> _saveAiTemperature() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_aiTemperatureKey, _aiTemperature);
  }

  Future<void> _saveDeveloperModeEnabled() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_developerModeEnabledKey, _developerModeEnabled);
  }

  Future<void> _saveHomeForumPreference() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_homeForumPreferenceKey, _homeForumPreference.name);
  }

  Future<void> _saveHomeWidgetFeedPreference() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _homeWidgetFeedPreferenceKey,
      _homeWidgetFeedPreference.name,
    );
  }

  Future<void> _saveMiniAppRemotePreviewEnabled() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(
      _miniAppRemotePreviewEnabledKey,
      _miniAppRemotePreviewEnabled,
    );
  }

  Future<void> _savePicUiEnabled() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_picUiEnabledKey, _picUiEnabled);
  }

  Future<void> _savePicUiApiBaseUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_picUiApiBaseUrlKey, _picUiApiBaseUrl);
  }

  Future<void> _savePicUiApiToken() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_picUiApiTokenKey, _picUiApiToken);
  }

  Future<void> _savePicUiDefaultPermission() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_picUiDefaultPermissionKey, _picUiDefaultPermission);
  }

  Future<void> _savePicUiDefaultStrategyId() async {
    _prefs ??= await SharedPreferences.getInstance();
    final value = _picUiDefaultStrategyId;
    if (value == null) {
      await _prefs!.remove(_picUiDefaultStrategyIdKey);
      return;
    }
    await _prefs!.setInt(_picUiDefaultStrategyIdKey, value);
  }

  Future<void> _savePicUiDefaultAlbumId() async {
    _prefs ??= await SharedPreferences.getInstance();
    final value = _picUiDefaultAlbumId;
    if (value == null) {
      await _prefs!.remove(_picUiDefaultAlbumIdKey);
      return;
    }
    await _prefs!.setInt(_picUiDefaultAlbumIdKey, value);
  }

  Future<void> _savePicUiTempUploadToken() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_picUiTempUploadTokenKey, _picUiTempUploadToken);
  }

  Future<void> _savePicUiExpiredAt() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_picUiExpiredAtKey, _picUiExpiredAt);
  }
}

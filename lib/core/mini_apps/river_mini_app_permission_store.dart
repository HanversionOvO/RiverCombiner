import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RiverMiniAppNativePermission {
  network,
  clipboard,
  uiPrompt,
  haptics,
  systemInfo,
  mediaImage,
  fileAccess,
  location,
  scanCode,
  storage,
  phoneCall,
  forumIdentity,
}

extension RiverMiniAppNativePermissionX on RiverMiniAppNativePermission {
  String get key {
    switch (this) {
      case RiverMiniAppNativePermission.network:
        return 'network';
      case RiverMiniAppNativePermission.clipboard:
        return 'clipboard';
      case RiverMiniAppNativePermission.uiPrompt:
        return 'ui_prompt';
      case RiverMiniAppNativePermission.haptics:
        return 'haptics';
      case RiverMiniAppNativePermission.systemInfo:
        return 'system_info';
      case RiverMiniAppNativePermission.mediaImage:
        return 'media_image';
      case RiverMiniAppNativePermission.fileAccess:
        return 'file_access';
      case RiverMiniAppNativePermission.location:
        return 'location';
      case RiverMiniAppNativePermission.scanCode:
        return 'scan_code';
      case RiverMiniAppNativePermission.storage:
        return 'storage';
      case RiverMiniAppNativePermission.phoneCall:
        return 'phone_call';
      case RiverMiniAppNativePermission.forumIdentity:
        return 'forum_identity';
    }
  }

  String get title {
    switch (this) {
      case RiverMiniAppNativePermission.network:
        return '网络请求';
      case RiverMiniAppNativePermission.clipboard:
        return '剪贴板';
      case RiverMiniAppNativePermission.uiPrompt:
        return '界面弹窗';
      case RiverMiniAppNativePermission.haptics:
        return '震动反馈';
      case RiverMiniAppNativePermission.systemInfo:
        return '系统信息';
      case RiverMiniAppNativePermission.mediaImage:
        return '图片访问';
      case RiverMiniAppNativePermission.fileAccess:
        return '文件访问';
      case RiverMiniAppNativePermission.location:
        return '位置信息';
      case RiverMiniAppNativePermission.scanCode:
        return '扫码能力';
      case RiverMiniAppNativePermission.storage:
        return '本地缓存';
      case RiverMiniAppNativePermission.phoneCall:
        return '拨号能力';
      case RiverMiniAppNativePermission.forumIdentity:
        return '论坛身份';
    }
  }

  String get description {
    switch (this) {
      case RiverMiniAppNativePermission.network:
        return '允许小程序通过宿主发起网络请求';
      case RiverMiniAppNativePermission.clipboard:
        return '允许读取和写入系统剪贴板';
      case RiverMiniAppNativePermission.uiPrompt:
        return '允许展示宿主 Toast / 弹窗';
      case RiverMiniAppNativePermission.haptics:
        return '允许触发短震动或长震动反馈';
      case RiverMiniAppNativePermission.systemInfo:
        return '允许读取设备与系统环境信息';
      case RiverMiniAppNativePermission.mediaImage:
        return '允许调用图片选择等媒体能力';
      case RiverMiniAppNativePermission.fileAccess:
        return '允许调用文件选择与读取能力';
      case RiverMiniAppNativePermission.location:
        return '允许获取当前位置';
      case RiverMiniAppNativePermission.scanCode:
        return '允许调用扫码与相册识别';
      case RiverMiniAppNativePermission.storage:
        return '允许读写宿主为小程序分配的本地缓存';
      case RiverMiniAppNativePermission.phoneCall:
        return '允许拉起系统拨号页面';
      case RiverMiniAppNativePermission.forumIdentity:
        return '允许访问论坛登录态并发起身份授权';
    }
  }

  IconData get icon {
    switch (this) {
      case RiverMiniAppNativePermission.network:
        return Icons.wifi_rounded;
      case RiverMiniAppNativePermission.clipboard:
        return Icons.content_paste_rounded;
      case RiverMiniAppNativePermission.uiPrompt:
        return Icons.notifications_active_rounded;
      case RiverMiniAppNativePermission.haptics:
        return Icons.vibration_rounded;
      case RiverMiniAppNativePermission.systemInfo:
        return Icons.phone_android_rounded;
      case RiverMiniAppNativePermission.mediaImage:
        return Icons.photo_library_rounded;
      case RiverMiniAppNativePermission.fileAccess:
        return Icons.folder_open_rounded;
      case RiverMiniAppNativePermission.location:
        return Icons.location_on_rounded;
      case RiverMiniAppNativePermission.scanCode:
        return Icons.qr_code_scanner_rounded;
      case RiverMiniAppNativePermission.storage:
        return Icons.save_rounded;
      case RiverMiniAppNativePermission.phoneCall:
        return Icons.phone_rounded;
      case RiverMiniAppNativePermission.forumIdentity:
        return Icons.verified_user_rounded;
    }
  }
}

class RiverMiniAppPermissionState {
  const RiverMiniAppPermissionState({
    required this.granted,
    required this.prompted,
  });

  final bool granted;
  final bool prompted;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'granted': granted, 'prompted': prompted};
  }

  static RiverMiniAppPermissionState fromJson(Map<String, dynamic> json) {
    final granted = json['granted'] == true;
    final prompted = json['prompted'] == true;
    return RiverMiniAppPermissionState(granted: granted, prompted: prompted);
  }
}

class RiverMiniAppPermissionPolicy {
  const RiverMiniAppPermissionPolicy({required this.states});

  final Map<RiverMiniAppNativePermission, RiverMiniAppPermissionState> states;

  RiverMiniAppPermissionState? stateOf(RiverMiniAppNativePermission permission) {
    return states[permission];
  }

  bool isGranted(RiverMiniAppNativePermission permission) {
    final state = stateOf(permission);
    if (state != null) {
      return state.granted;
    }
    return permission == RiverMiniAppNativePermission.network;
  }

  bool isPrompted(RiverMiniAppNativePermission permission) {
    final state = stateOf(permission);
    if (state != null) {
      return state.prompted;
    }
    return permission == RiverMiniAppNativePermission.network;
  }

  RiverMiniAppPermissionPolicy upsert(
    RiverMiniAppNativePermission permission, {
    required bool granted,
    required bool prompted,
  }) {
    final next = Map<RiverMiniAppNativePermission, RiverMiniAppPermissionState>
        .from(states);
    next[permission] = RiverMiniAppPermissionState(
      granted: granted,
      prompted: prompted,
    );
    return RiverMiniAppPermissionPolicy(states: next);
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    for (final entry in states.entries) {
      map[entry.key.key] = entry.value.toJson();
    }
    return map;
  }

  static RiverMiniAppPermissionPolicy fromJson(Map<String, dynamic> json) {
    final states = <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{};
    for (final permission in RiverMiniAppNativePermission.values) {
      final raw = json[permission.key];
      if (raw is Map) {
        final normalized = <String, dynamic>{};
        for (final entry in raw.entries) {
          normalized['${entry.key}'] = entry.value;
        }
        states[permission] = RiverMiniAppPermissionState.fromJson(normalized);
      }
    }
    return RiverMiniAppPermissionPolicy(states: states);
  }
}

class RiverMiniAppPermissionStore {
  static const String _prefix = 'river.mini_apps.permissions.v1.';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _storageKey(String appId) => '$_prefix$appId';

  Future<RiverMiniAppPermissionPolicy> loadPolicy(String appId) async {
    final key = _storageKey(appId.trim());
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(key) ?? '';
    if (raw.trim().isEmpty) {
      return const RiverMiniAppPermissionPolicy(
        states: <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{},
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const RiverMiniAppPermissionPolicy(
          states: <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{},
        );
      }
      final normalized = <String, dynamic>{};
      for (final entry in decoded.entries) {
        normalized['${entry.key}'] = entry.value;
      }
      return RiverMiniAppPermissionPolicy.fromJson(normalized);
    } catch (_) {
      return const RiverMiniAppPermissionPolicy(
        states: <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{},
      );
    }
  }

  Future<RiverMiniAppPermissionPolicy> updatePermission({
    required String appId,
    required RiverMiniAppNativePermission permission,
    required bool granted,
    bool prompted = true,
  }) async {
    final current = await loadPolicy(appId);
    final next = current.upsert(
      permission,
      granted: granted,
      prompted: prompted,
    );
    final key = _storageKey(appId.trim());
    final prefs = await _ensurePrefs();
    await prefs.setString(key, jsonEncode(next.toJson()));
    return next;
  }
}


import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';

class RiverJPushService {
  RiverJPushService();

  static const String _defaultAppKey = '9d432f3526f8a81d6d4fbca7';
  static const String _defaultChannel = 'developer-default';

  final dynamic _jpush = JPush.newJPush();
  final ValueNotifier<String?> registrationId = ValueNotifier<String?>(null);
  final StreamController<Map<String, dynamic>> _openedNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;

  Stream<Map<String, dynamic>> get onNotificationOpened =>
      _openedNotificationController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _jpush.addEventHandler(
      onOpenNotification: (Map<String, dynamic> event) {
        _openedNotificationController.add(event);
      },
      onReceiveNotification: (Map<String, dynamic> event) {
        debugPrint('[JPush] onReceiveNotification: $event');
      },
      onReceiveMessage: (Map<String, dynamic> event) {
        debugPrint('[JPush] onReceiveMessage: $event');
      },
      onReceiveNotificationAuthorization: (Map<String, dynamic> event) {
        debugPrint('[JPush] onReceiveNotificationAuthorization: $event');
      },
    );

    try {
      _jpush.setup(
        appKey: _defaultAppKey,
        channel: _defaultChannel,
        production: kReleaseMode,
        debug: !kReleaseMode,
      );
    } catch (error) {
      debugPrint('[JPush] setup failed: $error');
      rethrow;
    }

    // iOS will use this; on Android this is safe to ignore.
    try {
      _jpush.applyPushAuthority();
    } catch (_) {
      // no-op
    }
    try {
      _jpush.requestRequiredPermission();
    } catch (_) {
      // no-op
    }

    await refreshRegistrationId();
    await _emitLaunchNotificationIfExists();
  }

  Future<void> _emitLaunchNotificationIfExists() async {
    try {
      final launchEvent = await _jpush.getLaunchAppNotification();
      if (launchEvent is Map && launchEvent.isNotEmpty) {
        _openedNotificationController.add(
          launchEvent.cast<String, dynamic>(),
        );
      }
    } catch (_) {
      // no-op
    }
  }

  Future<void> refreshRegistrationId() async {
    try {
      final rid = await _jpush.getRegistrationID();
      if (rid != null && rid.trim().isNotEmpty) {
        registrationId.value = rid.trim();
      }
    } catch (error) {
      debugPrint('[JPush] getRegistrationID failed: $error');
    }
  }

  Future<void> bindAlias(String? alias) async {
    final normalized = _normalizeAlias(alias);
    try {
      if (normalized == null) {
        await _jpush.deleteAlias();
      } else {
        await _jpush.setAlias(normalized);
      }
    } catch (error) {
      debugPrint('[JPush] bindAlias failed: $error');
    }
  }

  Future<void> bindTags(Iterable<String> tags) async {
    final normalized = tags
        .map((value) => _normalizeTag(value))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    try {
      if (normalized.isEmpty) {
        await _jpush.cleanTags();
      } else {
        await _jpush.setTags(normalized);
      }
    } catch (error) {
      debugPrint('[JPush] bindTags failed: $error');
    }
  }

  String? _normalizeAlias(String? source) {
    final raw = source?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final sanitized = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-@.]'), '_');
    if (sanitized.isEmpty) {
      return null;
    }
    return sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
  }

  String? _normalizeTag(String source) {
    final raw = source.trim();
    if (raw.isEmpty) {
      return null;
    }
    final sanitized = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-@.]'), '_');
    if (sanitized.isEmpty) {
      return null;
    }
    return sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
  }

  Future<void> dispose() async {
    await _openedNotificationController.close();
    registrationId.dispose();
  }
}

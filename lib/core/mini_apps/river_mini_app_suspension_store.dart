import 'package:river/core/mini_apps/river_mini_app_models.dart';

class RiverMiniAppSuspendedSession {
  const RiverMiniAppSuspendedSession({
    required this.appId,
    required this.appVersion,
    required this.url,
    required this.title,
    required this.savedAt,
  });

  final String appId;
  final String appVersion;
  final String url;
  final String title;
  final DateTime savedAt;
}

class RiverMiniAppSuspensionStore {
  RiverMiniAppSuspensionStore._();

  static const Duration _ttl = Duration(hours: 12);
  static final Map<String, RiverMiniAppSuspendedSession> _sessions =
      <String, RiverMiniAppSuspendedSession>{};

  static RiverMiniAppSuspendedSession? read({
    required String appId,
    required String appVersion,
  }) {
    final key = appId.trim();
    if (key.isEmpty) {
      return null;
    }
    final existing = _sessions[key];
    if (existing == null) {
      return null;
    }
    final expired = DateTime.now().difference(existing.savedAt) > _ttl;
    if (expired || existing.appVersion.trim() != appVersion.trim()) {
      _sessions.remove(key);
      return null;
    }
    return existing;
  }

  static void save({
    required RiverMiniAppEntry miniApp,
    required String url,
    required String title,
  }) {
    final key = miniApp.id.trim();
    final normalizedUrl = url.trim();
    if (key.isEmpty || normalizedUrl.isEmpty) {
      return;
    }
    _sessions[key] = RiverMiniAppSuspendedSession(
      appId: key,
      appVersion: miniApp.version.trim(),
      url: normalizedUrl,
      title: title.trim(),
      savedAt: DateTime.now(),
    );
  }

  static void clearById(String appId) {
    final key = appId.trim();
    if (key.isEmpty) {
      return;
    }
    _sessions.remove(key);
  }
}

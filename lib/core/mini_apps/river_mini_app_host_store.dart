import 'package:flutter/foundation.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';

class RiverMiniAppHostSession {
  const RiverMiniAppHostSession({
    required this.id,
    required this.miniApp,
    required this.launchRoute,
    required this.launchParams,
    required this.launchAction,
    required this.launchSource,
    required this.generation,
  });

  final String id;
  final RiverMiniAppEntry miniApp;
  final String launchRoute;
  final Map<String, dynamic> launchParams;
  final String launchAction;
  final String launchSource;
  final int generation;

  RiverMiniAppHostSession copyWith({
    RiverMiniAppEntry? miniApp,
    String? launchRoute,
    Map<String, dynamic>? launchParams,
    String? launchAction,
    String? launchSource,
    int? generation,
  }) {
    return RiverMiniAppHostSession(
      id: id,
      miniApp: miniApp ?? this.miniApp,
      launchRoute: launchRoute ?? this.launchRoute,
      launchParams: launchParams ?? this.launchParams,
      launchAction: launchAction ?? this.launchAction,
      launchSource: launchSource ?? this.launchSource,
      generation: generation ?? this.generation,
    );
  }
}

class RiverMiniAppHostStore extends ChangeNotifier {
  final Map<String, RiverMiniAppHostSession> _sessionsById =
      <String, RiverMiniAppHostSession>{};
  String? _activeSessionId;

  List<RiverMiniAppHostSession> get sessions =>
      _sessionsById.values.toList(growable: false);

  String? get activeSessionId => _activeSessionId;

  bool hasSession(String appId) => _sessionsById.containsKey(appId.trim());

  void open({
    required RiverMiniAppEntry miniApp,
    String launchRoute = '',
    Map<String, dynamic> launchParams = const <String, dynamic>{},
    String launchAction = '',
    String launchSource = '',
  }) {
    final id = miniApp.id.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = _sessionsById[id];
    if (existing == null) {
      _sessionsById[id] = RiverMiniAppHostSession(
        id: id,
        miniApp: miniApp,
        launchRoute: launchRoute,
        launchParams: Map<String, dynamic>.from(launchParams),
        launchAction: launchAction,
        launchSource: launchSource,
        generation: 1,
      );
    } else {
      final versionChanged =
          existing.miniApp.version.trim() != miniApp.version.trim();
      _sessionsById[id] = existing.copyWith(
        miniApp: miniApp,
        launchRoute: launchRoute,
        launchParams: Map<String, dynamic>.from(launchParams),
        launchAction: launchAction,
        launchSource: launchSource,
        generation: versionChanged
            ? existing.generation + 1
            : existing.generation,
      );
    }
    _activeSessionId = id;
    notifyListeners();
  }

  void activate(String appId) {
    final id = appId.trim();
    if (id.isEmpty || !_sessionsById.containsKey(id)) {
      return;
    }
    if (_activeSessionId == id) {
      return;
    }
    _activeSessionId = id;
    notifyListeners();
  }

  void suspend(String appId) {
    final id = appId.trim();
    if (id.isEmpty || _activeSessionId != id) {
      return;
    }
    _activeSessionId = null;
    notifyListeners();
  }

  void close(String appId) {
    final id = appId.trim();
    if (id.isEmpty) {
      return;
    }
    final removed = _sessionsById.remove(id);
    if (removed == null) {
      return;
    }
    if (_activeSessionId == id) {
      _activeSessionId = null;
    }
    notifyListeners();
  }
}

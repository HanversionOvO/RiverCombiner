import 'package:flutter/foundation.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';

class RiverMiniAppFloatingEntry {
  const RiverMiniAppFloatingEntry({
    required this.miniApp,
    required this.suspendedUrl,
    required this.suspendedTitle,
    required this.updatedAt,
  });

  final RiverMiniAppEntry miniApp;
  final String suspendedUrl;
  final String suspendedTitle;
  final DateTime updatedAt;
}

class RiverMiniAppFloatingStore extends ChangeNotifier {
  final Map<String, RiverMiniAppFloatingEntry> _entriesById =
      <String, RiverMiniAppFloatingEntry>{};

  List<RiverMiniAppFloatingEntry> get entries {
    final items = _entriesById.values.toList(growable: false);
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  bool get isEmpty => _entriesById.isEmpty;

  void upsert({
    required RiverMiniAppEntry miniApp,
    required String suspendedUrl,
    required String suspendedTitle,
  }) {
    final key = miniApp.id.trim();
    if (key.isEmpty) {
      return;
    }
    _entriesById[key] = RiverMiniAppFloatingEntry(
      miniApp: miniApp,
      suspendedUrl: suspendedUrl.trim(),
      suspendedTitle: suspendedTitle.trim(),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  RiverMiniAppFloatingEntry? removeById(String appId, {bool notify = true}) {
    final key = appId.trim();
    if (key.isEmpty) {
      return null;
    }
    final removed = _entriesById.remove(key);
    if (removed != null && notify) {
      notifyListeners();
    }
    return removed;
  }

  void clear() {
    if (_entriesById.isEmpty) {
      return;
    }
    _entriesById.clear();
    notifyListeners();
  }
}

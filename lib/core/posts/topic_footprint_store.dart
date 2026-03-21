import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class TopicFootprintEntry {
  const TopicFootprintEntry({
    required this.provider,
    required this.topicId,
    required this.title,
    required this.excerpt,
    required this.categoryName,
    required this.replyCount,
    required this.commentCount,
    required this.viewCount,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.visitedAtMillis,
    this.categoryId,
    this.authorUserId,
    this.isHot = false,
    this.isPinned = false,
  });

  final AccountProvider provider;
  final int topicId;
  final String title;
  final String excerpt;
  final int? categoryId;
  final String categoryName;
  final int replyCount;
  final int? commentCount;
  final int viewCount;
  final String authorDisplayName;
  final String authorUsername;
  final int? authorUserId;
  final String authorAvatarUrl;
  final bool isHot;
  final bool isPinned;
  final int visitedAtMillis;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider': provider.name,
      'topicId': topicId,
      'title': title,
      'excerpt': excerpt,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'replyCount': replyCount,
      'commentCount': commentCount,
      'viewCount': viewCount,
      'authorDisplayName': authorDisplayName,
      'authorUsername': authorUsername,
      'authorUserId': authorUserId,
      'authorAvatarUrl': authorAvatarUrl,
      'isHot': isHot,
      'isPinned': isPinned,
      'visitedAtMillis': visitedAtMillis,
    };
  }

  static TopicFootprintEntry? fromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    final providerName = (map['provider'] ?? '').toString().trim();
    final provider = AccountProvider.values
        .where((item) => item.name == providerName)
        .cast<AccountProvider?>()
        .firstWhere((item) => item != null, orElse: () => null);
    final topicId = _asInt(map['topicId']) ?? 0;
    final title = (map['title'] ?? '').toString().trim();
    if (provider == null || topicId <= 0 || title.isEmpty) {
      return null;
    }
    return TopicFootprintEntry(
      provider: provider,
      topicId: topicId,
      title: title,
      excerpt: (map['excerpt'] ?? '').toString(),
      categoryId: _asInt(map['categoryId']),
      categoryName: (map['categoryName'] ?? '').toString(),
      replyCount: _asInt(map['replyCount']) ?? 0,
      commentCount: _asInt(map['commentCount']),
      viewCount: _asInt(map['viewCount']) ?? 0,
      authorDisplayName: (map['authorDisplayName'] ?? '').toString(),
      authorUsername: (map['authorUsername'] ?? '').toString(),
      authorUserId: _asInt(map['authorUserId']),
      authorAvatarUrl: (map['authorAvatarUrl'] ?? '').toString(),
      isHot: map['isHot'] == true,
      isPinned: map['isPinned'] == true,
      visitedAtMillis:
          _asInt(map['visitedAtMillis']) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  RiverSideTopicSummary toTopicSummary() {
    return RiverSideTopicSummary(
      id: topicId,
      title: title,
      excerpt: excerpt,
      categoryId: categoryId,
      categoryName: categoryName,
      replyCount: replyCount,
      commentCount: commentCount,
      viewCount: viewCount,
      createdAt: DateTime.fromMillisecondsSinceEpoch(visitedAtMillis),
      authorDisplayName: authorDisplayName,
      authorUsername: authorUsername,
      authorUserId: authorUserId,
      authorAvatarUrl: authorAvatarUrl,
      isHot: isHot,
      isPinned: isPinned,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class TopicFootprintStore extends ChangeNotifier {
  static const String _storageKey = 'river.topic.footprints.v1';
  static const int _maxCount = 200;

  SharedPreferences? _prefs;
  bool _initialized = false;
  final List<TopicFootprintEntry> _entries = <TopicFootprintEntry>[];

  Future<void> initialize({
    Future<SharedPreferences>? sharedPreferencesFuture,
  }) async {
    if (_initialized) {
      return;
    }
    _prefs = await (sharedPreferencesFuture ?? SharedPreferences.getInstance());
    _initialized = true;
    final rawList = _prefs?.getStringList(_storageKey) ?? const <String>[];
    _entries
      ..clear()
      ..addAll(
        rawList.map((raw) {
          try {
            return TopicFootprintEntry.fromJson(jsonDecode(raw));
          } catch (_) {
            return null;
          }
        }).whereType<TopicFootprintEntry>(),
      );
  }

  Future<List<TopicFootprintEntry>> entriesFor(AccountProvider provider) async {
    await initialize();
    return List<TopicFootprintEntry>.unmodifiable(
      _entries.where((item) => item.provider == provider),
    );
  }

  Future<void> record(TopicFootprintEntry entry) async {
    await initialize();
    _entries.removeWhere(
      (item) => item.provider == entry.provider && item.topicId == entry.topicId,
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxCount) {
      _entries.removeRange(_maxCount, _entries.length);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clear(AccountProvider provider) async {
    await initialize();
    _entries.removeWhere((item) => item.provider == provider);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(
      _storageKey,
      _entries.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
  }
}

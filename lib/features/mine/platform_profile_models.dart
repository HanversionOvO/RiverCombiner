import 'package:flutter/foundation.dart';
import 'package:river/core/account/account_models.dart';

enum PlatformProfileProvider { riverSide, qingShuiHePan }

@immutable
class PlatformProfileOverview {
  const PlatformProfileOverview({
    required this.provider,
    required this.account,
    required this.bio,
    required this.location,
    required this.website,
    required this.createdAt,
    required this.lastSeenAt,
    required this.topicCount,
    required this.replyCount,
    required this.likesOrFavoritesCount,
    required this.followersCount,
    required this.followingCount,
    this.trustLevel,
    this.extraDescription = '',
    this.profileUrl,
  });

  final PlatformProfileProvider provider;
  final UserAccount account;
  final String bio;
  final String location;
  final String website;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final int? topicCount;
  final int? replyCount;
  final int? likesOrFavoritesCount;
  final int? followersCount;
  final int? followingCount;
  final int? trustLevel;
  final String extraDescription;
  final String? profileUrl;
}

@immutable
class PlatformProfileTab {
  const PlatformProfileTab({
    required this.id,
    required this.label,
    this.supportsTopicOpen = false,
  });

  final String id;
  final String label;
  final bool supportsTopicOpen;
}

@immutable
class PlatformProfileActivityItem {
  const PlatformProfileActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.meta,
    this.createdAt,
    this.topicId,
    this.postNumber,
    this.boardId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String meta;
  final DateTime? createdAt;
  final int? topicId;
  final int? postNumber;
  final int? boardId;
}

@immutable
class PlatformProfileFollowUser {
  const PlatformProfileFollowUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final int id;
  final String username;
  final String displayName;
  final String avatarUrl;
}

import 'package:river/core/constants.dart';

enum RiverSideTopicFeed { latestCreated, latestReplied, hot }

extension RiverSideTopicFeedExtension on RiverSideTopicFeed {
  String get label {
    switch (this) {
      case RiverSideTopicFeed.latestCreated:
        return '最新发表';
      case RiverSideTopicFeed.latestReplied:
        return '最新回复';
      case RiverSideTopicFeed.hot:
        return '热门';
    }
  }

  Uri uri({int page = 0}) {
    switch (this) {
      case RiverSideTopicFeed.latestCreated:
        return Uri.parse(
          '$riverSideBaseUrl/latest.json?no_definitions=true&order=created&page=$page',
        );
      case RiverSideTopicFeed.latestReplied:
        return Uri.parse(
          '$riverSideBaseUrl/latest.json?no_definitions=true&page=$page',
        );
      case RiverSideTopicFeed.hot:
        return Uri.parse('$riverSideBaseUrl/hot.json?page=$page');
    }
  }
}

class RiverSideTopicSummary {
  const RiverSideTopicSummary({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.categoryId,
    required this.categoryName,
    required this.replyCount,
    this.commentCount,
    required this.viewCount,
    required this.createdAt,
    required this.authorDisplayName,
    required this.authorUsername,
    this.authorUserId,
    required this.authorAvatarUrl,
    required this.isHot,
    required this.isPinned,
  });

  final int id;
  final String title;
  final String excerpt;
  final int? categoryId;
  final String categoryName;
  final int replyCount;
  final int? commentCount;
  final int viewCount;
  final DateTime? createdAt;
  final String authorDisplayName;
  final String authorUsername;
  final int? authorUserId;
  final String authorAvatarUrl;
  final bool isHot;
  final bool isPinned;
}

class RiverSideCategoryOption {
  const RiverSideCategoryOption({
    required this.id,
    required this.name,
    required this.position,
    required this.parentCategoryId,
    required this.description,
    this.canCreateTopic = true,
    this.displayName = '',
  });

  final int id;
  final String name;
  final int position;
  final int? parentCategoryId;
  final String description;
  final bool canCreateTopic;
  final String displayName;
}

class RiverSideTopicPage {
  const RiverSideTopicPage({
    required this.topics,
    required this.hasMore,
    required this.page,
  });

  final List<RiverSideTopicSummary> topics;
  final bool hasMore;
  final int page;
}

class RiverSideTopicPostDetail {
  const RiverSideTopicPostDetail({
    required this.id,
    required this.topicId,
    required this.postNumber,
    this.postType = 1,
    this.actionCode = '',
    this.actionDescription = '',
    required this.authorUserId,
    required this.authorUsername,
    required this.authorDisplayName,
    required this.authorAvatarUrl,
    required this.authorTitle,
    required this.isOnline,
    required this.contentMarkdown,
    this.contentCookedHtml = '',
    required this.createdAt,
    required this.editCount,
    required this.likeCount,
    this.reactions = const <RiverSidePostReaction>[],
    this.currentUserReaction,
    this.reactionUsersCount = 0,
    this.replyToPostNumber,
    this.replyToUsername = '',
    this.polls = const <RiverSideTopicPoll>[],
    this.canVotePoll = false,
  });

  final int id;
  final int topicId;
  final int postNumber;
  final int postType;
  final String actionCode;
  final String actionDescription;
  final int? authorUserId;
  final String authorUsername;
  final String authorDisplayName;
  final String authorAvatarUrl;
  final String authorTitle;
  final bool? isOnline;
  final String contentMarkdown;
  final String contentCookedHtml;
  final DateTime? createdAt;
  final int editCount;
  final int likeCount;
  final List<RiverSidePostReaction> reactions;
  final RiverSideCurrentUserReaction? currentUserReaction;
  final int reactionUsersCount;
  final int? replyToPostNumber;
  final String replyToUsername;
  final List<RiverSideTopicPoll> polls;
  final bool canVotePoll;

  bool get isSystemActionPost => postType == 3 || actionCode.trim().isNotEmpty;

  RiverSideTopicPostDetail copyWith({
    int? id,
    int? topicId,
    int? postNumber,
    int? postType,
    String? actionCode,
    String? actionDescription,
    int? authorUserId,
    bool clearAuthorUserId = false,
    String? authorUsername,
    String? authorDisplayName,
    String? authorAvatarUrl,
    String? authorTitle,
    bool? isOnline,
    String? contentMarkdown,
    String? contentCookedHtml,
    DateTime? createdAt,
    int? editCount,
    int? likeCount,
    List<RiverSidePostReaction>? reactions,
    RiverSideCurrentUserReaction? currentUserReaction,
    bool clearCurrentUserReaction = false,
    int? reactionUsersCount,
    int? replyToPostNumber,
    String? replyToUsername,
    List<RiverSideTopicPoll>? polls,
    bool? canVotePoll,
  }) {
    return RiverSideTopicPostDetail(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      postNumber: postNumber ?? this.postNumber,
      postType: postType ?? this.postType,
      actionCode: actionCode ?? this.actionCode,
      actionDescription: actionDescription ?? this.actionDescription,
      authorUserId: clearAuthorUserId
          ? null
          : (authorUserId ?? this.authorUserId),
      authorUsername: authorUsername ?? this.authorUsername,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorTitle: authorTitle ?? this.authorTitle,
      isOnline: isOnline ?? this.isOnline,
      contentMarkdown: contentMarkdown ?? this.contentMarkdown,
      contentCookedHtml: contentCookedHtml ?? this.contentCookedHtml,
      createdAt: createdAt ?? this.createdAt,
      editCount: editCount ?? this.editCount,
      likeCount: likeCount ?? this.likeCount,
      reactions: reactions ?? this.reactions,
      currentUserReaction: clearCurrentUserReaction
          ? null
          : (currentUserReaction ?? this.currentUserReaction),
      reactionUsersCount: reactionUsersCount ?? this.reactionUsersCount,
      replyToPostNumber: replyToPostNumber ?? this.replyToPostNumber,
      replyToUsername: replyToUsername ?? this.replyToUsername,
      polls: polls ?? this.polls,
      canVotePoll: canVotePoll ?? this.canVotePoll,
    );
  }
}

class RiverSideTopicPoll {
  const RiverSideTopicPoll({
    required this.id,
    required this.name,
    required this.title,
    required this.type,
    required this.status,
    required this.public,
    required this.dynamic,
    required this.results,
    required this.chartType,
    required this.voters,
    required this.options,
    this.canVote = false,
  });

  final int id;
  final String name;
  final String title;
  final String type;
  final String status;
  final bool public;
  final bool dynamic;
  final String results;
  final String chartType;
  final int voters;
  final List<RiverSideTopicPollOption> options;
  final bool canVote;

  bool get isOpen => status.toLowerCase() == 'open';

  RiverSideTopicPoll copyWith({
    int? id,
    String? name,
    String? title,
    String? type,
    String? status,
    bool? public,
    bool? dynamic,
    String? results,
    String? chartType,
    int? voters,
    List<RiverSideTopicPollOption>? options,
    bool? canVote,
  }) {
    return RiverSideTopicPoll(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      type: type ?? this.type,
      status: status ?? this.status,
      public: public ?? this.public,
      dynamic: dynamic ?? this.dynamic,
      results: results ?? this.results,
      chartType: chartType ?? this.chartType,
      voters: voters ?? this.voters,
      options: options ?? this.options,
      canVote: canVote ?? this.canVote,
    );
  }
}

class RiverSideTopicPollOption {
  const RiverSideTopicPollOption({
    required this.id,
    required this.html,
    required this.votes,
    this.selected = false,
    this.voters = const <RiverSideTopicPollVoter>[],
  });

  final String id;
  final String html;
  final int votes;
  final bool selected;
  final List<RiverSideTopicPollVoter> voters;

  RiverSideTopicPollOption copyWith({
    String? id,
    String? html,
    int? votes,
    bool? selected,
    List<RiverSideTopicPollVoter>? voters,
  }) {
    return RiverSideTopicPollOption(
      id: id ?? this.id,
      html: html ?? this.html,
      votes: votes ?? this.votes,
      selected: selected ?? this.selected,
      voters: voters ?? this.voters,
    );
  }
}

class RiverSideTopicPollVoter {
  const RiverSideTopicPollVoter({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.title,
  });

  final int id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String title;
}

class RiverSideTopicDetail {
  const RiverSideTopicDetail({
    required this.topicId,
    required this.title,
    required this.viewCount,
    required this.replyCount,
    required this.likeCount,
    required this.createdAt,
    required this.mainPost,
    required this.comments,
    required this.streamPostIds,
    required this.loadedPostIds,
    this.validReactions = const <String>[],
    this.isBookmarked = false,
  });

  final int topicId;
  final String title;
  final int viewCount;
  final int replyCount;
  final int likeCount;
  final DateTime? createdAt;
  final RiverSideTopicPostDetail mainPost;
  final List<RiverSideTopicPostDetail> comments;
  final List<int> streamPostIds;
  final Set<int> loadedPostIds;
  final List<String> validReactions;
  final bool isBookmarked;

  RiverSideTopicDetail copyWith({
    int? topicId,
    String? title,
    int? viewCount,
    int? replyCount,
    int? likeCount,
    DateTime? createdAt,
    RiverSideTopicPostDetail? mainPost,
    List<RiverSideTopicPostDetail>? comments,
    List<int>? streamPostIds,
    Set<int>? loadedPostIds,
    List<String>? validReactions,
    bool? isBookmarked,
  }) {
    return RiverSideTopicDetail(
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      viewCount: viewCount ?? this.viewCount,
      replyCount: replyCount ?? this.replyCount,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt ?? this.createdAt,
      mainPost: mainPost ?? this.mainPost,
      comments: comments ?? this.comments,
      streamPostIds: streamPostIds ?? this.streamPostIds,
      loadedPostIds: loadedPostIds ?? this.loadedPostIds,
      validReactions: validReactions ?? this.validReactions,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}

class RiverSideAiTopicSummary {
  const RiverSideAiTopicSummary({
    required this.summarizedText,
    required this.algorithm,
    required this.outdated,
    required this.canRegenerate,
    required this.newPostsSinceSummary,
    required this.updatedAt,
  });

  final String summarizedText;
  final String algorithm;
  final bool outdated;
  final bool canRegenerate;
  final int newPostsSinceSummary;
  final DateTime? updatedAt;
}

class RiverSidePostReaction {
  const RiverSidePostReaction({
    required this.id,
    required this.type,
    required this.count,
  });

  final String id;
  final String type;
  final int count;
}

class RiverSideCurrentUserReaction {
  const RiverSideCurrentUserReaction({
    required this.id,
    required this.type,
    required this.canUndo,
  });

  final String id;
  final String type;
  final bool canUndo;
}

class RiverSidePostReactionUsersGroup {
  const RiverSidePostReactionUsersGroup({
    required this.id,
    required this.count,
    required this.users,
  });

  final String id;
  final int count;
  final List<RiverSideReactionUser> users;
}

class RiverSideReactionUser {
  const RiverSideReactionUser({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.canUndo,
    required this.createdAt,
  });

  final String username;
  final String displayName;
  final String avatarUrl;
  final bool canUndo;
  final DateTime? createdAt;
}

class RiverSidePostReactionState {
  const RiverSidePostReactionState({
    required this.postId,
    required this.reactions,
    required this.currentUserReaction,
    required this.reactionUsersCount,
  });

  final int postId;
  final List<RiverSidePostReaction> reactions;
  final RiverSideCurrentUserReaction? currentUserReaction;
  final int reactionUsersCount;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:motion/motion.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_profile_models.dart';
import 'package:river/core/platform/riverside_webview_support.dart';
import 'package:river/features/mine/platform_profile_models.dart';
import 'package:river/features/mine/platform_profile_repository.dart';
import 'package:river/features/mine/riverside_profile_action_bar.dart';
import 'package:river/features/mine/riverside_profile_webview_page.dart';
import 'package:river/features/notifications/chat_detail_page.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';
part 'riverside_profile_page_widgets.dart';

class RiverSideProfilePage extends StatefulWidget {
  const RiverSideProfilePage({
    super.key,
    required this.dependencies,
    required this.account,
    this.cookieHeader,
    this.heroTag, // 新增：接收头像 Hero Tag
    this.heroTagName, // 新增：接收昵称 Hero Tag
  });

  final AppDependencies dependencies;
  final UserAccount account;
  final String? cookieHeader;
  final String? heroTag;
  final String? heroTagName;

  @override
  State<RiverSideProfilePage> createState() => _RiverSideProfilePageState();
}

class _RiverSideProfilePageState extends State<RiverSideProfilePage>
    with TickerProviderStateMixin {
  static const int _riverActivityPageSize = 30;
  static const int _qingActivityPageSize = 20;

  late final PlatformProfileRepository _platformProfileRepository;
  late final List<_ProfileTabDef> _tabs;
  late TabController _tabController;
  late Future<RiverSideProfileOverview> _overviewFuture;

  final Map<
    RiverSideProfileActivityKind,
    Future<List<RiverSideProfileActivityItem>>
  >
  _activityFutures = {};
  final Map<RiverSideProfileActivityKind, int> _qingActivityPageByKind = {};
  final Map<RiverSideProfileActivityKind, bool> _qingActivityHasMoreByKind = {};
  final Map<RiverSideProfileActivityKind, List<RiverSideProfileActivityItem>>
  _qingActivityItemsByKind = {};
  final Map<RiverSideProfileActivityKind, int> _riverActivityOffsetByKind = {};
  final Map<RiverSideProfileActivityKind, bool> _riverActivityHasMoreByKind =
      {};
  final Map<RiverSideProfileActivityKind, List<RiverSideProfileActivityItem>>
  _riverActivityItemsByKind = {};
  final Set<RiverSideProfileActivityKind> _riverLoadingMoreKinds =
      <RiverSideProfileActivityKind>{};
  final Set<RiverSideProfileActivityKind> _qingLoadingMoreKinds =
      <RiverSideProfileActivityKind>{};
  Future<List<RiverSideProfileBadge>>? _badgesFuture;
  Future<List<RiverSideProfileFollowUser>>? _followingFuture;
  Future<List<RiverSideProfileFollowUser>>? _followersFuture;

  bool _openingDetailedProfile = false;
  bool _followBusy = false;
  bool _messageBusy = false;
  bool _isFollowing = false;
  bool _followStateResolved = false;

  String get _username => widget.account.username;
  bool get _isQingShuiHePanProfile =>
      widget.account.provider == AccountProvider.qingShuiHePan;

  @override
  void initState() {
    super.initState();
    _platformProfileRepository = PlatformProfileRepository(
      dependencies: widget.dependencies,
    );
    _tabs = _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _overviewFuture = _loadOverview();
    unawaited(
      _overviewFuture.then((overview) {
        if (!mounted) return;
        _syncRelationshipState(overview: overview);
      }),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _effectiveCookieHeader() {
    if (_isQingShuiHePanProfile) {
      final auth = widget.dependencies.accountStore.qingShuiHePanAuthFor(
        _username,
      );
      final cookie = auth?.cookieHeader.trim();
      if (cookie != null && cookie.isNotEmpty) {
        return cookie;
      }
      final active =
          widget.dependencies.accountStore.activeQingShuiHePanUsername;
      if (active != null && active.isNotEmpty) {
        final activeAuth = widget.dependencies.accountStore
            .qingShuiHePanAuthFor(active);
        final activeCookie = activeAuth?.cookieHeader.trim();
        if (activeCookie != null && activeCookie.isNotEmpty) {
          return activeCookie;
        }
      }
      return null;
    }
    final fromWidget = widget.cookieHeader?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    final active = widget.dependencies.accountStore.activeRiverSideUsername;
    if (active == null || active.isEmpty) return null;
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(active);
  }

  String _requiredCookieHeader() {
    final cookie = _effectiveCookieHeader()?.trim() ?? '';
    if (cookie.isEmpty) {
      throw const RiverSideApiException('当前账号登录态缺失，请重新登录后查看资料');
    }
    return cookie;
  }

  Future<RiverSideProfileOverview> _loadOverview() async {
    if (_isQingShuiHePanProfile) {
      final overview = await _platformProfileRepository.loadOverview(
        widget.account,
      );
      return _mapQingOverview(overview);
    }
    final cookie = _requiredCookieHeader();
    return widget.dependencies.accountStore.riverSideApiClient
        .fetchProfileOverview(_username, cookieHeader: cookie);
  }

  Future<List<RiverSideProfileActivityItem>> _loadActivities(
    RiverSideProfileActivityKind kind,
  ) async {
    if (_isQingShuiHePanProfile) {
      final activities = await _platformProfileRepository.loadActivities(
        account: widget.account,
        tab: _mapQingTab(kind),
        page: 1,
        pageSize: _qingActivityPageSize,
      );
      final mapped = activities.map(_mapQingActivity).toList();
      _qingActivityItemsByKind[kind] = mapped;
      _qingActivityPageByKind[kind] = 1;
      _qingActivityHasMoreByKind[kind] =
          activities.length >= _qingActivityPageSize;
      return mapped;
    }
    final cookie = _requiredCookieHeader();
    final activities = await widget.dependencies.accountStore.riverSideApiClient
        .fetchProfileActivities(_username, kind: kind, cookieHeader: cookie);
    _riverActivityItemsByKind[kind] = activities;
    _riverActivityOffsetByKind[kind] = activities.length;
    _riverActivityHasMoreByKind[kind] =
        activities.length >= _riverActivityPageSize;
    return activities;
  }

  Future<List<RiverSideProfileBadge>> _loadBadges() async {
    if (_isQingShuiHePanProfile) {
      return const <RiverSideProfileBadge>[];
    }
    final cookie = _requiredCookieHeader();
    return widget.dependencies.accountStore.riverSideApiClient
        .fetchProfileBadges(_username, cookieHeader: cookie);
  }

  Future<List<RiverSideProfileFollowUser>> _loadFollowUsers({
    required bool followers,
  }) async {
    if (_isQingShuiHePanProfile) {
      final users = await _platformProfileRepository.loadFollowUsers(
        account: widget.account,
        followers: followers,
      );
      return users
          .map(
            (item) => RiverSideProfileFollowUser(
              id: item.id,
              username: item.username,
              displayName: item.displayName,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList();
    }
    final cookie = _requiredCookieHeader();
    return widget.dependencies.accountStore.riverSideApiClient
        .fetchProfileFollowUsers(
          _username,
          followers: followers,
          cookieHeader: cookie,
        );
  }

  Future<List<RiverSideProfileActivityItem>> _ensureActivityFuture(
    RiverSideProfileActivityKind kind,
  ) {
    return _activityFutures.putIfAbsent(kind, () => _loadActivities(kind));
  }

  Future<bool> _loadMoreActivities(RiverSideProfileActivityKind kind) async {
    if (!_isQingShuiHePanProfile) {
      return _loadMoreRiverActivities(kind);
    }
    if (_qingLoadingMoreKinds.contains(kind)) {
      return false;
    }
    final hasMore = _qingActivityHasMoreByKind[kind] ?? true;
    if (!hasMore) {
      return false;
    }
    final currentPage = _qingActivityPageByKind[kind] ?? 1;
    final nextPage = currentPage + 1;
    _qingLoadingMoreKinds.add(kind);
    try {
      final pageData = await _platformProfileRepository.loadActivities(
        account: widget.account,
        tab: _mapQingTab(kind),
        page: nextPage,
        pageSize: _qingActivityPageSize,
      );
      final mapped = pageData.map(_mapQingActivity).toList();
      final oldItems =
          _qingActivityItemsByKind[kind] ?? <RiverSideProfileActivityItem>[];
      final oldKeys = oldItems
          .map(
            (item) => '${item.topicId}-${item.postNumber ?? 0}-${item.title}',
          )
          .toSet();
      final merged = <RiverSideProfileActivityItem>[
        ...oldItems,
        ...mapped.where(
          (item) => !oldKeys.contains(
            '${item.topicId}-${item.postNumber ?? 0}-${item.title}',
          ),
        ),
      ];
      if (!mounted) {
        return false;
      }
      setState(() {
        _qingActivityItemsByKind[kind] = merged;
        _qingActivityPageByKind[kind] = nextPage;
        _qingActivityHasMoreByKind[kind] =
            pageData.length >= _qingActivityPageSize;
        _activityFutures[kind] =
            Future<List<RiverSideProfileActivityItem>>.value(merged);
      });
      return mapped.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      _qingLoadingMoreKinds.remove(kind);
    }
  }

  Future<bool> _loadMoreRiverActivities(
    RiverSideProfileActivityKind kind,
  ) async {
    if (_riverLoadingMoreKinds.contains(kind)) {
      return false;
    }
    final hasMore = _riverActivityHasMoreByKind[kind] ?? true;
    if (!hasMore) {
      return false;
    }
    final cookie = _requiredCookieHeader();
    final offset = _riverActivityOffsetByKind[kind] ?? 0;
    _riverLoadingMoreKinds.add(kind);
    try {
      final pageData = await widget.dependencies.accountStore.riverSideApiClient
          .fetchProfileActivities(
            _username,
            kind: kind,
            cookieHeader: cookie,
            offset: offset,
          );
      final oldItems =
          _riverActivityItemsByKind[kind] ?? <RiverSideProfileActivityItem>[];
      final oldKeys = oldItems
          .map(
            (item) =>
                '${item.topicId}-${item.postNumber ?? 0}-${item.actionType ?? 0}',
          )
          .toSet();
      final append = pageData.where(
        (item) => !oldKeys.contains(
          '${item.topicId}-${item.postNumber ?? 0}-${item.actionType ?? 0}',
        ),
      );
      final merged = <RiverSideProfileActivityItem>[...oldItems, ...append];
      if (!mounted) {
        return false;
      }
      setState(() {
        _riverActivityItemsByKind[kind] = merged;
        _riverActivityOffsetByKind[kind] = merged.length;
        _riverActivityHasMoreByKind[kind] =
            pageData.length >= _riverActivityPageSize;
        _activityFutures[kind] =
            Future<List<RiverSideProfileActivityItem>>.value(merged);
      });
      return pageData.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      _riverLoadingMoreKinds.remove(kind);
    }
  }

  Future<List<RiverSideProfileBadge>> _ensureBadgesFuture() {
    return _badgesFuture ??= _loadBadges();
  }

  Future<List<RiverSideProfileFollowUser>> _ensureFollowingFuture() {
    return _followingFuture ??= _loadFollowUsers(followers: false);
  }

  Future<List<RiverSideProfileFollowUser>> _ensureFollowersFuture() {
    return _followersFuture ??= _loadFollowUsers(followers: true);
  }

  String _badgeHeroTag(RiverSideProfileBadge badge) {
    return 'profile_badge_${widget.account.provider.name}_${_username.toLowerCase()}_${badge.id}';
  }

  Future<void> _openBadgeDetail(RiverSideProfileBadge badge) async {
    if (_isQingShuiHePanProfile) {
      return;
    }
    final cookieHeader = _effectiveCookieHeader();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (sheetContext) {
        return _BadgeDetailDialog(
          badge: badge,
          heroTag: _badgeHeroTag(badge),
          username: _username,
          isBottomSheet: true,
          onLoadDetail: () {
            return widget.dependencies.accountStore.riverSideApiClient
                .fetchProfileBadgeDetail(
                  badgeId: badge.id,
                  username: _username,
                  cookieHeader: cookieHeader,
                );
          },
        );
      },
    );
  }

  Future<void> _openTopicDetail(RiverSideProfileActivityItem item) async {
    final topicId = item.topicId;
    if (topicId <= 0) {
      _showErrorSnack('帖子ID无效');
      return;
    }
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: topicId,
          provider: _isQingShuiHePanProfile
              ? AccountProvider.qingShuiHePan
              : AccountProvider.riverSide,
          qingBoardId: _isQingShuiHePanProfile
              ? ((item.actionType != null && item.actionType! > 0)
                    ? item.actionType
                    : null)
              : null,
        ),
      ),
    );
  }

  Future<void> _openRelatedProfile(RiverSideProfileFollowUser user) async {
    final account = UserAccount(
      provider: widget.account.provider,
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
    );

    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => RiverSideProfilePage(
          dependencies: widget.dependencies,
          account: account,
          cookieHeader: _isQingShuiHePanProfile
              ? null
              : _requiredCookieHeader(),
        ),
      ),
    );
  }

  Future<void> _openDetailedProfile() async {
    if (_openingDetailedProfile) return;
    setState(() => _openingDetailedProfile = true);

    try {
      if (_isQingShuiHePanProfile) {
        _showErrorSnack('清水河畔网页版详细资料暂未接入');
        return;
      }
      final cookie = _requiredCookieHeader();
      final support = await RiverSideWebViewSupport.check();
      if (!mounted) return;

      if (!support.canUseEmbeddedWebView) {
        ScaffoldMessenger.of(context).showRiverSnackBar('当前设备不支持内置 WebView');
        return;
      }

      await Navigator.of(context).push(
        riverPageRoute<void>(
          builder: (_) => RiverSideProfileWebViewPage(
            username: _username,
            title: widget.account.primaryDisplayLabel,
            cookieHeader: cookie,
          ),
        ),
      );
    } on RiverSideApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showRiverSnackBar(error.message);
    } finally {
      if (mounted) setState(() => _openingDetailedProfile = false);
    }
  }

  String? _activeUsername() {
    if (_isQingShuiHePanProfile) {
      return widget.dependencies.accountStore.activeQingShuiHePanUsername;
    }
    return widget.dependencies.accountStore.activeRiverSideUsername;
  }

  bool get _isSelfProfile {
    final active = _activeUsername()?.trim().toLowerCase();
    final target = _username.trim().toLowerCase();
    if (active == null || active.isEmpty || target.isEmpty) {
      return false;
    }
    return active == target;
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showRiverSnackBar(message);
  }

  Future<void> _syncRelationshipState({
    RiverSideProfileOverview? overview,
  }) async {
    if (_isQingShuiHePanProfile) {
      if (!mounted) {
        return;
      }
      setState(() {
        _followStateResolved = true;
        _isFollowing = false;
      });
      return;
    }
    if (_isSelfProfile) {
      if (!mounted) return;
      setState(() {
        _followStateResolved = true;
        _isFollowing = false;
      });
      return;
    }

    final initial = overview?.isFollowing;
    if (initial != null && mounted) {
      setState(() {
        _isFollowing = initial;
        _followStateResolved = true;
      });
    }

    final cookie = _effectiveCookieHeader()?.trim() ?? '';
    final active = _activeUsername()?.trim() ?? '';
    if (cookie.isEmpty || active.isEmpty) {
      return;
    }

    try {
      final isFollowing = await widget
          .dependencies
          .accountStore
          .riverSideApiClient
          .isFollowingUser(
            currentUsername: active,
            targetUsername: _username,
            cookieHeader: cookie,
          );
      if (!mounted) return;
      setState(() {
        _isFollowing = isFollowing;
        _followStateResolved = true;
      });
    } catch (_) {
      // Keep UI resilient.
    }
  }

  Future<void> _toggleFollow() async {
    if (_isQingShuiHePanProfile) {
      _showErrorSnack('清水河畔关注能力暂未接入');
      return;
    }
    if (_followBusy || _isSelfProfile) {
      return;
    }
    final cookie = _effectiveCookieHeader()?.trim() ?? '';
    final active = _activeUsername()?.trim() ?? '';
    if (cookie.isEmpty || active.isEmpty) {
      _showErrorSnack('请先登录 RiverSide 账号');
      return;
    }
    final nextFollowState = !_isFollowing;
    setState(() {
      _followBusy = true;
    });
    try {
      await widget.dependencies.accountStore.riverSideApiClient.setFollowState(
        targetUsername: _username,
        follow: nextFollowState,
        cookieHeader: cookie,
      );
      if (!mounted) return;
      setState(() {
        _isFollowing = nextFollowState;
        _followStateResolved = true;
      });
      _showErrorSnack(nextFollowState ? '关注成功' : '已取消关注');
      unawaited(_syncRelationshipState());
    } on RiverSideApiException catch (error) {
      _showErrorSnack(error.message);
    } catch (_) {
      _showErrorSnack(nextFollowState ? '关注失败，请稍后重试' : '取消关注失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _followBusy = false;
        });
      }
    }
  }

  Future<void> _startPrivateMessage() async {
    if (_isQingShuiHePanProfile) {
      _showErrorSnack('清水河畔私信能力暂未接入');
      return;
    }
    if (_messageBusy || _isSelfProfile) {
      return;
    }
    final cookie = _effectiveCookieHeader()?.trim() ?? '';
    if (cookie.isEmpty) {
      _showErrorSnack('请先登录 RiverSide 账号');
      return;
    }

    setState(() {
      _messageBusy = true;
    });
    try {
      final channel = await widget.dependencies.accountStore.riverSideApiClient
          .createOrOpenDirectMessageChannel(
            targetUsername: _username,
            cookieHeader: cookie,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        riverPageRoute<void>(
          builder: (_) => ChatDetailPage(
            dependencies: widget.dependencies,
            channel: channel,
          ),
        ),
      );
    } on RiverSideApiException catch (error) {
      _showErrorSnack(error.message);
    } catch (_) {
      _showErrorSnack('发起私信失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _messageBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = widget.account.primaryDisplayLabel;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 0,
              title: Text(
                innerBoxIsScrolled ? displayName : '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.95,
              ),
              elevation: 0,
              scrolledUnderElevation: 2,
              actions: [
                IconButton(
                  onPressed: _openingDetailedProfile
                      ? null
                      : _openDetailedProfile,
                  icon: _openingDetailedProfile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_browser_rounded),
                  tooltip: '网页版详细资料',
                ),
              ],
            ),
            SliverToBoxAdapter(child: _buildProfileHeader(theme, displayName)),
            SliverPersistentHeader(
              delegate: _StickyTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorColor: theme.colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: _tabs.map((t) => Tab(text: t.title)).toList(),
                ),
                color: theme.colorScheme.surface,
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            if (tab.kind != null) {
              return _ActivityTab(
                kind: tab.kind!,
                overviewFuture: _overviewFuture,
                activityFuture: _ensureActivityFuture(tab.kind!),
                onRefresh: () async {
                  setState(() {
                    _qingActivityItemsByKind.remove(tab.kind!);
                    _qingActivityPageByKind.remove(tab.kind!);
                    _qingActivityHasMoreByKind.remove(tab.kind!);
                    _riverActivityItemsByKind.remove(tab.kind!);
                    _riverActivityOffsetByKind.remove(tab.kind!);
                    _riverActivityHasMoreByKind.remove(tab.kind!);
                    _activityFutures[tab.kind!] = _loadActivities(tab.kind!);
                  });
                  await _activityFutures[tab.kind!];
                },
                onItemTap: _openTopicDetail,
                onLoadMore: () => _loadMoreActivities(tab.kind!),
                canLoadMore: _isQingShuiHePanProfile
                    ? () => _qingActivityHasMoreByKind[tab.kind!] ?? false
                    : () => _riverActivityHasMoreByKind[tab.kind!] ?? false,
              );
            } else if (tab.title == '徽章') {
              return _BadgesTab(
                overviewFuture: _overviewFuture,
                badgesFuture: _ensureBadgesFuture(),
                onBadgeTap: _openBadgeDetail,
                badgeHeroTagBuilder: _badgeHeroTag,
                onRefresh: () async {
                  setState(() => _badgesFuture = _loadBadges());
                  await _badgesFuture;
                },
              );
            } else {
              final isFollowers = tab.title == '粉丝';
              return _UsersTab(
                overviewFuture: _overviewFuture,
                usersFuture: isFollowers
                    ? _ensureFollowersFuture()
                    : _ensureFollowingFuture(),
                onRefresh: () async {
                  if (isFollowers) {
                    setState(
                      () =>
                          _followersFuture = _loadFollowUsers(followers: true),
                    );
                    await _followersFuture;
                  } else {
                    setState(
                      () =>
                          _followingFuture = _loadFollowUsers(followers: false),
                    );
                    await _followingFuture;
                  }
                },
                onUserTap: _openRelatedProfile,
                emptyText: isFollowers ? '暂无粉丝' : '暂无关注',
              );
            }
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme, String displayName) {
    return FutureBuilder<RiverSideProfileOverview>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _ProfileSectionAnimatedSwitcher(
            child: KeyedSubtree(
              key: const ValueKey<String>('profile_header_loading'),
              child: const _ProfileHeaderSkeleton(),
            ),
          );
        }

        final overview = snapshot.data!;
        final account = overview.account;
        final secondaryName = account.secondaryDisplayLabel;
        final showFollowButton = !_isSelfProfile && overview.canFollow;
        final showMessageButton =
            !_isSelfProfile && overview.canSendPrivateMessage;

        // 使用传入的 Hero Tag，如果没有则不使用
        Widget avatarWidget = Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.surfaceContainerHighest,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            image: account.avatarUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(account.avatarUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: account.avatarUrl.isEmpty
              ? Icon(Icons.person, size: 40, color: theme.colorScheme.primary)
              : null,
        );

        if (widget.heroTag != null) {
          avatarWidget = Hero(tag: widget.heroTag!, child: avatarWidget);
        }

        return _ProfileSectionAnimatedSwitcher(
          child: KeyedSubtree(
            key: const ValueKey<String>('profile_header_content'),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatarWidget,
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final nameWidget = Text(
                                  displayName,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                                final nameHeroTag = widget.heroTagName;
                                if (nameHeroTag == null ||
                                    nameHeroTag.isEmpty) {
                                  return nameWidget;
                                }
                                return Hero(
                                  tag: nameHeroTag,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: nameWidget,
                                  ),
                                );
                              },
                            ),
                            if (secondaryName.isNotEmpty)
                              Text(
                                secondaryName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (overview.location.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                    color: theme.colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      overview.location,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.secondary,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (showFollowButton || showMessageButton) ...[
                    const SizedBox(height: 16),
                    RiverSideProfileActionBar(
                      showFollowButton: showFollowButton,
                      showMessageButton: showMessageButton,
                      isFollowing: _followStateResolved
                          ? _isFollowing
                          : overview.isFollowing,
                      followLoading: _followBusy,
                      messageLoading: _messageBusy,
                      onToggleFollow: _toggleFollow,
                      onStartMessage: _startPrivateMessage,
                    ),
                  ],

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(context, '${overview.topicCount}', '帖子'),
                      _buildStatItem(
                        context,
                        '${overview.followingCount}',
                        '关注',
                      ),
                      _buildStatItem(
                        context,
                        '${overview.followersCount}',
                        '粉丝',
                      ),
                      _buildStatItem(
                        context,
                        '${overview.likesReceived}',
                        '获赞',
                      ),
                    ],
                  ),

                  if (overview.bio.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      overview.bio,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 16),

                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        label: '信任等级 ${overview.trustLevel}',
                        icon: Icons.verified_user_outlined,
                        color: Colors.green,
                      ),
                      if (overview.lastSeenAt != null)
                        _MetaChip(
                          label:
                              '最近活跃 ${_formatDateShort(overview.lastSeenAt!)}',
                          icon: Icons.access_time,
                        ),
                      if (overview.createdAt != null)
                        _MetaChip(
                          label: '加入于 ${_formatDateShort(overview.createdAt!)}',
                          icon: Icons.calendar_today_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatDateShort(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  List<_ProfileTabDef> _buildTabs() {
    return <_ProfileTabDef>[
      for (final kind in RiverSideProfileActivityKind.values)
        _ProfileTabDef(title: kind.label, kind: kind),
      const _ProfileTabDef(title: '徽章'),
      const _ProfileTabDef(title: '关注中'),
      const _ProfileTabDef(title: '粉丝'),
    ];
  }

  PlatformProfileTab _mapQingTab(RiverSideProfileActivityKind kind) {
    switch (kind) {
      case RiverSideProfileActivityKind.replies:
        return const PlatformProfileTab(id: 'reply', label: '回复');
      case RiverSideProfileActivityKind.likesGiven:
        return const PlatformProfileTab(id: 'favorite', label: '收藏');
      case RiverSideProfileActivityKind.all:
      case RiverSideProfileActivityKind.topics:
        return const PlatformProfileTab(id: 'topic', label: '主题');
    }
  }

  RiverSideProfileOverview _mapQingOverview(PlatformProfileOverview overview) {
    final statsTopicCount = overview.topicCount ?? 0;
    final statsReplyCount = overview.replyCount ?? 0;
    final statsFavCount = overview.likesOrFavoritesCount ?? 0;
    return RiverSideProfileOverview(
      account: overview.account,
      isProfileHidden: false,
      bio: overview.bio,
      location: overview.location,
      website: overview.website,
      createdAt: overview.createdAt,
      lastSeenAt: overview.lastSeenAt,
      lastPostedAt: overview.lastSeenAt,
      trustLevel: overview.trustLevel ?? 0,
      badgeCount: 0,
      profileViewCount: 0,
      topicCount: statsTopicCount,
      postCount: statsReplyCount,
      likesGiven: statsFavCount,
      likesReceived: statsFavCount,
      followersCount: overview.followersCount ?? 0,
      followingCount: overview.followingCount ?? 0,
      canFollow: false,
      canSendPrivateMessage: false,
      isFollowing: false,
    );
  }

  RiverSideProfileActivityItem _mapQingActivity(
    PlatformProfileActivityItem item,
  ) {
    final categoryName = _extractCategoryName(item.meta);
    final replyCount = _extractMetaCount(item.meta, '回复');
    final viewCount = _extractMetaCount(item.meta, '浏览');
    return RiverSideProfileActivityItem(
      topicId: item.topicId ?? 0,
      postNumber: item.postNumber,
      title: item.title,
      excerpt: item.subtitle,
      categoryName: categoryName,
      authorUsername: widget.account.username,
      authorDisplayName: widget.account.displayName,
      authorAvatarUrl: widget.account.avatarUrl,
      replyCount: replyCount,
      viewCount: viewCount,
      createdAt: item.createdAt,
      actionType: item.boardId,
    );
  }

  String _extractCategoryName(String meta) {
    final source = meta.trim();
    if (source.isEmpty) {
      return '清水河畔';
    }
    final parts = source.split('·');
    final first = parts.first.trim();
    if (first.isEmpty) {
      return '清水河畔';
    }
    return first;
  }

  int _extractMetaCount(String meta, String key) {
    final match = RegExp('$key\\s*(\\d+)').firstMatch(meta);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
}

class _ActivityTab extends StatefulWidget {
  final RiverSideProfileActivityKind kind;
  final Future<RiverSideProfileOverview> overviewFuture;
  final Future<List<RiverSideProfileActivityItem>> activityFuture;
  final Future<void> Function() onRefresh;
  final ValueChanged<RiverSideProfileActivityItem> onItemTap;
  final Future<bool> Function()? onLoadMore;
  final bool Function()? canLoadMore;

  const _ActivityTab({
    required this.kind,
    required this.overviewFuture,
    required this.activityFuture,
    required this.onRefresh,
    required this.onItemTap,
    this.onLoadMore,
    this.canLoadMore,
  });

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab>
    with AutomaticKeepAliveClientMixin {
  bool _refreshing = false;
  bool _loadingMore = false;

  bool get _canLoadMore => widget.canLoadMore?.call() ?? false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _tryLoadMore() async {
    if (_loadingMore || widget.onLoadMore == null || !_canLoadMore) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    try {
      await widget.onLoadMore!();
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<RiverSideProfileOverview>(
      future: widget.overviewFuture,
      builder: (context, overviewSnap) {
        if (!overviewSnap.hasData) return const SizedBox();
        if (overviewSnap.data!.isProfileHidden) {
          return const _ProfileHiddenView();
        }

        return FutureBuilder<List<RiverSideProfileActivityItem>>(
          future: widget.activityFuture,
          builder: (context, snapshot) {
            late final Widget content;
            if (_refreshing ||
                snapshot.connectionState == ConnectionState.waiting) {
              content = KeyedSubtree(
                key: ValueKey<String>('activity_loading_${widget.kind.name}'),
                child: _ActivityTabSkeleton(onRefresh: _handleRefresh),
              );
            } else if (snapshot.hasError) {
              content = KeyedSubtree(
                key: ValueKey<String>('activity_error_${widget.kind.name}'),
                child: _ErrorRetryView(
                  message: '加载失败',
                  onRetry: _handleRefresh,
                ),
              );
            } else {
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                content = KeyedSubtree(
                  key: ValueKey<String>('activity_empty_${widget.kind.name}'),
                  child: _EmptyView(
                    message: '暂无${widget.kind.label}动态',
                    onRefresh: _handleRefresh,
                  ),
                );
              } else {
                content = KeyedSubtree(
                  key: ValueKey<String>('activity_list_${widget.kind.name}'),
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    edgeOffset: 0,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 120) {
                          unawaited(_tryLoadMore());
                        }
                        return false;
                      },
                      child: ListView.separated(
                        key: PageStorageKey<String>(
                          'profile_activity_list_${widget.kind.name}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: items.length + (_canLoadMore ? 1 : 0),
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= items.length) {
                            return _ActivityLoadMoreFooter(
                              loading: _loadingMore,
                            );
                          }
                          final item = items[index];
                          return _ActivityCard(
                            item: item,
                            onTap: () => widget.onItemTap(item),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }
            }
            return _ProfileSectionAnimatedSwitcher(child: content);
          },
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item, required this.onTap});

  final RiverSideProfileActivityItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.categoryName,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(item.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.excerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.excerpt.replaceAll('\n', ' '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _IconStat(
                    Icons.chat_bubble_outline_rounded,
                    '${item.replyCount}',
                  ),
                  const SizedBox(width: 16),
                  _IconStat(Icons.remove_red_eye_outlined, '${item.viewCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.month}/${dt.day}';
  }
}

class _IconStat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconStat(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _ActivityLoadMoreFooter extends StatelessWidget {
  const _ActivityLoadMoreFooter({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            : Text(
                '上滑加载更多',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

Color _badgeAccentColor(BuildContext context, int badgeId) {
  final scheme = Theme.of(context).colorScheme;
  final palette = <Color>[
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.primaryContainer,
  ];
  return palette[badgeId.abs() % palette.length];
}

IconData _badgeIconFromToken(String source) {
  final normalized = source
      .trim()
      .toLowerCase()
      .replaceAll('far-', '')
      .replaceAll('fas-', '')
      .replaceAll('fa-', '')
      .replaceAll('_', '-');
  switch (normalized) {
    case 'certificate':
    case 'id-badge':
      return Icons.workspace_premium_rounded;
    case 'graduation-cap':
    case 'award':
      return Icons.school_rounded;
    case 'heart':
      return Icons.favorite_rounded;
    case 'star':
    case 'star-o':
      return Icons.auto_awesome_rounded;
    case 'fire':
      return Icons.local_fire_department_rounded;
    case 'rocket':
      return Icons.rocket_launch_rounded;
    case 'bolt':
      return Icons.flash_on_rounded;
    case 'gem':
      return Icons.diamond_rounded;
    case 'check':
    case 'check-circle':
      return Icons.verified_rounded;
    default:
      return Icons.military_tech_rounded;
  }
}

class _ProfileBadgeVisual extends StatelessWidget {
  const _ProfileBadgeVisual({
    required this.badgeId,
    required this.imageUrl,
    required this.iconToken,
    required this.size,
  });

  final int badgeId;
  final String imageUrl;
  final String iconToken;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _badgeAccentColor(context, badgeId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.14),
            blurRadius: size * 0.22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.trim().isNotEmpty
          ? Image.network(
              imageUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallbackIcon(accent);
              },
            )
          : _buildFallbackIcon(accent),
    );
  }

  Widget _buildFallbackIcon(Color accent) {
    return Center(
      child: Icon(
        _badgeIconFromToken(iconToken),
        size: size * 0.56,
        color: accent.withValues(alpha: 0.95),
      ),
    );
  }
}

class _BadgeDetailDialog extends StatefulWidget {
  const _BadgeDetailDialog({
    required this.badge,
    required this.heroTag,
    required this.username,
    this.isBottomSheet = false,
    required this.onLoadDetail,
  });

  final RiverSideProfileBadge badge;
  final String heroTag;
  final String username;
  final bool isBottomSheet;
  final Future<RiverSideProfileBadgeDetail> Function() onLoadDetail;

  @override
  State<_BadgeDetailDialog> createState() => _BadgeDetailDialogState();
}

class _BadgeDetailDialogState extends State<_BadgeDetailDialog> {
  late Future<RiverSideProfileBadgeDetail> _detailFuture;
  late final MotionController _dialogMotionController = MotionController(
    damping: null,
    maxAngle: 0.42,
  );
  late final MotionController _badgeMotionController = MotionController(
    damping: null,
    maxAngle: 0.72,
  );

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.onLoadDetail();
  }

  void _reload() {
    setState(() => _detailFuture = widget.onLoadDetail());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _badgeAccentColor(context, widget.badge.id);
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (size.height * (widget.isBottomSheet ? 0.88 : 0.82))
        .clamp(420.0, 820.0);
    final content = Motion.elevated(
      elevation: 32,
      controller: _dialogMotionController,
      borderRadius: BorderRadius.circular(28),
      glare: false,
      shadow: false,
      translation: false,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                theme.colorScheme.surface.withValues(alpha: 0.98),
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
              ],
            ),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.isBottomSheet) ...<Widget>[
                const SizedBox(height: 10),
                Align(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.36,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              _buildHeader(theme, accent),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: FutureBuilder<RiverSideProfileBadgeDetail>(
                  future: _detailFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _buildLoadingBody(theme);
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      final message = snapshot.error is RiverSideApiException
                          ? (snapshot.error as RiverSideApiException).message
                          : '加载徽章详情失败';
                      return _buildErrorBody(theme, message);
                    }
                    return _buildDetailBody(theme, snapshot.data!, accent);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.isBottomSheet) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
              child: content,
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 620, maxHeight: maxHeight),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.7),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 6, 44, 0),
            child: Column(
              children: <Widget>[
                Hero(
                  tag: widget.heroTag,
                  child: Motion.elevated(
                    elevation: 40,
                    controller: _badgeMotionController,
                    borderRadius: BorderRadius.circular(24),
                    child: _ProfileBadgeVisual(
                      badgeId: widget.badge.id,
                      imageUrl: widget.badge.imageUrl,
                      iconToken: widget.badge.icon,
                      size: 86,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.badge.name.isEmpty ? '徽章详情' : widget.badge.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '@${widget.username}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    _MetaChip(
                      label: 'Badge #${widget.badge.id}',
                      icon: Icons.tag_rounded,
                      color: accent,
                    ),
                    if (widget.badge.grantCount > 0)
                      _MetaChip(
                        label: '授予 ${widget.badge.grantCount}',
                        icon: Icons.celebration_outlined,
                        color: theme.colorScheme.secondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBody(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '正在加载徽章详情...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBody(ThemeData theme, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailBody(
    ThemeData theme,
    RiverSideProfileBadgeDetail detail,
    Color accent,
  ) {
    final chips = <Widget>[
      if (detail.badgeTypeName.isNotEmpty)
        _MetaChip(
          label: detail.badgeTypeName,
          icon: Icons.workspace_premium_outlined,
          color: accent,
        ),
      _MetaChip(
        label: '总授予 ${detail.grantCount}',
        icon: Icons.bar_chart_rounded,
        color: theme.colorScheme.secondary,
      ),
      if (detail.allowTitle)
        _MetaChip(
          label: '可作为头衔',
          icon: Icons.title_rounded,
          color: theme.colorScheme.primary,
        ),
      if (detail.multipleGrant)
        _MetaChip(
          label: '支持多次授予',
          icon: Icons.repeat_rounded,
          color: theme.colorScheme.tertiary,
        ),
    ];

    final normalizedDescription = detail.description.trim();
    final normalizedLongDescription = detail.longDescription.trim();
    final hasLongDescription =
        normalizedLongDescription.isNotEmpty &&
        normalizedLongDescription != normalizedDescription;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (chips.isNotEmpty) ...<Widget>[
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 14),
          ],
          if (normalizedDescription.isNotEmpty)
            _BadgeMarkdownCard(title: '简介', markdown: normalizedDescription),
          if (hasLongDescription) ...<Widget>[
            const SizedBox(height: 12),
            _BadgeMarkdownCard(
              title: '详细说明',
              markdown: normalizedLongDescription,
            ),
          ],
          if (detail.slug.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest.withValues(
                  alpha: 0.78,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail.slug,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgeMarkdownCard extends StatelessWidget {
  const _BadgeMarkdownCard({required this.title, required this.markdown});

  final String title;
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          MarkdownBody(
            data: markdown,
            selectable: true,
            onTapLink: (text, href, title) {
              final raw = href?.trim() ?? '';
              if (raw.isEmpty) {
                return;
              }
              final uri = Uri.tryParse(raw);
              if (uri == null) {
                return;
              }
              unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
              a: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgesTab extends StatefulWidget {
  final Future<RiverSideProfileOverview> overviewFuture;
  final Future<List<RiverSideProfileBadge>> badgesFuture;
  final Future<void> Function(RiverSideProfileBadge badge) onBadgeTap;
  final String Function(RiverSideProfileBadge badge) badgeHeroTagBuilder;
  final Future<void> Function() onRefresh;

  const _BadgesTab({
    required this.overviewFuture,
    required this.badgesFuture,
    required this.onBadgeTap,
    required this.badgeHeroTagBuilder,
    required this.onRefresh,
  });

  @override
  State<_BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<_BadgesTab>
    with AutomaticKeepAliveClientMixin {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<RiverSideProfileOverview>(
      future: widget.overviewFuture,
      builder: (context, overviewSnap) {
        if (overviewSnap.hasData && overviewSnap.data!.isProfileHidden) {
          return const _ProfileHiddenView();
        }
        return FutureBuilder<List<RiverSideProfileBadge>>(
          future: widget.badgesFuture,
          builder: (context, snapshot) {
            late final Widget content;
            if (_refreshing ||
                snapshot.connectionState == ConnectionState.waiting) {
              content = KeyedSubtree(
                key: const ValueKey<String>('badges_loading'),
                child: _BadgesTabSkeleton(onRefresh: _handleRefresh),
              );
            } else {
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                content = KeyedSubtree(
                  key: const ValueKey<String>('badges_empty'),
                  child: _EmptyView(message: '暂无徽章', onRefresh: _handleRefresh),
                );
              } else {
                content = KeyedSubtree(
                  key: ValueKey<String>('badges_list_${items.length}'),
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final badge = items[index];
                        final heroTag = widget.badgeHeroTagBuilder(badge);
                        final subtitle = badge.description.isNotEmpty
                            ? badge.description
                            : (badge.badgeTypeName.isNotEmpty
                                  ? badge.badgeTypeName
                                  : '点击查看徽章详情');
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              unawaited(widget.onBadgeTap(badge));
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Hero(
                                    tag: heroTag,
                                    child: _ProfileBadgeVisual(
                                      badgeId: badge.id,
                                      imageUrl: badge.imageUrl,
                                      iconToken: badge.icon,
                                      size: 42,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          badge.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                height: 1.3,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                      ),
                                      if (badge.grantCount > 0) ...<Widget>[
                                        const SizedBox(height: 4),
                                        Text(
                                          'x${badge.grantCount}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }
            }
            return _ProfileSectionAnimatedSwitcher(child: content);
          },
        );
      },
    );
  }
}

class _UsersTab extends StatefulWidget {
  final Future<RiverSideProfileOverview> overviewFuture;
  final Future<List<RiverSideProfileFollowUser>> usersFuture;
  final Future<void> Function() onRefresh;
  final ValueChanged<RiverSideProfileFollowUser> onUserTap;
  final String emptyText;

  const _UsersTab({
    required this.overviewFuture,
    required this.usersFuture,
    required this.onRefresh,
    required this.onUserTap,
    required this.emptyText,
  });

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab>
    with AutomaticKeepAliveClientMixin {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<RiverSideProfileOverview>(
      future: widget.overviewFuture,
      builder: (context, overviewSnap) {
        if (overviewSnap.hasData && overviewSnap.data!.isProfileHidden) {
          return const _ProfileHiddenView();
        }
        final isRiverSideProfile =
            overviewSnap.data?.account.provider == AccountProvider.riverSide;
        return FutureBuilder<List<RiverSideProfileFollowUser>>(
          future: widget.usersFuture,
          builder: (context, snapshot) {
            late final Widget content;
            if (_refreshing ||
                snapshot.connectionState == ConnectionState.waiting) {
              content = KeyedSubtree(
                key: const ValueKey<String>('users_loading'),
                child: _UsersTabSkeleton(onRefresh: _handleRefresh),
              );
            } else {
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                content = KeyedSubtree(
                  key: const ValueKey<String>('users_empty'),
                  child: _EmptyView(
                    message: widget.emptyText,
                    onRefresh: _handleRefresh,
                  ),
                );
              } else {
                content = KeyedSubtree(
                  key: ValueKey<String>('users_list_${items.length}'),
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final user = items[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.avatarUrl.isNotEmpty
                                ? NetworkImage(user.avatarUrl)
                                : null,
                            child: user.avatarUrl.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            isRiverSideProfile
                                ? riverSidePrimaryLabel(
                                    username: user.username,
                                    displayName: user.displayName,
                                  )
                                : user.displayName,
                          ),
                          subtitle: Text(
                            isRiverSideProfile
                                ? riverSideSecondaryLabel(
                                    username: user.username,
                                    displayName: user.displayName,
                                  )
                                : '@${user.username}',
                          ),
                          onTap: () => widget.onUserTap(user),
                        );
                      },
                    ),
                  ),
                );
              }
            }
            return _ProfileSectionAnimatedSwitcher(child: content);
          },
        );
      },
    );
  }
}

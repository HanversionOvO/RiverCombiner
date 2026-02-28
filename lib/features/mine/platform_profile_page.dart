import 'package:flutter/material.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/features/mine/platform_profile_models.dart';
import 'package:river/features/mine/platform_profile_repository.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:river/core/widgets/river_auto_animated_scroll.dart';
class PlatformProfilePage extends StatefulWidget {
  const PlatformProfilePage({
    super.key,
    required this.dependencies,
    required this.account,
  });

  final AppDependencies dependencies;
  final UserAccount account;

  @override
  State<PlatformProfilePage> createState() => _PlatformProfilePageState();
}

class _PlatformProfilePageState extends State<PlatformProfilePage>
    with SingleTickerProviderStateMixin {
  late final PlatformProfileRepository _repository;
  late final List<PlatformProfileTab> _tabs;
  late final TabController _tabController;
  late Future<PlatformProfileOverview> _overviewFuture;
  final Map<String, Future<List<PlatformProfileActivityItem>>>
  _activityFutures = <String, Future<List<PlatformProfileActivityItem>>>{};

  @override
  void initState() {
    super.initState();
    _repository = PlatformProfileRepository(dependencies: widget.dependencies);
    _tabs = _repository.tabsFor(widget.account);
    _tabController = TabController(length: _tabs.length, vsync: this);
    _overviewFuture = _repository.loadOverview(widget.account);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<PlatformProfileActivityItem>> _ensureActivityFuture(
    PlatformProfileTab tab,
  ) {
    return _activityFutures.putIfAbsent(
      tab.id,
      () => _repository.loadActivities(account: widget.account, tab: tab),
    );
  }

  Future<void> _refreshCurrentTab() async {
    final tab = _tabs[_tabController.index];
    setState(() {
      _activityFutures[tab.id] = _repository.loadActivities(
        account: widget.account,
        tab: tab,
      );
    });
    await _activityFutures[tab.id];
  }

  Future<void> _refreshOverview() async {
    setState(() {
      _overviewFuture = _repository.loadOverview(widget.account);
      _activityFutures.clear();
    });
    await _overviewFuture;
  }

  Future<void> _openTopicDetail(PlatformProfileActivityItem item) async {
    if (item.topicId == null || item.topicId! <= 0) {
      return;
    }
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => TopicDetailPage(
          dependencies: widget.dependencies,
          topicId: item.topicId!,
        ),
      ),
    );
  }

  Future<void> _openProfileInBrowser(String profileUrl) async {
    final uri = Uri.tryParse(profileUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String _formatCount(int? value) {
    if (value == null || value < 0) {
      return '--';
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerLabel = widget.account.provider == AccountProvider.riverSide
        ? 'RiverSide'
        : '清水河畔';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account.displayName),
        centerTitle: true,
      ),
      body: FutureBuilder<PlatformProfileOverview>(
        future: _overviewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is RiverSideApiException
                ? (snapshot.error as RiverSideApiException).message
                : '加载资料失败';
            return _ProfileErrorView(
              message: message,
              onRetry: _refreshOverview,
            );
          }
          final overview = snapshot.data;
          if (overview == null) {
            return _ProfileErrorView(
              message: '资料为空',
              onRetry: _refreshOverview,
            );
          }
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshOverview,
                  child: RiverAutoAnimatedCustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: _ProfileHeaderCard(
                            overview: overview,
                            providerLabel: providerLabel,
                            formatDate: _formatDate,
                            formatCount: _formatCount,
                            onOpenProfileInBrowser: overview.profileUrl == null
                                ? null
                                : () => _openProfileInBrowser(
                                    overview.profileUrl!,
                                  ),
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabHeaderDelegate(
                          color: theme.colorScheme.surface,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            indicatorSize: TabBarIndicatorSize.label,
                            tabs: _tabs
                                .map((tab) => Tab(text: tab.label))
                                .toList(),
                          ),
                        ),
                      ),
                      SliverFillRemaining(
                        child: TabBarView(
                          controller: _tabController,
                          children: _tabs.map((tab) {
                            return _ProfileActivityList(
                              future: _ensureActivityFuture(tab),
                              onRefresh: _refreshCurrentTab,
                              onTap: tab.supportsTopicOpen
                                  ? _openTopicDetail
                                  : null,
                              formatDate: _formatDate,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.overview,
    required this.providerLabel,
    required this.formatDate,
    required this.formatCount,
    this.onOpenProfileInBrowser,
  });

  final PlatformProfileOverview overview;
  final String providerLabel;
  final String Function(DateTime? value) formatDate;
  final String Function(int? value) formatCount;
  final VoidCallback? onOpenProfileInBrowser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.46),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: overview.account.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(overview.account.avatarUrl),
                child: overview.account.avatarUrl.isEmpty
                    ? const Icon(Icons.person_outline_rounded)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.account.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${overview.account.username}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpenProfileInBrowser != null)
                IconButton(
                  onPressed: onOpenProfileInBrowser,
                  tooltip: '浏览器打开',
                  icon: const Icon(Icons.open_in_browser_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoChip(label: providerLabel),
              if (overview.account.title.trim().isNotEmpty)
                _InfoChip(label: overview.account.title.trim()),
              if (overview.location.trim().isNotEmpty)
                _InfoChip(label: overview.location.trim()),
            ],
          ),
          if (overview.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(overview.bio.trim(), style: theme.textTheme.bodyMedium),
          ],
          if (overview.extraDescription.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              overview.extraDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: '主题',
                  value: formatCount(overview.topicCount),
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: '回复',
                  value: formatCount(overview.replyCount),
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: '获赞/收藏',
                  value: formatCount(overview.likesOrFavoritesCount),
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: '粉丝',
                  value: formatCount(overview.followersCount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '注册：${formatDate(overview.createdAt)}    最近活跃：${formatDate(overview.lastSeenAt)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ProfileActivityList extends StatelessWidget {
  const _ProfileActivityList({
    required this.future,
    required this.onRefresh,
    required this.formatDate,
    this.onTap,
  });

  final Future<List<PlatformProfileActivityItem>> future;
  final Future<void> Function() onRefresh;
  final Future<void> Function(PlatformProfileActivityItem item)? onTap;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlatformProfileActivityItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final message = snapshot.error is RiverSideApiException
              ? (snapshot.error as RiverSideApiException).message
              : '加载失败';
          return _ProfileErrorView(message: message, onRetry: onRefresh);
        }
        final items = snapshot.data ?? const <PlatformProfileActivityItem>[];
        if (items.isEmpty) {
          return _ProfileEmptyView(onRefresh: onRefresh);
        }
        return RiverAutoAnimatedListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          itemCount: items.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap == null ? null : () => onTap!(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (item.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '${item.meta} · ${formatDate(item.createdAt)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _ProfileEmptyView extends StatelessWidget {
  const _ProfileEmptyView({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '暂无内容',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRefresh, child: const Text('刷新')),
        ],
      ),
    );
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabHeaderDelegate({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: color,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.color != color;
  }
}




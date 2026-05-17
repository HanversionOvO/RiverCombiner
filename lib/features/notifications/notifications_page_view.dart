part of 'notifications_page.dart';

extension _NotificationsPageView on _NotificationsPageState {
  Widget _buildTopHeader(ThemeData theme, double t) {
    final topInset = MediaQuery.paddingOf(context).top;
    final collapse = t.clamp(0.0, 1.0);
    final unreadNotifications = _notifications
        .where((item) => !item.read)
        .length;
    final subtitle = unreadNotifications > 0
        ? '未读 $unreadNotifications 条'
        : '全部已读';
    const titleSize = 21.0;
    final subtitleVisibility = (1.0 - collapse).clamp(0.0, 1.0);
    final borderAlpha = lerpDouble(0.18, 0.26, collapse)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface.withValues(
              alpha: lerpDouble(0.90, 0.96, t)!,
            ),
            theme.colorScheme.surfaceContainerLowest.withValues(
              alpha: lerpDouble(0.82, 0.92, t)!,
            ),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(
              alpha: borderAlpha,
            ),
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: lerpDouble(7, 11, t)!,
            sigmaY: lerpDouble(7, 11, t)!,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: topInset + lerpDouble(9, 8, collapse)!,
              bottom: 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 64),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '通知',
                                  textAlign: TextAlign.left,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    fontSize: titleSize,
                                  ),
                                ),
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    heightFactor: subtitleVisibility,
                                    child: Opacity(
                                      opacity: subtitleVisibility,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            subtitle,
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _isIPhoneDevice(context)
                              ? Tooltip(
                                  message: '全部已读',
                                  child: SizedBox.square(
                                    dimension: 44,
                                    child: AdaptiveButton.sfSymbol(
                                      onPressed: unreadNotifications > 0
                                          ? _markAllNotificationItemsAsRead
                                          : null,
                                      enabled: unreadNotifications > 0,
                                      sfSymbol: const SFSymbol(
                                        'checkmark.circle',
                                        size: 18,
                                      ),
                                      style: AdaptiveButtonStyle.glass,
                                      size: AdaptiveButtonSize.large,
                                      minSize: const Size(44, 44),
                                      padding: EdgeInsets.zero,
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(999),
                                      ),
                                      useSmoothRectangleBorder: false,
                                    ),
                                  ),
                                )
                              : IconButton.filledTonal(
                                  onPressed: unreadNotifications > 0
                                      ? _markAllNotificationItemsAsRead
                                      : null,
                                  tooltip: '全部已读',
                                  icon: const Icon(Icons.done_all_rounded),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildSegmentedTabBar(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedTabBar(ThemeData theme) {
    if (_isIPhoneDevice(context)) {
      return _buildIPhoneSegmentedTabBar(theme);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RiverRadius.xl),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(RiverRadius.xl),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: theme.colorScheme.onPrimary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: [
          _buildTabItem('通知', _notifications.where((n) => !n.read).length),
          _buildTabItem(
            '频道',
            _channelMessages.fold(0, (sum, i) => sum + i.unreadCount),
          ),
          _buildTabItem(
            '私信',
            _directMessages.fold(0, (sum, i) => sum + i.unreadCount),
          ),
        ],
      ),
    );
  }

  Widget _buildIPhoneSegmentedTabBar(ThemeData theme) {
    final unreadNotifications = _notifications.where((n) => !n.read).length;
    final unreadChannels = _channelMessages.fold(
      0,
      (sum, i) => sum + i.unreadCount,
    );
    final unreadDirect = _directMessages.fold(
      0,
      (sum, i) => sum + i.unreadCount,
    );
    final accent = widget.dependencies.settingsController.themeSeedColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: IOS26SegmentedControl(
        key: ValueKey<int>(accent.toARGB32()),
        labels: [
          _buildAdaptiveTabLabel('通知', unreadNotifications),
          _buildAdaptiveTabLabel('频道', unreadChannels),
          _buildAdaptiveTabLabel('私信', unreadDirect),
        ],
        selectedIndex: _tabController.index,
        onValueChanged: (index) {
          if (index == _tabController.index) {
            return;
          }
          _tabController.animateTo(index);
          if (mounted) {
            _setState(() {});
          }
          _syncBackToTopVisibility();
        },
        color: accent,
        height: 40,
      ),
    );
  }

  String _buildAdaptiveTabLabel(String label, int count) {
    if (count <= 0) {
      return label;
    }
    return '$label •';
  }

  Widget _buildTabItem(String label, int count) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRefreshPlaceholder({
    required Future<void> Function() onRefresh,
    required Widget child,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Center(child: child),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationsList(ThemeData theme) {
    if (_loading && _notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: _buildNotificationsSkeletonList(theme),
      );
    }

    if (_notificationsError != null && _notifications.isEmpty) {
      return _buildRefreshPlaceholder(
        onRefresh: _refreshCurrentTab,
        child: _buildErrorView(
          theme,
          message: _notificationsError,
        ),
      );
    }

    if (_notifications.isEmpty) {
      return _buildRefreshPlaceholder(
        onRefresh: _refreshCurrentTab,
        child: _buildEmptyView(
          theme,
          '暂无通知',
          Icons.notifications_none_rounded,
          message: '下拉刷新后会在这里显示新的系统通知和互动提醒。',
        ),
      );
    }

    final visibleNotifications = _displayNotifications;
    final showQingFilter = _isQingForum;
    if (visibleNotifications.isEmpty && showQingFilter) {
      return RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: ListView(
          controller: _notificationsScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          children: [
            _buildQingNotificationFilterBar(theme),
            const SizedBox(height: 12),
            _buildEmptyView(
              theme,
              '该分类下暂无通知',
              Icons.mark_chat_read_outlined,
              message: '切换筛选项或下拉刷新后再试。',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView.separated(
        controller: _notificationsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount:
            visibleNotifications.length +
            (showQingFilter ? 1 : 0) +
            (_loadingMoreNotifications ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (showQingFilter && index == 0) {
            return _buildQingNotificationFilterBar(theme);
          }
          final dataIndex = showQingFilter ? index - 1 : index;
          if (dataIndex == visibleNotifications.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
              child: Skeletonizer(
                enabled: true,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(RiverRadius.lg),
                  ),
                  child: const ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.notifications_rounded),
                    ),
                    title: Text('正在加载更多通知...'),
                    subtitle: Text('请稍候'),
                  ),
                ),
              ),
            );
          }
          return _buildNotificationCard(
            theme: theme,
            item: visibleNotifications[dataIndex],
          );
        },
      ),
    );
  }

  Widget _buildQingNotificationFilterBar(ThemeData theme) {
    final totalCount = _notifications.length;
    final selectedColor = theme.colorScheme.primary;
    final selectedSurface = theme.colorScheme.primaryContainer.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.48 : 0.78,
    );
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.36,
    );
    final filterItems =
        <
          ({
            _QingNotificationFilter filter,
            IconData icon,
            String label,
            int count,
          })
        >[
          (
            filter: _QingNotificationFilter.all,
            icon: Icons.grid_view_rounded,
            label: '全部',
            count: totalCount,
          ),
          (
            filter: _QingNotificationFilter.atMe,
            icon: Icons.alternate_email_rounded,
            label: '@我',
            count: _qingCountForKind(_QingNotificationKind.atMe),
          ),
          (
            filter: _QingNotificationFilter.reply,
            icon: Icons.reply_rounded,
            label: '回复',
            count: _qingCountForKind(_QingNotificationKind.reply),
          ),
          (
            filter: _QingNotificationFilter.notice,
            icon: Icons.notifications_rounded,
            label: '通知',
            count: _qingCountForKind(_QingNotificationKind.notice),
          ),
        ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerLow,
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
          ],
        ),
        borderRadius: BorderRadius.circular(RiverRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '清水河畔通知筛选',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '共 $totalCount 条',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in filterItems) ...[
                  _buildQingNotificationFilterChip(
                    theme: theme,
                    icon: item.icon,
                    label: item.label,
                    count: item.count,
                    selected: _qingNotificationFilter == item.filter,
                    selectedSurface: selectedSurface,
                    selectedColor: selectedColor,
                    onTap: () => _setQingNotificationFilter(item.filter),
                  ),
                  if (item != filterItems.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQingNotificationFilterChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required Color selectedSurface,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    final foregroundColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? selectedSurface
            : theme.colorScheme.surface.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(RiverRadius.full),
        border: Border.all(
          color: selected
              ? selectedColor.withValues(alpha: 0.46)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: selectedColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RiverRadius.full),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foregroundColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedColor.withValues(alpha: 0.22)
                          : theme.colorScheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(RiverRadius.full),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? selectedColor
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard({
    required ThemeData theme,
    required RiverSideNotificationItem item,
  }) {
    // Resolve visual style by notification type.
    IconData typeIcon;
    Color typeColor;
    Color iconBgColor;

    switch (item.type) {
      case 6: // Private Message
        typeIcon = Icons.mail_rounded;
        typeColor = Colors.orange.shade700;
        iconBgColor = Colors.orange.shade50;
        break;
      case 5: // Like
        typeIcon = Icons.favorite_rounded;
        typeColor = Colors.pink.shade400;
        iconBgColor = Colors.pink.shade50;
        break;
      case 2: // Replied
        typeIcon = Icons.reply_rounded;
        typeColor = Colors.blue.shade600;
        iconBgColor = Colors.blue.shade50;
        break;
      case 12: // Badge
        typeIcon = Icons.military_tech_rounded;
        typeColor = Colors.amber.shade700;
        iconBgColor = Colors.amber.shade50;
        break;
      case 13: // System notice
        typeIcon = Icons.notifications_rounded;
        typeColor = Colors.teal.shade600;
        iconBgColor = Colors.teal.shade50;
        break;
      default: // Mention or others
        typeIcon = Icons.alternate_email_rounded;
        typeColor = theme.colorScheme.primary;
        iconBgColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
    }

    final isUnread = !item.read;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RiverRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Builder(
          builder: (cardContext) {
            return InkWell(
              onTap: () => _openNotificationTopic(cardContext, item),
              child: Stack(
                children: [
                  // Unread indicator strip.
                  if (isUnread)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 澶村儚涓庤鏍?
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainer,
                                backgroundImage: item.avatarUrl.isNotEmpty
                                    ? NetworkImage(item.avatarUrl)
                                    : null,
                                child: item.avatarUrl.isEmpty
                                    ? Icon(
                                        Icons.person,
                                        size: 22,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: iconBgColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: typeColor.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    typeIcon,
                                    size: 12,
                                    color: typeColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // 鍐呭
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: item.username,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '  ${item.actionText}',
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatTime(item.createdAt),
                                    style: TextStyle(
                                      color: theme.colorScheme.outline,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (item.title.isNotEmpty)
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (item.excerpt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.excerpt.replaceAll('\n', ' '),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatList(
    ThemeData theme,
    List<RiverSideChatChannelItem> items,
    String emptyMsg, {
    required ScrollController controller,
  }) {
    if (_loading && items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: _buildChatSkeletonList(theme),
      );
    }

    if (_chatError != null && items.isEmpty) {
      return _buildRefreshPlaceholder(
        onRefresh: _refreshCurrentTab,
        child: _buildErrorView(
          theme,
          message: _chatError,
        ),
      );
    }

    if (items.isEmpty) {
      return _buildRefreshPlaceholder(
        onRefresh: _refreshCurrentTab,
        child: _buildEmptyView(
          theme,
          emptyMsg,
          Icons.chat_bubble_outline_rounded,
          message: '新消息到达后会出现在这里。',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView.separated(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final title = item.name.trim().isNotEmpty
              ? item.name.trim()
              : (item.isDirectMessage ? '私信 #${item.id}' : '频道 #${item.id}');
          final subtitle = item.lastMessage.trim().isNotEmpty
              ? item.lastMessage.trim().replaceAll('\n', ' ')
              : (item.description.trim().isNotEmpty
                    ? item.description.trim().replaceAll('\n', ' ')
                    : '暂无最新消息');
          final isUnread = item.unreadCount > 0;
          final directAvatar = item.avatarUrl.trim();
          final isDeletingDirect = _deletingDirectMessageIds.contains(item.id);
          final card = Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(RiverRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              onTap: isDeletingDirect ? null : () => _openChatDetail(item),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: item.isDirectMessage
                    ? CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.surfaceContainer,
                        backgroundImage: directAvatar.isNotEmpty
                            ? NetworkImage(directAvatar)
                            : null,
                        child: directAvatar.isEmpty
                            ? Icon(
                                Icons.person_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : null,
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(RiverRadius.md),
                        ),
                        child: Icon(
                          Icons.tag_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
              ),
              title: Row(
                children: [
                  if (isUnread) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isUnread
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isUnread
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              trailing: isDeletingDirect
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : item.unreadCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(RiverRadius.md),
                      ),
                      child: Text(
                        '${item.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ),
          );
          final slidableCard = Padding(
            padding: const EdgeInsets.only(right: 8),
            child: card,
          );
          final canSwipeDelete =
              item.isDirectMessage && item.canDeleteSelf && !isDeletingDirect;
          if (!item.isDirectMessage) {
            return card;
          }
          return Slidable(
            key: ValueKey<String>('direct-channel-${item.id}'),
            enabled: canSwipeDelete,
            closeOnScroll: true,
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.30,
              children: [
                CustomSlidableAction(
                  autoClose: true,
                  borderRadius: BorderRadius.circular(RiverRadius.lg),
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  onPressed: (_) async {
                    if (!canSwipeDelete) {
                      return;
                    }
                    final confirmed = await _confirmDeleteDirectMessage(item);
                    if (!confirmed) {
                      return;
                    }
                    await _deleteDirectMessageChannel(item);
                  },
                  child: isDeletingDirect
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline_rounded),
                            SizedBox(height: 4),
                            Text(
                              '删除',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ],
            ),
            child: slidableCard,
          );
        },
      ),
    );
  }

  Widget _buildRealtimeChatUnavailablePlaceholder(
    ThemeData theme, {
    required ScrollController controller,
  }) {
    return _buildRefreshPlaceholder(
      onRefresh: _refreshCurrentTab,
      child: _buildStatePlaceholder(
        theme,
        icon: Icons.forum_outlined,
        title: '当前论坛暂不支持实时聊天',
        message:
            _NotificationsPageState._labelNeedSwitchToRiverSideRealtimeChat,
        actionLabel: '刷新',
        onAction: _loadAll,
      ),
    );
  }

  Widget _buildNotificationsSkeletonList(ThemeData theme) {
    final fakeItems = List<RiverSideNotificationItem>.generate(6, (index) {
      return RiverSideNotificationItem(
        id: index + 1,
        type: 2,
        read: false,
        highPriority: false,
        createdAt: DateTime.now(),
        topicId: index + 1000,
        postNumber: index + 1,
        slug: 'topic-skeleton-$index',
        title: 'RiverSide 通知骨架标题占位',
        excerpt: '这是通知内容的骨架占位，用于展示加载状态。',
        username: 'river_user_$index',
        actionText: '回复了你',
        badgeName: '',
        count: 1,
        avatarUrl: '',
      );
    });
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: fakeItems.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildNotificationCard(theme: theme, item: fakeItems[index]);
        },
      ),
    );
  }

  Widget _buildChatSkeletonList(ThemeData theme) {
    final fakeItems = List<RiverSideChatChannelItem>.generate(7, (index) {
      return RiverSideChatChannelItem(
        id: index + 1,
        name: '频道/私信 骨架占位',
        description: '加载中的描述信息',
        unreadCount: 1,
        lastMessage: '加载中的消息预览骨架占位',
        lastMessageAt: DateTime.now(),
        isDirectMessage: index.isEven,
        avatarUrl: '',
        canDeleteSelf: false,
      );
    });
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: fakeItems.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = fakeItems[index];
          final title = item.name;
          final subtitle = item.lastMessage;
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(RiverRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: const CircleAvatar(
                radius: 22,
                child: Icon(Icons.person_rounded),
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Container(
                width: 26,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(RiverRadius.full),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyView(
    ThemeData theme,
    String text,
    IconData icon, {
    String? message,
  }) {
    return _buildStatePlaceholder(
      theme,
      icon: icon,
      title: text,
      message: message,
      actionLabel: '刷新',
      onAction: () => _loadAll(showLoading: true),
    );
  }

  Widget _buildErrorView(
    ThemeData theme, {
    String? message,
  }) {
    return _buildStatePlaceholder(
      theme,
      icon: Icons.wifi_off_rounded,
      title: '加载失败',
      message: message ?? _NotificationsPageState._labelLoadFailed,
      actionLabel: '重试',
      onAction: _loadAll,
      accentColor: theme.colorScheme.error,
      filledAction: true,
    );
  }

  Widget _buildStatePlaceholder(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? message,
    required String actionLabel,
    required Future<void> Function() onAction,
    Color? accentColor,
    bool filledAction = false,
  }) {
    final accent = accentColor ?? theme.colorScheme.primary;
    final secondaryText = message?.trim() ?? '';
    final iconSurface = accent.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08,
    );
    final innerSurface = theme.colorScheme.surface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.82 : 0.92,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconSurface,
                ),
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: innerSurface,
                      border: Border.all(
                        color: accent.withValues(
                          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.1,
                        ),
                      ),
                    ),
                    child: Icon(icon, size: 28, color: accent),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.15,
                ),
              ),
              if (secondaryText.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  secondaryText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              filledAction
                  ? FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(actionLabel),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 13,
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(actionLabel),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 13,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}月${time.day}日';
  }
}

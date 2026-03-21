part of 'topic_detail_page.dart';

class _PostAuthorHeader extends StatelessWidget {
  const _PostAuthorHeader({
    required this.post,
    this.onTap,
    this.heroTagAvatar,
    this.heroTagName,
    this.enableHero = true,
    this.trailing,
    this.showAliasFirst = false,
  });

  final RiverSideTopicPostDetail post;
  final VoidCallback? onTap;
  final String? heroTagAvatar;
  final String? heroTagName;
  final bool enableHero;
  final Widget? trailing;
  final bool showAliasFirst;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final subtitleColor = colors.onSurfaceVariant;
    final onlineColor = _onlineStateColor(post.isOnline, context);

    final avatar = Stack(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: post.authorAvatarUrl.isEmpty
              ? null
              : NetworkImage(post.authorAvatarUrl),
          child: post.authorAvatarUrl.isEmpty
              ? const Icon(Icons.person_outline)
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: onlineColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
    final avatarWidget =
        !enableHero || heroTagAvatar == null || heroTagAvatar!.isEmpty
        ? avatar
        : Hero(tag: heroTagAvatar!, child: avatar);

    final username = post.authorUsername.trim();
    final alias = post.authorDisplayName.trim();
    final primaryName = showAliasFirst
        ? (alias.isNotEmpty ? alias : username)
        : (username.isNotEmpty ? username : alias);
    final secondaryName = showAliasFirst ? username : alias;

    final displayName = Text(
      primaryName,
      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final displayNameWidget =
        !enableHero || heroTagName == null || heroTagName!.isEmpty
        ? displayName
        : Hero(
            tag: heroTagName!,
            child: Material(color: Colors.transparent, child: displayName),
          );

    final child = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 頭像 + 在線狀態指示器
        avatarWidget,
        const SizedBox(width: 10),

        // 2. 用戶信息列
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              displayNameWidget,
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (secondaryName.isNotEmpty)
                    Text(
                      '@$secondaryName',
                      style: textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  if (post.authorTitle.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        post.authorTitle,
                        style: textTheme.labelSmall?.copyWith(
                          color: subtitleColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (trailing case final Widget trailingWidget) ...[
          const SizedBox(width: 8),
          trailingWidget,
        ],
      ],
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

part of 'compose_topic_page.dart';

extension _ComposeTopicPageView on _ComposeTopicPageState {
  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Subtle gradient background.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                      : [
                          colorScheme.surface,
                          colorScheme.surfaceContainer.withValues(alpha: 0.5),
                          colorScheme.primaryContainer.withValues(alpha: 0.1),
                        ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Main content.
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),

                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: ListView(
                        controller: _pageScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          const SizedBox(height: 18),

                          TextField(
                            controller: _titleController,
                            focusNode: _titleFocusNode,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                              letterSpacing: -0.5,
                            ),
                            decoration: InputDecoration(
                              hintText: '标题...',
                              hintStyle: TextStyle(
                                color: theme.hintColor.withValues(alpha: 0.3),
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            textInputAction: TextInputAction.next,
                            maxLines: null,
                          ),

                          const SizedBox(height: 24),

                          _buildEditorArea(theme),

                          SizedBox(
                            height:
                                MediaQuery.viewInsetsOf(context).bottom + 208,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom toolbar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomComposeDock(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = widget.dependencies.settingsController.themeSeedColor;
    final t = Curves.easeOutCubic.transform(_topBarFactor).clamp(0.0, 1.0);
    const titleSize = 21.0;
    final subtitleVisibility = (1.0 - t).clamp(0.0, 1.0);
    final borderAlpha = lerpDouble(0.18, 0.26, t)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface.withValues(alpha: lerpDouble(0.90, 0.96, t)!),
            colorScheme.surfaceContainerLowest.withValues(
              alpha: lerpDouble(0.82, 0.92, t)!,
            ),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: borderAlpha),
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
            padding: EdgeInsets.fromLTRB(16, lerpDouble(9, 8, t)!, 8, 8),
            child: SizedBox(
              height: 44,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 190),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '发帖',
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
                                child: Text(
                                  '分享此时此刻',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _isIPhoneDevice(context)
                            ? Tooltip(
                                message: '预览',
                                child: SizedBox.square(
                                  dimension: 44,
                                  child: AdaptiveButton.sfSymbol(
                                    onPressed: _previewTopic,
                                    sfSymbol: const SFSymbol('eye', size: 18),
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
                                onPressed: _previewTopic,
                                icon: const Icon(Icons.visibility_outlined),
                                tooltip: '预览',
                              ),
                        const SizedBox(width: 8),
                        _isIPhoneDevice(context)
                            ? _buildIPhoneNativePublishButton(accent: accent)
                            : _AnimatedScaleButton(
                                onTap: _publishing ? null : _publishTopic,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _publishing
                                          ? [Colors.grey, Colors.grey]
                                          : [
                                              colorScheme.primary,
                                              colorScheme.tertiary,
                                            ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(RiverRadius.xl),
                                    boxShadow: _publishing
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: colorScheme.primary
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: _publishing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          '发布',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIPhoneNativePublishButton({required Color accent}) {
    final baseColor = _publishing ? Colors.grey : accent;
    final foreground =
        ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return AdaptiveButton.child(
      key: ValueKey<int>(baseColor.toARGB32() ^ (_publishing ? 1 : 0)),
      onPressed: _publishing ? null : _publishTopic,
      enabled: !_publishing,
      style: AdaptiveButtonStyle.prominentGlass,
      color: baseColor,
      size: AdaptiveButtonSize.large,
      minSize: const Size(82, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      useSmoothRectangleBorder: false,
      useNative: true,
      child: _publishing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              '发布',
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
    );
  }

  Widget _buildComposeTargetChip({
    required ThemeData theme,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
    required ImageProvider icon,
  }) {
    final colorScheme = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(RiverRadius.lg),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.28)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(RiverRadius.lg),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(backgroundImage: icon, radius: 10),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCapsuleForProvider({
    required ThemeData theme,
    required AccountProvider provider,
    required String label,
    required bool loading,
    bool compact = false,
  }) {
    final selected = _selectedCategory(provider);
    final hasSelection = selected != null;
    final colorScheme = theme.colorScheme;
    var categoryCaption = label;
    var categoryText = hasSelection
        ? _displayCategoryName(selected, provider)
        : '选择板块';
    if (provider == AccountProvider.qingShuiHePan && selected != null) {
      final explicit = selected.displayName.trim();
      final parts = explicit
          .split(' · ')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (parts.length > 1) {
        categoryCaption =
            '$label · ${parts.sublist(0, parts.length - 1).join(' · ')}';
        categoryText = parts.last;
      }
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _loadingMeta ? null : () => _openCategoryPicker(provider),
        borderRadius: BorderRadius.circular(compact ? 16 : 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 13 : 12,
            compact ? 11 : 10,
            compact ? 11 : 10,
            compact ? 11 : 10,
          ),
          decoration: BoxDecoration(
            color: hasSelection
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(compact ? 16 : 14),
            border: Border.all(
              color: hasSelection
                  ? colorScheme.primary.withValues(alpha: 0.22)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              if (loading)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: compact ? 14 : 12,
                    height: compact ? 14 : 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                )
              else
                Icon(
                  hasSelection
                      ? Icons.dashboard_rounded
                      : Icons.dashboard_customize_outlined,
                  size: compact ? 17 : 16,
                  color: hasSelection
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryCaption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hasSelection
                            ? colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.82,
                              )
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categoryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasSelection
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 14.5 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: compact ? 20 : 18,
                color: hasSelection
                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomComposeDock(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final extraInset = bottomInset > 0 ? 0.0 : widget.bottomToolbarExtraInset;
    final canUseRiver = _activeRiverCookieHeader()?.trim().isNotEmpty == true;
    final canUseQing = _activeQingAuth() != null;
    final selectedTargets =
        (_enableRiverCompose ? 1 : 0) + (_enableQingCompose ? 1 : 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface.withValues(alpha: 0.96),
            colorScheme.surfaceContainerLowest.withValues(alpha: 0.98),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: extraInset),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '发帖论坛',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selectedTargets > 0
                          ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                          : colorScheme.surfaceContainerHigh.withValues(
                              alpha: 0.8,
                            ),
                      borderRadius: BorderRadius.circular(RiverRadius.full),
                    ),
                    child: Text(
                      selectedTargets > 0 ? '已选 $selectedTargets 个目标' : '请选择论坛',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selectedTargets > 0
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildComposeTargetChip(
                      theme: theme,
                      label: 'RiverSide',
                      selected: _enableRiverCompose,
                      enabled: canUseRiver,
                      onTap: () {
                        _mutateState(() {
                          _enableRiverCompose = !_enableRiverCompose;
                        });
                      },
                      icon: const AssetImage('assets/images/rs.png'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildComposeTargetChip(
                      theme: theme,
                      label: '清水河畔',
                      selected: _enableQingCompose,
                      enabled: canUseQing,
                      onTap: () {
                        _mutateState(() {
                          _enableQingCompose = !_enableQingCompose;
                        });
                      },
                      icon: const AssetImage('assets/images/hp.png'),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: (_enableRiverCompose || _enableQingCompose) ? 10 : 0,
                  ),
                  child: selectedTargets == 0
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            if (_enableRiverCompose)
                              _buildCategoryCapsuleForProvider(
                                theme: theme,
                                provider: AccountProvider.riverSide,
                                label: 'RiverSide',
                                loading: _loadingRiverMeta,
                                compact: true,
                              ),
                            if (_enableRiverCompose && _enableQingCompose)
                              const SizedBox(height: 8),
                            if (_enableQingCompose)
                              _buildCategoryCapsuleForProvider(
                                theme: theme,
                                provider: AccountProvider.qingShuiHePan,
                                label: '清水河畔',
                                loading: _loadingQingMeta,
                                compact: true,
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorArea(ThemeData theme) {
    final hasContent = _contentMarkdown.trim().isNotEmpty;

    return GestureDetector(
      onTap: _openEditor,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        child: hasContent
            ? Text(
                _contentMarkdown.trim(),
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  fontSize: 17,
                  color: theme.textTheme.bodyLarge?.color?.withValues(
                    alpha: 0.9,
                  ),
                ),
                maxLines: null,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '分享你的想法...',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.6,
                      color: theme.hintColor.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AnimatedScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _AnimatedScaleButton({required this.child, this.onTap});

  @override
  State<_AnimatedScaleButton> createState() => _AnimatedScaleButtonState();
}

class _AnimatedScaleButtonState extends State<_AnimatedScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _controller.forward();
      },
      onTapUp: (_) {
        if (widget.onTap != null) {
          _controller.reverse();
          widget.onTap!();
        }
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

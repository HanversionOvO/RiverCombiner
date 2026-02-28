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
                          const SizedBox(height: 10),

                          _buildTargetPanel(theme),

                          const SizedBox(height: 20),

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
                                MediaQuery.viewInsetsOf(context).bottom + 80,
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
            child: _buildBottomToolbar(context),
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
                                  '编辑标题与正文',
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
                                    borderRadius: BorderRadius.circular(30),
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

  Widget _buildTargetPanel(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final riverSelected = _enableRiverCompose;
    final qingSelected = _enableQingCompose;
    final canUseRiver = _activeRiverCookieHeader()?.trim().isNotEmpty == true;
    final canUseQing = _activeQingAuth() != null;

    Widget buildTargetChip({
      required String label,
      required bool selected,
      required bool enabled,
      required VoidCallback onTap,
      required ImageProvider icon,
    }) {
      return Opacity(
        opacity: enabled ? 1 : 0.52,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.28)
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(backgroundImage: icon, radius: 9),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '发帖论坛',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              buildTargetChip(
                label: 'RiverSide',
                selected: riverSelected,
                enabled: canUseRiver,
                onTap: () {
                  _mutateState(() {
                    _enableRiverCompose = !_enableRiverCompose;
                  });
                },
                icon: const AssetImage('assets/images/rs.png'),
              ),
              buildTargetChip(
                label: '清水河畔',
                selected: qingSelected,
                enabled: canUseQing,
                onTap: () {
                  _mutateState(() {
                    _enableQingCompose = !_enableQingCompose;
                  });
                },
                icon: const AssetImage('assets/images/hp.png'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_enableRiverCompose)
            _buildCategoryCapsuleForProvider(
              theme: theme,
              provider: AccountProvider.riverSide,
              label: 'RiverSide 板块',
              loading: _loadingRiverMeta,
            ),
          if (_enableRiverCompose && _enableQingCompose)
            const SizedBox(height: 8),
          if (_enableQingCompose)
            _buildCategoryCapsuleForProvider(
              theme: theme,
              provider: AccountProvider.qingShuiHePan,
              label: '清水河畔板块',
              loading: _loadingQingMeta,
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCapsuleForProvider({
    required ThemeData theme,
    required AccountProvider provider,
    required String label,
    required bool loading,
  }) {
    final selected = _selectedCategory(provider);
    final hasSelection = selected != null;
    final colorScheme = theme.colorScheme;
    final categoryText = hasSelection
        ? _displayCategoryName(selected, provider)
        : '选择板块';
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _loadingMeta ? null : () => _openCategoryPicker(provider),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: hasSelection
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
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
                    width: 12,
                    height: 12,
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
                  size: 16,
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
                      label,
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
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
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

  Widget _buildBottomToolbar(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = bottomInset > 0 || _titleFocusNode.hasFocus;
    final extraInset = bottomInset > 0 ? 0.0 : widget.bottomToolbarExtraInset;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: extraInset),
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.image_outlined,
              label: '图片',
              onTap: () {
                _openEditor();
              },
            ),
            const SizedBox(width: 16),
            _ToolButton(
              icon: Icons.sentiment_satisfied_rounded,
              label: '表情',
              onTap: _openEditor,
            ),
            const SizedBox(width: 16),
            _ToolButton(
              icon: Icons.format_quote_rounded,
              label: '引用',
              onTap: _openEditor,
            ),
            if (keyboardVisible) ...[
              const SizedBox(width: 8),
              _ToolButton(
                icon: Icons.keyboard_hide_rounded,
                label: '收起键盘',
                onTap: _dismissComposeKeyboard,
              ),
            ],
            const Spacer(),
            TextButton.icon(
              onPressed: _openEditor,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                backgroundColor: colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              icon: const Icon(Icons.fullscreen, size: 18),
              label: const Text('全屏编辑'),
            ),
          ],
        ),
      ),
    );
  }

  void _dismissComposeKeyboard() {
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    _titleFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
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

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
    );
  }
}

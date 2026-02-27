import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/ai/river_ai_service.dart';
import 'package:river/core/categories/riverside_category_utils.dart';
import 'package:river/core/categories/riverside_category_store.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/constants.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_profile_models.dart';
import 'package:river/core/network/riverside_topic_models.dart';
import 'package:river/core/qing/qing_emoji_catalog.dart';
import 'package:river/core/widgets/riverside_category_picker_sheet.dart';
import 'package:river/core/widgets/river_markdown_editor.dart';
import 'package:river/features/compose/compose_topic_preview_page.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

part 'compose_topic_page_view.dart';
part 'compose_topic_page_actions.dart';

class ComposeTopicPage extends StatefulWidget {
  const ComposeTopicPage({
    super.key,
    required this.dependencies,
    this.bottomToolbarExtraInset = 0,
    this.initialTitle,
    this.initialMarkdown,
    this.initialEnableRiverCompose,
    this.initialEnableQingCompose,
    this.initialSelectedRiverCategoryId,
    this.initialSelectedQingBoardId,
  });

  final AppDependencies dependencies;
  final double bottomToolbarExtraInset;
  final String? initialTitle;
  final String? initialMarkdown;
  final bool? initialEnableRiverCompose;
  final bool? initialEnableQingCompose;
  final int? initialSelectedRiverCategoryId;
  final int? initialSelectedQingBoardId;

  @override
  State<ComposeTopicPage> createState() => _ComposeTopicPageState();
}

class _ComposeTopicPageState extends State<ComposeTopicPage>
    with SingleTickerProviderStateMixin {
  static const String _labelNeedRiverLogin = '请先登录 RiverSide 账号';
  static const String _labelNeedQingLogin = '请先登录清水河畔账号';

  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final ScrollController _pageScrollController = ScrollController();

  List<RiverSideCategoryOption> _riverCategories =
      const <RiverSideCategoryOption>[];
  List<RiverSideCategoryOption> _qingCategories =
      const <RiverSideCategoryOption>[];
  Map<String, String> _riverEmojiUrls = const <String, String>{};
  Map<String, List<String>> _riverEmojiGroups = const <String, List<String>>{};
  Map<String, String> _qingEmojiUrls = const <String, String>{};
  Map<String, List<String>> _qingEmojiGroups = const <String, List<String>>{};
  final Map<String, _QingComposeUploadImage> _qingUploadedImagesByDisplayUrl =
      <String, _QingComposeUploadImage>{};

  String _contentMarkdown = '';
  int? _selectedRiverCategoryId;
  int? _selectedQingBoardId;
  bool _enableRiverCompose = true;
  bool _enableQingCompose = false;
  bool _loadingMeta = false;
  bool _loadingRiverMeta = false;
  bool _loadingQingMeta = false;
  bool _publishing = false;
  double _topBarFactor = 0;
  String? _lastActiveRiverUsername;
  String? _lastActiveQingUsername;

  // 动画控制器：用于入场动画
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    final initialTitle = widget.initialTitle?.trim() ?? '';
    if (initialTitle.isNotEmpty) {
      _titleController.text = initialTitle;
    }
    _contentMarkdown = widget.initialMarkdown?.trim() ?? '';
    if (widget.initialEnableRiverCompose != null) {
      _enableRiverCompose = widget.initialEnableRiverCompose!;
    }
    if (widget.initialEnableQingCompose != null) {
      _enableQingCompose = widget.initialEnableQingCompose!;
    }
    _selectedRiverCategoryId = widget.initialSelectedRiverCategoryId;
    _selectedQingBoardId = widget.initialSelectedQingBoardId;

    _lastActiveRiverUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    _lastActiveQingUsername =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    widget.dependencies.accountStore.addListener(_onAccountStoreChanged);

    // 初始化动画
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart),
        );

    _animController.forward();
    _loadMetaData();
    _pageScrollController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    widget.dependencies.accountStore.removeListener(_onAccountStoreChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _pageScrollController
      ..removeListener(_onPageScroll)
      ..dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    final next =
        (_pageScrollController.hasClients ? _pageScrollController.offset : 0) /
        96;
    final normalized = next.clamp(0.0, 1.0);
    if ((_topBarFactor - normalized).abs() < 0.01 || !mounted) {
      return;
    }
    setState(() {
      _topBarFactor = normalized;
    });
  }

  void _onAccountStoreChanged() {
    final currentRiver =
        widget.dependencies.accountStore.activeRiverSideUsername;
    final currentQing =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    if (currentRiver == _lastActiveRiverUsername &&
        currentQing == _lastActiveQingUsername) {
      return;
    }
    _lastActiveRiverUsername = currentRiver;
    _lastActiveQingUsername = currentQing;
    _loadMetaData();
  }

  String? _activeRiverCookieHeader() {
    final activeUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    if (activeUsername == null || activeUsername.isEmpty) return null;
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(
      activeUsername,
    );
  }

  QingShuiHePanAuth? _activeQingAuth() {
    final username =
        widget.dependencies.accountStore.activeQingShuiHePanUsername?.trim() ??
        '';
    if (username.isEmpty) {
      return null;
    }
    return widget.dependencies.accountStore.qingShuiHePanAuthFor(username);
  }

  UserAccount? get _activeAccount =>
      widget.dependencies.accountStore.activeRiverSideAccount;

  void _mutateState(VoidCallback action) {
    if (!mounted) return;
    setState(action);
  }

  @override
  Widget build(BuildContext context) {
    return _buildPage(context);
  }

  String _resolveForumUrl(String source) {
    // ... (保留原有逻辑)
    final raw = source.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('upload://')) {
      return '$riverSideBaseUrl/uploads/short-url/${raw.substring('upload://'.length)}';
    }
    if (raw.startsWith('https://') || raw.startsWith('http://')) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    if (raw.startsWith('/')) return '$riverSideBaseUrl$raw';
    return '$riverSideBaseUrl/$raw';
  }

  String _encodeQingForm(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  int? _parseInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  Map<String, dynamic> _toStringDynamicMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }

  String _pickStringFromMap(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = '${source[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }
}

class _QingComposeUploadImage {
  const _QingComposeUploadImage({
    required this.aid,
    required this.urlName,
    required this.resolvedUrl,
  });

  final String aid;
  final String urlName;
  final String resolvedUrl;
}

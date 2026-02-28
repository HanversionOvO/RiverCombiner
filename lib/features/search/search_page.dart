import 'dart:async';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/mini_apps/river_mini_app_install_store.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_repository.dart';
import 'package:river/core/network/riverside_api_client.dart';
import 'package:river/core/network/riverside_search_models.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:river/features/mini_apps/mini_app_webview_page.dart';
import 'package:river/features/mine/riverside_profile_page.dart';
import 'package:river/features/posts/topic_detail_page.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:skeletonizer/skeletonizer.dart';

part 'search_page_view.dart';
part 'search_page_actions.dart';

ImageProvider<Object>? _miniAppIconProvider(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return NetworkImage(value);
  }
  if (uri != null && uri.scheme == 'file') {
    final file = File.fromUri(uri);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }
  final file = File(value);
  if (file.existsSync()) {
    return FileImage(file);
  }
  return null;
}

const String postsSearchHeroTag = 'posts-search-entry-hero';

enum SearchPageInitialMode { posts, users, miniApps }

enum _SearchMode { posts, users, miniApps }

extension on _SearchMode {
  String get label {
    switch (this) {
      case _SearchMode.posts:
        return '帖子';
      case _SearchMode.users:
        return '用户';
      case _SearchMode.miniApps:
        return '小程序';
    }
  }
}

class SearchPageController {
  _SearchPageState? _state;

  void _attach(_SearchPageState state) {
    _state = state;
  }

  void _detach(_SearchPageState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void onNativeSearchQueryChanged(String query) {
    _state?._applyNativeSearchQuery(query);
  }

  Future<void> onNativeSearchSubmitted(String query) async {
    await _state?._submitNativeSearch(query);
  }

  void onNativeSearchCancelled() {
    _state?._cancelNativeSearch();
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.dependencies,
    this.initialMode = SearchPageInitialMode.posts,
    this.showEntryActionIcon = true,
    this.controller,
  });

  final AppDependencies dependencies;
  final SearchPageInitialMode initialMode;
  final bool showEntryActionIcon;
  final SearchPageController? controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _userSearchLimit = 20;
  static const double _loadMoreTriggerOffset = 260;
  static const double _showBackToTopOffset = 360;

  static const String _labelSearch = '搜索';
  static const String _labelSearchHint = '输入关键词';
  static const String _labelRetry = '重试';
  static const String _labelNoUsers = '未找到相关用户';
  static const String _labelNoPosts = '未找到相关帖子';
  static const String _labelNoMiniApps = '未找到相关小程序';
  static const String _labelNoMiniAppsCatalog = '暂无可用小程序';
  static const String _labelNoMore = '没有更多结果了';
  static const String _labelRecentSearches = '最近搜索';
  static const String _labelNoRecentSearches = '暂无最近搜索';
  static const String _labelClearRecent = '清空最近搜索';
  static const String _labelNeedKeyword = '请输入关键词开始搜索';
  static const String _labelSearchFailed = '搜索失败，请稍后重试';
  static const String _labelClearRecentSuccess = '已清空最近搜索';
  static const String _labelNeedLogin = '请先登录 RiverSide 账号';
  static const String _labelSuggestion = '搜索建议';
  static const String _labelSuggestionPosts = '帖子建议';
  static const String _labelSuggestionUsers = '用户建议';

  final TextEditingController _keywordController = TextEditingController();
  final FocusNode _keywordFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackToTop = ValueNotifier<bool>(false);
  final RiverMiniAppRepository _miniAppRepository = RiverMiniAppRepository();
  final RiverMiniAppInstallStore _miniAppInstallStore =
      RiverMiniAppInstallStore();
  StreamSubscription<int>? _miniAppsChangedSubscription;

  _SearchMode _searchMode = _SearchMode.posts;
  List<RiverSidePostSearchItem> _postItems = const <RiverSidePostSearchItem>[];
  List<RiverSideUserSearchItem> _userItems = const <RiverSideUserSearchItem>[];
  List<RiverMiniAppEntry> _miniAppItems = const <RiverMiniAppEntry>[];
  List<RiverMiniAppEntry> _miniAppCatalog = const <RiverMiniAppEntry>[];
  List<RiverMiniAppEntry> _installedMiniApps = const <RiverMiniAppEntry>[];
  List<String> _recentSearches = const <String>[];
  List<String> _keywordSuggestions = const <String>[];
  List<RiverSidePostSearchItem> _postSuggestions =
      const <RiverSidePostSearchItem>[];
  List<RiverSideUserSearchItem> _userSuggestions =
      const <RiverSideUserSearchItem>[];

  bool _loading = false;
  bool _loadingMorePosts = false;
  bool _hasMorePostPages = false;
  bool _loadingRecentSearches = false;
  bool _clearingRecentSearches = false;
  bool _loadingSuggestions = false;
  bool _loadingMiniAppCatalog = false;
  int _currentPostPage = 0;
  int _requestSerial = 0;
  int _suggestionSerial = 0;
  int _resultAnimationEpoch = 0;
  String _activeQuery = '';
  String? _error;
  String? _lastActiveUsername;
  bool _keywordFocused = false;
  Timer? _suggestionDebounce;
  final Set<String> _installingMiniAppIds = <String>{};

  void _applyNativeSearchQuery(String raw) {
    final query = raw;
    if (_keywordController.text != query) {
      _keywordController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    _onKeywordInputChanged(query);
  }

  Future<void> _submitNativeSearch(String raw) async {
    _applyNativeSearchQuery(raw);
    await _runSearch(reset: true);
  }

  void _cancelNativeSearch() {
    _keywordFocusNode.unfocus();
    _suggestionDebounce?.cancel();
    _clearSuggestionState();
    if (_keywordController.text.trim().isEmpty) {
      _clearKeywordInput();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _searchMode = switch (widget.initialMode) {
      SearchPageInitialMode.posts => _SearchMode.posts,
      SearchPageInitialMode.users => _SearchMode.users,
      SearchPageInitialMode.miniApps => _SearchMode.miniApps,
    };
    _lastActiveUsername =
        widget.dependencies.accountStore.activeRiverSideUsername;
    widget.dependencies.accountStore.addListener(_onAccountStoreChanged);
    _scrollController.addListener(_onScroll);
    _keywordFocusNode.addListener(_onKeywordFocusChanged);
    _miniAppsChangedSubscription = RiverMiniAppInstallStore.installedAppsChanged
        .listen((_) {
          unawaited(_loadInstalledMiniApps());
        });
    unawaited(_loadInstalledMiniApps());
    if (_searchMode == _SearchMode.miniApps) {
      unawaited(_loadMiniAppCatalog(forceRefresh: false));
    }
    _loadRecentSearches();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    widget.dependencies.accountStore.removeListener(_onAccountStoreChanged);
    _miniAppsChangedSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _keywordFocusNode.removeListener(_onKeywordFocusChanged);
    _suggestionDebounce?.cancel();
    _keywordController.dispose();
    _keywordFocusNode.dispose();
    _showBackToTop.dispose();
    super.dispose();
  }

  void _mutateState(VoidCallback action) {
    if (!mounted) {
      return;
    }
    setState(action);
  }

  @override
  Widget build(BuildContext context) {
    return _buildPage(context);
  }
}

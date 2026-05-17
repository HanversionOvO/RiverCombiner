import 'dart:async';

import 'package:flutter/material.dart';
import 'package:river/core/theme/river_design_tokens.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/constants.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/core/widgets/river_snack_bar.dart';
import 'package:river/features/home/home_shell_page.dart';
import 'package:river/features/login/riverside_external_fallback_page.dart';
import 'package:river/features/login/riverside_login_flow_mode.dart';
import 'package:river/features/login/riverside_session_reader.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RiverSideLoginWebViewPage extends StatefulWidget {
  const RiverSideLoginWebViewPage({
    super.key,
    required this.dependencies,
    this.flowMode = RiverSideLoginFlowMode.initialLogin,
  });

  final AppDependencies dependencies;
  final RiverSideLoginFlowMode flowMode;

  @override
  State<RiverSideLoginWebViewPage> createState() =>
      _RiverSideLoginWebViewPageState();
}

class _RiverSideLoginWebViewPageState extends State<RiverSideLoginWebViewPage> {
  static const List<String> _unsupportedBrowserSignals = <String>[
    'unsupported browser detected',
    'uncaught unsupported browser detected',
    'relativecolor is not supported',
  ];

  late final WebViewController _controller;

  bool _isLoading = true;
  bool _completedFlow = false;
  bool _syncingAccount = false;
  bool _openingExternalFallback = false;
  bool _unsupportedFallbackTriggered = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = true;
            });
            unawaited(_updateNavigationState());
          },
          onPageFinished: _onPageFinished,
          onNavigationRequest: (request) {
            unawaited(_updateNavigationState());
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showRiverSnackBar('WebView 加载失败，已切换账号密码登录');
            unawaited(_switchToCredentialLogin());
          },
        ),
      );

    unawaited(_prepareAndLoad());
  }

  Future<void> _prepareAndLoad() async {
    await _configureConsoleMonitoring();
    if (widget.flowMode == RiverSideLoginFlowMode.addAccount) {
      await widget.dependencies.accountStore
          .captureAndPersistActiveRiverSideCookies();
      await widget.dependencies.accountStore.clearWebViewCookies();
    }

    if (!mounted) {
      return;
    }
    await _controller.loadRequest(Uri.parse(riverSideLoginUrl));
  }

  Future<void> _configureConsoleMonitoring() async {
    try {
      await _controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
        final text = message.message.trim();
        if (_matchesUnsupportedBrowserSignal(text)) {
          unawaited(_handleUnsupportedBrowserDetected(details: text));
        }
      });
    } catch (_) {
      // Console callbacks may be unavailable on some platform implementations.
    }
  }

  Future<void> _updateNavigationState() async {
    final canBack = await _controller.canGoBack();
    final canForward = await _controller.canGoForward();
    if (!mounted) {
      return;
    }
    setState(() {
      _canGoBack = canBack;
      _canGoForward = canForward;
    });
  }

  bool _matchesUnsupportedBrowserSignal(String text) {
    final lowered = text.trim().toLowerCase();
    if (lowered.isEmpty) {
      return false;
    }
    for (final signal in _unsupportedBrowserSignals) {
      if (lowered.contains(signal)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleUnsupportedBrowserDetected({String? details}) async {
    if (!mounted ||
        _openingExternalFallback ||
        _completedFlow ||
        _unsupportedFallbackTriggered) {
      return;
    }
    final detailText = details?.trim() ?? '';
    if (detailText.isNotEmpty && !_matchesUnsupportedBrowserSignal(detailText)) {
      return;
    }
    _unsupportedFallbackTriggered = true;
    ScaffoldMessenger.of(context).showRiverSnackBar(
      '检测到当前 WebView 不兼容，已切换为账号密码登录',
    );
    await _switchToCredentialLogin();
  }

  Future<void> _inspectPageForUnsupportedBrowser() async {
    if (_openingExternalFallback ||
        _completedFlow ||
        _unsupportedFallbackTriggered) {
      return;
    }
    try {
      final snapshot = await _controller.runJavaScriptReturningResult('''
(() => {
  const chunks = [
    document.title || '',
    document.body ? document.body.innerText || '' : '',
    document.documentElement ? document.documentElement.textContent || '' : ''
  ];
  return chunks.join('\\n');
})();
''');
      final text = '$snapshot';
      if (_matchesUnsupportedBrowserSignal(text)) {
        await _handleUnsupportedBrowserDetected(details: text);
      }
    } catch (_) {
      // Ignore inspection failures and keep normal WebView login flow.
    }
  }

  Future<void> _switchToCredentialLogin() async {
    if (!mounted || _openingExternalFallback) {
      return;
    }
    _openingExternalFallback = true;
    try {
      final profile = await showRiverSideCredentialLoginSheet(
        context: context,
        dependencies: widget.dependencies,
      );
      if (!mounted || profile == null || _completedFlow) {
        return;
      }

      if (widget.flowMode == RiverSideLoginFlowMode.initialLogin) {
        _completedFlow = true;
        Navigator.of(context).pushAndRemoveUntil(
          riverPageRoute<void>(
            builder: (_) => HomeShellPage(dependencies: widget.dependencies),
          ),
          (_) => false,
        );
        return;
      }

      ScaffoldMessenger.of(context).showRiverSnackBar('账号密码登录成功，已添加账号。');
      Navigator.of(context).pop(profile);
    } finally {
      _openingExternalFallback = false;
    }
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });
    await _updateNavigationState();
    await _inspectPageForUnsupportedBrowser();
    await _checkLoginSuccess(url);
  }

  Future<void> _checkLoginSuccess(String url) async {
    if (_completedFlow || _syncingAccount) {
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final loggedIn = isRiverSideHost(host) && !path.startsWith('/login');
    if (!loggedIn) {
      return;
    }

    _syncingAccount = true;
    UserAccount? profile;
    try {
      profile = await _resolveProfile(path);
      if (profile != null) {
        await widget.dependencies.accountStore.upsertRiverSideAccount(profile);
        await widget.dependencies.accountStore
            .captureAndPersistCurrentRiverSideCookies(profile.username);
        await widget.dependencies.accountStore.switchActiveRiverSideAccount(
          profile.username,
        );
      }
    } finally {
      _syncingAccount = false;
    }

    if (!mounted) {
      return;
    }

    if (widget.flowMode == RiverSideLoginFlowMode.addAccount) {
      if (profile == null) {
        ScaffoldMessenger.of(context).showRiverSnackBar(
          '已检测登录，但未解析到账号信息，请重试。',
        );
        return;
      }
      _completedFlow = true;
      Navigator.of(context).pop(profile);
      return;
    }

    _completedFlow = true;
    Navigator.of(context).pushAndRemoveUntil(
      riverPageRoute<void>(
        builder: (_) => HomeShellPage(dependencies: widget.dependencies),
      ),
      (_) => false,
    );
  }

  Future<UserAccount?> _resolveProfile(String currentPath) async {
    final reader = RiverSideSessionReader(
      _controller,
      widget.dependencies.accountStore.riverSideApiClient,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      final profile = await reader.readCurrentProfile();
      if (profile != null && profile.username.isNotEmpty) {
        return profile;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final username = _extractUsernameFromPath(currentPath);
    if (username == null || username.isEmpty) {
      return null;
    }

    return UserAccount(
      provider: AccountProvider.riverSide,
      username: username,
      displayName: username,
      avatarUrl: '',
    );
  }

  String? _extractUsernameFromPath(String path) {
    final pattern = RegExp(r'^/u/([^/?#]+)', caseSensitive: false);
    final match = pattern.firstMatch(path);
    if (match == null) {
      return null;
    }
    final value = match.group(1);
    if (value == null || value.isEmpty) {
      return null;
    }
    return Uri.decodeComponent(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2.2),
            ),
          if (_isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.90),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '正在打开登录页',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildFloatingIconButton(
                        tooltip: '返回',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      _buildFloatingIconButton(
                        tooltip: '密码登录',
                        icon: Icons.password_rounded,
                        onPressed: _switchToCredentialLogin,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(RiverRadius.full),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.20,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: 0.08,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFloatingIconButton(
                            tooltip: '后退',
                            icon: Icons.arrow_back_rounded,
                            onPressed: _canGoBack
                                ? () async {
                                    await _controller.goBack();
                                    await _updateNavigationState();
                                  }
                                : null,
                          ),
                          _buildFloatingIconButton(
                            tooltip: '前进',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: _canGoForward
                                ? () async {
                                    await _controller.goForward();
                                    await _updateNavigationState();
                                  }
                                : null,
                          ),
                          _buildFloatingIconButton(
                            tooltip: '刷新',
                            icon: Icons.refresh_rounded,
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    await _controller.reload();
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_install_store.dart';
import 'package:river/core/mini_apps/river_mini_app_code_image_codec.dart';
import 'package:river/core/mini_apps/river_mini_app_permission_store.dart';
import 'package:river/core/mini_apps/river_mini_app_platform_client.dart';
import 'package:river/core/mini_apps/river_mini_app_repository.dart';
import 'package:river/core/widgets/river_confirm_dialog.dart';
import 'package:river/features/mini_apps/mini_app_permissions_page.dart';
import 'package:river/features/mine/mine_qr_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class MiniAppWebViewPage extends StatefulWidget {
  const MiniAppWebViewPage({
    super.key,
    required this.dependencies,
    required this.miniApp,
    this.launchRoute = '',
    this.launchParams = const <String, dynamic>{},
    this.launchAction = '',
    this.launchSource = '',
  });

  final AppDependencies dependencies;
  final RiverMiniAppEntry miniApp;
  final String launchRoute;
  final Map<String, dynamic> launchParams;
  final String launchAction;
  final String launchSource;

  @override
  State<MiniAppWebViewPage> createState() => _MiniAppWebViewPageState();
}

class _MiniAppWebViewPageState extends State<MiniAppWebViewPage> {
  late final WebViewController _controller;
  final ImagePicker _imagePicker = ImagePicker();
  String _title = '';
  bool _loading = true;
  bool _canGoBack = false;
  HttpServer? _localMiniAppServer;
  Uri? _localMiniAppEntryUri;
  late final RiverMiniAppPlatformClient _platformClient;
  final RiverMiniAppRepository _miniAppRepository = RiverMiniAppRepository();
  final RiverMiniAppInstallStore _miniAppInstallStore =
      RiverMiniAppInstallStore();
  final RiverMiniAppPermissionStore _permissionStore =
      RiverMiniAppPermissionStore();
  int _bridgeFileTokenSeed = 0;
  final Map<String, _BridgePickedFile> _bridgePickedFiles =
      <String, _BridgePickedFile>{};
  RiverMiniAppPermissionPolicy _permissionPolicy =
      const RiverMiniAppPermissionPolicy(
        states: <RiverMiniAppNativePermission, RiverMiniAppPermissionState>{},
      );
  bool _permissionLoaded = false;
  bool _checkingMiniAppUpdate = false;
  bool _showingUpdateReadySheet = false;

  @override
  void initState() {
    super.initState();
    _title = widget.miniApp.name;
    _platformClient = RiverMiniAppPlatformClient();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = true;
            });
            unawaited(_syncNavigationState());
          },
          onPageFinished: (url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
            });
            unawaited(_injectBridgeBootstrap());
            unawaited(_syncNavigationState());
          },
          onWebResourceError: (error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('小程序加载失败：${error.description}')),
            );
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      );
    unawaited(
      _controller.addJavaScriptChannel(
        'RiverMiniAppBridge',
        onMessageReceived: _onBridgeMessage,
      ),
    );
    unawaited(_loadPermissionPolicy());
    unawaited(_loadInitialUrl());
    unawaited(_scheduleMiniAppUpdateCheck());
  }

  Future<void> _scheduleMiniAppUpdateCheck() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await _checkMiniAppUpdateInBackground();
  }

  Future<void> _loadPermissionPolicy() async {
    final policy = await _permissionStore.loadPolicy(widget.miniApp.id);
    _permissionPolicy = policy;
    _permissionLoaded = true;
  }

  Future<void> _ensurePermissionPolicyLoaded() async {
    if (_permissionLoaded) {
      return;
    }
    await _loadPermissionPolicy();
  }

  Future<void> _loadInitialUrl() async {
    final localPath = widget.miniApp.localEntryFilePath.trim();
    if (localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (await localFile.exists()) {
        final localUri = await _ensureLocalMiniAppEntryUri(localFile);
        await _controller.loadRequest(_appendLaunchQuery(localUri));
        return;
      }
    }

    final uri = Uri.tryParse(widget.miniApp.url);
    if (uri == null) {
      return;
    }
    final headers = <String, String>{
      'X-River-MiniApp-Id': widget.miniApp.id,
      'X-River-MiniApp-Bridge': widget.miniApp.bridgeVersion,
    };
    if (widget.miniApp.requiresAuth) {
      final cookie = _activeCookieHeader();
      if (cookie.isNotEmpty &&
          RiverServerConfig.instance.isForumHost(uri.host.trim())) {
        headers['Cookie'] = cookie;
      }
    }
    await _controller.loadRequest(_appendLaunchQuery(uri), headers: headers);
  }

  Map<String, dynamic> _buildLaunchPayload() {
    final route = widget.launchRoute.trim();
    final action = widget.launchAction.trim();
    final source = widget.launchSource.trim();
    final params = widget.launchParams;
    if (route.isEmpty && action.isEmpty && source.isEmpty && params.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      if (route.isNotEmpty) 'route': route,
      if (action.isNotEmpty) 'action': action,
      if (source.isNotEmpty) 'source': source,
      if (params.isNotEmpty) 'params': params,
    };
  }

  Uri _appendLaunchQuery(Uri uri) {
    final launch = _buildLaunchPayload();
    if (launch.isEmpty) {
      return uri;
    }
    final encoded = base64Url.encode(utf8.encode(jsonEncode(launch)));
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        '_river_launch': encoded,
      },
    );
  }

  Future<Uri> _ensureLocalMiniAppEntryUri(File entryFile) async {
    if (_localMiniAppEntryUri != null && _localMiniAppServer != null) {
      return _localMiniAppEntryUri!;
    }

    final rootDir = entryFile.parent;
    final entryName = entryFile.uri.pathSegments.isNotEmpty
        ? entryFile.uri.pathSegments.last
        : 'index.html';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _localMiniAppServer = server;
    server.listen((request) async {
      try {
        final rawPath = Uri.decodeComponent(request.uri.path);
        final normalizedPath = rawPath == '/' || rawPath.trim().isEmpty
            ? entryName
            : rawPath.replaceFirst(RegExp(r'^/+'), '');
        final segments = normalizedPath
            .split('/')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != '.' && e != '..')
            .toList(growable: false);
        final localPath = segments.isEmpty
            ? entryName
            : segments.join(Platform.pathSeparator);
        final targetPath = '${rootDir.path}${Platform.pathSeparator}$localPath';
        final targetFile = File(targetPath);

        if (!await targetFile.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final bytes = await targetFile.readAsBytes();
        request.response.headers.contentType = _guessContentType(
          targetFile.path,
        );
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.add(bytes);
        await request.response.close();
      } catch (_) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });

    _localMiniAppEntryUri = Uri.parse(
      'http://127.0.0.1:${server.port}/${Uri.encodeComponent(entryName)}',
    );
    return _localMiniAppEntryUri!;
  }

  ContentType _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return ContentType.html;
    }
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (lower.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (lower.endsWith('.json')) {
      return ContentType.json;
    }
    if (lower.endsWith('.svg')) {
      return ContentType('image', 'svg+xml');
    }
    if (lower.endsWith('.png')) {
      return ContentType('image', 'png');
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return ContentType('image', 'jpeg');
    }
    if (lower.endsWith('.webp')) {
      return ContentType('image', 'webp');
    }
    if (lower.endsWith('.ico')) {
      return ContentType('image', 'x-icon');
    }
    if (lower.endsWith('.woff')) {
      return ContentType('font', 'woff');
    }
    if (lower.endsWith('.woff2')) {
      return ContentType('font', 'woff2');
    }
    if (lower.endsWith('.ttf')) {
      return ContentType('font', 'ttf');
    }
    return ContentType.binary;
  }

  String _activeCookieHeader() {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.isEmpty) {
      return '';
    }
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(
          username,
        ) ??
        '';
  }

  Future<void> _syncNavigationState() async {
    try {
      final canGoBack = await _controller.canGoBack();
      if (!mounted || canGoBack == _canGoBack) {
        return;
      }
      setState(() {
        _canGoBack = canGoBack;
      });
    } catch (_) {
      // Ignore navigation probe failures.
    }
  }

  Future<void> _injectBridgeBootstrap() async {
    const script = '''
(() => {
  if (window.__riverMiniAppBridgeBooted) return;
  window.__riverMiniAppBridgeBooted = true;
  window.__riverMiniAppPending = {};
  window.RiverMiniApp = {
    call(action, payload) {
      const id = Date.now().toString() + '_' + Math.random().toString(16).slice(2);
      return new Promise((resolve, reject) => {
        window.__riverMiniAppPending[id] = { resolve, reject };
        RiverMiniAppBridge.postMessage(JSON.stringify({
          id,
          action: String(action || ''),
          payload: payload || {}
        }));
      });
    }
  };
  window.__riverMiniAppOnNativeMessage = function(message) {
    try {
      const data = (typeof message === 'string') ? JSON.parse(message) : message;
      if (!data || !data.id) return;
      const pending = window.__riverMiniAppPending[data.id];
      if (!pending) return;
      delete window.__riverMiniAppPending[data.id];
      if (data.ok) pending.resolve(data.data || null);
      else pending.reject(data.error || 'native_error');
    } catch (_) {}
  };
  window.dispatchEvent(new CustomEvent('river-miniapp-ready'));
})();
''';
    try {
      await _controller.runJavaScript(script);
    } catch (_) {
      // Ignore JS injection failure on some pages.
    }
  }

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    final raw = message.message.trim();
    if (raw.isEmpty) {
      return;
    }
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      payload = <String, dynamic>{};
      for (final entry in decoded.entries) {
        payload['${entry.key}'] = entry.value;
      }
    } catch (_) {
      return;
    }

    final id = (payload['id'] ?? '').toString().trim();
    final action = (payload['action'] ?? '').toString().trim();
    final data = payload['payload'];
    if (id.isEmpty || action.isEmpty) {
      return;
    }

    try {
      final result = await _handleBridgeAction(action, data);
      await _postBridgeResponse(id: id, action: action, ok: true, data: result);
    } catch (error) {
      await _postBridgeResponse(
        id: id,
        action: action,
        ok: false,
        error: '$error',
      );
    }
  }

  Future<dynamic> _handleBridgeAction(String action, dynamic payload) async {
    final lowerAction = action.trim().toLowerCase();
    await _ensureActionPermission(lowerAction);
    switch (lowerAction) {
      case 'getcontext':
      case 'context':
        return _buildContextPayload();
      case 'getauth':
      case 'auth':
        return _buildAuthPayload();
      case 'settitle':
        final nextTitle = _readStringFromPayload(payload, 'title');
        if (nextTitle.isNotEmpty && mounted) {
          setState(() {
            _title = nextTitle;
          });
        }
        return <String, dynamic>{'success': true};
      case 'copytext':
      case 'setclipboarddata':
      case 'setclipboard':
        final text = _readStringFromPayload(payload, 'text');
        if (text.isEmpty) {
          throw Exception('setClipboardData missing text');
        }
        await Clipboard.setData(ClipboardData(text: text));
        return <String, dynamic>{'success': true};
      case 'getclipboarddata':
      case 'getclipboard':
        return _performGetClipboardData();
      case 'showtoast':
      case 'toast':
        return _performShowToast(payload);
      case 'showmodal':
      case 'modal':
        return _performShowModal(payload);
      case 'vibrateshort':
        await HapticFeedback.lightImpact();
        return <String, dynamic>{'success': true};
      case 'vibratelong':
        await HapticFeedback.heavyImpact();
        return <String, dynamic>{'success': true};
      case 'getsysteminfo':
      case 'systeminfo':
        return _performGetSystemInfo();
      case 'chooseimage':
        return _performChooseImage(payload);
      case 'choosefile':
        return _performChooseFile(payload);
      case 'readchosenfile':
      case 'readfile':
        return _performReadChosenFile(payload);
      case 'getlocation':
      case 'location':
        return _performGetLocation(payload);
      case 'scancode':
      case 'scan':
        return _performScanCode(payload);
      case 'setstorage':
        return _performSetStorage(payload);
      case 'getstorage':
        return _performGetStorage(payload);
      case 'removestorage':
        return _performRemoveStorage(payload);
      case 'clearstorage':
        return _performClearStorage();
      case 'getstorageinfo':
        return _performGetStorageInfo();
      case 'makephonecall':
      case 'phonecall':
        return _performMakePhoneCall(payload);
      case 'httprequest':
        return _performBridgeHttpRequest(payload);
      case 'openexternal':
        throw Exception('openExternal is disabled');
      case 'close':
        if (mounted) {
          Navigator.of(context).pop();
        }
        return <String, dynamic>{'success': true};
      case 'platformauth':
      case 'platformauthorize':
        return _performPlatformAuthorization(payload);
      default:
        throw Exception('Unsupported action: $action');
    }
  }

  RiverMiniAppNativePermission? _permissionForAction(String lowerAction) {
    switch (lowerAction) {
      case 'copytext':
      case 'setclipboarddata':
      case 'setclipboard':
      case 'getclipboarddata':
      case 'getclipboard':
        return RiverMiniAppNativePermission.clipboard;
      case 'showtoast':
      case 'toast':
      case 'showmodal':
      case 'modal':
        return RiverMiniAppNativePermission.uiPrompt;
      case 'vibrateshort':
      case 'vibratelong':
        return RiverMiniAppNativePermission.haptics;
      case 'getsysteminfo':
      case 'systeminfo':
        return RiverMiniAppNativePermission.systemInfo;
      case 'chooseimage':
        return RiverMiniAppNativePermission.mediaImage;
      case 'choosefile':
      case 'readchosenfile':
      case 'readfile':
        return RiverMiniAppNativePermission.fileAccess;
      case 'getlocation':
      case 'location':
        return RiverMiniAppNativePermission.location;
      case 'scancode':
      case 'scan':
        return RiverMiniAppNativePermission.scanCode;
      case 'setstorage':
      case 'getstorage':
      case 'removestorage':
      case 'clearstorage':
      case 'getstorageinfo':
        return RiverMiniAppNativePermission.storage;
      case 'makephonecall':
      case 'phonecall':
        return RiverMiniAppNativePermission.phoneCall;
      case 'platformauth':
      case 'platformauthorize':
      case 'getauth':
      case 'auth':
        return RiverMiniAppNativePermission.forumIdentity;
      case 'httprequest':
        return RiverMiniAppNativePermission.network;
      default:
        return null;
    }
  }

  String _actionLabel(String lowerAction) {
    switch (lowerAction) {
      case 'copytext':
      case 'setclipboarddata':
      case 'setclipboard':
        return '写入剪贴板';
      case 'getclipboarddata':
      case 'getclipboard':
        return '读取剪贴板';
      case 'showtoast':
      case 'toast':
        return '显示 Toast';
      case 'showmodal':
      case 'modal':
        return '显示弹窗';
      case 'vibrateshort':
        return '触发短震动';
      case 'vibratelong':
        return '触发长震动';
      case 'getsysteminfo':
      case 'systeminfo':
        return '读取系统信息';
      case 'chooseimage':
        return '选择图片';
      case 'choosefile':
        return '选择文件';
      case 'readchosenfile':
      case 'readfile':
        return '读取文件内容';
      case 'getlocation':
      case 'location':
        return '获取位置';
      case 'scancode':
      case 'scan':
        return '调用扫码';
      case 'setstorage':
      case 'getstorage':
      case 'removestorage':
      case 'clearstorage':
      case 'getstorageinfo':
        return '读写小程序缓存';
      case 'makephonecall':
      case 'phonecall':
        return '拨打电话';
      case 'platformauth':
      case 'platformauthorize':
      case 'getauth':
      case 'auth':
        return '使用论坛身份';
      case 'httprequest':
        return '发起网络请求';
      default:
        return lowerAction;
    }
  }

  Future<void> _ensureActionPermission(String lowerAction) async {
    final permission = _permissionForAction(lowerAction);
    if (permission == null) {
      return;
    }
    await _ensurePermissionPolicyLoaded();
    final granted = await _ensurePermissionGranted(
      permission,
      actionLabel: _actionLabel(lowerAction),
    );
    if (!granted) {
      throw Exception('未授予${permission.title}权限');
    }
  }

  Future<bool> _ensurePermissionGranted(
    RiverMiniAppNativePermission permission, {
    required String actionLabel,
  }) async {
    final state = _permissionPolicy.stateOf(permission);
    if (state != null) {
      return state.granted;
    }
    if (permission == RiverMiniAppNativePermission.network) {
      final updated = await _permissionStore.updatePermission(
        appId: widget.miniApp.id,
        permission: permission,
        granted: true,
        prompted: true,
      );
      _permissionPolicy = updated;
      return true;
    }
    if (!mounted) {
      return false;
    }
    final allowed = await _showPermissionRequestSheet(
      permission: permission,
      actionLabel: actionLabel,
    );
    final updated = await _permissionStore.updatePermission(
      appId: widget.miniApp.id,
      permission: permission,
      granted: allowed,
      prompted: true,
    );
    _permissionPolicy = updated;
    return allowed;
  }

  Future<bool> _showPermissionRequestSheet({
    required RiverMiniAppNativePermission permission,
    required String actionLabel,
  }) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (sheetContext) {
        final sheetTheme = Theme.of(sheetContext);
        final colorScheme = sheetTheme.colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            18 + MediaQuery.of(sheetContext).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      permission.icon,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '权限申请',
                          style: sheetTheme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.miniApp.name,
                          style: sheetTheme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '小程序请求调用「$actionLabel」能力，需要使用 ${permission.title} 权限。',
                style: sheetTheme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 8),
              Text(
                permission.description,
                style: sheetTheme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('拒绝'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('允许'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _openPermissionSettings() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiniAppPermissionsPage(
          miniApp: widget.miniApp,
          permissionStore: _permissionStore,
        ),
      ),
    );
    await _loadPermissionPolicy();
  }

  int _compareVersion(String a, String b) {
    final left = a
        .split(RegExp(r'[^\d]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => int.tryParse(e) ?? 0)
        .toList(growable: false);
    final right = b
        .split(RegExp(r'[^\d]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => int.tryParse(e) ?? 0)
        .toList(growable: false);
    final len = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < len; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) {
        return l.compareTo(r);
      }
    }
    return 0;
  }

  bool _isUpdateAvailable({
    required RiverMiniAppEntry current,
    required RiverMiniAppEntry latest,
  }) {
    if (latest.packageUrl.trim().isEmpty) {
      return false;
    }
    if (current.id != latest.id) {
      return false;
    }
    final latestSubmission = latest.submissionId.trim();
    final currentSubmission = current.submissionId.trim();
    if (latestSubmission.isNotEmpty &&
        currentSubmission.isNotEmpty &&
        latestSubmission != currentSubmission) {
      return true;
    }
    final latestSha = latest.packageSha256.trim().toLowerCase();
    final currentSha = current.packageSha256.trim().toLowerCase();
    if (latestSha.isNotEmpty &&
        currentSha.isNotEmpty &&
        latestSha != currentSha) {
      return true;
    }
    if (latestSha.isNotEmpty && currentSha.isEmpty) {
      return true;
    }
    final latestVersion = latest.version.trim();
    final currentVersion = current.version.trim();
    if (latestVersion.isNotEmpty &&
        currentVersion.isNotEmpty &&
        _compareVersion(latestVersion, currentVersion) > 0) {
      return true;
    }
    if (latestVersion.isNotEmpty && currentVersion.isEmpty) {
      return true;
    }
    if (latest.packageBytes > 0 &&
        current.packageBytes > 0 &&
        latest.packageBytes != current.packageBytes) {
      return true;
    }
    return false;
  }

  Future<void> _checkMiniAppUpdateInBackground() async {
    if (_checkingMiniAppUpdate) {
      return;
    }
    _checkingMiniAppUpdate = true;
    try {
      final manifest = await _miniAppRepository.load(
        manifestUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
        cookieHeader: _activeCookieHeader(),
        forceRefresh: true,
      );
      if (!mounted) {
        return;
      }
      RiverMiniAppEntry? latest;
      for (final item in manifest.entries) {
        if (item.id == widget.miniApp.id) {
          latest = item;
          break;
        }
      }
      if (latest == null) {
        return;
      }
      final latestEntry = latest;
      final installedApps = await _miniAppInstallStore.loadInstalledApps();
      final installedCurrent = installedApps.where(
        (e) => e.id == latestEntry.id,
      );
      final current = installedCurrent.isNotEmpty
          ? installedCurrent.first
          : widget.miniApp;
      if (!_isUpdateAvailable(current: current, latest: latestEntry)) {
        return;
      }
      final installed = await _miniAppInstallStore.install(
        app: latestEntry,
        cookieHeader: _activeCookieHeader(),
      );
      if (!mounted) {
        return;
      }
      await _showMiniAppUpdateReadySheet(installed);
    } catch (_) {
      // Keep silent to avoid interrupting current usage.
    } finally {
      _checkingMiniAppUpdate = false;
    }
  }

  Future<void> _restartWithUpdatedMiniApp(RiverMiniAppEntry updated) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MiniAppWebViewPage(
              dependencies: widget.dependencies,
              miniApp: updated,
              launchRoute: widget.launchRoute,
              launchParams: widget.launchParams,
              launchAction: widget.launchAction,
              launchSource: widget.launchSource,
            ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showMiniAppUpdateReadySheet(RiverMiniAppEntry updated) async {
    if (!mounted || _showingUpdateReadySheet) {
      return;
    }
    _showingUpdateReadySheet = true;
    try {
      final theme = Theme.of(context);
      final shouldRestart = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surface,
        builder: (sheetContext) {
          final sheetTheme = Theme.of(sheetContext);
          final colorScheme = sheetTheme.colorScheme;
          final nextVersion = updated.version.trim().isEmpty
              ? '新版本'
              : 'v${updated.version.trim()}';
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              18 + MediaQuery.of(sheetContext).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '新版本已准备好',
                            style: sheetTheme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$nextVersion · ${updated.name}',
                            style: sheetTheme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '已在后台完成下载与安装，点击“重启小程序”即可切换到最新版本。',
                  style: sheetTheme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('稍后'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('重启小程序'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
      if (shouldRestart == true && mounted) {
        await _restartWithUpdatedMiniApp(updated);
      }
    } finally {
      _showingUpdateReadySheet = false;
    }
  }

  Future<Map<String, dynamic>> _performGetClipboardData() async {
    final data = await Clipboard.getData('text/plain');
    return <String, dynamic>{'success': true, 'text': data?.text ?? ''};
  }

  Future<Map<String, dynamic>> _performShowToast(dynamic payload) async {
    final text = _readStringFromPayload(payload, 'title').isNotEmpty
        ? _readStringFromPayload(payload, 'title')
        : _readStringFromPayload(payload, 'text');
    if (text.isEmpty) {
      throw Exception('showToast missing title');
    }
    final durationMs =
        _readIntFromPayload(payload, 'durationMs') ??
        _readIntFromPayload(payload, 'duration') ??
        1600;
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: Duration(milliseconds: durationMs.clamp(800, 5000).toInt()),
        ),
      );
    }
    return <String, dynamic>{'success': true};
  }

  Future<Map<String, dynamic>> _performShowModal(dynamic payload) async {
    final title = _readStringFromPayload(payload, 'title');
    final content = _readStringFromPayload(payload, 'content');
    final confirmText = _readStringFromPayload(payload, 'confirmText');
    final cancelText = _readStringFromPayload(payload, 'cancelText');
    if (!mounted) {
      return <String, dynamic>{'success': false, 'confirm': false};
    }
    final confirmed = await showRiverConfirmDialog(
      context: context,
      title: title.isEmpty ? '提示' : title,
      message: content.isEmpty ? '是否确认继续？' : content,
      cancelText: cancelText.isEmpty ? '取消' : cancelText,
      confirmText: confirmText.isEmpty ? '确认' : confirmText,
      icon: Icons.task_alt_rounded,
    );
    return <String, dynamic>{
      'success': true,
      'confirm': confirmed,
      'cancel': !confirmed,
    };
  }

  Future<Map<String, dynamic>> _performGetSystemInfo() async {
    final mediaQuery = MediaQuery.of(context);
    final package = await PackageInfo.fromPlatform();
    return <String, dynamic>{
      'success': true,
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'pixelRatio': mediaQuery.devicePixelRatio,
      'screenWidth': mediaQuery.size.width,
      'screenHeight': mediaQuery.size.height,
      'statusBarHeight': mediaQuery.padding.top,
      'safeBottom': mediaQuery.padding.bottom,
      'appName': package.appName,
      'appVersion': package.version,
      'buildNumber': package.buildNumber,
    };
  }

  Future<Map<String, dynamic>> _performChooseImage(dynamic payload) async {
    final sourceText = _readStringFromPayload(payload, 'source').toLowerCase();
    final source = sourceText == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) {
      throw Exception('用户取消选择');
    }
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('所选图片为空');
    }
    final mime = _guessMimeTypeFromPath(picked.path, fallback: 'image/jpeg');
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    return <String, dynamic>{
      'success': true,
      'name': picked.name,
      'size': bytes.length,
      'mimeType': mime,
      'dataUrl': dataUrl,
    };
  }

  Future<Map<String, dynamic>> _performChooseFile(dynamic payload) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) {
      throw Exception('用户取消选择');
    }
    final picked = result.files.single;
    List<int> bytes = picked.bytes ?? <int>[];
    if (bytes.isEmpty &&
        picked.path != null &&
        picked.path!.trim().isNotEmpty) {
      final file = File(picked.path!);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }
    if (bytes.isEmpty) {
      throw Exception('无法读取所选文件');
    }
    final token =
        'file_${DateTime.now().millisecondsSinceEpoch}_${_bridgeFileTokenSeed++}';
    final name = picked.name.trim().isEmpty
        ? 'unnamed.file'
        : picked.name.trim();
    final mime = _guessMimeTypeFromPath(
      name,
      fallback: 'application/octet-stream',
    );
    _bridgePickedFiles[token] = _BridgePickedFile(
      token: token,
      name: name,
      bytes: bytes,
      mimeType: mime,
    );
    return <String, dynamic>{
      'success': true,
      'token': token,
      'name': name,
      'size': bytes.length,
      'mimeType': mime,
    };
  }

  Future<Map<String, dynamic>> _performReadChosenFile(dynamic payload) async {
    final token = _readStringFromPayload(payload, 'token');
    if (token.isEmpty) {
      throw Exception('readChosenFile missing token');
    }
    final maxChars = (_readIntFromPayload(payload, 'maxChars') ?? 800).clamp(
      50,
      5000,
    );
    final picked = _bridgePickedFiles[token];
    if (picked == null) {
      throw Exception('未找到已选择文件');
    }
    final text = utf8.decode(picked.bytes, allowMalformed: true);
    final snippet = text.length > maxChars ? text.substring(0, maxChars) : text;
    return <String, dynamic>{
      'success': true,
      'token': token,
      'name': picked.name,
      'size': picked.bytes.length,
      'mimeType': picked.mimeType,
      'snippet': snippet,
    };
  }

  Future<Map<String, dynamic>> _performGetLocation(dynamic payload) async {
    final fallbackUrl = Uri.parse('https://ipapi.co/json/');
    final client = http.Client();
    try {
      final response = await client
          .get(fallbackUrl, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('定位服务不可用(${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('定位响应格式错误');
      }
      final latitude = _dynamicToDouble(decoded['latitude']);
      final longitude = _dynamicToDouble(decoded['longitude']);
      if (latitude == null || longitude == null) {
        throw Exception('定位响应缺少经纬度');
      }
      return <String, dynamic>{
        'success': true,
        'source': 'ip-fallback',
        'latitude': latitude,
        'longitude': longitude,
        'city': '${decoded['city'] ?? ''}',
        'region': '${decoded['region'] ?? ''}',
        'country': '${decoded['country_name'] ?? ''}',
        'ip': '${decoded['ip'] ?? ''}',
      };
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _performScanCode(dynamic payload) async {
    final source = _readStringFromPayload(payload, 'sourceType').toLowerCase();
    final preferGallery = source == 'gallery';
    if (preferGallery) {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        throw Exception('用户取消选择');
      }
      final scanner = BarcodeScanner();
      try {
        final input = InputImage.fromFilePath(picked.path);
        final barcodes = await scanner.processImage(input);
        var code = '';
        if (barcodes.isNotEmpty) {
          code = _pickBestScannedRawValue(
            barcodes.map((e) => e.rawValue?.trim() ?? ''),
          );
        }
        if (code.isEmpty) {
          final bytes = await File(picked.path).readAsBytes();
          code =
              RiverMiniAppCodeImageCodec.decodeFromImageBytes(bytes)?.trim() ??
              '';
        }
        if (code.isEmpty) {
          throw Exception('未识别到二维码/小程序码');
        }
        return <String, dynamic>{
          'success': true,
          'result': code,
          'scanType': 'unknown',
          'sourceType': 'gallery',
        };
      } finally {
        await scanner.close();
      }
    }

    if (!mounted) {
      throw Exception('页面已关闭，无法扫码');
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => MineQrScanPage(
          dependencies: widget.dependencies,
          rawResultMode: true,
        ),
      ),
    );
    if (code == null || code.trim().isEmpty) {
      throw Exception('用户取消扫码');
    }
    return <String, dynamic>{
      'success': true,
      'result': code.trim(),
      'scanType': 'unknown',
      'sourceType': 'camera',
    };
  }

  String _pickBestScannedRawValue(Iterable<String> candidates) {
    String fallback = '';
    for (final raw in candidates) {
      final value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      fallback = fallback.isEmpty ? value : fallback;
      if (value.startsWith('riverapp://miniapp/open') ||
          value.startsWith('river://miniapp/open') ||
          value.contains('"kind":"river-miniapp-code"') ||
          value.contains('"kind": "river-miniapp-code"')) {
        return value;
      }
    }
    return fallback;
  }

  String _miniAppStoragePrefix() => 'miniapp:${widget.miniApp.id}:';

  String _miniAppStorageKey(String key) => '${_miniAppStoragePrefix()}$key';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  dynamic _normalizeStorageValue(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty &&
          ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
              (trimmed.startsWith('[') && trimmed.endsWith(']')))) {
        try {
          return jsonDecode(trimmed);
        } catch (_) {
          return value;
        }
      }
      return value;
    }
    return value;
  }

  Future<Map<String, dynamic>> _performSetStorage(dynamic payload) async {
    if (payload is! Map) {
      throw Exception('setStorage payload must be an object');
    }
    final key = _readStringFromPayload(payload, 'key');
    if (key.isEmpty) {
      throw Exception('setStorage missing key');
    }
    final rawValue = payload.containsKey('data')
        ? payload['data']
        : payload['value'];
    final value = _normalizeStorageValue(rawValue);
    final encoded = jsonEncode(<String, dynamic>{'data': value});
    final prefs = await _prefs();
    final ok = await prefs.setString(_miniAppStorageKey(key), encoded);
    if (!ok) {
      throw Exception('setStorage failed');
    }
    return <String, dynamic>{'success': true, 'key': key};
  }

  Future<Map<String, dynamic>> _performGetStorage(dynamic payload) async {
    if (payload is! Map) {
      throw Exception('getStorage payload must be an object');
    }
    final key = _readStringFromPayload(payload, 'key');
    if (key.isEmpty) {
      throw Exception('getStorage missing key');
    }
    final prefs = await _prefs();
    final raw = prefs.getString(_miniAppStorageKey(key));
    if (raw == null) {
      throw Exception('storage key not found');
    }
    dynamic data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('data')) {
        data = decoded['data'];
      } else {
        data = decoded;
      }
    } catch (_) {
      data = raw;
    }
    return <String, dynamic>{'success': true, 'key': key, 'data': data};
  }

  Future<Map<String, dynamic>> _performRemoveStorage(dynamic payload) async {
    if (payload is! Map) {
      throw Exception('removeStorage payload must be an object');
    }
    final key = _readStringFromPayload(payload, 'key');
    if (key.isEmpty) {
      throw Exception('removeStorage missing key');
    }
    final prefs = await _prefs();
    final ok = await prefs.remove(_miniAppStorageKey(key));
    return <String, dynamic>{'success': ok, 'key': key};
  }

  Future<Map<String, dynamic>> _performClearStorage() async {
    final prefs = await _prefs();
    final prefix = _miniAppStoragePrefix();
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    var removed = 0;
    for (final key in keys) {
      final ok = await prefs.remove(key);
      if (ok) {
        removed += 1;
      }
    }
    return <String, dynamic>{'success': true, 'removed': removed};
  }

  Future<Map<String, dynamic>> _performGetStorageInfo() async {
    final prefs = await _prefs();
    final prefix = _miniAppStoragePrefix();
    final scopedKeys = prefs.getKeys().where((k) => k.startsWith(prefix));
    final keys = <String>[];
    var currentSize = 0;
    for (final fullKey in scopedKeys) {
      final shortKey = fullKey.substring(prefix.length);
      keys.add(shortKey);
      final value = prefs.getString(fullKey) ?? '';
      currentSize += utf8.encode(value).length;
    }
    return <String, dynamic>{
      'success': true,
      'keys': keys,
      'currentSize': currentSize,
      'limitSize': 5 * 1024 * 1024,
    };
  }

  Future<Map<String, dynamic>> _performMakePhoneCall(dynamic payload) async {
    final phoneNumber = _readStringFromPayload(payload, 'phoneNumber');
    if (phoneNumber.isEmpty) {
      throw Exception('makePhoneCall missing phoneNumber');
    }
    final uri = Uri.parse('tel:$phoneNumber');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw Exception('无法打开拨号界面');
    }
    return <String, dynamic>{'success': true, 'phoneNumber': phoneNumber};
  }

  Future<Map<String, dynamic>> _performPlatformAuthorization(
    dynamic payload,
  ) async {
    final mode = _readStringFromPayload(payload, 'mode').toLowerCase();
    final normalizedMode = mode == 'register' ? 'register' : 'login';
    final scanSessionId = _readStringFromPayload(payload, 'scanSessionId');
    final identity = _resolveAuthIdentity(payload);
    final providerLabel = identity.provider == 'qing' ? '清水河畔' : 'RiverSide';
    final modeLabel = normalizedMode == 'register' ? '注册开发者账号' : '登录开发者账号';

    final confirmed = await _showPlatformAuthConfirmDialog(
      modeLabel: modeLabel,
      providerLabel: providerLabel,
      username: identity.username,
      displayName: identity.displayName,
    );
    if (!confirmed) {
      throw Exception('用户取消授权');
    }

    final result = await _platformClient.authorizeByMiniApp(
      catalogUrl: widget.dependencies.settingsController.miniAppsManifestUrl,
      mode: normalizedMode,
      provider: identity.provider,
      forumUsername: identity.username,
      forumUid: identity.userId,
      displayName: identity.displayName,
      scanSessionId: scanSessionId,
    );

    return <String, dynamic>{
      ...result,
      'success': true,
      'providerLabel': providerLabel,
    };
  }

  _MiniAppAuthIdentity _resolveAuthIdentity(dynamic payload) {
    final requestedProvider = _readStringFromPayload(
      payload,
      'provider',
    ).toLowerCase();
    final store = widget.dependencies.accountStore;
    final river = store.activeRiverSideAccount;
    final qing = store.activeQingShuiHePanAccount;

    if (requestedProvider == 'qing') {
      if (qing == null) {
        throw Exception('当前未登录清水河畔账号');
      }
      return _MiniAppAuthIdentity(
        provider: 'qing',
        userId: qing.userId?.toString() ?? '',
        username: qing.username,
        displayName: qing.displayName.trim().isEmpty
            ? qing.username
            : qing.displayName,
      );
    }
    if (requestedProvider == 'river') {
      if (river == null) {
        throw Exception('当前未登录 RiverSide 账号');
      }
      return _MiniAppAuthIdentity(
        provider: 'river',
        userId: river.userId?.toString() ?? '',
        username: river.username,
        displayName: river.displayName.trim().isEmpty
            ? river.username
            : river.displayName,
      );
    }

    // Default prefer RiverSide, fallback to QingShuiHePan.
    if (river != null) {
      return _MiniAppAuthIdentity(
        provider: 'river',
        userId: river.userId?.toString() ?? '',
        username: river.username,
        displayName: river.displayName.trim().isEmpty
            ? river.username
            : river.displayName,
      );
    }
    if (qing != null) {
      return _MiniAppAuthIdentity(
        provider: 'qing',
        userId: qing.userId?.toString() ?? '',
        username: qing.username,
        displayName: qing.displayName.trim().isEmpty
            ? qing.username
            : qing.displayName,
      );
    }
    throw Exception('请先登录论坛账号后再授权');
  }

  Future<bool> _showPlatformAuthConfirmDialog({
    required String modeLabel,
    required String providerLabel,
    required String username,
    required String displayName,
  }) async {
    if (!mounted) {
      return false;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        final subtitleColor = colorScheme.onSurfaceVariant;

        Widget infoRow({
          required IconData icon,
          required String label,
          required String value,
        }) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: subtitleColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            18 + MediaQuery.of(sheetContext).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '授权请求',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$modeLabel · 开发者平台',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '小程序申请使用当前论坛身份完成平台$modeLabel。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: subtitleColor,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              infoRow(
                icon: Icons.public_rounded,
                label: '论坛',
                value: providerLabel,
              ),
              const SizedBox(height: 8),
              infoRow(
                icon: Icons.badge_outlined,
                label: '昵称',
                value: displayName,
              ),
              const SizedBox(height: 8),
              infoRow(
                icon: Icons.alternate_email_rounded,
                label: '用户名',
                value: username,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('确认授权'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return confirmed == true;
  }

  Future<Map<String, dynamic>> _buildContextPayload() async {
    final brightness = Theme.of(context).brightness;
    final mediaQuery = MediaQuery.of(context);
    final active = widget.dependencies.accountStore.activeRiverSideAccount;
    final package = await PackageInfo.fromPlatform();
    const overlayButtonSize = 42.0;
    const overlayButtonGap = 8.0;
    const overlayHorizontalPadding = 16.0;
    const overlayTopSpacing = 2.0;
    final overlayReservedRight =
        overlayHorizontalPadding + overlayButtonSize * 2 + overlayButtonGap;
    return <String, dynamic>{
      'app': <String, dynamic>{
        'name': package.appName,
        'version': package.version,
        'buildNumber': package.buildNumber,
      },
      'miniApp': <String, dynamic>{
        'id': widget.miniApp.id,
        'name': widget.miniApp.name,
        'bridgeVersion': widget.miniApp.bridgeVersion,
      },
      'launch': _buildLaunchPayload(),
      'theme': <String, dynamic>{
        'brightness': brightness.name,
        'seedColor':
            '#${widget.dependencies.settingsController.themeSeedColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      },
      'account': <String, dynamic>{
        'isGuest': widget.dependencies.accountStore.isGuestBrowsing,
        'username': active?.username ?? '',
        'displayName': active?.displayName ?? '',
      },
      'baseUrl': widget.dependencies.settingsController.riverSideBaseUrl,
      'miniAppCatalogUrl':
          widget.dependencies.settingsController.miniAppsManifestUrl,
      'viewport': <String, dynamic>{
        'statusBarTop': mediaQuery.padding.top,
        'safeBottom': mediaQuery.padding.bottom,
        'overlayButtonSize': overlayButtonSize,
        'overlayButtonGap': overlayButtonGap,
        'overlayTopSpacing': overlayTopSpacing,
        'overlayReservedRight': overlayReservedRight,
      },
    };
  }

  Map<String, dynamic> _buildAuthPayload() {
    final accountStore = widget.dependencies.accountStore;
    final active = accountStore.activeRiverSideAccount;
    final cookieHeader = _activeCookieHeader();
    return <String, dynamic>{
      'isGuest': accountStore.isGuestBrowsing,
      'username': active?.username ?? '',
      'displayName': active?.displayName ?? '',
      'cookieHeader': cookieHeader,
      'forumBaseUrl': widget.dependencies.settingsController.riverSideBaseUrl,
    };
  }

  String _readStringFromPayload(dynamic payload, String key) {
    if (payload is! Map) {
      return '';
    }
    final value = payload[key];
    return (value ?? '').toString().trim();
  }

  int? _readIntFromPayload(dynamic payload, String key) {
    if (payload is! Map) {
      return null;
    }
    final value = payload[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _dynamicToDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String _guessMimeTypeFromPath(
    String path, {
    String fallback = 'application/octet-stream',
  }) {
    final lower = path.toLowerCase().trim();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp';
    }
    if (lower.endsWith('.heic')) {
      return 'image/heic';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain';
    }
    if (lower.endsWith('.json')) {
      return 'application/json';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return fallback;
  }

  Future<Map<String, dynamic>> _performBridgeHttpRequest(
    dynamic payload,
  ) async {
    if (payload is! Map) {
      throw Exception('httpRequest payload must be an object');
    }

    final url = _readStringFromPayload(payload, 'url');
    if (url.isEmpty) {
      throw Exception('httpRequest missing url');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw Exception('httpRequest invalid url');
    }

    final method = _readStringFromPayload(payload, 'method');
    final normalizedMethod = method.isEmpty ? 'GET' : method.toUpperCase();
    const allowedMethods = <String>{'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};
    if (!allowedMethods.contains(normalizedMethod)) {
      throw Exception('httpRequest unsupported method: $normalizedMethod');
    }

    final timeoutMsRaw = payload['timeoutMs'];
    final timeoutMs = timeoutMsRaw is num ? timeoutMsRaw.toInt() : 15000;
    final timeout = Duration(milliseconds: timeoutMs.clamp(2000, 60000));

    final headers = <String, String>{};
    final rawHeaders = payload['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty) {
          continue;
        }
        headers[key] = '${entry.value ?? ''}';
      }
    }

    final hasCookieHeader = headers.keys.any(
      (k) => k.toLowerCase() == HttpHeaders.cookieHeader,
    );
    if (!hasCookieHeader &&
        RiverServerConfig.instance.isForumHost(uri.host.trim())) {
      final cookie = _activeCookieHeader();
      if (cookie.isNotEmpty) {
        headers[HttpHeaders.cookieHeader] = cookie;
      }
    }

    String? body;
    final rawForm = payload['form'];
    if (rawForm is Map) {
      final formMap = <String, String>{};
      for (final entry in rawForm.entries) {
        final key = '${entry.key}'.trim();
        if (key.isEmpty) {
          continue;
        }
        formMap[key] = '${entry.value ?? ''}';
      }
      body = Uri(queryParameters: formMap).query;
      if (!headers.keys.any(
        (k) => k.toLowerCase() == HttpHeaders.contentTypeHeader,
      )) {
        headers[HttpHeaders.contentTypeHeader] =
            'application/x-www-form-urlencoded';
      }
    } else if (payload.containsKey('body')) {
      final rawBody = payload['body'];
      if (rawBody is String) {
        body = rawBody;
      } else if (rawBody != null) {
        body = jsonEncode(rawBody);
        if (!headers.keys.any(
          (k) => k.toLowerCase() == HttpHeaders.contentTypeHeader,
        )) {
          headers[HttpHeaders.contentTypeHeader] = 'application/json';
        }
      }
    }

    final request = http.Request(normalizedMethod, uri);
    request.headers.addAll(headers);
    if (body != null) {
      request.body = body;
    }

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      dynamic jsonData;
      final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
      if (contentType.toLowerCase().contains('application/json')) {
        try {
          jsonData = jsonDecode(response.body);
        } catch (_) {
          jsonData = null;
        }
      }
      return <String, dynamic>{
        'status': response.statusCode,
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'headers': response.headers,
        'body': response.body,
        'json': jsonData,
      };
    } finally {
      client.close();
    }
  }

  Future<void> _postBridgeResponse({
    required String id,
    required String action,
    required bool ok,
    dynamic data,
    String error = '',
  }) async {
    final response = <String, dynamic>{
      'id': id,
      'action': action,
      'ok': ok,
      if (ok) 'data': data,
      if (!ok) 'error': error,
    };
    final raw = jsonEncode(response);
    final js =
        'window.__riverMiniAppOnNativeMessage && '
        'window.__riverMiniAppOnNativeMessage(JSON.parse(${jsonEncode(raw)}));';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {
      // Ignore response delivery failure.
    }
  }

  Future<void> _refresh() async {
    await _controller.reload();
  }

  Future<void> _handleSystemBack() async {
    try {
      final result = await _controller.runJavaScriptReturningResult('''
(function () {
  try {
    if (typeof window.__riverMiniAppAppBackHandler === 'function') {
      const r = window.__riverMiniAppAppBackHandler();
      if (r === 'close') return 'close';
      if (r === true || r === 'handled') return 'handled';
    }
    if (window.history && window.history.length > 1) {
      window.history.back();
      return 'handled';
    }
    return 'pass';
  } catch (_) {
    return 'pass';
  }
})();
''');
      final normalized = '$result'.toLowerCase().replaceAll('"', '').trim();
      if (normalized == 'close') {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      if (normalized == 'handled') {
        await _syncNavigationState();
        return;
      }
    } catch (_) {
      // Ignore JS back probe failures.
    }

    final canGoBack = await _controller.canGoBack();
    if (canGoBack) {
      await _controller.goBack();
      await _syncNavigationState();
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showMoreSheet() async {
    final theme = Theme.of(context);
    final iconProvider = _miniAppIconProvider(widget.miniApp.iconUrl);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      image: iconProvider == null
                          ? null
                          : DecorationImage(
                              image: iconProvider,
                              fit: BoxFit.cover,
                            ),
                    ),
                    alignment: Alignment.center,
                    child: iconProvider == null
                        ? Icon(
                            Icons.widgets_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title.trim().isNotEmpty
                              ? _title.trim()
                              : widget.miniApp.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.miniApp.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.miniApp.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.miniApp.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.miniApp.tags
                      .take(6)
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MiniAppSheetAction(
                    icon: Icons.admin_panel_settings_outlined,
                    label: '权限设置',
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _openPermissionSettings();
                    },
                  ),
                  _MiniAppSheetAction(
                    icon: Icons.refresh_rounded,
                    label: '刷新小程序',
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _refresh();
                    },
                  ),
                  _MiniAppSheetAction(
                    icon: Icons.home_work_outlined,
                    label: '回到首页',
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _loadInitialUrl();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingWindowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: 0.52),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.24,
                    ),
                  ),
                ),
                child: Icon(icon, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_localMiniAppServer?.close(force: true));
    _bridgePickedFiles.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _handleSystemBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.985, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: _loading
                  ? _MiniAppLoadingOverlay(
                      key: const ValueKey('mini_app_loading'),
                      miniApp: widget.miniApp,
                    )
                  : const SizedBox.shrink(key: ValueKey('mini_app_loaded')),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.topRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFloatingWindowButton(
                      icon: Icons.close_rounded,
                      tooltip: '关闭小程序',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    _buildFloatingWindowButton(
                      icon: Icons.more_horiz_rounded,
                      tooltip: '更多',
                      onTap: () {
                        unawaited(_showMoreSheet());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppLoadingOverlay extends StatelessWidget {
  const _MiniAppLoadingOverlay({super.key, required this.miniApp});

  final RiverMiniAppEntry miniApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = miniApp.iconUrl.trim();
    final iconProvider = _miniAppIconProvider(iconUrl);

    return SizedBox.expand(
      child: Container(
        color: theme.colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      ),
                    ),
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                        image: iconProvider == null
                            ? null
                            : DecorationImage(
                                image: iconProvider,
                                fit: BoxFit.cover,
                              ),
                      ),
                      alignment: Alignment.center,
                      child: iconProvider == null
                          ? Icon(
                              Icons.widgets_rounded,
                              color: theme.colorScheme.primary,
                              size: 30,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                miniApp.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAppSheetAction extends StatelessWidget {
  const _MiniAppSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          unawaited(onTap());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAppAuthIdentity {
  const _MiniAppAuthIdentity({
    required this.provider,
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String provider;
  final String userId;
  final String username;
  final String displayName;
}

class _BridgePickedFile {
  const _BridgePickedFile({
    required this.token,
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String token;
  final String name;
  final List<int> bytes;
  final String mimeType;
}

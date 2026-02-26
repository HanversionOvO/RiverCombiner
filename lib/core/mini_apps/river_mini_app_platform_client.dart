import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:river/core/config/server_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiverMiniAppSubmissionStatusItem {
  const RiverMiniAppSubmissionStatusItem({
    required this.id,
    required this.projectId,
    required this.versionName,
    required this.status,
    required this.reviewComment,
    required this.updatedAtRaw,
  });

  final String id;
  final String projectId;
  final String versionName;
  final String status;
  final String reviewComment;
  final String updatedAtRaw;

  DateTime? get updatedAt {
    if (updatedAtRaw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(updatedAtRaw.trim());
  }
}

class RiverMiniAppPlatformClient {
  RiverMiniAppPlatformClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const String _accessTokenKey = 'miniapp.platform.access_token';
  static const String _usernameKey = 'miniapp.platform.username';

  final http.Client _httpClient;
  SharedPreferences? _prefs;

  Future<String?> loadAccessToken() async {
    _prefs ??= await SharedPreferences.getInstance();
    final token = _prefs?.getString(_accessTokenKey)?.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  Future<String?> loadUsername() async {
    _prefs ??= await SharedPreferences.getInstance();
    final username = _prefs?.getString(_usernameKey)?.trim() ?? '';
    return username.isEmpty ? null : username;
  }

  Future<void> clearAuth() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_accessTokenKey);
    await _prefs?.remove(_usernameKey);
  }

  Future<void> login({
    required String catalogUrl,
    required String username,
    required String password,
  }) async {
    final resolvedUsername = username.trim();
    final resolvedPassword = password.trim();
    if (resolvedUsername.isEmpty || resolvedPassword.isEmpty) {
      throw Exception('用户名或密码不能为空');
    }
    final baseUrl = resolvePlatformBaseUrl(catalogUrl);
    final uri = Uri.parse('$baseUrl/api/auth/login');
    final response = await _httpClient
        .post(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'account': resolvedUsername,
            'password': resolvedPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('登录失败(HTTP ${response.statusCode})');
    }
    final root = _parseApiEnvelope(response.body);
    final data = _toMap(root['data']);
    final token = '${data['accessToken'] ?? data['token'] ?? ''}'.trim();
    if (token.isEmpty) {
      throw Exception('登录响应缺少 accessToken');
    }
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_accessTokenKey, token);
    await _prefs?.setString(_usernameKey, resolvedUsername);
  }

  Future<Map<String, dynamic>> authorizeByMiniApp({
    required String catalogUrl,
    required String mode,
    required String provider,
    required String forumUsername,
    String forumUid = '',
    String displayName = '',
    String scanSessionId = '',
  }) async {
    final normalizedMode = mode.trim().toLowerCase();
    if (normalizedMode != 'login' && normalizedMode != 'register') {
      throw Exception('授权模式无效');
    }
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider != 'river' && normalizedProvider != 'qing') {
      throw Exception('授权平台无效');
    }
    final user = forumUsername.trim();
    if (user.isEmpty) {
      throw Exception('缺少论坛用户名');
    }
    final baseUrl = resolvePlatformBaseUrl(catalogUrl);
    final payload = jsonEncode(<String, String>{
      'mode': normalizedMode,
      'provider': normalizedProvider,
      'forumUid': forumUid.trim(),
      'forumUsername': user,
      'displayName': displayName.trim(),
      'scanSessionId': scanSessionId.trim(),
    });

    Future<http.Response> postTo(Uri uri) {
      return _httpClient
          .post(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 15));
    }

    final primaryUri = Uri.parse('$baseUrl/api/auth/miniapp/authorize');
    var response = await postTo(primaryUri);

    // Some deployments mount backend behind path proxies.
    if ((response.statusCode == 403 || response.statusCode == 404) &&
        baseUrl.endsWith('/api')) {
      final fallbackUri = Uri.parse('$baseUrl/auth/miniapp/authorize');
      response = await postTo(fallbackUri);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyPreview = response.body.length > 260
          ? '${response.body.substring(0, 260)}...'
          : response.body;
      throw Exception(
        '授权失败(HTTP ${response.statusCode}) '
        'url=${response.request?.url ?? primaryUri} body=$bodyPreview',
      );
    }

    final root = _parseApiEnvelope(response.body);
    final data = _toMap(root['data']);
    final token = '${data['accessToken'] ?? data['token'] ?? ''}'.trim();
    if (token.isEmpty) {
      throw Exception('授权响应缺少 accessToken');
    }
    final platformUsername = '${data['username'] ?? ''}'.trim();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_accessTokenKey, token);
    if (platformUsername.isNotEmpty) {
      await _prefs?.setString(_usernameKey, platformUsername);
    }
    return <String, dynamic>{
      'token': token,
      'username': platformUsername,
      'userId': '${data['userId'] ?? ''}',
      'roles': data['roles'],
      'mode': normalizedMode,
      'provider': normalizedProvider,
      'passwordLoginEnabled': data['passwordLoginEnabled'] == true,
    };
  }

  Future<List<RiverMiniAppSubmissionStatusItem>> fetchMySubmissions({
    required String catalogUrl,
  }) async {
    final token = await loadAccessToken();
    if (token == null || token.trim().isEmpty) {
      return const <RiverMiniAppSubmissionStatusItem>[];
    }
    final baseUrl = resolvePlatformBaseUrl(catalogUrl);
    final uri = Uri.parse('$baseUrl/api/dev/submissions');
    final response = await _httpClient
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearAuth();
      throw Exception('登录状态已失效，请重新登录平台');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取审核状态失败(HTTP ${response.statusCode})');
    }
    final root = _parseApiEnvelope(response.body);
    final data = root['data'];
    if (data is! List) {
      return const <RiverMiniAppSubmissionStatusItem>[];
    }
    final result = <RiverMiniAppSubmissionStatusItem>[];
    for (final item in data) {
      final map = _toMap(item);
      if (map.isEmpty) {
        continue;
      }
      final id = '${map['id'] ?? ''}'.trim();
      final projectId = '${map['projectId'] ?? ''}'.trim();
      if (id.isEmpty || projectId.isEmpty) {
        continue;
      }
      result.add(
        RiverMiniAppSubmissionStatusItem(
          id: id,
          projectId: projectId,
          versionName: '${map['versionName'] ?? ''}'.trim(),
          status: '${map['status'] ?? ''}'.trim().toUpperCase(),
          reviewComment: '${map['reviewComment'] ?? ''}'.trim(),
          updatedAtRaw:
              '${map['reviewedAt'] ?? map['updatedAt'] ?? map['createdAt'] ?? ''}'
                  .trim(),
        ),
      );
    }
    return result;
  }

  bool supportsPlatformCatalog(String catalogUrl) {
    try {
      final normalized = RiverServerConfig.normalizeUrl(catalogUrl);
      final path = Uri.parse(normalized).path.toLowerCase();
      return path.contains('/api/public/catalog');
    } catch (_) {
      return false;
    }
  }

  String resolvePlatformBaseUrl(String catalogUrl) {
    final normalized = RiverServerConfig.normalizeUrl(catalogUrl);
    final uri = Uri.parse(normalized);
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    var cutIndex = -1;
    for (var i = 0; i <= segments.length - 3; i++) {
      final a = segments[i].toLowerCase();
      final b = segments[i + 1].toLowerCase();
      final c = segments[i + 2].toLowerCase();
      if (a == 'api' && b == 'public' && c == 'catalog') {
        cutIndex = i;
        break;
      }
    }
    if (cutIndex < 0) {
      throw Exception('当前小程序目录链接不是平台 catalog 接口');
    }
    final basePath = segments.take(cutIndex).join('/');
    final rebuilt = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: basePath.isEmpty ? '' : '/$basePath',
    );
    return RiverServerConfig.normalizeUrl(rebuilt.toString());
  }

  Map<String, dynamic> _parseApiEnvelope(String rawBody) {
    final decoded = jsonDecode(rawBody);
    final root = _toMap(decoded);
    final ok = root['success'];
    if (ok is bool && !ok) {
      final message = '${root['message'] ?? '请求失败'}'.trim();
      throw Exception(message.isEmpty ? '请求失败' : message);
    }
    return root;
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      final result = <String, dynamic>{};
      for (final entry in raw.entries) {
        result['${entry.key}'] = entry.value;
      }
      return result;
    }
    return const <String, dynamic>{};
  }
}

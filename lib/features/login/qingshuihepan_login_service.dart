import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:river/core/account/account_models.dart';
import 'package:river/core/config/server_config.dart';

class QingShuiHePanLoginService {
  const QingShuiHePanLoginService();

  static const String _forumKey = '_CBQJazn9Wws8Ivhr6U_';
  static const String _sdkVersion = '2.4.2';
  static const String _authKey = 'appbyme_key';

  Future<QingShuiHePanLoginResult> login({
    required String username,
    required String password,
  }) async {
    final loginName = username.trim();
    final pwd = password;
    if (loginName.isEmpty || pwd.isEmpty) {
      throw const QingShuiHePanLoginException('请输入账号和密码');
    }

    final payload = await _requestLoginPayload(loginName: loginName, pwd: pwd);
    final rs = '${payload['rs']}';
    if (rs != '1') {
      throw QingShuiHePanLoginException(_extractErrorMessage(payload));
    }

    final token = _pickString(payload, 'token');
    final secret = _pickString(payload, 'secret');
    if (token.isEmpty || secret.isEmpty) {
      throw const QingShuiHePanLoginException('登录成功但未返回认证信息');
    }

    final uid = _pickInt(payload, 'uid');
    final userName = _pickString(payload, 'userName');
    final avatar = _pickString(payload, 'avatar');
    final displayName = userName.isEmpty ? loginName : userName;
    final cookieHeader = await _tryReadWebCookie(
      loginName: loginName,
      pwd: pwd,
    );

    final account = UserAccount(
      provider: AccountProvider.qingShuiHePan,
      userId: uid,
      username: displayName,
      displayName: displayName,
      avatarUrl: avatar,
    );

    final auth = QingShuiHePanAuth(
      username: displayName,
      token: token,
      secret: secret,
      userId: uid,
      displayName: displayName,
      avatarUrl: avatar,
      cookieHeader: cookieHeader,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    return QingShuiHePanLoginResult(
      account: account,
      auth: auth,
      rawPayload: payload,
    );
  }

  Future<Map<String, dynamic>> _requestLoginPayload({
    required String loginName,
    required String pwd,
  }) async {
    final siteBaseUrl = RiverServerConfig.instance.qingShuiHePanBaseUrl;
    final loginApiUrl = '$siteBaseUrl/mobcent/app/web/index.php';
    final body = <String, String>{
      'r': 'user/login',
      'type': 'login',
      'username': loginName,
      'password': pwd,
      'sdkVersion': _sdkVersion,
      'forumKey': _forumKey,
      'platType': '1',
      'apphash': _buildAppHash(),
    };

    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse(loginApiUrl),
        headers: const <String, String>{
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: _serialize(body),
      );
    } catch (_) {
      throw const QingShuiHePanLoginException('网络异常，请稍后重试');
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(utf8.decode(response.bodyBytes));
      if (raw is! Map) {
        throw const FormatException();
      }
      decoded = raw.map((key, value) => MapEntry('$key', value));
    } catch (_) {
      throw QingShuiHePanLoginException(
        '登录接口返回异常（HTTP ${response.statusCode}）',
      );
    }
    return decoded;
  }

  Future<String> _tryReadWebCookie({
    required String loginName,
    required String pwd,
  }) async {
    final siteBaseUrl = RiverServerConfig.instance.qingShuiHePanBaseUrl;
    final webLoginUrl =
        '$siteBaseUrl/member.php?mod=logging&action=login&loginsubmit=yes';
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(webLoginUrl))
        ..followRedirects = false
        ..headers.addAll(const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Accept': '*/*',
        })
        ..body = _serialize(<String, String>{
          'username': loginName,
          'password': pwd,
        });
      final response = await client.send(request);
      return (response.headers['set-cookie'] ?? '').trim();
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  String _extractErrorMessage(Map<String, dynamic> payload) {
    final errCode = (payload['errcode'] ?? '').toString().trim();
    if (errCode.isNotEmpty) {
      return errCode;
    }
    final head = _asMap(payload['head']);
    final headMessage = (head['errInfo'] ?? '').toString().trim();
    if (headMessage.isNotEmpty) {
      return headMessage;
    }
    return '登录失败，请检查账号密码';
  }

  String _pickString(Map<String, dynamic> payload, String key) {
    final root = payload[key];
    if (root != null && '$root'.trim().isNotEmpty) {
      return '$root'.trim();
    }
    final body = _asMap(payload['body']);
    final bodyValue = body[key];
    if (bodyValue != null && '$bodyValue'.trim().isNotEmpty) {
      return '$bodyValue'.trim();
    }
    return '';
  }

  int? _pickInt(Map<String, dynamic> payload, String key) {
    final source = _pickString(payload, key);
    return int.tryParse(source);
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, dynamic>{};
    }
    return raw.map((key, value) => MapEntry('$key', value));
  }

  String _serialize(Map<String, String> data) {
    return data.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  String _buildAppHash() {
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    final secondsPrefix = millis.substring(0, 5);
    final source = '$secondsPrefix$_authKey';
    final bytes = md5.convert(utf8.encode(source)).bytes;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (hex.length < 16) {
      return hex;
    }
    return hex.substring(8, 16);
  }
}

class QingShuiHePanLoginResult {
  const QingShuiHePanLoginResult({
    required this.account,
    required this.auth,
    required this.rawPayload,
  });

  final UserAccount account;
  final QingShuiHePanAuth auth;
  final Map<String, dynamic> rawPayload;
}

class QingShuiHePanLoginException implements Exception {
  const QingShuiHePanLoginException(this.message);

  final String message;
}

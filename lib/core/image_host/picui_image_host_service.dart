import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _asMap(dynamic raw) => PicUiImageHostService._asMap(raw);

String _asString(dynamic raw) => PicUiImageHostService._asString(raw);

int? _asInt(dynamic raw) => PicUiImageHostService._asInt(raw);

double _asDouble(dynamic raw) => PicUiImageHostService._asDouble(raw);

class PicUiImageHostException implements Exception {
  const PicUiImageHostException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PicUiUploadOptions {
  const PicUiUploadOptions({
    this.tempToken = '',
    this.permission,
    this.strategyId,
    this.albumId,
    this.expiredAt = '',
  });

  final String tempToken;
  final int? permission;
  final int? strategyId;
  final int? albumId;
  final String expiredAt;
}

class PicUiProfile {
  const PicUiProfile({
    required this.username,
    required this.name,
    required this.avatar,
    required this.email,
    required this.capacity,
    required this.size,
    required this.url,
    required this.imageNum,
    required this.albumNum,
  });

  final String username;
  final String name;
  final String avatar;
  final String email;
  final double capacity;
  final double size;
  final String url;
  final int imageNum;
  final int albumNum;

  factory PicUiProfile.fromJson(Map<String, dynamic> json) {
    return PicUiProfile(
      username: _asString(json['username']),
      name: _asString(json['name']),
      avatar: _asString(json['avatar']),
      email: _asString(json['email']),
      capacity: _asDouble(json['capacity']),
      size: _asDouble(json['size']),
      url: _asString(json['url']),
      imageNum: _asInt(json['image_num']) ?? 0,
      albumNum: _asInt(json['album_num']) ?? 0,
    );
  }
}

class PicUiStrategy {
  const PicUiStrategy({required this.id, required this.name});

  final int id;
  final String name;

  factory PicUiStrategy.fromJson(Map<String, dynamic> json) {
    return PicUiStrategy(
      id: _asInt(json['id']) ?? 0,
      name: _asString(json['name']),
    );
  }
}

class PicUiTemporaryToken {
  const PicUiTemporaryToken({required this.token, required this.expiredAt});

  final String token;
  final String expiredAt;

  factory PicUiTemporaryToken.fromJson(Map<String, dynamic> json) {
    return PicUiTemporaryToken(
      token: _asString(json['token']),
      expiredAt: _asString(json['expired_at']),
    );
  }
}

class PicUiImageLinks {
  const PicUiImageLinks({
    required this.url,
    required this.html,
    required this.bbcode,
    required this.markdown,
    required this.markdownWithLink,
    required this.thumbnailUrl,
    required this.deleteUrl,
  });

  final String url;
  final String html;
  final String bbcode;
  final String markdown;
  final String markdownWithLink;
  final String thumbnailUrl;
  final String deleteUrl;

  factory PicUiImageLinks.fromJson(Map<String, dynamic> json) {
    return PicUiImageLinks(
      url: _asString(json['url']),
      html: _asString(json['html']),
      bbcode: _asString(json['bbcode']),
      markdown: _asString(json['markdown']),
      markdownWithLink: _asString(json['markdown_with_link']),
      thumbnailUrl: _asString(json['thumbnail_url']),
      deleteUrl: _asString(json['delete_url']),
    );
  }
}

class PicUiImageItem {
  const PicUiImageItem({
    required this.key,
    required this.name,
    required this.originName,
    required this.pathname,
    required this.size,
    required this.width,
    required this.height,
    required this.md5,
    required this.sha1,
    required this.humanDate,
    required this.date,
    required this.links,
  });

  final String key;
  final String name;
  final String originName;
  final String pathname;
  final double size;
  final int width;
  final int height;
  final String md5;
  final String sha1;
  final String humanDate;
  final String date;
  final PicUiImageLinks links;

  factory PicUiImageItem.fromJson(Map<String, dynamic> json) {
    return PicUiImageItem(
      key: _asString(json['key']),
      name: _asString(json['name']),
      originName: _asString(json['origin_name']),
      pathname: _asString(json['pathname']),
      size: _asDouble(json['size']),
      width: _asInt(json['width']) ?? 0,
      height: _asInt(json['height']) ?? 0,
      md5: _asString(json['md5']),
      sha1: _asString(json['sha1']),
      humanDate: _asString(json['human_date']),
      date: _asString(json['date']),
      links: PicUiImageLinks.fromJson(_asMap(json['links'])),
    );
  }
}

class PicUiImagePage {
  const PicUiImagePage({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.items,
  });

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final List<PicUiImageItem> items;
}

class PicUiAlbumItem {
  const PicUiAlbumItem({
    required this.id,
    required this.name,
    required this.intro,
    required this.imageNum,
  });

  final int id;
  final String name;
  final String intro;
  final int imageNum;

  factory PicUiAlbumItem.fromJson(Map<String, dynamic> json) {
    return PicUiAlbumItem(
      id: _asInt(json['id']) ?? 0,
      name: _asString(json['name']),
      intro: _asString(json['intro']),
      imageNum: _asInt(json['image_num']) ?? 0,
    );
  }
}

class PicUiAlbumPage {
  const PicUiAlbumPage({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.items,
  });

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final List<PicUiAlbumItem> items;
}

class PicUiUploadHistoryRecord {
  const PicUiUploadHistoryRecord({
    required this.id,
    required this.key,
    required this.url,
    required this.thumbnailUrl,
    required this.deleteUrl,
    required this.createdAtMs,
    this.markdown = '',
  });

  final String id;
  final String key;
  final String url;
  final String thumbnailUrl;
  final String deleteUrl;
  final int createdAtMs;
  final String markdown;

  factory PicUiUploadHistoryRecord.fromJson(Map<String, dynamic> json) {
    return PicUiUploadHistoryRecord(
      id: _asString(json['id']),
      key: _asString(json['key']),
      url: _asString(json['url']),
      thumbnailUrl: _asString(json['thumbnailUrl']),
      deleteUrl: _asString(json['deleteUrl']),
      createdAtMs: _asInt(json['createdAtMs']) ?? 0,
      markdown: _asString(json['markdown']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'key': key,
      'url': url,
      'thumbnailUrl': thumbnailUrl,
      'deleteUrl': deleteUrl,
      'createdAtMs': createdAtMs,
      'markdown': markdown,
    };
  }
}

class PicUiImageHostService {
  PicUiImageHostService({
    String apiBaseUrl = 'https://picui.cn',
    http.Client? httpClient,
  }) : _apiBaseUrl = _normalizeBaseUrl(apiBaseUrl),
       _httpClient = httpClient;

  static const String _historyKey = 'app.picui_upload_history';
  static const int _maxHistoryCount = 120;

  final String _apiBaseUrl;
  final http.Client? _httpClient;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_apiBaseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/v1$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<PicUiProfile> fetchProfile({required String apiToken}) async {
    final payload = await _requestJson(
      method: 'GET',
      uri: _uri('/profile'),
      apiToken: apiToken,
    );
    final data = _asMap(payload['data']);
    return PicUiProfile.fromJson(data);
  }

  Future<void> verifyToken(String apiToken) async {
    await fetchProfile(apiToken: apiToken);
  }

  Future<List<PicUiStrategy>> fetchStrategies({
    String apiToken = '',
    String query = '',
  }) async {
    final payload = await _requestJson(
      method: 'GET',
      uri: _uri('/strategies', <String, String>{
        if (query.trim().isNotEmpty) 'q': query.trim(),
      }),
      apiToken: apiToken,
    );
    final data = _asMap(payload['data']);
    final list = _asList(data['strategies']);
    return list.map((e) => PicUiStrategy.fromJson(_asMap(e))).toList();
  }

  Future<List<PicUiTemporaryToken>> generateTemporaryTokens({
    required String apiToken,
    required int num,
    required int seconds,
  }) async {
    final normalizedNum = num.clamp(1, 100);
    final normalizedSeconds = seconds.clamp(1, 2626560);
    final payload = await _requestJson(
      method: 'POST',
      uri: _uri('/images/tokens'),
      apiToken: apiToken,
      contentType: 'application/json',
      body: jsonEncode(<String, dynamic>{
        'num': normalizedNum,
        'seconds': normalizedSeconds,
      }),
    );
    final data = _asMap(payload['data']);
    final list = _asList(data['tokens']);
    return list.map((e) => PicUiTemporaryToken.fromJson(_asMap(e))).toList();
  }

  Future<PicUiImageItem> uploadBytes({
    required String fileName,
    required List<int> bytes,
    String apiToken = '',
    PicUiUploadOptions options = const PicUiUploadOptions(),
  }) async {
    if (bytes.isEmpty) {
      throw const PicUiImageHostException('上传文件为空');
    }
    final mediaType = _guessImageMediaType(fileName);
    final normalizedFileName = _normalizeUploadFileName(fileName, mediaType);
    final request = http.MultipartRequest('POST', _uri('/upload'))
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'multipart/form-data'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: normalizedFileName,
          contentType: mediaType,
        ),
      );
    final token = apiToken.trim();
    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final tempToken = options.tempToken.trim();
    if (tempToken.isNotEmpty) {
      request.fields['token'] = tempToken;
    }
    final permission = options.permission;
    if (permission == 0 || permission == 1) {
      request.fields['permission'] = '$permission';
    }
    final strategyId = options.strategyId;
    if (strategyId != null && strategyId > 0) {
      request.fields['strategy_id'] = '$strategyId';
    }
    final albumId = options.albumId;
    if (albumId != null && albumId > 0) {
      request.fields['album_id'] = '$albumId';
    }
    final expiredAt = options.expiredAt.trim();
    if (expiredAt.isNotEmpty) {
      request.fields['expired_at'] = expiredAt;
    }
    final response = await _sendMultipart(request);
    final payload = _decodeResponseMap(response.bodyBytes);
    _ensureSuccess(payload, response.statusCode);
    final item = PicUiImageItem.fromJson(_asMap(payload['data']));
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await appendUploadHistory(
      PicUiUploadHistoryRecord(
        id: '${nowMs}_${item.key.hashCode.abs()}',
        key: item.key,
        url: item.links.url,
        thumbnailUrl: item.links.thumbnailUrl,
        deleteUrl: item.links.deleteUrl,
        createdAtMs: nowMs,
        markdown: item.links.markdown,
      ),
    );
    return item;
  }

  Future<PicUiImagePage> fetchImages({
    required String apiToken,
    int page = 1,
    String order = 'newest',
    String permission = '',
    int? albumId,
    String query = '',
  }) async {
    final payload = await _requestJson(
      method: 'GET',
      uri: _uri('/images', <String, String>{
        'page': '${page < 1 ? 1 : page}',
        if (order.trim().isNotEmpty) 'order': order.trim(),
        if (permission.trim().isNotEmpty) 'permission': permission.trim(),
        if (albumId != null && albumId > 0) 'album_id': '$albumId',
        if (query.trim().isNotEmpty) 'q': query.trim(),
      }),
      apiToken: apiToken,
    );
    final data = _asMap(payload['data']);
    final list = _asList(data['data']);
    final items = list
        .map((e) => PicUiImageItem.fromJson(_asMap(e)))
        .toList(growable: false);
    return PicUiImagePage(
      currentPage: _asInt(data['current_page']) ?? 1,
      lastPage: _asInt(data['last_page']) ?? 1,
      perPage: _asInt(data['per_page']) ?? items.length,
      total: _asInt(data['total']) ?? items.length,
      items: items,
    );
  }

  Future<void> deleteImage({
    required String apiToken,
    required String imageKey,
  }) async {
    final key = imageKey.trim();
    if (key.isEmpty) {
      throw const PicUiImageHostException('图片 key 不能为空');
    }
    await _requestJson(
      method: 'DELETE',
      uri: _uri('/images/$key'),
      apiToken: apiToken,
    );
  }

  Future<PicUiAlbumPage> fetchAlbums({
    required String apiToken,
    int page = 1,
    String order = 'newest',
    String query = '',
  }) async {
    final payload = await _requestJson(
      method: 'GET',
      uri: _uri('/albums', <String, String>{
        'page': '${page < 1 ? 1 : page}',
        if (order.trim().isNotEmpty) 'order': order.trim(),
        if (query.trim().isNotEmpty) 'q': query.trim(),
      }),
      apiToken: apiToken,
    );
    final data = _asMap(payload['data']);
    final list = _asList(data['data']);
    final items = list
        .map((e) => PicUiAlbumItem.fromJson(_asMap(e)))
        .toList(growable: false);
    return PicUiAlbumPage(
      currentPage: _asInt(data['current_page']) ?? 1,
      lastPage: _asInt(data['last_page']) ?? 1,
      perPage: _asInt(data['per_page']) ?? items.length,
      total: _asInt(data['total']) ?? items.length,
      items: items,
    );
  }

  Future<void> deleteAlbum({
    required String apiToken,
    required int albumId,
  }) async {
    if (albumId <= 0) {
      throw const PicUiImageHostException('相册 id 无效');
    }
    await _requestJson(
      method: 'DELETE',
      uri: _uri('/albums/$albumId'),
      apiToken: apiToken,
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required Uri uri,
    required String apiToken,
    String contentType = '',
    String body = '',
  }) async {
    final client = _httpClient ?? http.Client();
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      final token = apiToken.trim();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (contentType.isNotEmpty) {
        headers['Content-Type'] = contentType;
      }
      late final http.Response response;
      switch (method.toUpperCase()) {
        case 'POST':
          response = await client
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          response = await client
              .delete(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 30));
          break;
        default:
          response = await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30));
          break;
      }
      final payload = _decodeResponseMap(response.bodyBytes);
      _ensureSuccess(payload, response.statusCode);
      return payload;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async {
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    return http.Response.fromStream(streamed);
  }

  static void _ensureSuccess(Map<String, dynamic> payload, int httpStatusCode) {
    final status = payload['status'];
    final success = status == true || '$status'.trim() == '1';
    if (httpStatusCode >= 200 && httpStatusCode < 300 && success) {
      return;
    }
    throw PicUiImageHostException(
      _extractErrorMessage(payload, httpStatusCode),
    );
  }

  static String _extractErrorMessage(
    Map<String, dynamic> payload,
    int httpStatusCode,
  ) {
    final message = _asString(payload['message']);
    if (message.isNotEmpty) {
      return message;
    }
    if (httpStatusCode == 401) {
      return '认证失败，请检查 PicUI Token';
    }
    return 'PicUI 请求失败 (HTTP $httpStatusCode)';
  }

  static Future<List<PicUiUploadHistoryRecord>> loadUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_historyKey) ?? const <String>[];
    final records = <PicUiUploadHistoryRecord>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }
        final item = PicUiUploadHistoryRecord.fromJson(_asMap(decoded));
        if (item.url.isEmpty) {
          continue;
        }
        records.add(item);
      } catch (_) {
        // ignore malformed history
      }
    }
    return records;
  }

  static Future<void> appendUploadHistory(
    PicUiUploadHistoryRecord record,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadUploadHistory();
    final merged = <PicUiUploadHistoryRecord>[
      record,
      ...current.where(
        (item) => item.id != record.id && item.url != record.url,
      ),
    ];
    if (merged.length > _maxHistoryCount) {
      merged.removeRange(_maxHistoryCount, merged.length);
    }
    await prefs.setStringList(
      _historyKey,
      merged.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
  }

  static Future<void> removeUploadHistoryRecord(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = await loadUploadHistory();
    final next = current
        .where((item) => item.id != normalized)
        .toList(growable: false);
    await prefs.setStringList(
      _historyKey,
      next.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
  }

  static Future<void> clearUploadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    final fallback = 'https://picui.cn';
    if (trimmed.isEmpty) {
      return fallback;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      throw const PicUiImageHostException('PicUI 地址格式不正确');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const PicUiImageHostException('PicUI 地址仅支持 http/https');
    }
    final normalized = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  static MediaType _guessImageMediaType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.gif')) {
      return MediaType('image', 'gif');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    if (lower.endsWith('.bmp')) {
      return MediaType('image', 'bmp');
    }
    if (lower.endsWith('.ico')) {
      return MediaType('image', 'x-icon');
    }
    if (lower.endsWith('.tif') || lower.endsWith('.tiff')) {
      return MediaType('image', 'tiff');
    }
    return MediaType('image', 'jpeg');
  }

  static String _normalizeUploadFileName(String fileName, MediaType mediaType) {
    final raw = fileName.trim();
    if (raw.isEmpty) {
      return mediaType.subtype == 'png' ? 'image.png' : 'image.jpg';
    }
    if (raw.contains('.')) {
      return raw;
    }
    return '$raw.${mediaType.subtype == 'png' ? 'png' : 'jpg'}';
  }

  static Map<String, dynamic> _decodeResponseMap(List<int> bytes) {
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    return _asMap(decoded);
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic raw) {
    if (raw is List) {
      return raw;
    }
    return const <dynamic>[];
  }

  static String _asString(dynamic raw) {
    final value = '$raw'.trim();
    if (value.toLowerCase() == 'null') {
      return '';
    }
    return value;
  }

  static int? _asInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is double) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  static double _asDouble(dynamic raw) {
    if (raw is int) {
      return raw.toDouble();
    }
    if (raw is double) {
      return raw;
    }
    if (raw is String) {
      return double.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }
}

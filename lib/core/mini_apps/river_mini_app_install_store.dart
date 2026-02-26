import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:river/core/config/server_config.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiverMiniAppInstallStore {
  RiverMiniAppInstallStore();

  static const String _installedAppsKey = 'river.mini_apps.installed.apps.v1';
  static const int _maxInstallAttempts = 3;
  static const int _maxDownloadResumeRetries = 8;
  static final StreamController<int> _installedAppsChangedController =
      StreamController<int>.broadcast(sync: true);
  static int _installedAppsRevision = 0;

  static Stream<int> get installedAppsChanged =>
      _installedAppsChangedController.stream;

  SharedPreferences? _prefs;

  Future<List<RiverMiniAppEntry>> loadInstalledApps() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_installedAppsKey) ?? '';
    if (raw.trim().isEmpty) {
      return const <RiverMiniAppEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <RiverMiniAppEntry>[];
      }
      final result = <RiverMiniAppEntry>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final map = <String, dynamic>{};
        for (final entry in item.entries) {
          map['${entry.key}'] = entry.value;
        }
        final entry = RiverMiniAppEntry.fromJson(map);
        if (entry.id.isEmpty || entry.localEntryFilePath.isEmpty) {
          continue;
        }
        result.add(entry);
      }
      var changed = false;
      final normalized = <RiverMiniAppEntry>[];
      for (final item in result) {
        var next = item;
        if (next.iconUrl.trim().isEmpty &&
            next.localEntryFilePath.trim().isNotEmpty) {
          final localIcon = await _resolveInstalledIconFromEntryPath(
            next.localEntryFilePath,
          );
          if (localIcon.isNotEmpty) {
            next = next.copyWith(iconUrl: localIcon);
            changed = true;
          }
        }
        normalized.add(next);
      }

      normalized.sort((a, b) {
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) {
          return orderCmp;
        }
        return a.name.compareTo(b.name);
      });
      if (changed) {
        await _saveInstalled(normalized);
      }
      return normalized;
    } catch (_) {
      return const <RiverMiniAppEntry>[];
    }
  }

  Future<RiverMiniAppEntry> install({
    required RiverMiniAppEntry app,
    String? cookieHeader,
  }) async {
    final packageUrl = app.packageUrl.trim();
    if (packageUrl.isEmpty) {
      throw Exception('小程序未提供可安装包(package_url)');
    }

    final packageUri = Uri.tryParse(packageUrl);
    if (packageUri == null) {
      throw Exception('小程序安装包地址无效');
    }

    final headers = <String, String>{
      'Accept': '*/*',
      HttpHeaders.acceptEncodingHeader: 'identity',
      HttpHeaders.connectionHeader: 'close',
    };
    final cookie = cookieHeader?.trim() ?? '';
    if (cookie.isNotEmpty &&
        RiverServerConfig.instance.isForumHost(packageUri.host.trim())) {
      headers['Cookie'] = cookie;
    }

    final meta = await _resolvePackageMeta(
      packageUri: packageUri,
      headers: headers,
      app: app,
    );
    if (meta.length <= 0) {
      throw Exception('无法获取安装包长度，已中止安装');
    }

    final zipFile = await _downloadPackageFile(
      packageUri: packageUri,
      headers: headers,
      appId: app.id,
      expectedLength: meta.length,
      expectedSha256: meta.sha256,
    );
    try {
      final installed = await _installZipAtomically(app: app, zipFile: zipFile);
      await _upsertInstalledApp(installed);
      return installed;
    } finally {
      await _safeDeleteFile(zipFile);
      await _safeDeleteFile(File('${zipFile.path}.part'));
    }
  }

  Future<RiverMiniAppEntry> installFromLocalZip({
    required RiverMiniAppEntry app,
    required String zipFilePath,
  }) async {
    final path = zipFilePath.trim();
    if (path.isEmpty) {
      throw Exception('未选择本地安装包');
    }
    final zipFile = File(path);
    if (!await zipFile.exists()) {
      throw Exception('本地安装包不存在');
    }
    final length = await _fileLengthOrZero(zipFile);
    if (length <= 0) {
      throw Exception('本地安装包为空');
    }

    if (app.packageBytes > 0 && app.packageBytes != length) {
      throw Exception('本地安装包大小不匹配(${app.packageBytes}/$length)');
    }

    final expectedSha = app.packageSha256.trim().toLowerCase();
    if (expectedSha.isNotEmpty) {
      final actualSha = await _computeFileSha256(zipFile);
      if (actualSha != expectedSha) {
        throw Exception('本地安装包SHA256不匹配');
      }
    }

    if (!await _isValidZipArchive(zipFile)) {
      throw Exception('本地安装包不是有效ZIP');
    }

    final installed = await _installZipAtomically(app: app, zipFile: zipFile);
    await _upsertInstalledApp(installed);
    return installed;
  }

  Future<void> removeInstalledById(String appId) async {
    final installed = await loadInstalledApps();
    final target = installed.where((item) => item.id == appId).toList();
    if (target.isNotEmpty) {
      final path = target.first.localEntryFilePath.trim();
      if (path.isNotEmpty) {
        final file = File(path);
        final dir = file.parent;
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    }
    final remain = installed
        .where((item) => item.id != appId)
        .toList(growable: false);
    await _saveInstalled(remain);
  }

  Future<void> clearAllInstalled() async {
    final root = await _appsRootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
    await _saveInstalled(const <RiverMiniAppEntry>[]);
  }

  Future<void> reorderInstalledByIds(List<String> idsInOrder) async {
    final installed = await loadInstalledApps();
    if (installed.isEmpty) {
      return;
    }
    final normalizedIds = idsInOrder
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final byId = <String, RiverMiniAppEntry>{
      for (final item in installed) item.id: item,
    };
    final reordered = <RiverMiniAppEntry>[];
    for (final id in normalizedIds) {
      final item = byId.remove(id);
      if (item != null) {
        reordered.add(item);
      }
    }
    reordered.addAll(byId.values);

    final withOrder = <RiverMiniAppEntry>[];
    for (var i = 0; i < reordered.length; i++) {
      withOrder.add(reordered[i].copyWith(order: i));
    }
    await _saveInstalled(withOrder);
  }

  Future<RiverMiniAppStorageOverview> loadStorageOverview() async {
    final installed = await loadInstalledApps();
    final result = <RiverMiniAppStorageItem>[];
    var total = 0;
    for (final app in installed) {
      final bytes = await _appDirectoryBytes(app.localEntryFilePath);
      total += bytes;
      result.add(
        RiverMiniAppStorageItem(
          appId: app.id,
          appName: app.name,
          bytes: bytes,
          installedAtMillis: app.installedAtMillis,
        ),
      );
    }
    result.sort((a, b) => b.bytes.compareTo(a.bytes));
    return RiverMiniAppStorageOverview(
      totalBytes: total,
      appCount: installed.length,
      items: result,
    );
  }

  Future<void> _upsertInstalledApp(RiverMiniAppEntry app) async {
    final installed = await loadInstalledApps();
    final byId = <String, RiverMiniAppEntry>{
      for (final item in installed) item.id: item,
    };
    byId[app.id] = app;
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) {
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) {
          return orderCmp;
        }
        return a.name.compareTo(b.name);
      });
    await _saveInstalled(merged);
  }

  Future<void> _saveInstalled(List<RiverMiniAppEntry> apps) async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = apps.map((item) => item.toJson()).toList(growable: false);
    final saved = await _prefs?.setString(_installedAppsKey, jsonEncode(list));
    if (saved == true && !_installedAppsChangedController.isClosed) {
      _installedAppsChangedController.add(++_installedAppsRevision);
    }
  }

  Future<Directory> _appsRootDir() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}mini_apps');
    await root.create(recursive: true);
    return root;
  }

  Future<int> _appDirectoryBytes(String localEntryPath) async {
    final path = localEntryPath.trim();
    if (path.isEmpty) {
      return 0;
    }
    final entry = File(path);
    final dir = entry.parent;
    if (!await dir.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Ignore unreadable file.
        }
      }
    }
    return total;
  }

  Future<RiverMiniAppEntry> _installZipAtomically({
    required RiverMiniAppEntry app,
    required File zipFile,
  }) async {
    final root = await _appsRootDir();
    final appDirName = _safeSegment(app.id);
    final appDir = Directory(
      '${root.path}${Platform.pathSeparator}$appDirName',
    );
    final stagingDir = Directory(
      '${root.path}${Platform.pathSeparator}.$appDirName.staging',
    );

    await _safeDeleteDirectory(stagingDir);
    await stagingDir.create(recursive: true);

    await _extractZipToDirectory(zipFile: zipFile, outputDir: stagingDir);

    final stagingEntry = await _resolveEntryFile(app: app, appDir: stagingDir);
    if (stagingEntry == null || !await stagingEntry.exists()) {
      throw Exception('安装完成但未找到入口页面(index.html)');
    }
    final stagingIcon = await _resolveIconFile(
      appDir: stagingDir,
      entryFile: stagingEntry,
    );

    final relativeEntryPath = _relativePath(
      rootDirPath: stagingDir.path,
      filePath: stagingEntry.path,
    );
    final relativeIconPath = stagingIcon == null
        ? ''
        : _relativePath(
            rootDirPath: stagingDir.path,
            filePath: stagingIcon.path,
          );

    await _safeDeleteDirectory(appDir);
    await _moveDirectory(source: stagingDir, target: appDir);

    final installedEntry = File(
      '${appDir.path}${Platform.pathSeparator}$relativeEntryPath',
    );
    if (!await installedEntry.exists()) {
      throw Exception('安装后入口文件丢失，请重试');
    }
    var installedIconUrl = app.iconUrl;
    if (relativeIconPath.isNotEmpty) {
      final installedIcon = File(
        '${appDir.path}${Platform.pathSeparator}$relativeIconPath',
      );
      if (await installedIcon.exists()) {
        installedIconUrl = installedIcon.uri.toString();
      }
    }

    return app.copyWith(
      iconUrl: installedIconUrl,
      localEntryFilePath: installedEntry.path,
      installedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _relativePath({
    required String rootDirPath,
    required String filePath,
  }) {
    final separator = Platform.pathSeparator;
    final normalizedRoot = rootDirPath.endsWith(separator)
        ? rootDirPath
        : '$rootDirPath$separator';
    if (!filePath.startsWith(normalizedRoot)) {
      throw Exception('安装目录结构异常，无法定位入口文件');
    }
    return filePath.substring(normalizedRoot.length);
  }

  Future<void> _moveDirectory({
    required Directory source,
    required Directory target,
  }) async {
    try {
      await source.rename(target.path);
      return;
    } catch (_) {
      // fall back to copy
    }

    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = _relativePath(
        rootDirPath: source.path,
        filePath: entity.path,
      );
      final nextPath = '${target.path}${Platform.pathSeparator}$relative';
      if (entity is Directory) {
        await Directory(nextPath).create(recursive: true);
        continue;
      }
      if (entity is File) {
        final dst = File(nextPath);
        await dst.parent.create(recursive: true);
        await entity.copy(dst.path);
      }
    }
    await _safeDeleteDirectory(source);
  }

  Future<_PackageMeta> _resolvePackageMeta({
    required Uri packageUri,
    required Map<String, String> headers,
    required RiverMiniAppEntry app,
  }) async {
    final expectedFromManifest = app.packageBytes > 0 ? app.packageBytes : null;
    final expectedFromProbe = await _probeContentLength(
      packageUri: packageUri,
      headers: headers,
    );

    // Prefer manifest metadata for platform packages; probe only as fallback.
    final length = expectedFromManifest ?? expectedFromProbe ?? 0;
    return _PackageMeta(
      length: length,
      sha256: app.packageSha256.trim().toLowerCase(),
    );
  }

  Future<File> _downloadPackageFile({
    required Uri packageUri,
    required Map<String, String> headers,
    required String appId,
    required int expectedLength,
    required String expectedSha256,
  }) async {
    final tempRoot = await getTemporaryDirectory();
    final downloadDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}mini_app_downloads',
    );
    await downloadDir.create(recursive: true);

    final safeId = _safeSegment(appId);
    final finalZip = File(
      '${downloadDir.path}${Platform.pathSeparator}$safeId.zip',
    );
    final partZip = File('${finalZip.path}.part');

    await _safeDeleteFile(finalZip);
    var targetLength = expectedLength;
    Object? lastError;
    for (var attempt = 1; attempt <= _maxInstallAttempts; attempt++) {
      try {
        final downloaded = await _downloadPackageWithResume(
          packageUri: packageUri,
          headers: headers,
          partZip: partZip,
          expectedLength: targetLength,
        );
        if (targetLength <= 0 && downloaded > 0) {
          targetLength = downloaded;
        }

        final current = await _fileLengthOrZero(partZip);
        if (targetLength > 0 && current != targetLength) {
          throw Exception('整包下载不完整($current/$targetLength)');
        }

        if (expectedSha256.isNotEmpty) {
          final actualSha = await _computeFileSha256(partZip);
          if (actualSha != expectedSha256) {
            throw Exception(
              'SHA256校验失败(expected=$expectedSha256, actual=$actualSha)',
            );
          }
        }

        if (!await _isValidZipArchive(partZip)) {
          throw Exception('ZIP校验失败');
        }

        await _safeDeleteFile(finalZip);
        await partZip.rename(finalZip.path);
        return finalZip;
      } catch (error) {
        lastError = error;
        // Keep partial file for resume when possible.
        if ('$error'.contains('SHA256校验失败') ||
            '$error'.contains('ZIP校验失败') ||
            '$error'.contains('整包下载长度超出')) {
          await _safeDeleteFile(partZip);
        }
        if (attempt >= _maxInstallAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 320 * attempt));
      }
    }

    throw Exception('下载小程序失败：$lastError');
  }

  Future<int> _downloadPackageWithResume({
    required Uri packageUri,
    required Map<String, String> headers,
    required File partZip,
    required int expectedLength,
  }) async {
    var targetLength = expectedLength;
    if (targetLength > 0) {
      final existing = await _fileLengthOrZero(partZip);
      if (existing == targetLength) {
        return existing;
      }
    }
    Object? lastError;
    for (var attempt = 1; attempt <= _maxDownloadResumeRetries; attempt++) {
      try {
        final result = await _downloadStep(
          packageUri: packageUri,
          headers: headers,
          partZip: partZip,
          expectedLength: targetLength,
        );
        if (result.resetRequired) {
          await _safeDeleteFile(partZip);
          if (attempt < _maxDownloadResumeRetries) {
            await Future<void>.delayed(Duration(milliseconds: 220 * attempt));
            continue;
          }
          throw Exception('服务端断点续传偏移不一致，且自动重置失败');
        }
        if (result.inferredTotal > 0 && targetLength <= 0) {
          targetLength = result.inferredTotal;
        }
        final current = await _fileLengthOrZero(partZip);
        if (targetLength > 0) {
          if (current > targetLength) {
            throw Exception('整包下载长度超出($current/$targetLength)');
          }
          if (current == targetLength) {
            return current;
          }
        } else if (result.completed) {
          return current;
        }
      } catch (error) {
        lastError = error;
        if (attempt < _maxDownloadResumeRetries) {
          await Future<void>.delayed(Duration(milliseconds: 180 * attempt));
        }
      }
    }

    throw Exception('整包下载失败：$lastError');
  }

  Future<_DownloadStepResult> _downloadStep({
    required Uri packageUri,
    required Map<String, String> headers,
    required File partZip,
    required int expectedLength,
  }) async {
    if (!await partZip.parent.exists()) {
      await partZip.parent.create(recursive: true);
    }

    var existingBytes = await _fileLengthOrZero(partZip);
    if (expectedLength > 0 && existingBytes > expectedLength) {
      await _safeDeleteFile(partZip);
      existingBytes = 0;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 12)
      ..maxConnectionsPerHost = 4;

    try {
      final request = await client.getUrl(packageUri);
      headers.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          request.headers.set(key, value);
        }
      });
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (existingBytes > 0 &&
          response.statusCode == HttpStatus.partialContent) {
        final rawRange = response.headers.value(HttpHeaders.contentRangeHeader);
        final parsedStart = _parseContentRangeStart(rawRange);
        if (parsedStart != null && parsedStart != existingBytes) {
          return const _DownloadStepResult(
            completed: false,
            inferredTotal: 0,
            resetRequired: true,
          );
        }
      }

      FileMode mode;
      var downloaded = existingBytes;
      var bytesToSkipFromFullResponse = 0;
      if (response.statusCode == HttpStatus.partialContent &&
          existingBytes > 0) {
        mode = FileMode.append;
      } else if (response.statusCode == HttpStatus.ok) {
        if (existingBytes > 0) {
          // Server ignores Range and returns full content.
          // Keep local partial file and skip duplicate bytes from stream.
          mode = FileMode.append;
          bytesToSkipFromFullResponse = existingBytes;
        } else {
          downloaded = 0;
          mode = FileMode.write;
        }
      } else if (response.statusCode ==
          HttpStatus.requestedRangeNotSatisfiable) {
        return const _DownloadStepResult(
          completed: false,
          inferredTotal: 0,
          resetRequired: true,
        );
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }

      final sink = partZip.openWrite(mode: mode);
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 75),
        )) {
          if (bytesToSkipFromFullResponse > 0) {
            if (chunk.length <= bytesToSkipFromFullResponse) {
              bytesToSkipFromFullResponse -= chunk.length;
              continue;
            }
            final start = bytesToSkipFromFullResponse;
            bytesToSkipFromFullResponse = 0;
            final remain = chunk.sublist(start);
            sink.add(remain);
            downloaded += remain.length;
          } else {
            sink.add(chunk);
            downloaded += chunk.length;
          }
          if (expectedLength > 0 && downloaded > expectedLength) {
            throw Exception('整包下载长度超出($downloaded/$expectedLength)');
          }
        }
      } finally {
        await sink.close();
      }

      var inferredTotal = 0;
      if (response.statusCode == HttpStatus.ok && response.contentLength > 0) {
        inferredTotal = response.contentLength;
      } else if (response.statusCode == HttpStatus.partialContent) {
        final total = _parseContentRangeTotal(
          response.headers.value(HttpHeaders.contentRangeHeader),
        );
        if (total != null && total > 0) {
          inferredTotal = total;
        } else if (response.contentLength > 0) {
          inferredTotal = downloaded;
        }
      }

      return _DownloadStepResult(
        completed: true,
        inferredTotal: inferredTotal,
        resetRequired: false,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<int?> _probeContentLength({
    required Uri packageUri,
    required Map<String, String> headers,
  }) async {
    return _probeContentLengthByHead(packageUri: packageUri, headers: headers);
  }

  Future<int?> _probeContentLengthByHead({
    required Uri packageUri,
    required Map<String, String> headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.openUrl('HEAD', packageUri);
      headers.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          request.headers.set(key, value);
        }
      });
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.connectionHeader, 'close');

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final raw = response.headers.value(HttpHeaders.contentLengthHeader) ?? '';
      final length = int.tryParse(raw);
      if (length != null && length > 0) {
        return length;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  int? _parseContentRangeStart(String? rawHeader) {
    final raw = rawHeader?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(raw);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  int? _parseContentRangeTotal(String? rawHeader) {
    final raw = rawHeader?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(raw);
    if (match == null) {
      return null;
    }
    final totalRaw = match.group(3)!;
    if (totalRaw == '*') {
      return null;
    }
    return int.tryParse(totalRaw);
  }

  Future<String> _computeFileSha256(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString().toLowerCase();
  }

  Future<bool> _isValidZipArchive(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }
      final length = await file.length();
      if (length < 4) {
        return false;
      }
      final raf = await file.open();
      try {
        final head = await raf.read(4);
        if (head.length < 4 || head[0] != 0x50 || head[1] != 0x4b) {
          return false;
        }
      } finally {
        await raf.close();
      }
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      return archive.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<File?> _resolveEntryFile({
    required RiverMiniAppEntry app,
    required Directory appDir,
  }) async {
    final fromUrl = _entryPathFromUrl(app.url);
    if (fromUrl.isNotEmpty) {
      final candidate = File('${appDir.path}${Platform.pathSeparator}$fromUrl');
      if (await candidate.exists()) {
        return candidate;
      }
    }

    final defaultEntry = File(
      '${appDir.path}${Platform.pathSeparator}index.html',
    );
    if (await defaultEntry.exists()) {
      return defaultEntry;
    }

    final htmlFiles = await appDir
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.html'),
        )
        .cast<File>()
        .toList();
    if (htmlFiles.isEmpty) {
      return null;
    }
    htmlFiles.sort((a, b) => a.path.length.compareTo(b.path.length));
    return htmlFiles.first;
  }

  Future<File?> _resolveIconFile({
    required Directory appDir,
    required File entryFile,
  }) async {
    final fromConfig = await _resolveIconFromMiniAppConfig(appDir);
    if (fromConfig != null) {
      return fromConfig;
    }

    final candidates = <String>[
      'icon.png',
      'icon.jpg',
      'icon.jpeg',
      'icon.webp',
      'logo.png',
      'logo.jpg',
      'logo.jpeg',
      'logo.webp',
      'favicon.png',
      'favicon.ico',
    ];
    final probeDirs = <Directory>[
      entryFile.parent,
      appDir,
      Directory('${appDir.path}${Platform.pathSeparator}public'),
      Directory('${appDir.path}${Platform.pathSeparator}assets'),
      Directory(
        '${appDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}icons',
      ),
      Directory(
        '${appDir.path}${Platform.pathSeparator}src${Platform.pathSeparator}assets',
      ),
    ];
    for (final dir in probeDirs) {
      if (!await dir.exists()) {
        continue;
      }
      for (final name in candidates) {
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        if (await file.exists()) {
          return file;
        }
      }
    }
    return null;
  }

  Future<File?> _resolveIconFromMiniAppConfig(Directory appDir) async {
    final configs = <File>[];
    await for (final entity in appDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('${Platform.pathSeparator}miniapp.config.json') ||
          lower.endsWith('/miniapp.config.json') ||
          lower.endsWith('\\miniapp.config.json')) {
        configs.add(entity);
      }
    }
    if (configs.isEmpty) {
      return null;
    }
    configs.sort((a, b) => a.path.length.compareTo(b.path.length));

    for (final configFile in configs) {
      try {
        final decoded = jsonDecode(await configFile.readAsString());
        final map = decoded is Map
            ? _toStringMap(decoded)
            : const <String, dynamic>{};
        if (map.isEmpty) {
          continue;
        }
        final iconRaw = _readString(
          map['icon'],
          fallback: _readString(
            map['iconUrl'],
            fallback: _readString(
              map['icon_url'],
              fallback: _readString(map['logo']),
            ),
          ),
        );
        if (iconRaw.isEmpty) {
          continue;
        }
        final normalized = iconRaw.replaceAll('\\', '/').trim();
        if (normalized.isEmpty) {
          continue;
        }
        final uri = Uri.tryParse(normalized);
        if (uri != null && uri.hasScheme) {
          continue;
        }
        final relPath = normalized
            .split('/')
            .where((s) => s.trim().isNotEmpty && s != '.' && s != '..')
            .join(Platform.pathSeparator);
        if (relPath.isEmpty) {
          continue;
        }
        final iconFile = File(
          '${configFile.parent.path}${Platform.pathSeparator}$relPath',
        );
        if (await iconFile.exists()) {
          return iconFile;
        }
      } catch (_) {
        // Ignore malformed config.
      }
    }
    return null;
  }

  Future<String> _resolveInstalledIconFromEntryPath(
    String localEntryPath,
  ) async {
    final entry = File(localEntryPath.trim());
    if (!await entry.exists()) {
      return '';
    }
    final iconFile = await _resolveIconFile(
      appDir: entry.parent,
      entryFile: entry,
    );
    if (iconFile == null || !await iconFile.exists()) {
      return '';
    }
    return iconFile.uri.toString();
  }

  Future<void> _extractZipToDirectory({
    required File zipFile,
    required Directory outputDir,
  }) async {
    final bytes = await zipFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('安装包为空');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.isEmpty) {
      final head = bytes
          .take(8)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      throw Exception('安装包解压后为空(len=${bytes.length}, head=$head)');
    }

    for (final item in archive) {
      final rawName = item.name.trim();
      if (rawName.isEmpty) {
        continue;
      }
      final normalized = rawName.replaceAll('\\', '/');
      if (normalized.startsWith('/') || normalized.contains('../')) {
        continue;
      }
      final targetPath = normalized
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .join(Platform.pathSeparator);
      if (targetPath.isEmpty) {
        continue;
      }
      final fullPath = '${outputDir.path}${Platform.pathSeparator}$targetPath';
      if (item.isFile) {
        final outFile = File(fullPath);
        await outFile.parent.create(recursive: true);
        final data = item.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
      } else {
        await Directory(fullPath).create(recursive: true);
      }
    }
  }

  String _entryPathFromUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl.trim());
    if (uri == null) {
      return '';
    }
    final path = uri.path.trim();
    if (path.isEmpty) {
      return '';
    }
    final segments = path
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .map((segment) => segment.trim())
        .toList(growable: false);
    if (segments.isEmpty) {
      return '';
    }
    if (segments.length >= 2 && segments.first == 'miniapps') {
      return segments.skip(2).join(Platform.pathSeparator);
    }
    if (segments.length >= 2) {
      return segments.skip(1).join(Platform.pathSeparator);
    }
    return segments.first;
  }

  String _safeSegment(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
  }

  Map<String, dynamic> _toStringMap(Map raw) {
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      result['${entry.key}'] = entry.value;
    }
    return result;
  }

  String _readString(dynamic raw, {String fallback = ''}) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) {
      return fallback;
    }
    return text;
  }

  Future<int> _fileLengthOrZero(File file) async {
    try {
      if (!await file.exists()) {
        return 0;
      }
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _safeDeleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _safeDeleteDirectory(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // ignore
    }
  }
}

class _PackageMeta {
  const _PackageMeta({required this.length, required this.sha256});

  final int length;
  final String sha256;
}

class _DownloadStepResult {
  const _DownloadStepResult({
    required this.completed,
    required this.inferredTotal,
    required this.resetRequired,
  });

  final bool completed;
  final int inferredTotal;
  final bool resetRequired;
}

class RiverMiniAppStorageOverview {
  const RiverMiniAppStorageOverview({
    required this.totalBytes,
    required this.appCount,
    required this.items,
  });

  final int totalBytes;
  final int appCount;
  final List<RiverMiniAppStorageItem> items;
}

class RiverMiniAppStorageItem {
  const RiverMiniAppStorageItem({
    required this.appId,
    required this.appName,
    required this.bytes,
    required this.installedAtMillis,
  });

  final String appId;
  final String appName;
  final int bytes;
  final int installedAtMillis;
}

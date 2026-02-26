import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:river/app/app_dependencies.dart';
import 'package:river/core/account/account_models.dart';
import 'package:river/core/mini_apps/river_mini_app_code_image_codec.dart';
import 'package:river/core/mini_apps/river_mini_app_install_store.dart';
import 'package:river/core/mini_apps/river_mini_app_models.dart';
import 'package:river/core/mini_apps/river_mini_app_orbit_code_codec.dart';
import 'package:river/core/mini_apps/river_mini_app_platform_client.dart';
import 'package:river/core/mini_apps/river_mini_app_repository.dart';
import 'package:river/core/navigation/river_page_route.dart';
import 'package:river/features/mini_apps/mini_app_webview_page.dart';
import 'package:river/features/mine/widgets/mine_settings_app_bar.dart';
import 'package:river/features/mine/riverside_profile_page.dart';

class MineQrScanPage extends StatefulWidget {
  const MineQrScanPage({
    super.key,
    required this.dependencies,
    this.rawResultMode = false,
  });

  final AppDependencies dependencies;
  final bool rawResultMode;

  @override
  State<MineQrScanPage> createState() => _MineQrScanPageState();
}

class _MineQrScanPageState extends State<MineQrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: true,
  );
  final ImagePicker _picker = ImagePicker();
  final mlkit.BarcodeScanner _barcodeScanner = mlkit.BarcodeScanner(
    formats: <mlkit.BarcodeFormat>[mlkit.BarcodeFormat.qrCode],
  );
  final RiverMiniAppRepository _miniAppRepository = RiverMiniAppRepository();
  final RiverMiniAppInstallStore _miniAppInstallStore =
      RiverMiniAppInstallStore();
  final RiverMiniAppPlatformClient _miniAppPlatformClient =
      RiverMiniAppPlatformClient();

  bool _handlingResult = false;
  bool _pickingFromGallery = false;
  bool _torchEnabled = false;
  DateTime _lastOrbitScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOrbitResolveFailTipAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _openIdentityQr() async {
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => MineIdentityQrPage(dependencies: widget.dependencies),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handlingResult) {
      return;
    }
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      final now = DateTime.now();
      if (now.difference(_lastOrbitScanAt).inMilliseconds < 900) {
        return;
      }
      _lastOrbitScanAt = now;
      final frameBytes = capture.image;
      if (frameBytes != null && frameBytes.isNotEmpty) {
        final orbitTry = await _resolveRawByOrbitBytes(
          frameBytes,
          maxCandidates: 12,
        );
        final orbitRaw = orbitTry.rawValue;
        if (orbitRaw != null && orbitRaw.isNotEmpty) {
          await _handleRawResult(orbitRaw);
        } else if (orbitTry.decoded && mounted) {
          final nowTip = DateTime.now();
          if (nowTip.difference(_lastOrbitResolveFailTipAt).inSeconds >= 3) {
            _lastOrbitResolveFailTipAt = nowTip;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已识别小程序码图形，但平台解析失败。请确认服务器地址一致并刷新小程序码后重试'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
      return;
    }
    final rawValue = _pickBestRawValue(
      barcodes.map((e) => e.rawValue?.trim() ?? ''),
    );
    if (rawValue.isEmpty) {
      return;
    }
    await _handleRawResult(rawValue);
  }

  Future<void> _handleRawResult(String rawValue) async {
    if (_handlingResult) {
      return;
    }

    if (widget.rawResultMode) {
      if (!mounted) {
        return;
      }
      setState(() {
        _handlingResult = true;
      });
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(rawValue);
      return;
    }

    final miniAppCode = _parseMiniAppCodePayload(rawValue);
    if (miniAppCode != null) {
      setState(() {
        _handlingResult = true;
      });
      HapticFeedback.mediumImpact();
      try {
        await _openMiniAppByCode(miniAppCode);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('打开小程序失败：$error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 260));
          setState(() {
            _handlingResult = false;
          });
        }
      }
      return;
    }

    final parsed = _parseIdentityPayload(rawValue);
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未识别到可用身份二维码'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _handlingResult = true;
    });
    HapticFeedback.mediumImpact();
    try {
      await _openProfile(parsed);
    } finally {
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 260));
        setState(() {
          _handlingResult = false;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_pickingFromGallery || _handlingResult) {
      return;
    }
    setState(() {
      _pickingFromGallery = true;
    });
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (!mounted || picked == null) {
        return;
      }
      final inputImage = mlkit.InputImage.fromFilePath(picked.path);
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!mounted) {
        return;
      }
      final rawValue = _pickBestRawValue(
        barcodes.map((e) => e.rawValue?.trim() ?? ''),
      );
      if (rawValue.isEmpty) {
        final bytes = await File(picked.path).readAsBytes();
        final orbitTry = await _resolveRawByOrbitBytes(
          bytes,
          maxCandidates: 28,
        );
        final orbitRaw = orbitTry.rawValue;
        if (!mounted) {
          return;
        }
        if (orbitRaw != null && orbitRaw.isNotEmpty) {
          await _handleRawResult(orbitRaw);
          return;
        }
        if (orbitTry.decoded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已识别小程序码图形，但平台解析失败。请确认服务器地址一致并刷新小程序码后重试'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        final miniAppCode = RiverMiniAppCodeImageCodec.decodeFromImageBytes(
          bytes,
        );
        if (!mounted) {
          return;
        }
        if (miniAppCode != null && miniAppCode.trim().isNotEmpty) {
          await _handleRawResult(miniAppCode.trim());
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未在图片中识别到二维码/小程序码'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _handleRawResult(rawValue);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('读取图库二维码失败，请重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _pickingFromGallery = false;
        });
      }
    }
  }

  Future<_OrbitResolveAttempt> _resolveRawByOrbitBytes(
    Uint8List bytes, {
    int maxCandidates = 20,
  }) async {
    final candidates =
        RiverMiniAppOrbitCodeCodec.decodeCandidatesFromImageBytes(
          bytes,
          maxCandidates: maxCandidates,
        );
    if (candidates.isEmpty) {
      final hiddenRaw = RiverMiniAppCodeImageCodec.decodeFromImageBytes(
        bytes,
      )?.trim();
      if (hiddenRaw != null && hiddenRaw.isNotEmpty) {
        return _OrbitResolveAttempt(rawValue: hiddenRaw, decoded: true);
      }
      return const _OrbitResolveAttempt(rawValue: null, decoded: false);
    }
    for (final orbit in candidates) {
      final raw = await _resolveOrbitCodePayload(
        idHex: orbit.idHex,
        checksumHex: orbit.checksumHex,
        timeoutSeconds: 3,
      );
      if (raw != null && raw.isNotEmpty) {
        return _OrbitResolveAttempt(rawValue: raw, decoded: true);
      }
    }
    final hiddenRaw = RiverMiniAppCodeImageCodec.decodeFromImageBytes(
      bytes,
    )?.trim();
    if (hiddenRaw != null && hiddenRaw.isNotEmpty) {
      return _OrbitResolveAttempt(rawValue: hiddenRaw, decoded: true);
    }
    return const _OrbitResolveAttempt(rawValue: null, decoded: true);
  }

  Future<String?> _resolveOrbitCodePayload({
    required String idHex,
    required String checksumHex,
    int timeoutSeconds = 8,
  }) async {
    final id = idHex.trim().toLowerCase();
    final checksum = checksumHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        !RegExp(r'^[0-9a-f]$').hasMatch(checksum)) {
      return null;
    }
    final manifestUrl =
        widget.dependencies.settingsController.miniAppsManifestUrl;
    String baseUrl;
    try {
      baseUrl = _miniAppPlatformClient.resolvePlatformBaseUrl(manifestUrl);
    } catch (_) {
      return null;
    }
    final uri = Uri.parse('$baseUrl/api/public/orbit-code/resolve').replace(
      queryParameters: <String, String>{'id': id, 'checksum': checksum},
    );
    try {
      final response = await http
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(Duration(seconds: timeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final root = jsonDecode(response.body);
      if (root is! Map) {
        return null;
      }
      final data = root['data'];
      if (data is! Map) {
        return null;
      }
      final raw = '${data['code'] ?? ''}'.trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  String _pickBestRawValue(Iterable<String> candidates) {
    String fallback = '';
    for (final raw in candidates) {
      final value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      fallback = fallback.isEmpty ? value : fallback;
      if (_parseMiniAppCodePayload(value) != null) {
        return value;
      }
      if (_parseIdentityPayload(value) != null) {
        return value;
      }
    }
    return fallback;
  }

  _ScannedIdentity? _parseIdentityPayload(String raw) {
    try {
      if (raw.startsWith('{') && raw.endsWith('}')) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry('$k', v));
          final provider = _providerFromRaw((map['provider'] ?? '').toString());
          final username = (map['username'] ?? '').toString().trim();
          if (provider != null && username.isNotEmpty) {
            return _ScannedIdentity(
              provider: provider,
              username: username,
              displayName: (map['displayName'] ?? username).toString().trim(),
              userId: _tryParseInt(map['userId']),
            );
          }
        }
      }

      final uri = Uri.tryParse(raw);
      if (uri == null) {
        return null;
      }

      final isCustomProfileUri =
          (uri.scheme == 'riverapp' || uri.scheme == 'river') &&
          uri.host == 'profile';
      if (isCustomProfileUri) {
        final provider = _providerFromRaw(
          uri.queryParameters['provider'] ?? '',
        );
        final username = (uri.queryParameters['username'] ?? '').trim();
        if (provider != null && username.isNotEmpty) {
          return _ScannedIdentity(
            provider: provider,
            username: username,
            displayName: (uri.queryParameters['displayName'] ?? username)
                .trim(),
            userId: _tryParseInt(uri.queryParameters['userId']),
          );
        }
      }

      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final riverHost = Uri.parse(
          widget.dependencies.settingsController.riverSideBaseUrl,
        ).host.toLowerCase();
        final qingHost = Uri.parse(
          widget.dependencies.settingsController.qingShuiHePanBaseUrl,
        ).host.toLowerCase();
        final host = uri.host.toLowerCase();
        final segments = uri.pathSegments;
        if (host == riverHost &&
            segments.length >= 2 &&
            segments.first == 'u') {
          final username = segments[1].trim();
          if (username.isNotEmpty) {
            return _ScannedIdentity(
              provider: AccountProvider.riverSide,
              username: username,
              displayName: username,
              userId: null,
            );
          }
        }
        if (host == qingHost) {
          final username =
              (uri.queryParameters['username'] ?? uri.queryParameters['user'])
                  ?.trim() ??
              '';
          if (username.isNotEmpty) {
            return _ScannedIdentity(
              provider: AccountProvider.qingShuiHePan,
              username: username,
              displayName: username,
              userId: _tryParseInt(uri.queryParameters['uid']),
            );
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  _ScannedMiniAppCode? _parseMiniAppCodePayload(String raw) {
    Map<String, dynamic>? readMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        final mapped = <String, dynamic>{};
        for (final entry in value.entries) {
          mapped['${entry.key}'] = entry.value;
        }
        return mapped;
      }
      return null;
    }

    Map<String, dynamic>? decodePacked(String packed) {
      final source = packed.trim();
      if (source.isEmpty) {
        return null;
      }
      try {
        var normalized = source.replaceAll('-', '+').replaceAll('_', '/');
        final rem = normalized.length % 4;
        if (rem > 0) {
          normalized = '$normalized${List.filled(4 - rem, '=').join()}';
        }
        final decodedRaw = utf8.decode(base64Decode(normalized));
        final decodedJson = jsonDecode(decodedRaw);
        return readMap(decodedJson);
      } catch (_) {
        return null;
      }
    }

    _ScannedMiniAppCode? fromMap(Map<String, dynamic> map) {
      final kind = (map['kind'] ?? map['type'] ?? '').toString().trim();
      if (kind.isNotEmpty &&
          kind != 'river-miniapp-code' &&
          kind != 'miniapp') {
        return null;
      }
      final catalog = (map['catalog'] ?? map['catalogUrl'] ?? '')
          .toString()
          .trim();
      final appId = (map['appId'] ?? map['miniAppId'] ?? map['id'] ?? '')
          .toString()
          .trim();
      final projectId = (map['projectId'] ?? '').toString().trim();
      final appCode = (map['appCode'] ?? '').toString().trim();
      final route = (map['route'] ?? map['path'] ?? '').toString().trim();
      final action = (map['action'] ?? '').toString().trim();
      Map<String, dynamic> params = const <String, dynamic>{};
      final rawParams = map['params'];
      if (rawParams is Map) {
        params = rawParams.map((k, v) => MapEntry('$k', v));
      } else if (rawParams is String && rawParams.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(rawParams);
          if (parsed is Map) {
            params = parsed.map((k, v) => MapEntry('$k', v));
          }
        } catch (_) {
          // ignore invalid params
        }
      }
      if (appId.isEmpty && projectId.isEmpty && appCode.isEmpty) {
        return null;
      }
      return _ScannedMiniAppCode(
        catalogUrl: catalog,
        miniAppId: appId,
        projectId: projectId,
        appCode: appCode,
        route: route,
        action: action,
        params: params,
      );
    }

    try {
      final rawTrim = raw.trim();
      if (rawTrim.isEmpty) {
        return null;
      }
      if (rawTrim.startsWith('{') && rawTrim.endsWith('}')) {
        final decoded = jsonDecode(rawTrim);
        final map = readMap(decoded);
        if (map == null) {
          return null;
        }
        return fromMap(map);
      }

      final uri = Uri.tryParse(rawTrim);
      if (uri == null) {
        return null;
      }

      final isMiniAppScheme =
          (uri.scheme == 'riverapp' || uri.scheme == 'river') &&
          uri.host == 'miniapp';
      if (!isMiniAppScheme) {
        return null;
      }

      final packed = uri.queryParameters['data']?.trim() ?? '';
      if (packed.isNotEmpty) {
        final decoded = decodePacked(packed);
        if (decoded != null) {
          final parsed = fromMap(decoded);
          if (parsed != null) {
            return parsed;
          }
        }
      }
      final queryMap = <String, dynamic>{
        for (final entry in uri.queryParameters.entries) entry.key: entry.value,
      };
      return fromMap(queryMap);
    } catch (_) {
      return null;
    }
  }

  String _activeCookieHeader() {
    final username = widget.dependencies.accountStore.activeRiverSideUsername;
    if (username == null || username.trim().isEmpty) {
      return '';
    }
    return widget.dependencies.accountStore.riverSideCookieHeaderFor(
          username,
        ) ??
        '';
  }

  Future<void> _openMiniAppByCode(_ScannedMiniAppCode code) async {
    final settings = widget.dependencies.settingsController;
    // Always resolve catalog from current app settings so scan behavior
    // follows the configured platform environment.
    final manifestUrl = settings.miniAppsManifestUrl;
    final cookieHeader = _activeCookieHeader();

    final manifest = await _miniAppRepository.load(
      manifestUrl: manifestUrl,
      cookieHeader: cookieHeader,
      forceRefresh: true,
    );
    if (!mounted) {
      return;
    }
    RiverMiniAppEntry? target;
    for (final item in manifest.entries) {
      if (code.miniAppId.isNotEmpty && item.id == code.miniAppId) {
        target = item;
        break;
      }
      if (code.projectId.isNotEmpty &&
          (item.projectId == code.projectId || item.id == code.projectId)) {
        target = item;
        break;
      }
      if (code.appCode.isNotEmpty &&
          item.appCode.toLowerCase() == code.appCode.toLowerCase()) {
        target = item;
        break;
      }
    }

    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该小程序未上架或不可搜索，无法打开'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final resolvedTarget = target;
    final installedList = await _miniAppInstallStore.loadInstalledApps();
    final installed = installedList
        .where((e) => e.id == resolvedTarget.id)
        .toList();
    var newlyInstalled = false;
    RiverMiniAppEntry toOpen;
    if (installed.isNotEmpty &&
        installed.first.localEntryFilePath.trim().isNotEmpty &&
        File(installed.first.localEntryFilePath).existsSync()) {
      final local = installed.first;
      toOpen = resolvedTarget.copyWith(
        localEntryFilePath: local.localEntryFilePath,
        installedAtMillis: local.installedAtMillis,
        order: local.order,
        iconUrl: local.iconUrl.isNotEmpty
            ? local.iconUrl
            : resolvedTarget.iconUrl,
      );
    } else {
      newlyInstalled = true;
      toOpen = await _miniAppInstallStore.install(
        app: resolvedTarget,
        cookieHeader: cookieHeader,
      );
    }

    final latestInstalled = await _miniAppInstallStore.loadInstalledApps();
    if (newlyInstalled) {
      final nextOrder = <String>[
        resolvedTarget.id,
        ...latestInstalled
            .where((e) => e.id != resolvedTarget.id)
            .map((e) => e.id),
      ];
      await _miniAppInstallStore.reorderInstalledByIds(nextOrder);
    }
    final listed = (await _miniAppInstallStore.loadInstalledApps())
        .where((e) => e.id == resolvedTarget.id)
        .toList();
    if (listed.isNotEmpty) {
      toOpen = listed.first;
    }

    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => MiniAppWebViewPage(
          dependencies: widget.dependencies,
          miniApp: toOpen,
          launchRoute: code.route,
          launchParams: code.params,
          launchAction: code.action,
          launchSource: 'scan',
        ),
      ),
    );
  }

  AccountProvider? _providerFromRaw(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'riverside' || value == 'river_side' || value == 'river') {
      return AccountProvider.riverSide;
    }
    if (value == 'qingshuihepan' || value == 'qing' || value == 'hp') {
      return AccountProvider.qingShuiHePan;
    }
    return null;
  }

  int? _tryParseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Future<void> _openProfile(_ScannedIdentity identity) async {
    final activeRiver =
        widget.dependencies.accountStore.activeRiverSideUsername;
    final activeQing =
        widget.dependencies.accountStore.activeQingShuiHePanUsername;
    final hasLogin = identity.provider == AccountProvider.riverSide
        ? (activeRiver != null && activeRiver.trim().isNotEmpty)
        : (activeQing != null && activeQing.trim().isNotEmpty);
    if (!hasLogin) {
      if (!mounted) {
        return;
      }
      final label = identity.provider == AccountProvider.riverSide
          ? '请先登录 RiverSide 账号'
          : '请先登录清水河畔账号';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final account = UserAccount(
      provider: identity.provider,
      username: identity.username,
      displayName: identity.displayName.isEmpty
          ? identity.username
          : identity.displayName,
      avatarUrl: '',
      userId: identity.userId,
    );
    final cookie = identity.provider == AccountProvider.riverSide
        ? widget.dependencies.accountStore.riverSideCookieHeaderFor(
            activeRiver ?? '',
          )
        : null;
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      riverPageRoute<void>(
        builder: (_) => RiverSideProfilePage(
          dependencies: widget.dependencies,
          account: account,
          cookieHeader: cookie,
        ),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) {
      return;
    }
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _QrScannerMaskPainter()),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                _GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: _torchEnabled
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  onTap: _toggleTorch,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _handlingResult ? '正在解析二维码...' : '将二维码放入框内自动识别',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (!widget.rawResultMode)
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _openIdentityQr,
                                    icon: const Icon(Icons.qr_code_2_rounded),
                                    label: const Text('我的身份二维码'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(44),
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              if (!widget.rawResultMode)
                                const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickingFromGallery
                                      ? null
                                      : _pickFromGallery,
                                  icon: _pickingFromGallery
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.photo_library_outlined,
                                        ),
                                  label: Text(
                                    _pickingFromGallery ? '识别中...' : '从图库识别',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.44,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MineIdentityQrPage extends StatefulWidget {
  const MineIdentityQrPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<MineIdentityQrPage> createState() => _MineIdentityQrPageState();
}

class _MineIdentityQrPageState extends State<MineIdentityQrPage> {
  static const List<_QrStylePreset> _styles = <_QrStylePreset>[
    _QrStylePreset(
      name: '流光',
      colors: <Color>[Color(0xFF12457A), Color(0xFF2174F1), Color(0xFF7CC8FF)],
      qrColor: Color(0xFF0F2A4A),
      eyeShape: QrEyeShape.square,
      moduleShape: QrDataModuleShape.square,
    ),
    _QrStylePreset(
      name: '晨雾',
      colors: <Color>[Color(0xFF6B7FA9), Color(0xFF8FB3E8), Color(0xFFD6E4FF)],
      qrColor: Color(0xFF1D3557),
      eyeShape: QrEyeShape.circle,
      moduleShape: QrDataModuleShape.square,
    ),
    _QrStylePreset(
      name: '活力',
      colors: <Color>[Color(0xFF2167B8), Color(0xFF5FA9F8), Color(0xFFA9D8FF)],
      qrColor: Color(0xFF0A2F5A),
      eyeShape: QrEyeShape.square,
      moduleShape: QrDataModuleShape.circle,
    ),
  ];

  late AccountProvider _provider;
  int _styleIndex = 0;

  UserAccount? get _riverAccount =>
      widget.dependencies.accountStore.activeRiverSideAccount;
  UserAccount? get _qingAccount =>
      widget.dependencies.accountStore.activeQingShuiHePanAccount;

  @override
  void initState() {
    super.initState();
    _provider =
        _qingAccount != null &&
            widget.dependencies.accountStore.activeRiverSideAccount == null
        ? AccountProvider.qingShuiHePan
        : AccountProvider.riverSide;
  }

  UserAccount? get _selectedAccount {
    if (_provider == AccountProvider.riverSide) {
      return _riverAccount;
    }
    return _qingAccount;
  }

  String _buildQrData(UserAccount account) {
    final query = <String, String>{
      'provider': account.provider == AccountProvider.riverSide
          ? 'riverside'
          : 'qingshuihepan',
      'username': account.username,
      'displayName': account.displayName,
    };
    if ((account.userId ?? 0) > 0) {
      query['userId'] = '${account.userId}';
    }
    return Uri(
      scheme: 'riverapp',
      host: 'profile',
      queryParameters: query,
    ).toString();
  }

  void _nextStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % _styles.length;
    });
  }

  Future<void> _copyQrData(String data) async {
    await Clipboard.setData(ClipboardData(text: data));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('身份链接已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedAccount;
    final style = _styles[_styleIndex];
    final hasBoth = _riverAccount != null && _qingAccount != null;

    return Scaffold(
      appBar: MineSettingsAppBar(
        title: '身份二维码',
        subtitle: '个性化展示与扫码跳转',
        icon: Icons.qr_code_2_rounded,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: '切换样式',
              onPressed: _selectedAccount == null ? null : _nextStyle,
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.06),
                      theme.colorScheme.surface,
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -30,
              child: _GlowBlob(
                size: 160,
                color: style.colors.first.withValues(alpha: 0.20),
              ),
            ),
            Positioned(
              bottom: 120,
              left: -48,
              child: _GlowBlob(
                size: 180,
                color: style.colors[1].withValues(alpha: 0.16),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                if (hasBoth)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ForumSwitchBar(
                      selected: _provider,
                      onChanged: (value) {
                        setState(() => _provider = value);
                      },
                    ),
                  ),
                if (selected == null)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Text(
                      _provider == AccountProvider.riverSide
                          ? '请先登录 RiverSide 账号'
                          : '请先登录清水河畔账号',
                    ),
                  )
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _IdentityQrCard(
                      key: ValueKey<String>(
                        '${selected.provider.name}-${selected.username}-$_styleIndex',
                      ),
                      account: selected,
                      style: style,
                      qrData: _buildQrData(selected),
                    ),
                  ),
                if (selected != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '样式主题',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _styles.length,
                      separatorBuilder: (_, unused) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = _styles[index];
                        final selectedStyle = index == _styleIndex;
                        return _QrStyleCard(
                          preset: item,
                          selected: selectedStyle,
                          onTap: () => setState(() => _styleIndex = index),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _nextStyle,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: Text('换一个 · ${style.name}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _copyQrData(_buildQrData(selected)),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('复制身份链接'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityQrCard extends StatelessWidget {
  const _IdentityQrCard({
    super.key,
    required this.account,
    required this.style,
    required this.qrData,
  });

  final UserAccount account;
  final _QrStylePreset style;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.colors,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: style.colors.first.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.88),
                backgroundImage: account.avatarUrl.isNotEmpty
                    ? NetworkImage(account.avatarUrl)
                    : null,
                child: account.avatarUrl.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${account.username}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  account.provider == AccountProvider.riverSide
                      ? 'RiverSide'
                      : '清水河畔',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              size: 236,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
              eyeStyle: QrEyeStyle(
                eyeShape: style.eyeShape,
                color: style.qrColor,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: style.moduleShape,
                color: style.qrColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '扫码即可跳转到我的个人主页',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.93),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _QrScannerMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cutout = 250.0;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: cutout,
      height: cutout,
    );

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.42);
    final path = Path()..addRect(Offset.zero & size);
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)));
    final finalPath = Path.combine(PathOperation.difference, path, cutoutPath);
    canvas.drawPath(finalPath, overlayPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannedIdentity {
  const _ScannedIdentity({
    required this.provider,
    required this.username,
    required this.displayName,
    required this.userId,
  });

  final AccountProvider provider;
  final String username;
  final String displayName;
  final int? userId;
}

class _ScannedMiniAppCode {
  const _ScannedMiniAppCode({
    required this.catalogUrl,
    required this.miniAppId,
    required this.projectId,
    required this.appCode,
    required this.route,
    required this.action,
    required this.params,
  });

  final String catalogUrl;
  final String miniAppId;
  final String projectId;
  final String appCode;
  final String route;
  final String action;
  final Map<String, dynamic> params;
}

class _OrbitResolveAttempt {
  const _OrbitResolveAttempt({required this.rawValue, required this.decoded});

  final String? rawValue;
  final bool decoded;
}

class _QrStylePreset {
  const _QrStylePreset({
    required this.name,
    required this.colors,
    required this.qrColor,
    required this.eyeShape,
    required this.moduleShape,
  });

  final String name;
  final List<Color> colors;
  final Color qrColor;
  final QrEyeShape eyeShape;
  final QrDataModuleShape moduleShape;
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}

class _ForumSwitchBar extends StatelessWidget {
  const _ForumSwitchBar({required this.selected, required this.onChanged});

  final AccountProvider selected;
  final ValueChanged<AccountProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ForumSwitchItem(
              active: selected == AccountProvider.riverSide,
              label: 'RiverSide',
              onTap: () => onChanged(AccountProvider.riverSide),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ForumSwitchItem(
              active: selected == AccountProvider.qingShuiHePan,
              label: '清水河畔',
              onTap: () => onChanged(AccountProvider.qingShuiHePan),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumSwitchItem extends StatelessWidget {
  const _ForumSwitchItem({
    required this.active,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _QrStyleCard extends StatelessWidget {
  const _QrStyleCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _QrStylePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 130,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: preset.colors
                  .map((c) => c.withValues(alpha: 0.84))
                  .toList(),
            ),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.32),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: preset.colors.first.withValues(alpha: 0.26),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preset.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  for (final c in preset.colors.take(3))
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.tune_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

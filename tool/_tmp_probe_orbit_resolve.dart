import 'dart:convert';
import 'dart:io';
import 'package:river/core/mini_apps/river_mini_app_orbit_code_codec.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : '../miniapp-orbit-code.png';
  final base = args.length > 1 ? args[1] : 'http://192.168.3.6:8080';
  final file = File(path);
  if (!await file.exists()) {
    print('file-not-found: $path');
    return;
  }
  final bytes = await file.readAsBytes();
  final cands = RiverMiniAppOrbitCodeCodec.decodeCandidatesFromImageBytes(bytes, maxCandidates: 20);
  print('candidates=${cands.length}');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  for (var i = 0; i < cands.length; i++) {
    final c = cands[i];
    final uri = Uri.parse('$base/api/public/orbit-code/resolve?id=${c.idHex}&checksum=${c.checksumHex}');
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      String mark = ok ? 'OK' : 'ERR';
      String msg = '';
      try {
        final m = jsonDecode(body);
        if (m is Map && m['message'] != null) msg = ' msg=${m['message']}';
        if (m is Map && m['data'] is Map && (m['data']['code'] ?? '').toString().isNotEmpty) {
          mark = 'HIT';
          msg = ' code=${(m['data']['code'] as String).substring(0, ((m['data']['code'] as String).length > 80 ? 80 : (m['data']['code'] as String).length))}';
        }
      } catch (_) {}
      print('#$i score=${c.score.toStringAsFixed(4)} rot=${c.rotationDeg.toStringAsFixed(1)} id=${c.idHex} cs=${c.checksumHex} => $mark(${resp.statusCode})$msg');
    } catch (e) {
      print('#$i score=${c.score.toStringAsFixed(4)} id=${c.idHex} cs=${c.checksumHex} => NET_ERR $e');
    }
  }
  client.close(force: true);
}

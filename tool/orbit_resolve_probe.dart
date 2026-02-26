import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:river/core/mini_apps/river_mini_app_orbit_code_codec.dart';

Future<void> main(List<String> args) async {
  final endpointBase = args.isNotEmpty
      ? args.first
      : 'http://127.0.0.1:8080/api/public/orbit-code/resolve';
  final files = args.length > 1
      ? args.sublist(1)
      : <String>['../test1.jpg', '../test2.jpg', '../miniapp-orbit-code.png'];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('MISS $path');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final cands = RiverMiniAppOrbitCodeCodec.decodeCandidatesFromImageBytes(
      bytes,
      maxCandidates: 20,
    );
    stdout.writeln('FILE $path candidates=${cands.length}');
    var hit = false;
    for (var i = 0; i < cands.length; i++) {
      final c = cands[i];
      final uri = Uri.parse(endpointBase).replace(
        queryParameters: <String, String>{
          'id': c.idHex,
          'checksum': c.checksumHex,
        },
      );
      try {
        final resp = await http
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          continue;
        }
        final root = jsonDecode(resp.body);
        if (root is! Map || root['success'] != true || root['data'] is! Map) {
          continue;
        }
        final code = '${(root['data'] as Map)['code'] ?? ''}'.trim();
        if (code.isEmpty) {
          continue;
        }
        stdout.writeln(
          '  HIT[$i] id=${c.idHex} ck=${c.checksumHex} score=${c.score.toStringAsFixed(4)} -> ${code.substring(0, code.length > 80 ? 80 : code.length)}',
        );
        hit = true;
        break;
      } catch (_) {
        // ignore timeout/network errors
      }
    }
    if (!hit) {
      stdout.writeln('  HIT none');
    }
  }
}

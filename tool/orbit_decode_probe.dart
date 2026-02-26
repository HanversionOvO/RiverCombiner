import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:river/core/mini_apps/river_mini_app_orbit_code_codec.dart';

void main(List<String> args) {
  final inputs = args.isEmpty
      ? <String>['../test1.jpg', '../test2.jpg', '../miniapp-orbit-code.png']
      : args;
  for (final path in inputs) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('MISS $path');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    stdout.writeln(
      'FILE $path bytes=${bytes.length} size=${decoded?.width}x${decoded?.height}',
    );
    final one = RiverMiniAppOrbitCodeCodec.decodeFromImageBytes(bytes);
    if (one != null) {
      stdout.writeln(
        'BEST id=${one.idHex} checksum=${one.checksumHex} score=${one.score.toStringAsFixed(4)} rot=${one.rotationDeg.toStringAsFixed(1)}',
      );
    } else {
      stdout.writeln('BEST null');
    }
    final all = RiverMiniAppOrbitCodeCodec.decodeCandidatesFromImageBytes(
      bytes,
      maxCandidates: 20,
    );
    stdout.writeln('CAND count=${all.length}');
    for (var i = 0; i < all.length && i < 5; i++) {
      final c = all[i];
      stdout.writeln(
        '  [$i] id=${c.idHex} ck=${c.checksumHex} score=${c.score.toStringAsFixed(4)} rot=${c.rotationDeg.toStringAsFixed(1)}',
      );
    }
  }
}

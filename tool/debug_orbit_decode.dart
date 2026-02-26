import 'dart:io';
import 'package:river/core/mini_apps/river_mini_app_orbit_code_codec.dart';

void main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : '../miniapp-orbit-code.png';
  final file = File(path);
  if (!await file.exists()) {
    print('file-not-found: $path');
    return;
  }
  final bytes = await file.readAsBytes();
  final decoded = RiverMiniAppOrbitCodeCodec.decodeFromImageBytes(bytes);
  if (decoded == null) {
    print('decode=null');
    return;
  }
  print('id=${decoded.idHex} checksum=${decoded.checksumHex} rot=${decoded.rotationDeg} score=${decoded.score}');
}

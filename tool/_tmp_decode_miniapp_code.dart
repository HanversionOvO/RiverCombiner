import 'dart:io';
import 'package:river/core/mini_apps/river_mini_app_code_image_codec.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/_tmp_decode_miniapp_code.dart <image...>');
    exit(1);
  }
  for (final path in args) {
    final file = File(path);
    if (!await file.exists()) {
      print('MISS $path');
      continue;
    }
    final bytes = await file.readAsBytes();
    final decoded = RiverMiniAppCodeImageCodec.decodeFromImageBytes(bytes);
    print('FILE $path');
    print(decoded ?? 'NULL');
    print('---');
  }
}

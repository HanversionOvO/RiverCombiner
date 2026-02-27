import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_settings_controller.dart';

class AppIconSwitcher {
  AppIconSwitcher._();

  static const MethodChannel _channel = MethodChannel('river/app_icon');

  static Future<bool> switchToPreset(AppAppIconPreset preset) async {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'switchIcon',
        <String, Object>{'preset': preset.name},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

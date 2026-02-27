import 'package:flutter/foundation.dart';
import 'package:flutter_dynamic_icon/flutter_dynamic_icon.dart';
import 'package:flutter/services.dart';
import 'package:river/app/app_settings_controller.dart';

class AppIconSwitcher {
  AppIconSwitcher._();

  static const MethodChannel _channel = MethodChannel('river/app_icon');

  static Future<bool> switchToPreset(AppAppIconPreset preset) async {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _switchOnIOS(preset);
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return _switchOnAndroid(preset);
  }

  static Future<bool> _switchOnAndroid(AppAppIconPreset preset) async {
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

  static Future<bool> _switchOnIOS(AppAppIconPreset preset) async {
    try {
      final supports = await FlutterDynamicIcon.supportsAlternateIcons;
      if (!supports) {
        return false;
      }
      await FlutterDynamicIcon.setAlternateIconName(_iosIconName(preset));
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static String? _iosIconName(AppAppIconPreset preset) {
    switch (preset) {
      case AppAppIconPreset.origin:
        return null;
      case AppAppIconPreset.quality:
        return 'AppIconQuality';
      case AppAppIconPreset.pixel:
        return 'AppIconPixel';
      case AppAppIconPreset.cloud:
        return 'AppIconCloud';
      case AppAppIconPreset.neon:
        return 'AppIconNeon';
      case AppAppIconPreset.vaporwave:
        return 'AppIconVaporwave';
      case AppAppIconPreset.china:
        return 'AppIconChina';
      case AppAppIconPreset.chengdu:
        return 'AppIconChengdu';
      case AppAppIconPreset.animation:
        return 'AppIconAnimation';
      case AppAppIconPreset.sweet:
        return 'AppIconSweet';
    }
  }
}

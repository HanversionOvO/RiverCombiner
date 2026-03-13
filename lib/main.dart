import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:motion/motion.dart';
import 'package:river/app/app.dart';
import 'package:toastification/toastification.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const ToastificationWrapper(child: RiverApp()));
  unawaited(_initializeMotionBridge());
}

Future<void> _initializeMotionBridge() async {
  try {
    await Motion.instance.initialize();
  } catch (_) {
    // Keep app startup resilient if motion sensor bridge is unavailable.
  }
}

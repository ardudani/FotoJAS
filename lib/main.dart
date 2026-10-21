import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'services/camera_service.dart';
import 'services/drive_service.dart';
import 'settings.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings();
  await settings.load();
  App.settings = settings;
  App.camera = CameraService(settings);
  App.drive = DriveService(settings);
  await App.drive.init();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'FotoJAS',
        size: Size(1280, 800),
        minimumSize: Size(800, 600),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
        if (settings.fullscreen) await windowManager.setFullScreen(true);
      },
    );
  }
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  try {
    await WakelockPlus.enable();
  } catch (_) {}

  runApp(const FotoJasApp());
  App.camera.init();
}

class FotoJasApp extends StatefulWidget {
  const FotoJasApp({super.key});

  @override
  State<FotoJasApp> createState() => _FotoJasAppState();
}

class _FotoJasAppState extends State<FotoJasApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.paused) {
      App.camera.release();
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (App.camera.controller == null) App.camera.init();
      App.drive.pump();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.settings,
      builder: (context, _) {
        final scheme = ColorScheme.fromSeed(
          seedColor: App.settings.accent,
          brightness: Brightness.dark,
        ).copyWith(primary: App.settings.accent);
        return MaterialApp(
          title: 'FotoJAS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            fontFamily: 'Montserrat',
            scaffoldBackgroundColor: const Color(0xFF0B0B10),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

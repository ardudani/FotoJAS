import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'services/camera_service.dart';
import 'services/drive_service.dart';
import 'services/log.dart';
import 'settings.dart';
import 'ui/home_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      AppLog.I.add('${d.exceptionAsString()}\n${d.stack.toString().split('\n').take(6).join('\n')}',
          error: true);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      AppLog.I.add('$e\n${st.toString().split('\n').take(6).join('\n')}', error: true);
      return true;
    };
    // En modo release los errores de dibujo salen como cajas grises: mejor verlos
    ErrorWidget.builder = (d) => Material(
          color: const Color(0xFF400000),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(d.exceptionAsString(),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        );
    runApp(const BootApp());
  }, (e, st) {
    AppLog.I.add('$e\n${st.toString().split('\n').take(6).join('\n')}', error: true);
  });
}

/// Arranque con pasos visibles: si algo se cuelga o falla se ve en pantalla.
class BootApp extends StatefulWidget {
  const BootApp({super.key});

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _step(String name, Future<void> Function() action,
      {int seconds = 8}) async {
    AppLog.I.add('$name…');
    try {
      await action().timeout(Duration(seconds: seconds));
      AppLog.I.add('$name: OK');
    } on TimeoutException {
      AppLog.I.add('$name: no responde (se continúa)', error: true);
    } catch (e) {
      AppLog.I.add('$name: $e', error: true);
    }
  }

  Future<void> _boot() async {
    AppLog.I.add('FotoJAS arrancando en ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    final settings = AppSettings();
    App.settings = settings;
    App.camera = CameraService(settings);
    App.drive = DriveService(settings);

    await _step('Cargar ajustes', settings.load);
    await _step('Cola de subidas', App.drive.init);
    if (Platform.isWindows) {
      await _step('Ventana', () async {
        await windowManager.ensureInitialized();
        await windowManager.setTitle('FotoJAS');
        await windowManager.show();
        if (settings.fullscreen) await windowManager.setFullScreen(true);
      });
    }
    if (Platform.isAndroid) {
      await _step('Pantalla completa',
          () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    }
    // No se espera: si tarda no debe bloquear el arranque
    WakelockPlus.enable().catchError((e) => AppLog.I.add('Pantalla siempre encendida: $e', error: true));

    if (!mounted) return;
    setState(() => _ready = true);
    AppLog.I.add('Abriendo cámara…');
    App.camera.init().then((_) {
      AppLog.I.add(App.camera.error ?? 'Cámara: OK (${App.camera.controller?.description.name})',
          error: App.camera.error != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const FotoJasApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Montserrat'),
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B10),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FotoJAS',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Expanded(
                  child: ListenableBuilder(
                    listenable: AppLog.I,
                    builder: (_, __) => ListView(
                      children: [
                        for (final l in AppLog.I.lines)
                          Text(l, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

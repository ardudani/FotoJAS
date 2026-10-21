import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../settings.dart';

/// Gestiona la cámara del dispositivo (una sola instancia para toda la app).
class CameraService extends ChangeNotifier {
  final AppSettings settings;
  List<CameraDescription> cameras = [];
  CameraController? controller;
  String? error;
  bool _initializing = false;

  CameraService(this.settings);

  bool get ready => controller?.value.isInitialized ?? false;

  static String describe(CameraDescription c) {
    final dir = switch (c.lensDirection) {
      CameraLensDirection.front => 'Frontal',
      CameraLensDirection.back => 'Trasera',
      CameraLensDirection.external => 'Externa',
    };
    return '$dir · ${c.name}';
  }

  ResolutionPreset get _preset => switch (settings.resolution) {
        'high' => ResolutionPreset.high,
        'ultraHigh' => ResolutionPreset.ultraHigh,
        'max' => ResolutionPreset.max,
        _ => ResolutionPreset.veryHigh,
      };

  Future<void> init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      error = null;
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        error = 'No se ha encontrado ninguna cámara';
        return;
      }
      var cam = cameras.where((c) => c.name == settings.cameraName).firstOrNull;
      cam ??= cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      cam ??= cameras.first;

      final old = controller;
      controller = null;
      notifyListeners();
      await old?.dispose();

      final c = CameraController(cam, _preset, enableAudio: false);
      await c.initialize();
      if (Platform.isAndroid) {
        try {
          await c.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      controller = c;
    } catch (e) {
      error = 'Error al abrir la cámara: $e';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> release() async {
    final c = controller;
    controller = null;
    notifyListeners();
    await c?.dispose();
  }

  Future<XFile> takePicture() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      throw Exception('La cámara no está lista');
    }
    return c.takePicture();
  }
}

/// Vista previa de la cámara que rellena todo el espacio disponible.
class CameraCover extends StatelessWidget {
  final CameraService camera;
  const CameraCover({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final c = camera.controller;
        if (c == null || !c.value.isInitialized) {
          return Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: camera.error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(camera.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  )
                : const CircularProgressIndicator(),
          );
        }
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        var ar = c.value.aspectRatio; // ancho/alto del sensor (horizontal)
        if (Platform.isAndroid && portrait) ar = 1 / ar;
        Widget preview = CameraPreview(c);
        if (camera.settings.mirrorPreview) {
          preview = Transform.flip(flipX: true, child: preview);
        }
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: 1000, height: 1000 / ar, child: preview),
          ),
        );
      },
    );
  }
}

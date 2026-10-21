import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/camera_service.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Pantalla de inicio: vista previa de la cámara y botones para empezar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openSettings(BuildContext context) async {
    if (await askPin(context)) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
  }

  void _start(BuildContext context, int count) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => CaptureScreen(count: count),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([s, App.drive]),
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          final scale = (size.shortestSide / 600).clamp(0.7, 1.6).toDouble();
          final title = s.titleText.trim().isEmpty ? s.eventName : s.titleText;
          return Stack(
            fit: StackFit.expand,
            children: [
              CameraCover(camera: App.camera),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x22000000), Color(0xCC000000)],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24 * scale),
                  child: Column(
                    children: [
                      SizedBox(height: 12 * scale),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontFamily: s.fontFamily,
                          fontSize: 64 * scale,
                          color: Colors.white,
                          shadows: const [Shadow(blurRadius: 16, color: Colors.black54)],
                        ),
                      ),
                      if (s.subtitleText.trim().isNotEmpty)
                        Text(
                          s.subtitleText.toUpperCase(),
                          style: TextStyle(
                            fontSize: 16 * scale,
                            letterSpacing: 4,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        s.welcomeText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30 * scale,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
                        ),
                      ),
                      SizedBox(height: 24 * scale),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 24 * scale,
                        runSpacing: 16 * scale,
                        children: [
                          if (s.enableSingle)
                            BigButton(
                              icon: Icons.photo_camera_rounded,
                              label: 'FOTO',
                              scale: scale,
                              onTap: () => _start(context, 1),
                            ),
                          if (s.enableCollage)
                            BigButton(
                              icon: Icons.grid_view_rounded,
                              label: 'COLLAGE · ${s.collageCount} FOTOS',
                              scale: scale,
                              onTap: () => _start(context, s.collageCount),
                            ),
                          if (!s.enableSingle && !s.enableCollage)
                            BigButton(
                              icon: Icons.photo_camera_rounded,
                              label: 'EMPEZAR',
                              scale: scale,
                              onTap: () => _start(context, 1),
                            ),
                        ],
                      ),
                      SizedBox(height: 12 * scale),
                    ],
                  ),
                ),
              ),
              // Indicadores discretos para el operador
              Positioned(
                left: 12,
                bottom: 8,
                child: SafeArea(
                  child: Text(
                    [
                      if (s.printEnabled && s.maxTotalPrints > 0)
                        'Impresiones: ${s.printedCount}/${s.maxTotalPrints}',
                      if (s.driveEnabled && App.drive.pendingCount > 0)
                        'Pendientes de subir: ${App.drive.pendingCount}',
                    ].join('   ·   '),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ),
              // Esquina oculta: mantener pulsado para abrir ajustes
              Positioned(
                top: 0,
                right: 0,
                width: 90,
                height: 90,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPress: () => _openSettings(context),
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(Icons.settings, color: Colors.white10, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/camera_service.dart';
import '../services/composer.dart';
import 'review_screen.dart';
import 'widgets.dart';

/// Cuenta atrás y captura de una o varias fotos.
class CaptureScreen extends StatefulWidget {
  final int count;
  const CaptureScreen({super.key, required this.count});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  int _shot = 0;
  int? _countdown;
  bool _smile = false;
  bool _flash = false;
  bool _processing = false;
  final List<String> _paths = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    final s = App.settings;
    await _wait(600);
    for (var i = 0; i < widget.count; i++) {
      if (!mounted) return;
      setState(() {
        _shot = i;
        _smile = false;
      });
      for (var c = s.countdown; c >= 1; c--) {
        if (!mounted) return;
        setState(() => _countdown = c);
        await _wait(1000);
      }
      if (!mounted) return;
      setState(() {
        _countdown = null;
        _smile = true;
      });
      try {
        final x = await App.camera.takePicture();
        _paths.add(x.path);
      } catch (e) {
        if (!mounted) return;
        await _fail('No se pudo hacer la foto: $e');
        return;
      }
      if (!mounted) return;
      setState(() {
        _flash = true;
        _smile = false;
      });
      await _wait(180);
      if (!mounted) return;
      setState(() => _flash = false);
      if (i < widget.count - 1) await _wait(s.betweenShots * 1000);
    }
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final images = <ui.Image>[];
      for (final p in _paths) {
        images.add(await Composer.loadFile(p));
      }
      final jpeg = await Composer.composeJpeg(images, s);
      for (final im in images) {
        im.dispose();
      }
      for (final p in _paths) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => ReviewScreen(jpeg: jpeg, count: widget.count),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    } catch (e) {
      await _fail('Error al montar la foto: $e');
    }
  }

  Future<void> _fail(String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ups…'),
        content: Text(msg),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver'))],
      ),
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = (size.shortestSide / 600).clamp(0.7, 1.6).toDouble();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraCover(camera: App.camera),
          if (widget.count > 1)
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      'Foto ${_shot + 1} de ${widget.count}',
                      style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: Tween(begin: 1.6, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: _countdown != null
                  ? Text(
                      '$_countdown',
                      key: ValueKey('c$_countdown$_shot'),
                      style: TextStyle(
                        fontSize: 220 * scale,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: const [Shadow(blurRadius: 30, color: Colors.black87)],
                      ),
                    )
                  : _smile
                      ? Text(
                          '¡Sonríe!',
                          key: ValueKey('s$_shot'),
                          style: TextStyle(
                            fontSize: 90 * scale,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: const [Shadow(blurRadius: 30, color: Colors.black87)],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
          if (_paths.isNotEmpty && widget.count > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final p in _paths)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.file(File(p),
                              width: 110 * scale, height: 80 * scale, fit: BoxFit.cover,
                              cacheWidth: 300),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flash ? 1 : 0,
              duration: Duration(milliseconds: _flash ? 40 : 300),
              child: Container(color: Colors.white),
            ),
          ),
          if (_processing)
            DarkBackdrop(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text('Preparando tu foto…',
                        style: TextStyle(fontSize: 26 * scale, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

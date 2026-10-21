import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/drive_service.dart';
import '../services/printer_service.dart';
import '../services/storage.dart';
import 'capture_screen.dart';
import 'qr_screen.dart';
import 'widgets.dart';

/// Muestra la foto montada y pregunta si gusta o se repite.
class ReviewScreen extends StatefulWidget {
  final Uint8List jpeg;
  final int count;
  const ReviewScreen({super.key, required this.jpeg, required this.count});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _saving = false;

  void _retake() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => CaptureScreen(count: widget.count),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  Future<void> _accept() async {
    final s = App.settings;
    setState(() => _saving = true);
    var upload = s.driveEnabled;
    if (upload && s.askConsent) {
      upload = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Galería online'),
              content: const Text(
                  '¿Aceptas que esta foto se suba a la galería online del evento para poder descargarla con el código QR?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, acepto')),
              ],
            ),
          ) ??
          false;
    }
    File? file;
    UploadJob? job;
    try {
      file = await Storage.savePhoto(s.eventName, widget.jpeg);
      if (upload) job = App.drive.enqueue(file.path, s.eventName);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => ActionsScreen(jpeg: widget.jpeg, job: job),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = (size.shortestSide / 600).clamp(0.7, 1.6).toDouble();
    final wide = size.width > size.height;
    final buttons = [
      BigButton(
        icon: Icons.replay_rounded,
        label: 'REPETIR',
        filled: false,
        scale: scale,
        onTap: _saving ? null : _retake,
      ),
      SizedBox(width: 20 * scale, height: 20 * scale),
      BigButton(
        icon: Icons.favorite_rounded,
        label: '¡ME GUSTA!',
        scale: scale,
        onTap: _saving ? null : _accept,
      ),
    ];
    return Scaffold(
      body: IdleGuard(
        child: DarkBackdrop(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24 * scale),
              child: Column(
                children: [
                  Text('¿Te gusta?',
                      style: TextStyle(fontSize: 40 * scale, fontWeight: FontWeight.w800)),
                  SizedBox(height: 16 * scale),
                  Expanded(child: Center(child: PhotoCard(image: MemoryImage(widget.jpeg)))),
                  SizedBox(height: 24 * scale),
                  wide
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons)
                      : Column(mainAxisSize: MainAxisSize.min, children: buttons),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Imprimir, ver QR o terminar.
class ActionsScreen extends StatefulWidget {
  final Uint8List jpeg;
  final UploadJob? job;
  const ActionsScreen({super.key, required this.jpeg, this.job});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  int _copies = 1;
  bool _printing = false;
  bool _printed = false;

  int get _maxCopies {
    final s = App.settings;
    return s.maxCopies.clamp(1, 99).clamp(0, s.remainingPrints).toInt();
  }

  Future<void> _print() async {
    final s = App.settings;
    final copies = _copies.clamp(1, _maxCopies).toInt();
    setState(() => _printing = true);
    try {
      await PrinterService.printPhoto(widget.jpeg, copies, s);
      await s.update((x) => x.printedCount += copies);
      if (!mounted) return;
      setState(() {
        _printing = false;
        _printed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _printing = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No se pudo imprimir'),
          content: Text('Avisa al responsable del fotomatón.\n\n$e'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vale'))],
        ),
      );
    }
  }

  void _qr() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QrScreen(job: widget.job, event: App.settings.eventName),
    ));
  }

  void _finish() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    final size = MediaQuery.sizeOf(context);
    final scale = (size.shortestSide / 600).clamp(0.7, 1.6).toDouble();
    final wide = size.width > size.height;
    final maxCopies = _maxCopies;
    final canPrint = s.printEnabled && maxCopies > 0;
    final hasQr = s.driveEnabled &&
        (widget.job != null || App.drive.galleryUrlFor(s.eventName) != null);

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.printEnabled) ...[
          if (_printed)
            Padding(
              padding: EdgeInsets.only(bottom: 16 * scale),
              child: Column(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 64 * scale),
                  SizedBox(height: 8 * scale),
                  Text('¡Imprimiendo!\nRecoge tu foto en la impresora',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else if (!canPrint)
            Padding(
              padding: EdgeInsets.only(bottom: 16 * scale),
              child: Text('Se han agotado las impresiones de este evento',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18 * scale, color: Colors.white70)),
            )
          else ...[
            if (maxCopies > 1)
              Padding(
                padding: EdgeInsets.only(bottom: 16 * scale),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Copias', style: TextStyle(fontSize: 22 * scale)),
                    SizedBox(width: 16 * scale),
                    IconButton.filledTonal(
                      iconSize: 32 * scale,
                      onPressed: _copies > 1 && !_printing ? () => setState(() => _copies--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 60 * scale,
                      child: Text('$_copies',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 36 * scale, fontWeight: FontWeight.w800)),
                    ),
                    IconButton.filledTonal(
                      iconSize: 32 * scale,
                      onPressed: _copies < maxCopies && !_printing
                          ? () => setState(() => _copies++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            _printing
                ? Padding(
                    padding: EdgeInsets.all(16 * scale),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      SizedBox(width: 16 * scale),
                      Text('Enviando a la impresora…', style: TextStyle(fontSize: 20 * scale)),
                    ]),
                  )
                : BigButton(
                    icon: Icons.print_rounded,
                    label: 'IMPRIMIR',
                    scale: scale,
                    onTap: _print,
                  ),
            SizedBox(height: 16 * scale),
          ],
        ],
        if (hasQr) ...[
          BigButton(
            icon: Icons.qr_code_2_rounded,
            label: 'VER QR',
            filled: !s.printEnabled || _printed || !canPrint,
            scale: scale,
            onTap: _printing ? null : _qr,
          ),
          SizedBox(height: 16 * scale),
        ],
        TextButton.icon(
          onPressed: _printing ? null : _finish,
          icon: const Icon(Icons.check_rounded, color: Colors.white70),
          label: Text('Terminar',
              style: TextStyle(fontSize: 20 * scale, color: Colors.white70)),
        ),
      ],
    );

    final photo = PhotoCard(image: MemoryImage(widget.jpeg));
    return Scaffold(
      body: IdleGuard(
        seconds: _printed ? 25 : null,
        key: ValueKey(_printed),
        child: DarkBackdrop(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24 * scale),
              child: wide
                  ? Row(children: [
                      Expanded(child: Center(child: photo)),
                      SizedBox(width: 32 * scale),
                      Expanded(child: Center(child: SingleChildScrollView(child: controls))),
                    ])
                  : Column(children: [
                      Expanded(child: Center(child: photo)),
                      SizedBox(height: 24 * scale),
                      controls,
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

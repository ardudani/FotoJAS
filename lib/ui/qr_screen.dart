import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../services/drive_service.dart';
import 'widgets.dart';

/// Muestra el QR de la foto y/o de la galería del evento.
class QrScreen extends StatelessWidget {
  final UploadJob? job;
  final String event;
  const QrScreen({super.key, required this.job, required this.event});

  Widget _qrCard(String label, String url, double size, double scale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(14 * scale),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: QrImageView(
            data: url,
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
          ),
        ),
        SizedBox(height: 12 * scale),
        Text(label, style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    final size = MediaQuery.sizeOf(context);
    final scale = (size.shortestSide / 600).clamp(0.7, 1.6).toDouble();
    return Scaffold(
      body: IdleGuard(
        child: DarkBackdrop(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: App.drive,
              builder: (context, _) {
                final showPhoto = s.qrMode != 'gallery';
                final showGallery = s.qrMode != 'photo';
                final photoUrl = job?.fileUrl;
                final galleryUrl = App.drive.galleryUrlFor(event);
                final uploading = job != null &&
                    job!.status != UploadStatus.done &&
                    job!.error == null;
                final failed = job != null && job!.status != UploadStatus.done && job!.error != null;

                final cards = <Widget>[];
                final both = showPhoto && showGallery && photoUrl != null && galleryUrl != null;
                final qrSize = (size.shortestSide * (both ? 0.32 : 0.45)).clamp(160.0, 520.0);
                if (showPhoto && photoUrl != null) {
                  cards.add(_qrCard('Tu foto', photoUrl, qrSize, scale));
                }
                if (showGallery && galleryUrl != null) {
                  cards.add(_qrCard('Galería del evento', galleryUrl, qrSize, scale));
                }
                // Si solo se quería la foto y no hay conexión, ofrecemos la galería
                if (cards.isEmpty && failed && galleryUrl != null) {
                  cards.add(_qrCard('Galería del evento', galleryUrl, qrSize, scale));
                }

                String? message;
                if (showPhoto && uploading) {
                  message = 'Subiendo tu foto…';
                } else if (showPhoto && failed) {
                  message = 'Ahora mismo no hay conexión.\nTu foto se subirá a la galería en cuanto vuelva internet.';
                } else if (cards.isEmpty) {
                  message = 'La galería todavía no está disponible.';
                }

                return Padding(
                  padding: EdgeInsets.all(24 * scale),
                  child: Column(
                    children: [
                      Text('Escanea con tu móvil',
                          style: TextStyle(fontSize: 36 * scale, fontWeight: FontWeight.w800)),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (cards.isNotEmpty)
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 48 * scale,
                                    runSpacing: 24 * scale,
                                    children: cards,
                                  ),
                                if (message != null) ...[
                                  SizedBox(height: 24 * scale),
                                  if (uploading) const CircularProgressIndicator(),
                                  SizedBox(height: 16 * scale),
                                  Text(message,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 20 * scale, color: Colors.white70)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 20 * scale,
                        runSpacing: 12 * scale,
                        alignment: WrapAlignment.center,
                        children: [
                          BigButton(
                            icon: Icons.arrow_back_rounded,
                            label: 'VOLVER',
                            filled: false,
                            scale: scale,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          BigButton(
                            icon: Icons.check_rounded,
                            label: 'TERMINAR',
                            scale: scale,
                            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

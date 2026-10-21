import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../settings.dart';
import 'composer.dart';
import 'ipp.dart';

/// Envía la foto final a la impresora según el método configurado.
class PrinterService {
  static final PdfPageFormat photo10x15 = PdfPageFormat(
      4 * PdfPageFormat.inch, 6 * PdfPageFormat.inch,
      marginAll: 0);

  static Future<Uint8List> buildPdf(Uint8List portraitJpeg) async {
    final doc = pw.Document(title: 'FotoJAS');
    final image = pw.MemoryImage(portraitJpeg);
    doc.addPage(pw.Page(
      pageFormat: photo10x15,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Image(image, fit: pw.BoxFit.cover),
      ),
    ));
    return doc.save();
  }

  /// Imprime [copies] copias. Lanza una excepción con mensaje legible si falla.
  static Future<void> printPhoto(Uint8List jpeg, int copies, AppSettings s) async {
    final portrait = await compute(ensurePortraitJpeg, jpeg);
    switch (s.printMethod) {
      case 'system':
        if (!Platform.isWindows && !Platform.isMacOS) {
          throw Exception(
              'La impresión silenciosa con impresora del sistema solo funciona en Windows. Usa "Directo por red (IPP)".');
        }
        final printers = await Printing.listPrinters();
        if (printers.isEmpty) throw Exception('No hay impresoras instaladas en Windows');
        final printer = printers.firstWhere(
          (p) => p.name == s.systemPrinterName,
          orElse: () => printers.firstWhere((p) => p.isDefault, orElse: () => printers.first),
        );
        final pdf = await buildPdf(portrait);
        for (var i = 0; i < copies; i++) {
          final ok = await Printing.directPrintPdf(
            printer: printer,
            name: 'FotoJAS',
            format: photo10x15,
            onLayout: (_) async => pdf,
          );
          if (!ok) throw Exception('Windows no pudo enviar el trabajo a ${printer.name}');
        }
        break;
      case 'dialog':
        final pdf = await buildPdf(portrait);
        await Printing.layoutPdf(
          name: 'FotoJAS',
          format: photo10x15,
          onLayout: (_) async => pdf,
        );
        break;
      default:
        if (s.printerIp.trim().isEmpty) {
          throw Exception('Falta la IP de la impresora en Ajustes');
        }
        final client = IppClient(s.printerIp.trim(), path: s.ippPath.trim().isEmpty ? '/ipp/print' : s.ippPath.trim());
        await client.printJpeg(
          portrait,
          copies: copies,
          borderless: s.borderless,
          mediaType: s.mediaType,
          mediaSource: s.mediaSource,
          quality: s.printQuality,
        );
    }
  }
}

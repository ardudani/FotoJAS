import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../settings.dart';

/// Monta las fotos en una hoja 10x15 (300 ppp) con texto y marco.
class Composer {
  static const int longSide = 1800; // 6" a 300 ppp
  static const int shortSide = 1200; // 4" a 300 ppp

  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<ui.Image> loadFile(String path) async =>
      decode(await File(path).readAsBytes());

  static Future<ui.Image?> loadFrame(AppSettings s) async {
    final path = s.framePath;
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      return await decode(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// Rectángulos (normalizados 0..1) de cada foto según la cantidad.
  static List<ui.Rect> _layout(int n, bool portrait) {
    switch (n) {
      case 1:
        return const [ui.Rect.fromLTWH(0, 0, 1, 1)];
      case 2:
        return portrait
            ? const [ui.Rect.fromLTWH(0, 0, 1, .5), ui.Rect.fromLTWH(0, .5, 1, .5)]
            : const [ui.Rect.fromLTWH(0, 0, .5, 1), ui.Rect.fromLTWH(.5, 0, .5, 1)];
      case 3:
        return portrait
            ? const [
                ui.Rect.fromLTWH(0, 0, 1, .5),
                ui.Rect.fromLTWH(0, .5, .5, .5),
                ui.Rect.fromLTWH(.5, .5, .5, .5),
              ]
            : const [
                ui.Rect.fromLTWH(0, 0, .5, 1),
                ui.Rect.fromLTWH(.5, 0, .5, .5),
                ui.Rect.fromLTWH(.5, .5, .5, .5),
              ];
      default:
        return const [
          ui.Rect.fromLTWH(0, 0, .5, .5),
          ui.Rect.fromLTWH(.5, 0, .5, .5),
          ui.Rect.fromLTWH(0, .5, .5, .5),
          ui.Rect.fromLTWH(.5, .5, .5, .5),
        ];
    }
  }

  static void _drawCover(ui.Canvas c, ui.Image image, ui.Rect dst,
      {int quarterTurns = 0, bool mirror = false, double radius = 0}) {
    c.save();
    if (radius > 0) {
      c.clipRRect(ui.RRect.fromRectAndRadius(dst, ui.Radius.circular(radius)));
    } else {
      c.clipRect(dst);
    }
    c.translate(dst.center.dx, dst.center.dy);
    if (mirror) c.scale(-1, 1);
    c.rotate(quarterTurns * math.pi / 2);
    final odd = quarterTurns.isOdd;
    final bw = odd ? dst.height : dst.width;
    final bh = odd ? dst.width : dst.height;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = math.max(bw / iw, bh / ih);
    final sw = bw / scale;
    final sh = bh / scale;
    final src = ui.Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
    c.drawImageRect(
      image,
      src,
      ui.Rect.fromCenter(center: ui.Offset.zero, width: bw, height: bh),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    c.restore();
  }

  static ui.Paragraph _paragraph(String text, String family, double size,
      int color, double maxWidth,
      {double letterSpacing = 0, ui.FontWeight? weight}) {
    ui.Paragraph build(double fs) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
      ))
        ..pushStyle(ui.TextStyle(
          color: ui.Color(color),
          fontFamily: family,
          fontSize: fs,
          letterSpacing: letterSpacing * fs,
          fontWeight: weight,
        ))
        ..addText(text);
      return pb.build()..layout(const ui.ParagraphConstraints(width: 100000));
    }

    var fs = size;
    var p = build(fs);
    while (p.maxIntrinsicWidth > maxWidth && fs > 12) {
      fs *= 0.92;
      p = build(fs);
    }
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(
        color: ui.Color(color),
        fontFamily: family,
        fontSize: fs,
        letterSpacing: letterSpacing * fs,
        fontWeight: weight,
      ))
      ..addText(text);
    return pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  /// Dibuja la composición y devuelve la imagen (sin codificar).
  static Future<ui.Image> composeImage(List<ui.Image> photos, AppSettings s,
      {ui.Image? frame}) async {
    final portrait = s.isPortrait;
    final w = portrait ? shortSide : longSide;
    final h = portrait ? longSide : shortSide;
    final wd = w.toDouble();
    final hd = h.toDouble();

    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, wd, hd));
    c.drawRect(ui.Rect.fromLTWH(0, 0, wd, hd), ui.Paint()..color = ui.Color(s.bgColor));

    final margin = math.min(wd, hd) * 0.04;
    final gap = margin * 0.6;
    final hasText = s.showText &&
        (s.titleText.trim().isNotEmpty || s.subtitleText.trim().isNotEmpty);
    final footer = hasText ? hd * (portrait ? 0.16 : 0.18) : 0.0;

    final area = ui.Rect.fromLTRB(
        margin, margin, wd - margin, hd - margin - (hasText ? footer - margin * 0.5 : 0));
    final expanded = area.inflate(gap / 2);
    final slots = _layout(photos.length.clamp(1, 4), portrait);
    final turns = (s.extraRotation ~/ 90) % 4;
    for (var i = 0; i < slots.length && i < photos.length; i++) {
      final n = slots[i];
      final r = ui.Rect.fromLTWH(
        expanded.left + n.left * expanded.width,
        expanded.top + n.top * expanded.height,
        n.width * expanded.width,
        n.height * expanded.height,
      ).deflate(gap / 2);
      _drawCover(c, photos[i], r,
          quarterTurns: turns,
          mirror: s.mirrorPhoto,
          radius: s.roundedPhotos ? margin * 0.45 : 0);
    }

    if (hasText) {
      final top = hd - footer - margin * 0.2;
      final maxW = wd - margin * 4;
      final title = s.titleText.trim();
      final sub = s.subtitleText.trim();
      final paras = <ui.Paragraph>[];
      if (title.isNotEmpty) {
        paras.add(_paragraph(title, s.fontFamily,
            footer * (sub.isEmpty ? 0.55 : 0.45), s.textColor, maxW));
      }
      if (sub.isNotEmpty) {
        paras.add(_paragraph(sub.toUpperCase(), 'Montserrat', footer * 0.13,
            s.subtitleColor, maxW,
            letterSpacing: 0.18, weight: ui.FontWeight.w500));
      }
      final spacing = footer * 0.02;
      final total = paras.fold<double>(0, (a, p) => a + p.height) +
          spacing * (paras.length - 1);
      var y = top + (footer - total) / 2;
      for (final p in paras) {
        c.drawParagraph(p, ui.Offset((wd - maxW) / 2, y));
        y += p.height + spacing;
      }
    }

    if (frame != null) {
      c.drawImageRect(
        frame,
        ui.Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, wd, hd),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    }

    final picture = rec.endRecording();
    return picture.toImage(w, h);
  }

  /// Composición final codificada como JPEG.
  static Future<Uint8List> composeJpeg(List<ui.Image> photos, AppSettings s) async {
    final frame = await loadFrame(s);
    final image = await composeImage(photos, s, frame: frame);
    return toJpeg(image);
  }

  static Future<Uint8List> toJpeg(ui.Image image, {int quality = 93}) async {
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) throw Exception('No se pudo leer la imagen');
    final rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    return compute(_encodeJpeg, _EncodeArgs(image.width, image.height, rgba, quality));
  }

  /// Imágenes grises de ejemplo para la vista previa del diseño.
  static Future<List<ui.Image>> placeholders(int n) async {
    final out = <ui.Image>[];
    const colors = [0xFF8EC5FC, 0xFFE0C3FC, 0xFFFFD3A5, 0xFFA8E6CF];
    for (var i = 0; i < n; i++) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      const r = ui.Rect.fromLTWH(0, 0, 1600, 1200);
      c.drawRect(
          r,
          ui.Paint()
            ..shader = ui.Gradient.linear(r.topLeft, r.bottomRight,
                [ui.Color(colors[i % 4]), const ui.Color(0xFF555566)]));
      final p = _paragraph('FOTO ${i + 1}', 'Montserrat', 160, 0xCCFFFFFF, 1500,
          weight: ui.FontWeight.w700);
      c.drawParagraph(p, ui.Offset(50, 600 - p.height / 2));
      out.add(await rec.endRecording().toImage(1600, 1200));
    }
    return out;
  }
}

class _EncodeArgs {
  final int w;
  final int h;
  final Uint8List rgba;
  final int quality;
  _EncodeArgs(this.w, this.h, this.rgba, this.quality);
}

Uint8List _encodeJpeg(_EncodeArgs a) {
  final im = img.Image.fromBytes(
    width: a.w,
    height: a.h,
    bytes: a.rgba.buffer,
    bytesOffset: a.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(im, quality: a.quality);
}

/// Gira a vertical (para papel 10x15) si la imagen es horizontal.
Uint8List ensurePortraitJpeg(Uint8List jpeg) {
  final im = img.decodeJpg(jpeg);
  if (im == null) return jpeg;
  if (im.width <= im.height) return jpeg;
  final rotated = img.copyRotate(im, angle: 90);
  return img.encodeJpg(rotated, quality: 95);
}

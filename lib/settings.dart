import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'services/storage.dart';

/// Toda la configuración de la app. Se guarda como JSON en ajustes.json.
class AppSettings extends ChangeNotifier {
  // ---------- Evento ----------
  String eventName = 'Mi evento';
  String titleText = '¡Gracias por venir!';
  String subtitleText = '';
  String welcomeText = '¡Hazte una foto!';
  bool showText = true;
  String fontFamily = 'GreatVibes';
  int textColor = 0xFF2B2B2B;
  int subtitleColor = 0xFF6B6B6B;
  int bgColor = 0xFFFFFFFF;
  int accentColor = 0xFFE0457B;

  // ---------- Diseño ----------
  /// 'portrait' (10x15 vertical) o 'landscape' (15x10 horizontal)
  String orientation = 'portrait';
  bool enableSingle = true;
  bool enableCollage = true;
  int collageCount = 4; // 2..4
  bool roundedPhotos = true;
  String? framePath; // PNG con transparencia que se pinta encima

  // ---------- Cámara ----------
  String? cameraName;
  String resolution = 'veryHigh'; // high | veryHigh | ultraHigh | max
  bool mirrorPreview = false;
  bool mirrorPhoto = false;
  int extraRotation = 0; // 0, 90, 180, 270
  int countdown = 3;
  int betweenShots = 2;

  // ---------- Impresión ----------
  bool printEnabled = true;
  /// 'ipp' = directo a la impresora por red (Android y Windows, sin diálogo)
  /// 'system' = impresora instalada en Windows (sin diálogo)
  /// 'dialog' = diálogo de impresión del sistema
  String printMethod = 'ipp';
  String printerIp = '';
  String ippPath = '/ipp/print';
  bool borderless = true;
  String mediaType = 'photographic-glossy';
  String mediaSource = 'auto';
  int printQuality = 5; // 3 borrador, 4 normal, 5 alta
  String systemPrinterName = '';
  int maxCopies = 2;
  int maxTotalPrints = 0; // 0 = sin límite
  int printedCount = 0;

  // ---------- Drive / QR ----------
  bool driveEnabled = false;
  String scriptUrl = '';
  String scriptSecret = '';
  String qrMode = 'both'; // photo | gallery | both
  bool askConsent = false;

  // ---------- Sistema ----------
  String pin = '1234';
  int idleTimeout = 60;
  bool fullscreen = true;

  Color get accent => Color(accentColor);
  bool get isPortrait => orientation == 'portrait';
  int get remainingPrints =>
      maxTotalPrints <= 0 ? 1 << 30 : (maxTotalPrints - printedCount).clamp(0, 1 << 30);

  Map<String, dynamic> toJson() => {
        'eventName': eventName,
        'titleText': titleText,
        'subtitleText': subtitleText,
        'welcomeText': welcomeText,
        'showText': showText,
        'fontFamily': fontFamily,
        'textColor': textColor,
        'subtitleColor': subtitleColor,
        'bgColor': bgColor,
        'accentColor': accentColor,
        'orientation': orientation,
        'enableSingle': enableSingle,
        'enableCollage': enableCollage,
        'collageCount': collageCount,
        'roundedPhotos': roundedPhotos,
        'framePath': framePath,
        'cameraName': cameraName,
        'resolution': resolution,
        'mirrorPreview': mirrorPreview,
        'mirrorPhoto': mirrorPhoto,
        'extraRotation': extraRotation,
        'countdown': countdown,
        'betweenShots': betweenShots,
        'printEnabled': printEnabled,
        'printMethod': printMethod,
        'printerIp': printerIp,
        'ippPath': ippPath,
        'borderless': borderless,
        'mediaType': mediaType,
        'mediaSource': mediaSource,
        'printQuality': printQuality,
        'systemPrinterName': systemPrinterName,
        'maxCopies': maxCopies,
        'maxTotalPrints': maxTotalPrints,
        'printedCount': printedCount,
        'driveEnabled': driveEnabled,
        'scriptUrl': scriptUrl,
        'scriptSecret': scriptSecret,
        'qrMode': qrMode,
        'askConsent': askConsent,
        'pin': pin,
        'idleTimeout': idleTimeout,
        'fullscreen': fullscreen,
      };

  void _fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T def) {
      final x = j[k];
      return x is T ? x : def;
    }

    eventName = v('eventName', eventName);
    titleText = v('titleText', titleText);
    subtitleText = v('subtitleText', subtitleText);
    welcomeText = v('welcomeText', welcomeText);
    showText = v('showText', showText);
    fontFamily = v('fontFamily', fontFamily);
    textColor = v('textColor', textColor);
    subtitleColor = v('subtitleColor', subtitleColor);
    bgColor = v('bgColor', bgColor);
    accentColor = v('accentColor', accentColor);
    orientation = v('orientation', orientation);
    enableSingle = v('enableSingle', enableSingle);
    enableCollage = v('enableCollage', enableCollage);
    collageCount = v('collageCount', collageCount);
    roundedPhotos = v('roundedPhotos', roundedPhotos);
    framePath = j['framePath'] as String?;
    cameraName = j['cameraName'] as String?;
    resolution = v('resolution', resolution);
    mirrorPreview = v('mirrorPreview', mirrorPreview);
    mirrorPhoto = v('mirrorPhoto', mirrorPhoto);
    extraRotation = v('extraRotation', extraRotation);
    countdown = v('countdown', countdown);
    betweenShots = v('betweenShots', betweenShots);
    printEnabled = v('printEnabled', printEnabled);
    printMethod = v('printMethod', printMethod);
    printerIp = v('printerIp', printerIp);
    ippPath = v('ippPath', ippPath);
    borderless = v('borderless', borderless);
    mediaType = v('mediaType', mediaType);
    mediaSource = v('mediaSource', mediaSource);
    printQuality = v('printQuality', printQuality);
    systemPrinterName = v('systemPrinterName', systemPrinterName);
    maxCopies = v('maxCopies', maxCopies);
    maxTotalPrints = v('maxTotalPrints', maxTotalPrints);
    printedCount = v('printedCount', printedCount);
    driveEnabled = v('driveEnabled', driveEnabled);
    scriptUrl = v('scriptUrl', scriptUrl);
    scriptSecret = v('scriptSecret', scriptSecret);
    qrMode = v('qrMode', qrMode);
    askConsent = v('askConsent', askConsent);
    pin = v('pin', pin);
    idleTimeout = v('idleTimeout', idleTimeout);
    fullscreen = v('fullscreen', fullscreen);
  }

  static Future<File> _file() async =>
      File(p.join((await Storage.supportDir()).path, 'ajustes.json'));

  Future<void> load() async {
    final f = await _file();
    if (!await f.exists()) return;
    try {
      _fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // Si el archivo principal está dañado, prueba con la copia
      final bak = File('${f.path}.bak');
      if (await bak.exists()) {
        _fromJson(jsonDecode(await bak.readAsString()) as Map<String, dynamic>);
      }
    }
  }

  Future<void>? _saving;
  bool _dirty = false;

  /// Guarda en disco. Nunca lanza error: la interfaz siempre se actualiza.
  Future<void> save() async {
    notifyListeners();
    _dirty = true;
    if (_saving != null) return _saving;
    _saving = () async {
      try {
        while (_dirty) {
          _dirty = false;
          final f = await _file();
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(jsonEncode(toJson()), flush: true);
          if (await f.exists()) await f.copy('${f.path}.bak');
          await tmp.rename(f.path);
        }
      } catch (e) {
        debugPrint('No se pudieron guardar los ajustes: $e');
      } finally {
        _saving = null;
      }
    }();
    return _saving;
  }

  /// Modifica y guarda en un solo paso.
  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    await save();
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rutas donde se guardan fotos, marcos y datos internos.
class Storage {
  static String sanitize(String s) {
    final clean = s.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return clean.isEmpty ? 'Evento' : clean;
  }

  /// Carpeta base visible para el usuario:
  /// - Android: Android/data/<app>/files/FotoJAS (accesible por USB)
  /// - Windows: Documentos\FotoJAS
  static Future<Directory> baseDir() async {
    Directory? root;
    if (Platform.isAndroid) {
      root = await getExternalStorageDirectory();
    }
    root ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'FotoJAS'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> eventDir(String eventName) async {
    final dir = Directory(p.join((await baseDir()).path, sanitize(eventName)));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> supportDir() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> framesDir() async {
    final dir = Directory(p.join((await supportDir()).path, 'marcos'));
    await dir.create(recursive: true);
    return dir;
  }

  static String timestamp([DateTime? t]) {
    final d = t ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  /// Guarda la foto final del evento y devuelve su ruta.
  static Future<File> savePhoto(String eventName, List<int> jpeg) async {
    final dir = await eventDir(eventName);
    var file = File(p.join(dir.path, 'FotoJAS_${timestamp()}.jpg'));
    var i = 1;
    while (await file.exists()) {
      file = File(p.join(dir.path, 'FotoJAS_${timestamp()}_$i.jpg'));
      i++;
    }
    await file.writeAsBytes(jpeg, flush: true);
    return file;
  }
}

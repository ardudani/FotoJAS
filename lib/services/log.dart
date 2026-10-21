import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage.dart';

/// Registro de diagnóstico: se muestra en pantalla y se guarda en
/// FotoJAS/registro.txt para poder enviarlo si algo falla.
class AppLog extends ChangeNotifier {
  static final AppLog I = AppLog._();
  AppLog._();

  final List<String> lines = [];
  int errors = 0;

  void add(String msg, {bool error = false}) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)} ${error ? '❌ ' : ''}$msg';
    lines.add(line);
    if (lines.length > 300) lines.removeAt(0);
    if (error) errors++;
    debugPrint(line);
    notifyListeners();
    _write(line);
  }

  Future<void> _write(String line) async {
    try {
      final dir = await Storage.baseDir().timeout(const Duration(seconds: 3));
      await File(p.join(dir.path, 'registro.txt'))
          .writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

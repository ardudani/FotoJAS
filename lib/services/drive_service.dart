import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../settings.dart';
import 'storage.dart';

enum UploadStatus { pending, uploading, done, error }

class UploadJob {
  final String id;
  final String path;
  final String event;
  UploadStatus status;
  String? fileUrl;
  String? error;

  UploadJob(this.id, this.path, this.event,
      {this.status = UploadStatus.pending, this.fileUrl, this.error});

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'event': event,
        'status': status == UploadStatus.done ? 'done' : 'pending',
        'fileUrl': fileUrl,
      };

  static UploadJob fromJson(Map<String, dynamic> j) => UploadJob(
        j['id'] as String,
        j['path'] as String,
        j['event'] as String,
        status: j['status'] == 'done' ? UploadStatus.done : UploadStatus.pending,
        fileUrl: j['fileUrl'] as String?,
      );
}

/// Sube fotos a Google Drive a través de un script de Google Apps Script
/// (ver carpeta `google_apps_script/`). Mantiene una cola que se reintenta
/// sola si no hay internet.
class DriveService extends ChangeNotifier {
  final AppSettings settings;
  final List<UploadJob> jobs = [];
  final Map<String, String> galleryUrls = {};
  Timer? _timer;
  bool _busy = false;
  String? lastError;

  DriveService(this.settings);

  int get pendingCount => jobs.where((j) => j.status != UploadStatus.done).length;

  String? galleryUrlFor(String event) => galleryUrls[event];

  Future<File> _stateFile() async =>
      File(p.join((await Storage.supportDir()).path, 'subidas.json'));

  Future<void> init() async {
    try {
      final f = await _stateFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final e in (j['jobs'] as List? ?? const [])) {
          jobs.add(UploadJob.fromJson((e as Map).cast<String, dynamic>()));
        }
        (j['galleries'] as Map? ?? const {}).forEach((k, v) {
          galleryUrls[k as String] = v as String;
        });
      }
    } catch (_) {}
    // Guarda solo las últimas 500 subidas completadas
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => pump());
    pump();
  }

  Future<void> _persist() async {
    try {
      final done = jobs.where((j) => j.status == UploadStatus.done).toList();
      if (done.length > 500) {
        jobs.removeWhere((j) => done.take(done.length - 500).contains(j));
      }
      final f = await _stateFile();
      await f.writeAsString(jsonEncode({
        'jobs': jobs.map((e) => e.toJson()).toList(),
        'galleries': galleryUrls,
      }));
    } catch (_) {}
  }

  UploadJob enqueue(String path, String event) {
    final job = UploadJob(DateTime.now().microsecondsSinceEpoch.toString(), path, event);
    jobs.add(job);
    _persist();
    notifyListeners();
    pump();
    return job;
  }

  void retryAll() {
    for (final j in jobs) {
      if (j.status == UploadStatus.error) j.status = UploadStatus.pending;
    }
    pump();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final url = settings.scriptUrl.trim();
    if (url.isEmpty) throw Exception('Falta la URL del script de Drive en Ajustes');
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(url))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain; charset=utf-8'
        ..body = jsonEncode({...payload, 'secret': settings.scriptSecret});
      var resp = await http.Response.fromStream(
          await client.send(req).timeout(const Duration(seconds: 120)));
      var hops = 0;
      while ((resp.statusCode == 301 || resp.statusCode == 302 || resp.statusCode == 303) &&
          hops < 5) {
        final loc = resp.headers['location'];
        if (loc == null) break;
        resp = await client.get(Uri.parse(loc)).timeout(const Duration(seconds: 60));
        hops++;
      }
      if (resp.statusCode != 200) {
        throw Exception('Drive respondió HTTP ${resp.statusCode}');
      }
      Map<String, dynamic> data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception(
            'Respuesta no válida del script. ¿Lo desplegaste como aplicación web con acceso "Cualquier usuario"?');
      }
      if (data['ok'] != true) {
        throw Exception('Error del script: ${data['error'] ?? 'desconocido'}');
      }
      return data;
    } finally {
      client.close();
    }
  }

  /// Comprueba la conexión y crea (si no existe) la carpeta del evento.
  Future<String> testConnection() async {
    final data = await _call({'action': 'ping', 'event': settings.eventName});
    final url = data['folderUrl'] as String? ?? '';
    if (url.isNotEmpty) {
      galleryUrls[settings.eventName] = url;
      await _persist();
      notifyListeners();
    }
    return url;
  }

  Future<void> pump() async {
    if (_busy || !settings.driveEnabled || settings.scriptUrl.trim().isEmpty) return;
    _busy = true;
    try {
      while (true) {
        final job = jobs.cast<UploadJob?>().firstWhere(
            (j) => j!.status == UploadStatus.pending,
            orElse: () => null);
        if (job == null) break;
        job.status = UploadStatus.uploading;
        notifyListeners();
        try {
          final file = File(job.path);
          if (!await file.exists()) {
            jobs.remove(job);
            continue;
          }
          final bytes = await file.readAsBytes();
          final data = await _call({
            'action': 'upload',
            'event': job.event,
            'filename': p.basename(job.path),
            'image': base64Encode(bytes),
          });
          job.fileUrl = data['fileUrl'] as String?;
          job.status = UploadStatus.done;
          job.error = null;
          final folder = data['folderUrl'] as String?;
          if (folder != null && folder.isNotEmpty) galleryUrls[job.event] = folder;
          lastError = null;
        } catch (e) {
          job.status = UploadStatus.error;
          job.error = e.toString();
          lastError = e.toString();
          notifyListeners();
          break; // sin conexión: se reintenta en el próximo ciclo
        } finally {
          await _persist();
          notifyListeners();
        }
      }
    } finally {
      _busy = false;
    }
    // Los fallidos vuelven a la cola para el siguiente intento automático
    for (final j in jobs) {
      if (j.status == UploadStatus.error) j.status = UploadStatus.pending;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

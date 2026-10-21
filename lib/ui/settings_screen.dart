import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../services/camera_service.dart';
import '../services/composer.dart';
import '../services/ipp.dart';
import '../services/printer_service.dart';
import '../services/storage.dart';
import '../settings.dart';
import 'home_screen.dart' show showLogDialog;

const _fonts = {
  'GreatVibes': 'Great Vibes (caligrafía)',
  'DancingScript': 'Dancing Script (manuscrita)',
  'Pacifico': 'Pacifico (divertida)',
  'PlayfairDisplay': 'Playfair Display (elegante)',
  'Montserrat': 'Montserrat (moderna)',
  'BebasNeue': 'Bebas Neue (titular)',
};

const _swatches = [
  0xFFFFFFFF, 0xFFFFF8F0, 0xFFF9E4E8, 0xFFEFE6DA, 0xFF000000, 0xFF2B2B2B,
  0xFF6B6B6B, 0xFFC9A227, 0xFFB76E79, 0xFFE0457B, 0xFF7B1E3A, 0xFF1F2A44,
  0xFF7A9CC6, 0xFF1A9E8F, 0xFF9CAF88, 0xFFFF7A3D,
];

/// Ajustes del operador (protegidos por PIN).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get s => App.settings;
  String _photosPath = '';
  int _subtitleRev = 0;

  @override
  void initState() {
    super.initState();
    Storage.eventDir(s.eventName).then((d) {
      if (mounted) setState(() => _photosPath = d.path);
    });
  }

  Future<void> _set(void Function(AppSettings s) change) async {
    await s.update(change);
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }

  Future<void> _info(String title, String body) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(body)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );

  // ---------------------------------------------------------------- Diseño
  Future<void> _pickFrame() async {
    const group = XTypeGroup(
      label: 'PNG',
      extensions: ['png'],
      mimeTypes: ['image/png'],
      uniformTypeIdentifiers: ['public.png'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final dir = await Storage.framesDir();
    final dest = File(p.join(dir.path, 'marco_${Storage.timestamp()}.png'));
    await dest.writeAsBytes(bytes, flush: true);
    try {
      final im = await Composer.decode(bytes);
      final portrait = im.height >= im.width;
      if (portrait != s.isPortrait) {
        _toast('Aviso: el marco es ${portrait ? 'vertical' : 'horizontal'} y el diseño está en ${s.isPortrait ? 'vertical' : 'horizontal'}');
      }
      im.dispose();
    } catch (_) {
      _toast('No se pudo leer el PNG');
      return;
    }
    await _set((x) => x.framePath = dest.path);
  }

  Future<void> _preview() async {
    final single = await Composer.placeholders(1);
    final collage = await Composer.placeholders(s.collageCount);
    final frame = await Composer.loadFrame(s);
    final images = <ui.Image>[];
    if (s.enableSingle || !s.enableCollage) {
      images.add(await Composer.composeImage(single, s, frame: frame));
    }
    if (s.enableCollage) images.add(await Composer.composeImage(collage, s, frame: frame));
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final im in images)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: RawImage(image: im, fit: BoxFit.contain),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final copy = AppSettings()..orientation = s.orientation;
    copy
      ..showText = s.showText
      ..titleText = s.titleText
      ..subtitleText = s.subtitleText
      ..fontFamily = s.fontFamily
      ..textColor = s.textColor
      ..subtitleColor = s.subtitleColor
      ..bgColor = s.bgColor
      ..roundedPhotos = s.roundedPhotos;
    final dir = await Storage.baseDir();
    final saved = <String>[];
    for (final n in {1, s.collageCount}) {
      final im = await Composer.composeImage(await Composer.placeholders(n), copy);
      final bd = await im.toByteData(format: ui.ImageByteFormat.png);
      final f = File(p.join(dir.path,
          'plantilla_${s.isPortrait ? 'vertical' : 'horizontal'}_${n}foto${n > 1 ? 's' : ''}.png'));
      await f.writeAsBytes(bd!.buffer.asUint8List());
      saved.add(f.path);
    }
    _info('Plantillas guardadas',
        'Úsalas como capa de fondo en Canva/Photoshop para diseñar tu marco (${s.isPortrait ? '1200×1800' : '1800×1200'} px). Deja transparente donde van las fotos y exporta como PNG.\n\n${saved.join('\n')}');
  }

  // ---------------------------------------------------------------- Impresión
  Future<void> _checkPrinter() async {
    if (s.printerIp.trim().isEmpty) {
      _toast('Escribe primero la IP de la impresora');
      return;
    }
    _toast('Consultando impresora…');
    try {
      final r = await IppClient(s.printerIp.trim(), path: s.ippPath.trim()).getPrinterAttributes();
      const states = {3: 'Lista', 4: 'Imprimiendo', 5: 'Detenida'};
      final names = r.list('marker-names');
      final levels = r.list('marker-levels');
      final ink = <String>[];
      for (var i = 0; i < names.length && i < levels.length; i++) {
        ink.add('  ${names[i]}: ${levels[i]}%');
      }
      final state = r.attributes['printer-state']?.first;
      _info('Impresora', [
        'Modelo: ${r.list('printer-make-and-model').join()}',
        'Estado: ${states[state] ?? state} ${r.list('printer-state-reasons').join(', ')}',
        if (ink.isNotEmpty) 'Tinta:\n${ink.join('\n')}',
        'Papel cargado: ${r.list('media-ready').join(', ')}',
        'Tipos de papel: ${r.list('media-type-supported').join(', ')}',
        'Bandejas: ${r.list('media-source-supported').join(', ')}',
        'Formatos: ${r.list('document-format-supported').join(', ')}',
      ].join('\n\n'));
    } catch (e) {
      _info('Error', e.toString());
    }
  }

  Future<void> _testPrint() async {
    _toast('Enviando página de prueba…');
    try {
      final im = await Composer.composeImage(
          await Composer.placeholders(s.enableCollage ? s.collageCount : 1), s,
          frame: await Composer.loadFrame(s));
      final jpeg = await Composer.toJpeg(im);
      await PrinterService.printPhoto(jpeg, 1, s);
      _toast('Prueba enviada correctamente');
    } catch (e) {
      _info('Error al imprimir', e.toString());
    }
  }

  // ---------------------------------------------------------------- Drive
  Future<void> _testDrive() async {
    _toast('Conectando con Google Drive…');
    try {
      final url = await App.drive.testConnection();
      _info('Conexión correcta', 'Carpeta del evento "${s.eventName}":\n$url');
    } catch (e) {
      _info('Error', e.toString());
    }
  }

  // ---------------------------------------------------------------- UI helpers
  Widget _section(String title, IconData icon, List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              ...children,
            ],
          ),
        ),
      );

  Widget _text(String label, String value, void Function(String) onChanged,
      {String? hint, bool number = false, bool obscure = false, Widget? suffix, Key? key}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextFormField(
        key: key,
        initialValue: value,
        obscureText: obscure,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _switch(String title, bool value, void Function(bool) onChanged, {String? subtitle}) =>
      SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: onChanged,
      );

  Widget _dropdown<T>(String title, T value, Map<T, String> items, void Function(T) onChanged) {
    final safe = items.containsKey(value) ? value : items.keys.first;
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: safe,
        items: [
          for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _stepper(String title, int value, int min, int max, void Function(int) onChanged,
      {String Function(int)? format, int step = 1}) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > min ? () => onChanged((value - step).clamp(min, max).toInt()) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 64,
            child: Text(format?.call(value) ?? '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged((value + step).clamp(min, max).toInt()) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _color(String title, int value, void Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _swatches)
                GestureDetector(
                  onTap: () => onChanged(c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == value ? Theme.of(context).colorScheme.primary : Colors.white24,
                        width: c == value ? 4 : 1,
                      ),
                    ),
                  ),
                ),
              ActionChip(
                avatar: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: Color(value), shape: BoxShape.circle),
                ),
                label: Text('#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'),
                onPressed: () async {
                  final ctrl = TextEditingController(
                      text: (value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase());
                  final res = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Color hexadecimal'),
                      content: TextField(
                        controller: ctrl,
                        decoration: const InputDecoration(prefixText: '#', hintText: 'RRGGBB'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Aplicar')),
                      ],
                    ),
                  );
                  if (res == null) return;
                  final hex = res.replaceAll('#', '').trim();
                  final v = int.tryParse(hex, radix: 16);
                  if (v != null && hex.length == 6) onChanged(0xFF000000 | v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buttons(List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(spacing: 12, runSpacing: 8, children: children),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      );

  // ---------------------------------------------------------------- Build
  @override
  Widget build(BuildContext context) {
    final cams = App.camera.cameras;
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}·${now.month.toString().padLeft(2, '0')}·${now.year}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes de FotoJAS'),
        actions: [
          IconButton(
            tooltip: 'Vista previa del diseño',
            icon: const Icon(Icons.visibility_rounded),
            onPressed: _preview,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              _section('Evento', Icons.celebration_rounded, [
                _text('Nombre del evento (carpeta de fotos y de Drive)', s.eventName,
                    (v) => _set((x) => x.eventName = v.trim().isEmpty ? 'Evento' : v.trim())),
                _text('Texto principal (en la foto)', s.titleText, (v) => _set((x) => x.titleText = v),
                    hint: 'Boda de Ana & Luis'),
                _text('Texto secundario (en la foto)', s.subtitleText,
                    (v) => _set((x) => x.subtitleText = v),
                    hint: today,
                    key: ValueKey('sub$_subtitleRev'),
                    suffix: IconButton(
                      tooltip: 'Poner fecha de hoy',
                      icon: const Icon(Icons.today),
                      onPressed: () async {
                        _subtitleRev++;
                        await _set((x) => x.subtitleText = today);
                      },
                    )),
                _text('Mensaje de la pantalla de inicio', s.welcomeText,
                    (v) => _set((x) => x.welcomeText = v)),
                _switch('Mostrar texto en la foto', s.showText, (v) => _set((x) => x.showText = v)),
                _dropdown('Tipografía', s.fontFamily, _fonts, (v) => _set((x) => x.fontFamily = v)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(s.titleText.isEmpty ? 'Ejemplo de texto' : s.titleText,
                      style: TextStyle(fontFamily: s.fontFamily, fontSize: 34)),
                ),
                _color('Color del texto principal', s.textColor, (v) => _set((x) => x.textColor = v)),
                _color('Color del texto secundario', s.subtitleColor,
                    (v) => _set((x) => x.subtitleColor = v)),
                _color('Color de fondo de la foto', s.bgColor, (v) => _set((x) => x.bgColor = v)),
                _color('Color de los botones', s.accentColor, (v) => _set((x) => x.accentColor = v)),
              ]),
              _section('Diseño de la foto (10×15)', Icons.dashboard_customize_rounded, [
                _dropdown('Orientación', s.orientation,
                    const {'portrait': 'Vertical', 'landscape': 'Horizontal'},
                    (v) => _set((x) => x.orientation = v)),
                _switch('Opción "Foto" (1 foto)', s.enableSingle, (v) => _set((x) => x.enableSingle = v)),
                _switch('Opción "Collage"', s.enableCollage, (v) => _set((x) => x.enableCollage = v)),
                _stepper('Fotos en el collage', s.collageCount, 2, 4,
                    (v) => _set((x) => x.collageCount = v)),
                _switch('Esquinas redondeadas', s.roundedPhotos,
                    (v) => _set((x) => x.roundedPhotos = v)),
                ListTile(
                  title: const Text('Marco PNG (encima de todo)'),
                  subtitle: Text(s.framePath == null ? 'Sin marco' : p.basename(s.framePath!)),
                  trailing: s.framePath == null
                      ? null
                      : IconButton(
                          tooltip: 'Quitar marco',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _set((x) => x.framePath = null),
                        ),
                ),
                _buttons([
                  FilledButton.tonalIcon(
                      onPressed: _pickFrame,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Elegir marco PNG')),
                  OutlinedButton.icon(
                      onPressed: _saveTemplate,
                      icon: const Icon(Icons.grid_on),
                      label: const Text('Guardar plantilla guía')),
                  OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.visibility),
                      label: const Text('Vista previa')),
                ]),
                _note(
                    'Marco: PNG de ${s.isPortrait ? '1200×1800' : '1800×1200'} px con transparencia donde se ven las fotos. La "plantilla guía" te dice dónde caen las fotos y el texto.'),
              ]),
              _section('Cámara', Icons.photo_camera_rounded, [
                if (cams.isNotEmpty)
                  _dropdown<String>(
                    'Cámara',
                    s.cameraName ?? App.camera.controller?.description.name ?? cams.first.name,
                    {for (final c in cams) c.name: CameraService.describe(c)},
                    (v) async {
                      await _set((x) => x.cameraName = v);
                      await App.camera.init();
                    },
                  ),
                _dropdown('Resolución', s.resolution, const {
                  'high': '720p',
                  'veryHigh': '1080p (recomendado)',
                  'ultraHigh': '4K',
                  'max': 'Máxima',
                }, (v) async {
                  await _set((x) => x.resolution = v);
                  await App.camera.init();
                }),
                _switch('Invertir vista previa (efecto espejo)', s.mirrorPreview,
                    (v) => _set((x) => x.mirrorPreview = v)),
                _switch('Invertir foto final', s.mirrorPhoto, (v) => _set((x) => x.mirrorPhoto = v),
                    subtitle: 'Normalmente desactivado para que los textos se lean bien'),
                _dropdown<int>('Girar fotos', s.extraRotation,
                    const {0: 'No', 90: '90°', 180: '180°', 270: '270°'},
                    (v) => _set((x) => x.extraRotation = v)),
                _stepper('Cuenta atrás', s.countdown, 0, 10, (v) => _set((x) => x.countdown = v),
                    format: (v) => '$v s'),
                _stepper('Pausa entre fotos del collage', s.betweenShots, 0, 10,
                    (v) => _set((x) => x.betweenShots = v),
                    format: (v) => '$v s'),
                _buttons([
                  OutlinedButton.icon(
                    onPressed: () async {
                      await App.camera.init();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reiniciar cámara'),
                  ),
                ]),
              ]),
              _section('Impresión', Icons.print_rounded, [
                _switch('Permitir imprimir', s.printEnabled, (v) => _set((x) => x.printEnabled = v)),
                _dropdown('Método', s.printMethod, {
                  'ipp': 'Directo por red (IPP) · sin diálogo',
                  if (Platform.isWindows) 'system': 'Impresora de Windows · sin diálogo',
                  'dialog': 'Diálogo del sistema',
                }, (v) => _set((x) => x.printMethod = v)),
                if (s.printMethod == 'ipp') ...[
                  _text('IP de la impresora', s.printerIp, (v) => _set((x) => x.printerIp = v.trim()),
                      hint: '192.168.1.50'),
                  _text('Ruta IPP', s.ippPath, (v) => _set((x) => x.ippPath = v.trim()),
                      hint: '/ipp/print'),
                  _switch('Sin bordes', s.borderless, (v) => _set((x) => x.borderless = v)),
                  _dropdown('Tipo de papel', s.mediaType, const {
                    'photographic-glossy': 'Fotográfico brillo',
                    'photographic-high-gloss': 'Fotográfico alto brillo (Premium)',
                    'photographic-semi-gloss': 'Fotográfico semibrillo',
                    'photographic-matte': 'Fotográfico mate',
                    'photographic': 'Fotográfico (genérico)',
                    'stationery': 'Papel normal',
                  }, (v) => _set((x) => x.mediaType = v)),
                  _dropdown('Bandeja', s.mediaSource, const {
                    'auto': 'Automática',
                    'photo': 'Bandeja de fotos',
                    'main': 'Bandeja principal',
                  }, (v) => _set((x) => x.mediaSource = v)),
                  _dropdown<int>('Calidad', s.printQuality,
                      const {4: 'Normal', 5: 'Alta'}, (v) => _set((x) => x.printQuality = v)),
                  _note(
                      'Pon la IP fija a la impresora en el router (o anótala desde el panel de la Epson: Configuración > Red). Usa "Comprobar impresora" para ver la tinta y los papeles y bandejas que admite.'),
                ],
                if (s.printMethod == 'system')
                  FutureBuilder(
                    future: Printing.listPrinters(),
                    builder: (context, snap) {
                      final printers = snap.data ?? const [];
                      if (printers.isEmpty) {
                        return const ListTile(title: Text('Buscando impresoras de Windows…'));
                      }
                      return _dropdown<String>(
                        'Impresora',
                        s.systemPrinterName,
                        {
                          '': 'Predeterminada de Windows',
                          for (final pr in printers) pr.name: pr.name,
                        },
                        (v) => _set((x) => x.systemPrinterName = v),
                      );
                    },
                  ),
                if (s.printMethod == 'system')
                  _note(
                      'En Windows, configura en las preferencias de la impresora: papel 10×15, tipo fotográfico y sin bordes.'),
                _stepper('Copias máximas por foto', s.maxCopies, 1, 10,
                    (v) => _set((x) => x.maxCopies = v)),
                _stepper('Límite total de impresiones', s.maxTotalPrints, 0, 2000,
                    (v) => _set((x) => x.maxTotalPrints = v),
                    format: (v) => v == 0 ? '∞' : '$v', step: 10),
                ListTile(
                  title: Text('Impresas en este evento: ${s.printedCount}'),
                  trailing: TextButton(
                    onPressed: () => _set((x) => x.printedCount = 0),
                    child: const Text('Poner a cero'),
                  ),
                ),
                _buttons([
                  if (s.printMethod == 'ipp')
                    FilledButton.tonalIcon(
                        onPressed: _checkPrinter,
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('Comprobar impresora')),
                  OutlinedButton.icon(
                      onPressed: _testPrint,
                      icon: const Icon(Icons.print),
                      label: const Text('Imprimir prueba')),
                ]),
              ]),
              _section('Google Drive y QR', Icons.qr_code_2_rounded, [
                _switch('Subir fotos a Google Drive', s.driveEnabled, (v) async {
                  await _set((x) => x.driveEnabled = v);
                  App.drive.pump();
                }),
                _text('URL del script (aplicación web)', s.scriptUrl,
                    (v) => _set((x) => x.scriptUrl = v.trim()),
                    hint: 'https://script.google.com/macros/s/…/exec'),
                _text('Clave secreta del script', s.scriptSecret,
                    (v) => _set((x) => x.scriptSecret = v), obscure: true),
                _dropdown('QR a mostrar', s.qrMode, const {
                  'both': 'Foto y galería',
                  'photo': 'Solo la foto',
                  'gallery': 'Solo la galería',
                }, (v) => _set((x) => x.qrMode = v)),
                _switch('Pedir consentimiento antes de subir', s.askConsent,
                    (v) => _set((x) => x.askConsent = v),
                    subtitle: 'Recomendado (RGPD) si el evento es público'),
                ListenableBuilder(
                  listenable: App.drive,
                  builder: (context, _) => ListTile(
                    title: Text('Pendientes de subir: ${App.drive.pendingCount}'),
                    subtitle: App.drive.lastError == null ? null : Text(App.drive.lastError!),
                    trailing: TextButton(
                      onPressed: App.drive.retryAll,
                      child: const Text('Reintentar'),
                    ),
                  ),
                ),
                _buttons([
                  FilledButton.tonalIcon(
                      onPressed: _testDrive,
                      icon: const Icon(Icons.cloud_done),
                      label: const Text('Probar conexión')),
                ]),
                _note(
                    'Sigue la guía GUIA_GOOGLE_DRIVE.md del proyecto para crear el script en tu cuenta de Google (5 minutos, una sola vez).'),
              ]),
              _section('Sistema', Icons.admin_panel_settings_rounded, [
                _text('PIN de ajustes', s.pin, (v) {
                  if (v.length >= 4) _set((x) => x.pin = v);
                }, number: true, obscure: true, hint: 'Mínimo 4 cifras'),
                _stepper('Volver al inicio sin actividad', s.idleTimeout, 15, 300,
                    (v) => _set((x) => x.idleTimeout = v),
                    format: (v) => '$v s'),
                if (Platform.isWindows)
                  _switch('Pantalla completa', s.fullscreen, (v) async {
                    await _set((x) => x.fullscreen = v);
                    await windowManager.setFullScreen(v);
                  }),
                ListTile(
                  title: const Text('Carpeta de fotos del evento'),
                  subtitle: SelectableText(_photosPath),
                ),
                if (Platform.isWindows)
                  _buttons([
                    OutlinedButton.icon(
                      onPressed: () => Process.run('explorer', [_photosPath]),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Abrir carpeta'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => exit(0),
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Salir de FotoJAS'),
                    ),
                  ]),
                _buttons([
                  OutlinedButton.icon(
                    onPressed: () => showLogDialog(context),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Ver registro de diagnóstico'),
                  ),
                ]),
                if (Platform.isAndroid)
                  _note(
                      'Para que nadie salga de la app: Ajustes de Android > Seguridad > Fijar aplicaciones, y fija FotoJAS.'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

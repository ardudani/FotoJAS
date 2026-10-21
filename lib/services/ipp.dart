import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Cliente IPP mínimo para imprimir JPEG directamente en una impresora de red
/// (Epson XP-8600 y cualquier impresora AirPrint / IPP Everywhere) sin diálogo.
class IppClient {
  final String host;
  final int port;
  final String path;

  IppClient(this.host, {this.port = 631, this.path = '/ipp/print'});

  static int _requestId = 1;

  String get printerUri => 'ipp://$host:$port$path';
  Uri get httpUri => Uri.parse('http://$host:$port$path');

  Future<IppResponse> _send(Uint8List body,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(httpUri);
      req.headers.contentType = ContentType('application', 'ipp');
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(timeout);
      final bytes = await resp
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
          .timeout(timeout);
      if (resp.statusCode != 200) {
        throw IppException('La impresora respondió HTTP ${resp.statusCode}');
      }
      return IppResponse.parse(bytes.takeBytes());
    } on SocketException catch (e) {
      throw IppException(
          'No se puede conectar con la impresora en $host ($e). Comprueba la IP y que esté en la misma red WiFi.');
    } on TimeoutException {
      throw IppException('La impresora no responde (tiempo agotado).');
    } finally {
      client.close(force: true);
    }
  }

  _IppWriter _start(int operation) {
    final w = _IppWriter(operation, _requestId++);
    w.group(0x01); // operation-attributes
    w.string(0x47, 'attributes-charset', 'utf-8');
    w.string(0x48, 'attributes-natural-language', 'en');
    w.string(0x45, 'printer-uri', printerUri);
    w.string(0x42, 'requesting-user-name', 'fotojas');
    return w;
  }

  /// Consulta estado, formatos, papeles y niveles de tinta.
  Future<IppResponse> getPrinterAttributes() async {
    final w = _start(0x000B);
    w.strings(0x44, 'requested-attributes', const [
      'printer-make-and-model',
      'printer-state',
      'printer-state-reasons',
      'document-format-supported',
      'media-supported',
      'media-ready',
      'media-type-supported',
      'media-source-supported',
      'print-quality-supported',
      'marker-names',
      'marker-levels',
    ]);
    final resp = await _send(w.finish(), timeout: const Duration(seconds: 15));
    resp.throwIfError();
    return resp;
  }

  /// Envía un JPEG a imprimir en 10x15.
  Future<IppResponse> printJpeg(
    Uint8List jpeg, {
    int copies = 1,
    bool borderless = true,
    String mediaType = 'photographic-glossy',
    String mediaSource = 'auto',
    int quality = 5,
    String jobName = 'FotoJAS',
  }) async {
    final w = _start(0x0002);
    w.string(0x42, 'job-name', jobName);
    w.string(0x49, 'document-format', 'image/jpeg');
    w.group(0x02); // job-attributes
    w.integer(0x21, 'copies', copies.clamp(1, 99));
    w.integer(0x23, 'print-quality', quality);
    w.string(0x44, 'print-color-mode', 'color');
    w.string(0x44, 'print-scaling', borderless ? 'fill' : 'fit');
    // media-col: 10x15 cm (4x6 in), márgenes, tipo de papel y bandeja
    w.begCollection('media-col');
    w.memberBegCollection('media-size');
    w.memberInt('x-dimension', 10160);
    w.memberInt('y-dimension', 15240);
    w.endCollection();
    if (borderless) {
      w.memberInt('media-top-margin', 0);
      w.memberInt('media-bottom-margin', 0);
      w.memberInt('media-left-margin', 0);
      w.memberInt('media-right-margin', 0);
    }
    if (mediaType.isNotEmpty) w.memberKeyword('media-type', mediaType);
    if (mediaSource.isNotEmpty && mediaSource != 'auto') {
      w.memberKeyword('media-source', mediaSource);
    }
    w.endCollection();
    final resp = await _send(w.finish(jpeg));
    resp.throwIfError();
    return resp;
  }
}

class IppException implements Exception {
  final String message;
  IppException(this.message);
  @override
  String toString() => message;
}

class _IppWriter {
  final BytesBuilder _b = BytesBuilder();

  _IppWriter(int operation, int requestId) {
    _b.add([0x02, 0x00]);
    _u16(operation);
    _u32(requestId);
  }

  void _u16(int v) {
    _b.addByte((v >> 8) & 0xff);
    _b.addByte(v & 0xff);
  }

  void _u32(int v) {
    _b.addByte((v >> 24) & 0xff);
    _b.addByte((v >> 16) & 0xff);
    _b.addByte((v >> 8) & 0xff);
    _b.addByte(v & 0xff);
  }

  void _lenBytes(List<int> v) {
    _u16(v.length);
    _b.add(v);
  }

  void group(int tag) => _b.addByte(tag);

  void string(int tag, String name, String value) {
    _b.addByte(tag);
    _lenBytes(utf8.encode(name));
    _lenBytes(utf8.encode(value));
  }

  void strings(int tag, String name, List<String> values) {
    for (var i = 0; i < values.length; i++) {
      _b.addByte(tag);
      _lenBytes(i == 0 ? utf8.encode(name) : const []);
      _lenBytes(utf8.encode(values[i]));
    }
  }

  void integer(int tag, String name, int value) {
    _b.addByte(tag);
    _lenBytes(utf8.encode(name));
    _u16(4);
    _u32(value);
  }

  void begCollection(String name) {
    _b.addByte(0x34);
    _lenBytes(utf8.encode(name));
    _u16(0);
  }

  void endCollection() {
    _b.addByte(0x37);
    _u16(0);
    _u16(0);
  }

  void _member(String memberName) {
    _b.addByte(0x4A);
    _u16(0);
    _lenBytes(utf8.encode(memberName));
  }

  void memberInt(String name, int value) {
    _member(name);
    _b.addByte(0x21);
    _u16(0);
    _u16(4);
    _u32(value);
  }

  void memberKeyword(String name, String value) {
    _member(name);
    _b.addByte(0x44);
    _u16(0);
    _lenBytes(utf8.encode(value));
  }

  void memberBegCollection(String name) {
    _member(name);
    _b.addByte(0x34);
    _u16(0);
    _u16(0);
  }

  Uint8List finish([Uint8List? document]) {
    _b.addByte(0x03);
    if (document != null) _b.add(document);
    return _b.takeBytes();
  }
}

class IppResponse {
  final int status;
  final Map<String, List<Object>> attributes;

  IppResponse(this.status, this.attributes);

  bool get ok => status < 0x0100;

  String? get statusMessage {
    final v = attributes['status-message'];
    return (v == null || v.isEmpty) ? null : v.first.toString();
  }

  String describeStatus() {
    const known = {
      0x0400: 'petición incorrecta',
      0x0403: 'no autorizado',
      0x0406: 'no encontrado (revisa la ruta IPP)',
      0x040A: 'formato de documento no soportado',
      0x040B: 'atributos o valores no soportados',
      0x0500: 'error interno de la impresora',
      0x0506: 'impresora no acepta trabajos',
      0x0507: 'impresora ocupada',
    };
    final hex = '0x${status.toRadixString(16).padLeft(4, '0')}';
    final txt = known[status] ?? 'error';
    return '$txt ($hex)${statusMessage != null ? ': $statusMessage' : ''}';
  }

  void throwIfError() {
    if (!ok) throw IppException('La impresora rechazó el trabajo: ${describeStatus()}');
  }

  List<String> list(String name) =>
      (attributes[name] ?? const []).map((e) => e.toString()).toList();

  static IppResponse parse(Uint8List d) {
    if (d.length < 8) throw IppException('Respuesta IPP vacía');
    final bd = ByteData.sublistView(d);
    final status = bd.getUint16(2);
    final attrs = <String, List<Object>>{};
    var pos = 8;
    var last = '';
    var depth = 0;
    while (pos < d.length) {
      final tag = d[pos++];
      if (tag == 0x03) break;
      if (tag < 0x10) continue; // delimitador de grupo
      if (pos + 2 > d.length) break;
      final nl = bd.getUint16(pos);
      pos += 2;
      final name = utf8.decode(d.sublist(pos, pos + nl), allowMalformed: true);
      pos += nl;
      if (pos + 2 > d.length) break;
      final vl = bd.getUint16(pos);
      pos += 2;
      if (pos + vl > d.length) break;
      final val = d.sublist(pos, pos + vl);
      pos += vl;

      if (tag == 0x34) {
        if (depth == 0 && name.isNotEmpty) last = name;
        depth++;
        continue;
      }
      if (tag == 0x37) {
        if (depth > 0) depth--;
        continue;
      }
      if (depth > 0) continue;
      if (name.isNotEmpty) last = name;

      Object? value;
      final vd = ByteData.sublistView(val);
      switch (tag) {
        case 0x21: // integer
        case 0x23: // enum
          value = vl == 4 ? vd.getInt32(0) : 0;
          break;
        case 0x22: // boolean
          value = vl > 0 && val[0] != 0;
          break;
        case 0x33: // rangeOfInteger
          value = vl == 8 ? '${vd.getInt32(0)}-${vd.getInt32(4)}' : '';
          break;
        case 0x30:
        case 0x31:
        case 0x32:
          value = null; // octetString, dateTime, resolution: se ignoran
          break;
        default:
          if (tag >= 0x10 && tag < 0x20) {
            value = '(sin valor)';
          } else {
            value = utf8.decode(val, allowMalformed: true);
          }
      }
      if (value != null) attrs.putIfAbsent(last, () => []).add(value);
    }
    return IppResponse(status, attrs);
  }
}

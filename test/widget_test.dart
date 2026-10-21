import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotojas/services/ipp.dart';

void main() {
  test('IPP: parsea una respuesta con estado correcto', () {
    // version 2.0, status 0x0000, request-id 1, operation group, end
    final bytes = [
      0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, //
      0x01, //
      0x47, 0x00, 0x12, ...'attributes-charset'.codeUnits, 0x00, 0x05, ...'utf-8'.codeUnits,
      0x03,
    ];
    final r = IppResponse.parse(Uint8List.fromList(bytes));
    expect(r.ok, isTrue);
    expect(r.list('attributes-charset'), ['utf-8']);
  });
}

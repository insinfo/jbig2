import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';

/// Encodes a synthetic page, reports how much it saved, and decodes it back.
///
/// ```
/// dart run example/jbig2_example.dart
/// ```
void main() {
  final page = _syntheticPage(width: 1200, height: 1600);

  final encoded = encodeJbig2Embedded(page);
  final raw = page.rowStride * page.height;
  print('raw      ${raw ~/ 1024} KiB');
  print('jbig2    ${encoded.length ~/ 1024} KiB  '
      '(${(raw / encoded.length).toStringAsFixed(1)}x smaller)');

  final decoded = decodeJbig2Embedded(encoded);
  print('decoded  ${decoded.width}x${decoded.height}');
  print('lossless ${_identical(page, decoded)}');

  final info = probeJbig2(encodeJbig2File(page));
  print('probe    ${info.width}x${info.height}, ${info.pageCount} page(s)');
}

/// A page of black bars on white, the shape a scanned text page has.
Jbig2Image _syntheticPage({required int width, required int height}) {
  final stride = (width + 7) >> 3;
  final data = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    // Eight text lines per 100 rows, indented like a paragraph.
    if (y % 100 < 8) {
      for (var x = 100; x < width - 100; x++) {
        if ((x ~/ 7) % 3 != 0) {
          data[y * stride + (x >> 3)] |= 1 << (7 - (x & 7));
        }
      }
    }
  }
  return Jbig2Image.fromPacked(
      width: width, height: height, data: data, rowStride: stride);
}

bool _identical(Jbig2Image a, Jbig2Image b) {
  if (a.width != b.width || a.height != b.height) return false;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (a.isBlack(x, y) != b.isBlack(x, y)) return false;
    }
  }
  return true;
}

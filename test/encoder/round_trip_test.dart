import 'dart:math';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:test/test.dart';

/// Builds an image from a list of rows written as strings, `#` for black.
Jbig2Image _image(List<String> rows) {
  final height = rows.length;
  final width = rows.first.length;
  for (final row in rows) {
    if (row.length != width) fail('every row must be the same width');
  }
  final stride = (width + 7) >> 3;
  final data = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rows[y][x] == '#') {
        data[y * stride + (x >> 3)] |= 1 << (7 - (x & 7));
      }
    }
  }
  return Jbig2Image.fromPacked(
      width: width, height: height, data: data, rowStride: stride);
}

/// Fails with the first pixel that differs, which is far more useful than a
/// byte-array mismatch when a context recurrence is off by one.
void _expectSamePixels(Jbig2Image actual, Jbig2Image expected) {
  expect(actual.width, equals(expected.width), reason: 'width');
  expect(actual.height, equals(expected.height), reason: 'height');
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      if (actual.isBlack(x, y) != expected.isBlack(x, y)) {
        fail('pixel ($x, $y) is ${actual.isBlack(x, y) ? 'black' : 'white'} '
            'but should be ${expected.isBlack(x, y) ? 'black' : 'white'}');
      }
    }
  }
}

void _roundTrip(Jbig2Image source, {bool typicalPrediction = true}) {
  final options = Jbig2EncodeOptions(typicalPrediction: typicalPrediction);

  final embedded = encodeJbig2Embedded(source, options: options);
  _expectSamePixels(decodeJbig2Embedded(embedded), source);

  final file = encodeJbig2File(source, options: options);
  expect(isJbig2File(file), isTrue);
  _expectSamePixels(decodeJbig2(file), source);
}

void main() {
  group('generic region round trip', () {
    test('a single black pixel', () {
      _roundTrip(_image(['#']));
    });

    test('an all white image', () {
      _roundTrip(_image(List.filled(16, '.' * 16)));
    });

    test('an all black image', () {
      _roundTrip(_image(List.filled(16, '#' * 16)));
    });

    test('a width that is not a multiple of eight', () {
      _roundTrip(_image([
        '#....',
        '.#...',
        '..#..',
        '...#.',
        '....#',
      ]));
    });

    test('a checkerboard, which defeats typical prediction', () {
      final rows = <String>[];
      for (var y = 0; y < 24; y++) {
        final buffer = StringBuffer();
        for (var x = 0; x < 37; x++) {
          buffer.write((x + y) % 2 == 0 ? '#' : '.');
        }
        rows.add(buffer.toString());
      }
      _roundTrip(_image(rows));
    });

    test('repeated identical rows', () {
      _roundTrip(_image([
        '..######..',
        '..######..',
        '..######..',
        '..######..',
        '..........',
        '..........',
        '..######..',
      ]));
    });

    test('text-like content at a realistic page width', () {
      final random = Random(20260906);
      final rows = <String>[];
      for (var y = 0; y < 120; y++) {
        final buffer = StringBuffer();
        // Mostly white with occasional runs, the way a scanned page looks.
        final inLine = y % 20 >= 4 && y % 20 < 12;
        for (var x = 0; x < 300; x++) {
          final black = inLine && x > 20 && x < 280 && random.nextInt(4) == 0;
          buffer.write(black ? '#' : '.');
        }
        rows.add(buffer.toString());
      }
      _roundTrip(_image(rows));
    });

    test('agrees with and without typical prediction', () {
      final source = _image([
        '########',
        '########',
        '.#.#.#.#',
        '........',
        '........',
        '#......#',
      ]);
      _roundTrip(source, typicalPrediction: true);
      _roundTrip(source, typicalPrediction: false);
    });

    test('typical prediction shrinks an image made of repeated rows', () {
      final rows = List.filled(200, '#' * 64 + '.' * 64);
      final source = _image(rows);

      final withTpgd = encodeJbig2Embedded(source,
          options: const Jbig2EncodeOptions(typicalPrediction: true));
      final withoutTpgd = encodeJbig2Embedded(source,
          options: const Jbig2EncodeOptions(typicalPrediction: false));

      expect(withTpgd.length, lessThan(withoutTpgd.length));
      _expectSamePixels(decodeJbig2Embedded(withTpgd), source);
      _expectSamePixels(decodeJbig2Embedded(withoutTpgd), source);
    });

    test('compresses a mostly white page well', () {
      final rows = <String>[];
      for (var y = 0; y < 300; y++) {
        rows.add(y % 50 == 0 ? '#' * 600 : '.' * 600);
      }
      final source = _image(rows);
      final encoded = encodeJbig2Embedded(source);

      final raw = (600 + 7) ~/ 8 * 300;
      expect(encoded.length, lessThan(raw ~/ 20),
          reason: 'encoded ${encoded.length} bytes against $raw raw');
      _expectSamePixels(decodeJbig2Embedded(encoded), source);
    });
  });

  group('encodeJbig2Packed', () {
    test('inverts PDF oriented data when told to', () {
      // In PDF a 1 bit is white, so an all-ones row is a white row.
      final packed = Uint8List.fromList([0xff, 0xff]);

      final encoded =
          encodeJbig2Packed(packed, width: 16, height: 1, oneIsBlack: false);
      final decoded = decodeJbig2Embedded(encoded);

      expect(decoded.isBlack(0, 0), isFalse);
      expect(decoded.isBlack(15, 0), isFalse);
    });

    test('treats a set bit as black by default', () {
      final packed = Uint8List.fromList([0xff, 0xff]);

      final decoded =
          decodeJbig2Embedded(encodeJbig2Packed(packed, width: 16, height: 1));

      expect(decoded.isBlack(0, 0), isTrue);
      expect(decoded.isBlack(15, 0), isTrue);
    });

    test('can be asked for a standalone file', () {
      final packed = Uint8List.fromList([0xaa]);

      final file = encodeJbig2Packed(packed, width: 8, height: 1, asFile: true);

      expect(isJbig2File(file), isTrue);
      final decoded = decodeJbig2(file);
      expect(decoded.isBlack(0, 0), isTrue);
      expect(decoded.isBlack(1, 0), isFalse);
    });
  });
}

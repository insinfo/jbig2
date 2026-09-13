import 'dart:math';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/decoder/mmr/mmr_decompressor.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:jbig2/src/encoder/mmr_encoder.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:test/test.dart';

Bitmap _noise(int width, int height, int seed, double density) {
  final bitmap = Bitmap(width, height);
  final rng = Random(seed);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rng.nextDouble() < density) bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

Bitmap _blobs(int width, int height, int seed) {
  final bitmap = Bitmap(width, height);
  final rng = Random(seed);
  for (var i = 0; i < 30; i++) {
    final cx = rng.nextInt(width);
    final cy = rng.nextInt(height);
    final r = 1 + rng.nextInt(12);
    for (var y = max(0, cy - r); y <= min(height - 1, cy + r); y++) {
      for (var x = max(0, cx - r); x <= min(width - 1, cx + r); x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          bitmap.setPixel(x, y, 1);
        }
      }
    }
  }
  return bitmap;
}

Bitmap _filled(int width, int height) {
  final bitmap = Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

/// The staircase the golden vector below was measured on.
Bitmap _staircase() {
  final bitmap = Bitmap(24, 6);
  for (var y = 0; y < 6; y++) {
    for (var x = 0; x < 24; x++) {
      if (x >= y * 3 && x < y * 3 + 5) bitmap.setPixel(x, y, 1);
      if (y == 3 && x > 18) bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

void _expectSame(Bitmap expected, Bitmap actual) {
  expect(actual.width, equals(expected.width));
  expect(actual.height, equals(expected.height));
  var wrong = 0;
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      if (actual.getPixel(x, y) != expected.getPixel(x, y)) wrong++;
    }
  }
  expect(wrong, isZero, reason: '$wrong pixels differ after a round trip');
}

Bitmap _decode(Bitmap source, Uint8List stream) {
  return MMRDecompressor(
          source.width, source.height, RandomAccessReadBuffer.fromBytes(stream))
      .uncompress();
}

/// Wraps an MMR codeword in a one page standalone file.
Uint8List _file(Bitmap source, Uint8List codeword) {
  final writer = Jbig2Writer();
  writer.writeFileHeader(pageCount: 1);
  writer.writeSegment(
    number: 0,
    type: Jbig2SegmentType.pageInformation,
    page: 1,
    data:
        Jbig2Writer.pageInformation(width: source.width, height: source.height),
  );
  writer.writeSegment(
    number: 1,
    type: Jbig2SegmentType.immediateLosslessGenericRegion,
    page: 1,
    data: Jbig2Writer.genericRegion(
      width: source.width,
      height: source.height,
      mmr: true,
      codeword: codeword,
    ),
  );
  writer.writeSegment(
    number: 2,
    type: Jbig2SegmentType.endOfPage,
    page: 1,
    data: Uint8List(0),
  );
  return writer.takeBytes();
}

void main() {
  group('6.2.6 MMR in a generic region', () {
    test('an empty region round trips', () {
      final source = Bitmap(64, 16);
      _expectSame(source, _decode(source, MmrEncoder(source).encode()));
    });

    test('a fully black region round trips', () {
      final source = _filled(64, 16);
      _expectSame(source, _decode(source, MmrEncoder(source).encode()));
    });

    for (final width in [1, 7, 8, 9, 63, 64, 65, 200]) {
      test('noise $width pixels wide round trips', () {
        // Widths around a byte boundary are where a padding mistake hides:
        // the coder works in pixels and the bitmap in bytes.
        for (final density in [0.1, 0.5, 0.9]) {
          final source = _noise(width, 37, width * 31 + 7, density);
          _expectSame(source, _decode(source, MmrEncoder(source).encode()));
        }
      });
    }

    test('blobs round trip', () {
      final source = _blobs(300, 200, 42);
      _expectSame(source, _decode(source, MmrEncoder(source).encode()));
    });

    test('runs longer than one make-up code round trip', () {
      // A single make-up code reaches 2560 pixels (T.4 table 3); past that the
      // longest one has to repeat.
      final source = Bitmap(6000, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 1000 + y; x < 5800; x++) {
          source.setPixel(x, y, 1);
        }
      }
      _expectSame(source, _decode(source, MmrEncoder(source).encode()));
    });

    test('the bitstream matches a Group 4 reference', () {
      // These eighteen bytes were decoded by libtiff, through ImageMagick, out
      // of a TIFF whose only content was this codeword under compression 4,
      // and came back as the staircase pixel for pixel. Pinning them keeps the
      // encoder honest against a third party, not only against this package's
      // own decoder: a change that broke both consistently would still fail
      // here.
      const golden = [
        0x26, 0xa7, 0x06, 0x0e, 0x0c, 0x1c, 0x18, 0x33, 0x86, //
        0x0c, 0x19, 0xf0, 0xdc, 0x18, 0x38, 0x00, 0x80, 0x08
      ];
      final source = _staircase();
      expect(MmrEncoder(source).encode(), equals(golden));
      _expectSame(source, _decode(source, MmrEncoder(source).encode()));
    });

    test('the stream ends with EOFB and can do without it', () {
      final source = _blobs(80, 40, 5);
      final withEofb = MmrEncoder(source).encode();
      final without = MmrEncoder(source, writeEofb: false).encode();
      expect(withEofb.length, greaterThan(without.length));
      _expectSame(source, _decode(source, without));
    });

    test('the MMR flag and the absent adaptive pixels reach the header', () {
      final data = Jbig2Writer.genericRegion(
        width: 8,
        height: 1,
        mmr: true,
        codeword: Uint8List.fromList(const [1, 2, 3]),
      );
      // 17 bytes of region segment information, then the flags byte, then the
      // codeword: 7.4.6.3 says MMR carries no AT pixels at all.
      expect(data[17] & 0x01, equals(1), reason: 'MMR bit');
      expect(data[17] & 0x08, isZero,
          reason: 'TPGDON is meaningless under MMR');
      expect(data.sublist(18), equals(const [1, 2, 3]));
    });

    test('a whole file decodes through the public decoder', () {
      final source = _blobs(120, 90, 17);
      final image = decodeJbig2(_file(source, MmrEncoder(source).encode()));
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          expect(image.isBlack(x, y), equals(source.getPixel(x, y) == 1),
              reason: 'pixel ($x, $y)');
        }
      }
    });

    test('the public encoder emits it on request', () {
      final source = _blobs(120, 90, 23);
      final input = Jbig2Image(
        width: source.width,
        height: source.height,
        rowStride: source.rowStride,
        data: source.bitmap,
      );
      const options = Jbig2EncodeOptions(
        mode: Jbig2EncodeMode.genericRegion,
        genericRegionMmr: true,
      );
      final file = encodeJbig2File(input, options: options);
      final embedded = encodeJbig2Embedded(input, options: options);
      for (final decoded in [
        decodeJbig2(file),
        decodeJbig2Embedded(embedded),
      ]) {
        for (var y = 0; y < source.height; y++) {
          for (var x = 0; x < source.width; x++) {
            expect(decoded.isBlack(x, y), equals(source.getPixel(x, y) == 1),
                reason: 'pixel ($x, $y)');
          }
        }
      }
    });

    test('MMR and EXTTEMPLATE cannot be asked for together', () {
      final input = Jbig2Image(
        width: 8,
        height: 8,
        rowStride: 1,
        data: Uint8List(8),
      );
      expect(
          () => encodeJbig2File(input,
              options: const Jbig2EncodeOptions(
                mode: Jbig2EncodeMode.genericRegion,
                genericRegionMmr: true,
                genericRegionExtTemplate: true,
              )),
          throwsArgumentError);
    });
  });
}

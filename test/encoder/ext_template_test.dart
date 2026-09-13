import 'dart:math';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/generic_region_encoder.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:test/test.dart';

/// Blobs of varied size: enough structure that a wrong context shows up as
/// thousands of wrong pixels rather than as a lucky match.
Bitmap _blobs(int width, int height, int seed) {
  final bitmap = Bitmap(width, height);
  final rng = Random(seed);
  for (var i = 0; i < 40; i++) {
    final cx = rng.nextInt(width);
    final cy = rng.nextInt(height);
    final r = 1 + rng.nextInt(9);
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

/// Wraps an EXTTEMPLATE generic region codeword in a one page standalone file.
Uint8List _file(
  Bitmap source, {
  required List<int> atX,
  required List<int> atY,
  bool typicalPrediction = true,
}) {
  final codeword = GenericRegionEncoder(
    source,
    extTemplate: true,
    typicalPrediction: typicalPrediction,
    atX: atX,
    atY: atY,
  ).encode();

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
      extTemplate: true,
      typicalPrediction: typicalPrediction,
      atX: atX,
      atY: atY,
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

void _expectRoundTrip(Bitmap source, Uint8List file) {
  final image = decodeJbig2(file);
  expect(image.width, equals(source.width));
  expect(image.height, equals(source.height));
  var wrong = 0;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (image.isBlack(x, y) != (source.getPixel(x, y) == 1)) wrong++;
    }
  }
  expect(wrong, isZero, reason: '$wrong pixels differ after a round trip');
}

void main() {
  group('6.2.5.3 EXTTEMPLATE', () {
    final source = _blobs(97, 71, 3);
    final nominalX = GenericRegionEncoder.nominalAtX(0, extTemplate: true);
    final nominalY = GenericRegionEncoder.nominalAtY(0, extTemplate: true);

    test('the nominal extended template codes to the same bits as template 0',
        () {
      // Figure 8 covers the very same sixteen neighbours figure 4 covers once
      // the adaptive pixels sit where the standard puts them, and assembles
      // the context in the same order. So the codeword has to come out byte
      // identical — which is an independent check on the pixel list and on the
      // slot map, since the two paths share no code.
      final extended = GenericRegionEncoder(source, extTemplate: true).encode();
      final plain = GenericRegionEncoder(source).encode();
      expect(extended, equals(plain));
    });

    test('the nominal extended template round trips', () {
      _expectRoundTrip(source, _file(source, atX: nominalX, atY: nominalY));
    });

    test('without TPGDON too', () {
      _expectRoundTrip(
          source,
          _file(source,
              atX: nominalX, atY: nominalY, typicalPrediction: false));
    });

    for (var i = 0; i < 12; i++) {
      test('A${i + 1} moved off its nominal position round trips', () {
        // One at a time, so a wrong context bit names the adaptive pixel it
        // belongs to. This is what caught the A12 mask: every other pixel
        // decoded, A12 alone produced garbage from the first row.
        final atX = [...nominalX]..[i] = -5 - i;
        final atY = [...nominalY]..[i] = -2;
        _expectRoundTrip(source, _file(source, atX: atX, atY: atY));
      });
    }

    test('all twelve moved at once round trips', () {
      final atX = [-5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15, -16];
      final atY = [-2, -2, -3, -3, -4, -4, -2, -2, -3, -3, -4, -4];
      _expectRoundTrip(source, _file(source, atX: atX, atY: atY));
    });

    test('adaptive pixels on the current row round trip', () {
      // Y = 0 takes both encoder and decoder down the branch that reads the
      // pixels already written into the byte being decoded rather than the
      // bitmap.
      final atX = [-2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13];
      final atY = List.filled(12, 0);
      _expectRoundTrip(source, _file(source, atX: atX, atY: atY));
    });

    test('moving an adaptive pixel changes the stream', () {
      // Without this the round trips above would also pass on a decoder that
      // ignored EXTTEMPLATE and its twelve pixels entirely.
      final nominal = _file(source, atX: nominalX, atY: nominalY);
      final moved = _file(source,
          atX: [...nominalX]..[5] = -7, atY: [...nominalY]..[5] = -3);
      expect(moved, isNot(equals(nominal)));
    });

    test('the flag and the twelve pairs reach the segment header', () {
      final data = Jbig2Writer.genericRegion(
        width: 8,
        height: 1,
        extTemplate: true,
        atX: nominalX,
        atY: nominalY,
        codeword: Uint8List(0),
      );
      // 17 bytes of region segment information, then the flags byte.
      expect(data[17] & 0x10, equals(0x10), reason: 'EXTTEMPLATE bit');
      expect(data.length - 18, equals(24), reason: 'twelve AT pairs');
      for (var i = 0; i < 12; i++) {
        expect(data[18 + i * 2].toSigned(8), equals(nominalX[i]));
        expect(data[19 + i * 2].toSigned(8), equals(nominalY[i]));
      }
    });

    test('EXTTEMPLATE is refused where the standard does not allow it', () {
      expect(() => GenericRegionEncoder(source, extTemplate: true, template: 1),
          throwsArgumentError);
      expect(
          () => GenericRegionEncoder(source,
              extTemplate: true, atX: const [0], atY: const [-1]),
          throwsArgumentError);
      expect(
          () => Jbig2Writer.genericRegion(
              width: 8,
              height: 1,
              extTemplate: true,
              mmr: true,
              codeword: Uint8List(0)),
          throwsArgumentError);
    });

    test('the public encoder emits it on request', () {
      final image = Jbig2Image(
        width: source.width,
        height: source.height,
        rowStride: source.rowStride,
        data: source.bitmap,
      );
      const options = Jbig2EncodeOptions(
        mode: Jbig2EncodeMode.genericRegion,
        genericRegionExtTemplate: true,
      );
      for (final encoded in [
        encodeJbig2File(image, options: options),
        encodeJbig2Embedded(image, options: options),
      ]) {
        final decoded = encoded[0] == 0x97
            ? decodeJbig2(encoded)
            : decodeJbig2Embedded(encoded);
        for (var y = 0; y < source.height; y++) {
          for (var x = 0; x < source.width; x++) {
            expect(decoded.isBlack(x, y), equals(source.getPixel(x, y) == 1));
          }
        }
      }
    });
  });
}

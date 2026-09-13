import 'dart:math';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/generic_region_encoder.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:test/test.dart';

/// Text-like content: a few glyph shaped blobs with wide white margins, plus a
/// run of identical rows so typical prediction has something to predict.
Bitmap _page(int width, int height, int seed) {
  final bitmap = Bitmap(width, height);
  final rng = Random(seed);
  for (var glyph = 0; glyph < 12; glyph++) {
    final x0 = rng.nextInt(width - 8);
    final y0 = rng.nextInt(height - 10);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 6; x++) {
        if ((x * 3 + y * 5 + glyph) % 7 < 4) bitmap.setPixel(x0 + x, y0 + y, 1);
      }
    }
  }
  for (var y = height - 6; y < height - 2; y++) {
    for (var x = 2; x < width - 2; x++) {
      bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

/// Wraps a generic region codeword in a one page standalone file.
Uint8List _file(
  Bitmap source, {
  required int template,
  required bool typicalPrediction,
  required List<int> atX,
  required List<int> atY,
}) {
  final codeword = GenericRegionEncoder(
    source,
    template: template,
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
      template: template,
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
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (image.isBlack(x, y) != (source.getPixel(x, y) == 1)) {
        fail('pixel ($x, $y) differs after a round trip');
      }
    }
  }
}

void main() {
  group('6.2 generic region templates', () {
    final source = _page(61, 40, 7);

    for (var template = 0; template < 4; template++) {
      for (final typicalPrediction in [false, true]) {
        test(
            'template $template with the nominal adaptive pixels round trips '
            '${typicalPrediction ? 'with' : 'without'} TPGDON', () {
          _expectRoundTrip(
              source,
              _file(source,
                  template: template,
                  typicalPrediction: typicalPrediction,
                  atX: GenericRegionEncoder.nominalAtX(template),
                  atY: GenericRegionEncoder.nominalAtY(template)));
        });
      }

      test('template $template with moved adaptive pixels round trips', () {
        // 6.2.5.3 lets the AT pixels sit anywhere already decoded. Moving
        // every one of them takes the decoder off its fast path and onto the
        // context override, which has to reproduce the same context the
        // encoder gathered from the figure.
        final atX = template == 0 ? const [-2, -4, 1, -1] : const [-2];
        final atY = template == 0 ? const [0, -1, -2, -2] : const [0];
        _expectRoundTrip(
            source,
            _file(source,
                template: template,
                typicalPrediction: true,
                atX: atX,
                atY: atY));
      });
    }

    test('a template moves every context, so the streams differ', () {
      // If the template number were ignored somewhere, all four encodings
      // would come out byte identical and the round trips above would prove
      // nothing.
      final sizes = <int>{
        for (var template = 0; template < 4; template++)
          _file(source,
                  template: template,
                  typicalPrediction: true,
                  atX: GenericRegionEncoder.nominalAtX(template),
                  atY: GenericRegionEncoder.nominalAtY(template))
              .length,
      };
      expect(sizes.length, greaterThan(1));
    });

    test('an adaptive pixel that is not yet decoded is rejected', () {
      expect(
          () => GenericRegionEncoder(source,
              template: 1, atX: const [1], atY: const [0]),
          throwsArgumentError);
      expect(
          () => GenericRegionEncoder(source,
              template: 1, atX: const [-1], atY: const [1]),
          throwsArgumentError);
    });

    test('the public encoder honours the chosen template', () {
      final image = Jbig2Image.fromPacked(
          width: source.width,
          height: source.height,
          data: source.bitmap,
          rowStride: source.rowStride);
      for (var template = 0; template < 4; template++) {
        final file = encodeJbig2File(image,
            options: Jbig2EncodeOptions(
              mode: Jbig2EncodeMode.genericRegion,
              genericRegionTemplate: template,
            ));
        _expectRoundTrip(source, file);
      }
    });

    test('a template outside 0 to 3 is rejected', () {
      expect(
          () => GenericRegionEncoder(source, template: 4), throwsArgumentError);
    });
  });
}

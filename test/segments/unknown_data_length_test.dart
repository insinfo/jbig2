import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/generic_region_encoder.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:test/test.dart';

/// A diagonal stripe pattern, black where `(x + y) % 7 < 3`.
Bitmap _pattern(int width, int height) {
  final bitmap = Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if ((x + y) % 7 < 3) bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

Uint8List _uint32(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}

/// Builds a one page file whose generic region segment declares the unknown
/// length of T.88 clause 7.2.7.
///
/// [declaredHeight] is what the region segment information field announces and
/// [rows] is how many rows the data really holds, the situation 7.4.6.4 warns
/// about: the trailing row count, not the region header, decides the height.
Uint8List _unknownLengthFile({
  required int width,
  required int declaredHeight,
  required int rows,
  int? pageHeight,
}) {
  final codeword = GenericRegionEncoder(_pattern(width, rows)).encode();
  // The arithmetic codeword already ends with the FF AC of Figure E.11, which
  // is exactly the terminating sequence 7.4.6.4 asks for; the row count goes
  // straight after it.
  final region = Jbig2Writer.genericRegion(
    width: width,
    height: declaredHeight,
    codeword: Uint8List.fromList([...codeword, ..._uint32(rows)]),
  );

  final writer = Jbig2Writer();
  writer.writeFileHeader(pageCount: 1);
  writer.writeSegment(
    number: 0,
    type: Jbig2SegmentType.pageInformation,
    page: 1,
    data: Jbig2Writer.pageInformation(
        width: width, height: pageHeight ?? rows),
  );
  writer.writeSegment(
    number: 1,
    type: Jbig2SegmentType.immediateGenericRegion,
    page: 1,
    data: region,
    declaredLength: Jbig2Writer.unknownDataLength,
  );
  writer.writeSegment(
    number: 2,
    type: Jbig2SegmentType.endOfPage,
    page: 1,
    data: Uint8List(0),
  );
  writer.writeSegment(
    number: 3,
    type: Jbig2SegmentType.endOfFile,
    page: 0,
    data: Uint8List(0),
  );
  return writer.takeBytes();
}

void main() {
  group('7.2.7 unknown segment data length', () {
    test('a generic region of unknown length decodes like a normal one', () {
      const width = 37;
      const height = 24;
      final file = _unknownLengthFile(
        width: width,
        declaredHeight: height,
        rows: height,
      );
      final image = decodeJbig2(file);
      expect(image.width, equals(width));
      expect(image.height, equals(height));

      final expected = _pattern(width, height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          expect(image.isBlack(x, y), equals(expected.getPixel(x, y) == 1),
              reason: 'pixel ($x, $y)');
        }
      }
    });

    test('the trailing row count shortens a region that holds fewer rows', () {
      // 7.4.6.4: "it is also possible that the segment may contain fewer rows
      // of bitmap data than are indicated in the segment's region segment
      // information field".
      const width = 20;
      // The page is as tall as the region claims to be, so a decoder that
      // ignored the row count would fill rows 9 to 63 with whatever the
      // arithmetic decoder invents past the end of the data.
      final file = _unknownLengthFile(
        width: width,
        declaredHeight: 64,
        rows: 9,
        pageHeight: 64,
      );
      final image = decodeJbig2(file);
      expect(image.height, equals(64));

      final expected = _pattern(width, 9);
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < width; x++) {
          expect(image.isBlack(x, y), equals(expected.getPixel(x, y) == 1),
              reason: 'pixel ($x, $y)');
        }
      }
      for (var y = 9; y < 64; y++) {
        for (var x = 0; x < width; x++) {
          expect(image.isBlack(x, y), isFalse, reason: 'pixel ($x, $y)');
        }
      }
    });

    test('the segments after the unknown-length one are still found', () {
      // Resolving the length wrongly would desynchronise the whole segment
      // chain, so the page count coming out of the file header check is the
      // proof that scanning stopped in the right place.
      final file = _unknownLengthFile(
        width: 16,
        declaredHeight: 8,
        rows: 8,
      );
      expect(probeJbig2(file).pageCount, equals(1));
    });

    test('only an immediate generic region may declare an unknown length', () {
      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(width: 8, height: 8),
        declaredLength: Jbig2Writer.unknownDataLength,
      );
      expect(() => decodeJbig2(writer.takeBytes()),
          throwsA(isA<Jbig2Exception>()));
    });

    test('a missing terminating sequence is rejected', () {
      final region = Jbig2Writer.genericRegion(
        width: 8,
        height: 8,
        // Neither FF AC nor 00 00 appears here.
        codeword: Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
      );
      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(width: 8, height: 8),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateGenericRegion,
        page: 1,
        data: region,
        declaredLength: Jbig2Writer.unknownDataLength,
      );
      expect(() => decodeJbig2(writer.takeBytes()),
          throwsA(isA<Jbig2Exception>()));
    });
  });
}

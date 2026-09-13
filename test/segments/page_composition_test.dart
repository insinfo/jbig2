import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/decoder/arithmetic/cx.dart';
import 'package:jbig2/src/encoder/generic_refinement_region_encoder.dart';
import 'package:jbig2/src/encoder/generic_region_encoder.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:jbig2/src/encoder/mq_encoder.dart';
import 'package:jbig2/src/image/bitmaps.dart';
import 'package:jbig2/src/util/rectangle.dart';
import 'package:test/test.dart';

/// Builds a bitmap from rows written as strings, `#` for black.
Bitmap _bitmap(List<String> rows) {
  final bitmap = Bitmap(rows.first.length, rows.length);
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] == '#') bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

List<String> _rows(Jbig2Image image) {
  return List<String>.generate(image.height, (y) {
    final row = StringBuffer();
    for (var x = 0; x < image.width; x++) {
      row.write(image.isBlack(x, y) ? '#' : '.');
    }
    return row.toString();
  });
}

/// A bitmap whose content depends on [seed], so two of them differ everywhere
/// a refinement would have to correct something.
Bitmap _noise(int width, int height, int seed) {
  final bitmap = Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if ((x * 7 + y * 13 + seed * 5) % 11 < 4) bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

Uint8List _genericRegionSegment(Bitmap source, {int x = 0, int y = 0}) {
  return Jbig2Writer.genericRegion(
    width: source.width,
    height: source.height,
    x: x,
    y: y,
    codeword: GenericRegionEncoder(source).encode(),
  );
}

void main() {
  group('8.2 page image composition', () {
    test('a page whose default pixel is 1 starts out black', () {
      // 8.2 3): the buffer is filled with the default pixel value before any
      // region is drawn, so the part of the page no region covers stays black.
      final region = _bitmap(const [
        '........',
        '..####..',
        '..####..',
        '........',
      ]);
      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(
          width: 16,
          height: 8,
          defaultPixelBlack: true,
          // AND, so the region can clear pixels on a black page.
          defaultCombinationOperator: 1,
        ),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(region, x: 4, y: 2),
      );
      writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0),
      );

      expect(
          _rows(decodeJbig2(writer.takeBytes())),
          equals(const [
            '################',
            '################',
            '####........####',
            '####..####..####',
            '####..####..####',
            '####........####',
            '################',
            '################',
          ]));
    });

    test('a striped page of unknown height is as tall as its last stripe', () {
      // 7.4.8.2 lets the height be 0xFFFFFFFF and 7.4.9 then supplies it: the
      // end of stripe segment gives the Y coordinate of the stripe's last row.
      final top = _bitmap(const [
        '########',
        '#......#',
        '#......#',
        '########',
      ]);
      final bottom = _bitmap(const [
        '..####..',
        '.######.',
        '.######.',
        '..####..',
      ]);

      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(
          width: 8,
          height: Jbig2Writer.unknownPageHeight,
          striped: true,
          maxStripeSize: 4,
        ),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(top, y: 0),
      );
      writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.endOfStripe,
        page: 1,
        data: Jbig2Writer.endOfStripe(3),
      );
      writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(bottom, y: 4),
      );
      writer.writeSegment(
        number: 4,
        type: Jbig2SegmentType.endOfStripe,
        page: 1,
        data: Jbig2Writer.endOfStripe(7),
      );
      writer.writeSegment(
        number: 5,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0),
      );

      final image = decodeJbig2(writer.takeBytes());
      expect(image.height, equals(8));
      expect(
          _rows(image),
          equals(const [
            '########',
            '#......#',
            '#......#',
            '########',
            '..####..',
            '.######.',
            '.######.',
            '..####..',
          ]));
    });

    test('a striped page keeps its default pixel value', () {
      // The striped path has its own buffer allocation, so 8.2 3) has to be
      // honoured there too.
      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(
          width: 8,
          height: Jbig2Writer.unknownPageHeight,
          defaultPixelBlack: true,
          striped: true,
          maxStripeSize: 4,
        ),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(Bitmap(8, 2), y: 0),
      );
      writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.endOfStripe,
        page: 1,
        data: Jbig2Writer.endOfStripe(3),
      );
      writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0),
      );

      final image = decodeJbig2(writer.takeBytes());
      expect(image.height, equals(4));
      // The region ORs two blank rows over a black page, which changes
      // nothing; every row stays black.
      expect(_rows(image), equals(List<String>.filled(4, '########')));
    });

    test('a striped page without an end of stripe segment still has rows', () {
      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(
          width: 8,
          height: Jbig2Writer.unknownPageHeight,
          striped: true,
          maxStripeSize: 4,
        ),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(
            _bitmap(const ['########', '........', '########']),
            y: 1),
      );
      writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0),
      );

      final image = decodeJbig2(writer.takeBytes());
      expect(image.height, equals(4));
      expect(
          _rows(image),
          equals(const [
            '........',
            '########',
            '........',
            '########',
          ]));
    });

    test('a refinement region referring to nothing refines the page buffer',
        () {
      // 8.2 5) c): "the region segment is acting as a refinement of part of the
      // page buffer [...] This replaces a part of the page buffer with a
      // refined version."
      const width = 40;
      const height = 24;
      final background = _noise(width, height, 1);
      final refined = _noise(24, 16, 2);

      final reference =
          Bitmaps.extract(Rectangle(8, 4, 24, 16), background);
      final mq = MqEncoder();
      GenericRefinementRegionEncoder(refined, reference)
          .encodeInto(mq, CX(1 << 13, 0));

      final writer = Jbig2Writer();
      writer.writeFileHeader(pageCount: 1);
      writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(width: width, height: height),
      );
      writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: 1,
        data: _genericRegionSegment(background),
      );
      writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.immediateLosslessGenericRefinementRegion,
        page: 1,
        data: Jbig2Writer.refinementRegion(
          width: 24,
          height: 16,
          x: 8,
          y: 4,
          codeword: mq.flush(),
        ),
      );
      writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0),
      );

      final image = decodeJbig2(writer.takeBytes());
      expect(image.width, equals(width));
      expect(image.height, equals(height));
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final inside = x >= 8 && x < 32 && y >= 4 && y < 20;
          final expected = inside
              ? refined.getPixel(x - 8, y - 4)
              : background.getPixel(x, y);
          expect(image.isBlack(x, y), equals(expected == 1),
              reason: 'pixel ($x, $y)');
        }
      }
      // The refinement really changed something, so the test is not passing by
      // the two bitmaps happening to agree.
      var differences = 0;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 24; x++) {
          if (refined.getPixel(x, y) != reference.getPixel(x, y)) {
            differences++;
          }
        }
      }
      expect(differences, greaterThan(50));
    });
  });
}

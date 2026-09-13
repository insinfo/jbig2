import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/halftone_region_encoder.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:jbig2/src/util/combination_operator.dart';
import 'package:test/test.dart';

const int _patternSize = 8;

/// Eight visually distinct 8 x 8 patterns, index 0 blank.
List<Bitmap> _patterns() {
  return List<Bitmap>.generate(8, (index) {
    final pattern = Bitmap(_patternSize, _patternSize);
    for (var y = 0; y < _patternSize; y++) {
      for (var x = 0; x < _patternSize; x++) {
        final on = switch (index) {
          0 => false,
          1 => (x + y).isEven,
          2 => x < 4,
          3 => y < 4,
          4 => x == y || x + y == 7,
          5 => x == 0 || y == 0 || x == 7 || y == 7,
          6 => (x ~/ 2 + y ~/ 2).isOdd,
          _ => true,
        };
        if (on) pattern.setPixel(x, y, 1);
      }
    }
    return pattern;
  });
}

/// The image a grid of patterns tiles, which is what the halftone region has
/// to reproduce pixel for pixel.
Bitmap _render(List<List<int>> grid, List<Bitmap> patterns, int offsetNg,
    int offsetMg, int width, int height) {
  final image = Bitmap(width, height);
  for (var mg = 0; mg < grid.length; mg++) {
    for (var ng = 0; ng < grid[mg].length; ng++) {
      final pattern = patterns[grid[mg][ng]];
      final originX = (ng - offsetNg) * _patternSize;
      final originY = (mg - offsetMg) * _patternSize;
      for (var y = 0; y < _patternSize; y++) {
        for (var x = 0; x < _patternSize; x++) {
          final targetX = originX + x;
          final targetY = originY + y;
          if (targetX < 0 ||
              targetY < 0 ||
              targetX >= width ||
              targetY >= height) {
            continue;
          }
          if (pattern.getPixel(x, y) == 1)
            image.writePixel(targetX, targetY, 1);
        }
      }
    }
  }
  return image;
}

Uint8List _file(
  PatternDictionaryEncoder dictionary,
  HalftoneRegionEncoder region,
  int width,
  int height, {
  bool pageDefaultPixelBlack = false,
  int pageCombinationOperator = 0,
}) {
  final writer = Jbig2Writer();
  writer.writeFileHeader(pageCount: 1);
  writer.writeSegment(
    number: 0,
    type: Jbig2SegmentType.pageInformation,
    page: 1,
    data: Jbig2Writer.pageInformation(
      width: width,
      height: height,
      defaultPixelBlack: pageDefaultPixelBlack,
      defaultCombinationOperator: pageCombinationOperator,
    ),
  );
  writer.writeSegment(
    number: 1,
    type: 16, // Pattern dictionary
    page: 1,
    data: dictionary.encode(),
  );
  writer.writeSegment(
    number: 2,
    type: 23, // Immediate lossless halftone region
    page: 1,
    referredTo: const [1],
    data: region.encode(),
  );
  writer.writeSegment(
    number: 3,
    type: Jbig2SegmentType.endOfPage,
    page: 1,
    data: Uint8List(0),
  );
  return writer.takeBytes();
}

void _expectSame(Jbig2Image actual, Bitmap expected) {
  expect(actual.width, equals(expected.width));
  expect(actual.height, equals(expected.height));
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      if (actual.isBlack(x, y) != (expected.getPixel(x, y) == 1)) {
        fail('pixel ($x, $y) differs');
      }
    }
  }
}

void main() {
  group('6.6 halftone region and 6.7 pattern dictionary', () {
    final patterns = _patterns();
    const columns = 5;
    const rows = 4;
    const width = columns * _patternSize;
    const height = rows * _patternSize;

    List<List<int>> gridOf(int offsetNg, int offsetMg) {
      return List<List<int>>.generate(rows + offsetMg, (mg) {
        return List<int>.generate(columns + offsetNg, (ng) {
          if (ng < offsetNg || mg < offsetMg) return 0;
          return ((ng - offsetNg) * 3 + (mg - offsetMg) * 5) % patterns.length;
        });
      });
    }

    for (var template = 0; template < 4; template++) {
      test('a grid of patterns round trips with template $template', () {
        final grid = gridOf(0, 0);
        final dictionary =
            PatternDictionaryEncoder(patterns, template: template);
        final region = HalftoneRegionEncoder(
          grid: grid,
          dictionary: dictionary,
          regionWidth: width,
          regionHeight: height,
          template: template,
        );
        final image = decodeJbig2(_file(dictionary, region, width, height));
        _expectSame(image, _render(grid, patterns, 0, 0, width, height));
      });
    }

    test('HENABLESKIP leaves the cells outside the region uncoded', () {
      // 6.6.5.1 computes HSKIP from the grid geometry; a cell whose pattern
      // misses the region is not coded at all, so the decoder has to skip the
      // very same cells or the arithmetic decoder falls out of step for the
      // whole rest of the grey-scale image.
      final grid = gridOf(1, 1);
      final dictionary = PatternDictionaryEncoder(patterns);
      final region = HalftoneRegionEncoder(
        grid: grid,
        dictionary: dictionary,
        regionWidth: width,
        regionHeight: height,
        // One column to the left of the region and one row above it.
        gridX: -_patternSize << 8,
        gridY: -_patternSize << 8,
        enableSkip: true,
      );

      final skip = region.skipBitmap();
      var skipped = 0;
      for (var mg = 0; mg < grid.length; mg++) {
        for (var ng = 0; ng < grid[mg].length; ng++) {
          if (skip.getPixel(ng, mg) == 1) skipped++;
        }
      }
      expect(skipped, equals(rows + 1 + columns));

      final image = decodeJbig2(_file(dictionary, region, width, height));
      _expectSame(image, _render(grid, patterns, 1, 1, width, height));
    });

    test('skipping actually shortens the grey-scale image', () {
      final grid = gridOf(1, 1);
      final dictionary = PatternDictionaryEncoder(patterns);
      HalftoneRegionEncoder build({required bool enableSkip}) {
        return HalftoneRegionEncoder(
          grid: grid,
          dictionary: dictionary,
          regionWidth: width,
          regionHeight: height,
          gridX: -_patternSize << 8,
          gridY: -_patternSize << 8,
          enableSkip: enableSkip,
        );
      }

      expect(build(enableSkip: true).encode().length,
          lessThan(build(enableSkip: false).encode().length));
    });

    test('HDEFPIXEL and HCOMBOP put the patterns onto a black region', () {
      // The region starts out black and every pattern is ANDed into it, so the
      // result is the patterns themselves; decoding it wrongly would leave the
      // region solid black.
      final grid = gridOf(0, 0);
      final dictionary = PatternDictionaryEncoder(patterns);
      final region = HalftoneRegionEncoder(
        grid: grid,
        dictionary: dictionary,
        regionWidth: width,
        regionHeight: height,
        defaultPixelBlack: true,
        combinationOperator: CombinationOperator.AND,
      );
      final image = decodeJbig2(_file(dictionary, region, width, height));
      _expectSame(image, _render(grid, patterns, 0, 0, width, height));
    });

    test('a grid coarser than the patterns leaves the gaps at the default', () {
      // HRX larger than HPW spreads the patterns out, which is the case
      // NOTE 3 of 6.6.5 calls out as not being the simple axis-aligned grid.
      final grid = gridOf(0, 0);
      final dictionary = PatternDictionaryEncoder(patterns);
      const step = _patternSize + 2;
      final region = HalftoneRegionEncoder(
        grid: grid,
        dictionary: dictionary,
        regionWidth: columns * step,
        regionHeight: rows * step,
        vectorX: step << 8,
      );
      final image =
          decodeJbig2(_file(dictionary, region, columns * step, rows * step));

      final expected = Bitmap(columns * step, rows * step);
      for (var mg = 0; mg < rows; mg++) {
        for (var ng = 0; ng < columns; ng++) {
          final pattern = patterns[grid[mg][ng]];
          for (var y = 0; y < _patternSize; y++) {
            for (var x = 0; x < _patternSize; x++) {
              if (pattern.getPixel(x, y) == 1) {
                expected.writePixel(ng * step + x, mg * step + y, 1);
              }
            }
          }
        }
      }
      _expectSame(image, expected);
    });

    test('the pattern dictionary rejects sizes it cannot store', () {
      expect(() => PatternDictionaryEncoder([patterns.first]),
          throwsArgumentError);
      expect(() => PatternDictionaryEncoder([patterns[0], Bitmap(4, 4)]),
          throwsArgumentError);
    });

    test('a grid value outside the dictionary is rejected', () {
      expect(
          () => HalftoneRegionEncoder(
                grid: const [
                  [0, 99]
                ],
                dictionary: PatternDictionaryEncoder(patterns),
                regionWidth: 16,
                regionHeight: 8,
              ),
          throwsArgumentError);
    });
  });
}

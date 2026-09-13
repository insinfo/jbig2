import 'package:test/test.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/image/bitmaps.dart';
import 'package:jbig2/src/util/combination_operator.dart';
import 'package:jbig2/src/util/rectangle.dart';
import 'dart:math';

/// Fills [bitmap] with random pixels.
///
/// The bits past the last column of a row are padding, not pixels, and a
/// bitmap is defined to keep them clear; writing random bytes straight into
/// the array would make an image whose two halves — pixels and padding —
/// disagree with each other.
void _randomise(Bitmap bitmap, Random rng) {
  for (int y = 0; y < bitmap.height; y++) {
    for (int x = 0; x < bitmap.width; x++) {
      bitmap.writePixel(x, y, rng.nextInt(2));
    }
  }
}

void main() {
  group('BitmapsBlitTest', () {
    test('testCompleteBitmapTransfer', () {
      final width = 100;
      final height = 100;
      final src = Bitmap(width, height);
      final rng = Random();
      _randomise(src, rng);

      final dst = Bitmap(width, height);
      Bitmaps.blit(src, dst, 0, 0, CombinationOperator.REPLACE);

      expect(dst.getByteArray(), equals(src.getByteArray()));
    });

    test('test', () {
      // Create a dst bitmap with some data
      final width = 500;
      final height = 500;
      final dst = Bitmap(width, height);
      final rng = Random();
      _randomise(dst, rng);

      final roi = Rectangle(100, 100, 100, 100);
      final src = Bitmap(roi.width, roi.height);
      // src is blank (all zeros)

      Bitmaps.blit(src, dst, roi.x, roi.y, CombinationOperator.REPLACE);

      final dstRegionBitmap = Bitmaps.extract(roi, dst);

      expect(dstRegionBitmap.getByteArray(), equals(src.getByteArray()));
    });

    test('an operator whose identity is 1 leaves the pixels around the region '
        'alone', () {
      // 7.4.1.5 allows AND, XNOR and REPLACE as well as OR and XOR. A blit
      // that writes whole destination bytes would drag the zero bits padding
      // the source row into the destination, clearing pixels several columns
      // to either side of the region.
      for (final op in [
        CombinationOperator.AND,
        CombinationOperator.XNOR,
        CombinationOperator.REPLACE,
      ]) {
        final dst = Bitmap(32, 4);
        for (int y = 0; y < dst.height; y++) {
          for (int x = 0; x < dst.width; x++) {
            dst.writePixel(x, y, 1);
          }
        }

        // A blank source, five pixels wide, at an offset that is neither byte
        // aligned nor a whole number of bytes long.
        final src = Bitmap(5, 2);
        Bitmaps.blit(src, dst, 3, 1, op);

        for (int y = 0; y < dst.height; y++) {
          for (int x = 0; x < dst.width; x++) {
            final inside = x >= 3 && x < 8 && y >= 1 && y < 3;
            final expected = inside
                ? Bitmaps.combinePixels(1, 0, op)
                : 1;
            expect(dst.getPixel(x, y), equals(expected),
                reason: '$op at pixel ($x, $y)');
          }
        }
      }
    });
  });
}

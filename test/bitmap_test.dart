import 'package:test/test.dart';
import 'package:jbig2/src/bitmap.dart';

void main() {
  group('BitmapTest', () {
    test('getPixelAndSetPixelTest', () {
      final bitmap = Bitmap(37, 49);
      expect(bitmap.getPixel(3, 19), 0);

      bitmap.setPixel(3, 19, 1);

      expect(bitmap.getPixel(3, 19), 1);
    });

    test('getByteAndSetByteTest', () {
      final bitmap = Bitmap(16, 16);

      final int value = 4;
      bitmap.setByte(0, value);
      bitmap.setByte(31, value);

      expect(bitmap.getByte(0), value);
      expect(bitmap.getByte(31), value);
    });

    test('getByteThrowsExceptionTest', () {
      final bitmap = Bitmap(16, 16);
      expect(() => bitmap.getByte(32), throwsRangeError);
    });

    test('setByteThrowsExceptionTest', () {
      final bitmap = Bitmap(16, 16);
      expect(() => bitmap.setByte(32, 0), throwsRangeError);
    });

    test('getByteAsIntegerTest', () {
      final bitmap = Bitmap(16, 16);

      final int byteValue = 4;
      final int integerValue = byteValue;
      bitmap.setByte(0, byteValue);
      bitmap.setByte(31, byteValue);

      expect(bitmap.getByteAsInteger(0), integerValue);
      expect(bitmap.getByteAsInteger(31), integerValue);
    });

    test('getByteAsIntegerThrowsExceptionTest', () {
      final bitmap = Bitmap(16, 16);
      expect(() => bitmap.getByteAsInteger(32), throwsRangeError);
    });

    test('getHeightTest', () {
      final int height = 16;
      final bitmap = Bitmap(1, height);
      expect(bitmap.height, height);
    });

    test('getWidthTest', () {
      final int width = 16;
      final bitmap = Bitmap(width, 1);
      expect(bitmap.width, width);
    });
  });
}

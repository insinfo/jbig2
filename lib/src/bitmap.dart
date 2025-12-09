import 'dart:math';
import 'dart:typed_data';

/// This class represents a bi-level image that is organized like a bitmap.
class Bitmap {
  /// The height of the bitmap in pixels.
  final int height;

  /// The width of the bitmap in pixels.
  final int width;

  /// The amount of bytes used per row.
  final int rowStride;

  /// 8 pixels per byte, 0 for white, 1 for black
  final Uint8List bitmap;

  /// Creates an instance of a blank image.
  /// The image data is stored in a byte array. Each pixels is stored as one bit, so that each byte
  /// contains 8 pixel. A pixel has by default the value 0 for white and 1 for black.
  /// Row stride means the amount of bytes per line. It is computed automatically and fills the pad
  /// bits with 0.
  ///
  /// [width] - The real width of the bitmap in pixels.
  /// [height] - The real height of the bitmap in pixels.
  Bitmap(this.width, this.height)
      : rowStride = (width + 7) >> 3,
        bitmap = Uint8List(height * ((width + 7) >> 3));

  /// Returns the value of a pixel specified by the given coordinates.
  ///
  /// By default, the value is 0 for a white pixel and 1 for a black pixel. The value
  /// is placed in the rightmost bit in the byte.
  ///
  /// [x] - The x coordinate of the pixel.
  /// [y] - The y coordinate of the pixel.
  /// Returns The value of a pixel.
  int getPixel(int x, int y) {
    int byteIndex = getByteIndex(x, y);
    int bitOffset = getBitOffset(x);

    int toShift = 7 - bitOffset;
    return (getByte(byteIndex) >> toShift) & 0x01;
  }

  void setPixel(int x, int y, int pixelValue) {
    final byteIndex = getByteIndex(x, y);
    final bitOffset = getBitOffset(x);

    final shift = 7 - bitOffset;

    final src = bitmap[byteIndex];
    final result = (src | (pixelValue << shift));
    bitmap[byteIndex] = result;
  }

  /// Returns the index of the byte that contains the pixel, specified by the pixel's x and y
  /// coordinates.
  ///
  /// [x] - The pixel's x coordinate.
  /// [y] - The pixel's y coordinate.
  /// Returns The index of the byte that contains the specified pixel.
  int getByteIndex(int x, int y) {
    return y * rowStride + (x >> 3);
  }

  /// Simply returns the byte array of this bitmap.
  ///
  /// Returns The byte array of this bitmap.
  Uint8List getByteArray() {
    return bitmap;
  }

  /// Simply returns a byte from the bitmap byte array. Throws an [RangeError]
  /// if the given index is out of bound.
  ///
  /// [index] - The array index that specifies the position of the wanted byte.
  /// Returns The byte at the [index]-position.
  int getByte(int index) {
    return bitmap[index];
  }

  /// Simply sets the given value at the given array index position. Throws an
  /// [RangeError] if the given index is out of bound.
  ///
  /// [index] - The array index that specifies the position of a byte.
  /// [value] - The byte that should be set.
  void setByte(int index, int value) {
    bitmap[index] = value;
  }

  /// Converts the byte at specified index into an integer and returns the value. Throws an
  /// [RangeError] if the given index is out of bound.
  ///
  /// [index] - The array index that specifies the position of the wanted byte.
  /// Returns The converted byte at the [index]-position as an integer.
  int getByteAsInteger(int index) {
    return bitmap[index] & 0xff;
  }

  /// Computes the offset of the given x coordinate in its byte. The method uses optimized modulo
  /// operation for a better performance.
  ///
  /// [x] - The x coordinate of a pixel.
  /// Returns The bit offset of a pixel in its byte.
  int getBitOffset(int x) {
    // The same like x % 8.
    // The rightmost three bits are 1. The value masks all bits upon the value "7".
    return (x & 0x07);
  }

  Rectangle<int> getBounds() {
    return Rectangle<int>(0, 0, width, height);
  }

  int getMemorySize() {
    return bitmap.length;
  }
}

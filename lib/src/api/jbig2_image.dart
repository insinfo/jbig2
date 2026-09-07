import 'dart:typed_data';

import '../bitmap.dart';

/// A decoded bi-level image.
///
/// Pixels are packed eight to a byte, most significant bit first, with each row
/// starting on a byte boundary. A set bit is a **black** pixel, which is the
/// JBIG2 convention and the opposite of PDF's `/DeviceGray` sample convention;
/// [toPdfImageData] does that inversion for you.
class Jbig2Image {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Bytes per row, including the padding bits at the end of a row.
  final int rowStride;

  /// Packed pixel data, `rowStride * height` bytes long. A set bit is black.
  final Uint8List data;

  Jbig2Image({
    required this.width,
    required this.height,
    required this.rowStride,
    required this.data,
  });

  /// Wraps a decoded internal bitmap without copying its bytes.
  factory Jbig2Image.fromBitmap(Bitmap bitmap) => Jbig2Image(
        width: bitmap.width,
        height: bitmap.height,
        rowStride: bitmap.rowStride,
        data: bitmap.getByteArray(),
      );

  /// Builds an image from packed rows, one bit per pixel, black bits set.
  ///
  /// [data] must hold `rowStride * height` bytes, where [rowStride] defaults to
  /// the tightest packing of [width].
  factory Jbig2Image.fromPacked({
    required int width,
    required int height,
    required Uint8List data,
    int? rowStride,
  }) {
    final stride = rowStride ?? ((width + 7) >> 3);
    if (width <= 0 || height <= 0) {
      throw ArgumentError('An image must have a positive extent.');
    }
    if (stride < ((width + 7) >> 3)) {
      throw ArgumentError(
          'rowStride $stride is too small for a width of $width.');
    }
    if (data.length < stride * height) {
      throw ArgumentError('data holds ${data.length} bytes, but '
          '${stride * height} are needed for ${width}x$height.');
    }
    return Jbig2Image(
        width: width, height: height, rowStride: stride, data: data);
  }

  /// Number of pixels in the image.
  int get pixelCount => width * height;

  /// True when the pixel at ([x], [y]) is black.
  ///
  /// Coordinates outside the image are white, which matches how JBIG2 composes
  /// a region that overhangs its page.
  bool isBlack(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final byte = data[y * rowStride + (x >> 3)];
    return (byte >> (7 - (x & 7))) & 1 == 1;
  }

  /// Expands the image to one byte per pixel, 0 for black and 255 for white.
  ///
  /// This is the `/DeviceGray` 8-bit form, ready to hand to an image library
  /// or to re-encode as PNG or JPEG.
  Uint8List toGrayscale() {
    final out = Uint8List(width * height);
    var index = 0;
    for (var y = 0; y < height; y++) {
      final row = y * rowStride;
      for (var x = 0; x < width; x++) {
        final byte = data[row + (x >> 3)];
        out[index++] = ((byte >> (7 - (x & 7))) & 1) == 1 ? 0 : 255;
      }
    }
    return out;
  }

  /// The packed rows a PDF `/ImageMask` or 1-bit `/DeviceGray` image expects.
  ///
  /// PDF reads a 1 bit sample as white and a 0 as black, the opposite of
  /// JBIG2, so every bit is inverted. Padding bits at the end of a row are set
  /// to 1 (white) so a viewer that ignores the width does not draw a black
  /// margin.
  Uint8List toPdfImageData() {
    final out = Uint8List(rowStride * height);
    final usedBits = width & 7;
    final lastByte = (width + 7) >> 3;
    for (var y = 0; y < height; y++) {
      final row = y * rowStride;
      for (var i = 0; i < rowStride; i++) {
        out[row + i] = ~data[row + i] & 0xff;
      }
      if (usedBits != 0 && lastByte <= rowStride) {
        // Bits beyond `width` are padding; leave them white.
        final keep = 0xff << (8 - usedBits) & 0xff;
        out[row + lastByte - 1] =
            (out[row + lastByte - 1] & keep) | (~keep & 0xff);
      }
    }
    return out;
  }

  /// Converts back to the internal bitmap the codec works on.
  Bitmap toBitmap() {
    final bitmap = Bitmap(width, height);
    if (bitmap.rowStride == rowStride) {
      bitmap.bitmap.setRange(0, bitmap.bitmap.length, data);
    } else {
      for (var y = 0; y < height; y++) {
        bitmap.bitmap.setRange(y * bitmap.rowStride,
            y * bitmap.rowStride + bitmap.rowStride, data, y * rowStride);
      }
    }
    return bitmap;
  }

  @override
  String toString() => 'Jbig2Image(${width}x$height)';
}

/// What a header says about an image, without decoding a pixel.
///
/// Reading this first lets a caller apply a size policy before any allocation.
class Jbig2ImageInfo {
  /// Width in pixels of the first, or requested, page.
  final int width;

  /// Height in pixels. A page whose height was unknown when it was written
  /// reports the height reached by its end-of-stripe segments.
  final int height;

  /// Pages the stream carries.
  final int pageCount;

  /// Resolution in pixels per metre, or 0 when the stream does not say.
  final int xResolution, yResolution;

  const Jbig2ImageInfo({
    required this.width,
    required this.height,
    required this.pageCount,
    this.xResolution = 0,
    this.yResolution = 0,
  });

  int get pixelCount => width * height;

  @override
  String toString() => 'Jbig2ImageInfo(${width}x$height, $pageCount page(s))';
}

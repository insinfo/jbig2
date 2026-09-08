import '../bitmap.dart';
import '../decoder/arithmetic/cx.dart';
import 'mq_encoder.dart';

/// Encodes a lossless generic refinement bitmap with T.88 template 1.
class GenericRefinementRegionEncoder {
  final Bitmap bitmap;
  final Bitmap reference;
  final int referenceDX;
  final int referenceDY;

  const GenericRefinementRegionEncoder(this.bitmap, this.reference,
      {this.referenceDX = 0, this.referenceDY = 0});

  void encodeInto(MqEncoder encoder, CX context) {
    for (var y = 0; y < bitmap.height; y++) {
      for (var x = 0; x < bitmap.width; x++) {
        final referenceX = x - referenceDX;
        final referenceY = y - referenceDY;
        final c1 = _three(reference, referenceX, referenceY - 1);
        final c2 = _three(reference, referenceX, referenceY);
        final c3 = _three(reference, referenceX, referenceY + 1);
        final c4 = _three(bitmap, x, y - 1);
        final c5 = _pixel(bitmap, x - 1, y);
        final index = ((c1 & 0x02) << 8) |
            (c2 << 6) |
            ((c3 & 0x03) << 4) |
            (c4 << 1) |
            c5;
        context.setIndex(index);
        encoder.encode(context, bitmap.getPixel(x, y));
      }
    }
  }

  static int _three(Bitmap source, int x, int y) =>
      (_pixel(source, x - 1, y) << 2) |
      (_pixel(source, x, y) << 1) |
      _pixel(source, x + 1, y);

  static int _pixel(Bitmap source, int x, int y) =>
      x < 0 || y < 0 || x >= source.width || y >= source.height
          ? 0
          : source.getPixel(x, y);
}

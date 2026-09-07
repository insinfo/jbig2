import 'dart:typed_data';

import '../bitmap.dart';
import '../decoder/arithmetic/cx.dart';
import 'mq_encoder.dart';

/// Encodes a bi-level bitmap as a JBIG2 generic region, template 0, with the
/// nominal adaptive pixels.
///
/// The context recurrence below is the exact mirror of the decoder's
/// `_decodeTemplate0a`: the same sliding window over the two rows above and the
/// pixels already coded on the current row. Deriving it from the decoder rather
/// than from the figure in the specification is deliberate — it makes encoder
/// and decoder agree by construction, and the round-trip tests check that.
///
/// Template 0 with nominal AT pixels is what general purpose encoders emit for
/// scanned pages; symbol dictionaries and refinement, which pay off only on
/// text with many repeated glyphs, are not produced here.
class GenericRegionEncoder {
  /// The source image. Set bits are black, as everywhere in this package.
  final Bitmap bitmap;

  /// Emit typical prediction (TPGDON) so a row identical to the one above
  /// costs a single decision instead of a full row of pixels.
  final bool typicalPrediction;

  GenericRegionEncoder(this.bitmap, {this.typicalPrediction = true});

  /// Context value the specification reserves for the TPGDON decision under
  /// template 0.
  static const int _sltpContext = 0x9b25;

  /// Encodes the bitmap and returns the arithmetic codeword.
  Uint8List encode() {
    final encoder = MqEncoder();
    final cx = CX(1 << 16, 0);
    final width = bitmap.width;
    final height = bitmap.height;
    final rowStride = bitmap.rowStride;
    final paddedWidth = (width + 7) & -8;

    var ltp = 0;
    for (var line = 0; line < height; line++) {
      if (typicalPrediction) {
        final duplicate = line > 0 && _rowsMatch(line, line - 1);
        final wanted = duplicate ? 1 : 0;
        cx.index = _sltpContext;
        encoder.encode(cx, ltp ^ wanted);
        ltp = wanted;
        if (ltp == 1) continue;
      }
      _encodeLine(encoder, cx, line, width, rowStride, paddedWidth);
    }
    return encoder.flush();
  }

  bool _rowsMatch(int a, int b) {
    final stride = bitmap.rowStride;
    final data = bitmap.bitmap;
    final left = a * stride;
    final right = b * stride;
    for (var i = 0; i < stride; i++) {
      if (data[left + i] != data[right + i]) return false;
    }
    return true;
  }

  void _encodeLine(MqEncoder encoder, CX cx, int lineNumber, int width,
      int rowStride, int paddedWidth) {
    final byteIndex = bitmap.getByteIndex(0, lineNumber);
    var idx = byteIndex - rowStride;

    var line1 = 0;
    var line2 = 0;
    if (lineNumber >= 1) {
      line1 = bitmap.getByte(idx);
    }
    if (lineNumber >= 2) {
      line2 = bitmap.getByte(idx - rowStride) << 6;
    }

    var context = (line1 & 0xf0) | (line2 & 0x3800);
    var current = byteIndex;

    int nextByte;
    for (var x = 0; x < paddedWidth; x = nextByte) {
      nextByte = x + 8;
      final minorWidth = width - x > 8 ? 8 : width - x;
      final source = bitmap.getByte(current);

      if (lineNumber > 0) {
        line1 = (line1 << 8) | (nextByte < width ? bitmap.getByte(idx + 1) : 0);
      }
      if (lineNumber > 1) {
        line2 = (line2 << 8) |
            (nextByte < width ? bitmap.getByte(idx - rowStride + 1) << 6 : 0);
      }

      for (var minorX = 0; minorX < minorWidth; minorX++) {
        final toShift = 7 - minorX;
        cx.index = context;
        final bit = (source >> toShift) & 1;
        encoder.encode(cx, bit);
        context = ((context & 0x7bf7) << 1) |
            bit |
            ((line1 >> toShift) & 0x10) |
            ((line2 >> toShift) & 0x800);
      }

      current++;
      idx++;
    }
  }
}

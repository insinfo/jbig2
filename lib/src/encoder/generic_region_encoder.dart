import 'dart:typed_data';

import '../bitmap.dart';
import '../decoder/arithmetic/cx.dart';
import 'mq_encoder.dart';

/// Encodes a bi-level bitmap as a JBIG2 generic region (T.88 clause 6.2).
///
/// All four templates of 6.2.5.3 are supported, with the nominal adaptive
/// pixels or with any other causal ones. Template 0 with the nominal AT pixels
/// — what general purpose encoders emit for scanned pages — goes through a
/// byte-wide context recurrence that is the exact mirror of the decoder's
/// `_decodeTemplate0a`; every other combination goes through a per-pixel path
/// that gathers the template straight from the figures of 6.2.5.3. Deriving
/// the fast path from the decoder rather than from the figures is deliberate:
/// it makes encoder and decoder agree by construction, and the round-trip
/// tests check both paths against the decoder.
class GenericRegionEncoder {
  /// The source image. Set bits are black, as everywhere in this package.
  final Bitmap bitmap;

  /// Emit typical prediction (TPGDON) so a row identical to the one above
  /// costs a single decision instead of a full row of pixels.
  final bool typicalPrediction;

  /// GBTEMPLATE of 7.4.6.2, 0 to 3.
  final int template;

  /// GBATX, one entry for template 0 and four for the others (7.4.6.3).
  final List<int> atX;

  /// GBATY, paired with [atX].
  final List<int> atY;

  /// 6.2.5.6 SKIP: pixels masked here are not coded at all, and the decoder
  /// leaves them at 0. They must already be 0 in [bitmap].
  final Bitmap? skip;

  GenericRegionEncoder(
    this.bitmap, {
    this.typicalPrediction = true,
    this.template = 0,
    List<int>? atX,
    List<int>? atY,
    this.skip,
  })  : atX = atX ?? nominalAtX(template),
        atY = atY ?? nominalAtY(template) {
    if (template < 0 || template > 3) {
      throw ArgumentError('GBTEMPLATE is 0 to 3, not $template.');
    }
    final needed = template == 0 ? 4 : 1;
    if (this.atX.length < needed || this.atY.length < needed) {
      throw ArgumentError('Template $template needs $needed adaptive pixels.');
    }
    for (var i = 0; i < needed; i++) {
      final x = this.atX[i];
      final y = this.atY[i];
      if (y > 0 || (y == 0 && x >= 0)) {
        throw ArgumentError(
            'Adaptive pixel ${i + 1} at ($x, $y) is not yet decoded when the '
            'current pixel is coded.');
      }
    }
  }

  /// The nominal AT positions of 6.2.5.3 for [template].
  static List<int> nominalAtX(int template) => template == 0
      ? const [3, -3, 2, -2]
      : (template <= 1 ? const [3] : const [2]);

  /// The nominal AT ordinates of 6.2.5.3 for [template].
  static List<int> nominalAtY(int template) =>
      template == 0 ? const [-1, -1, -2, -2] : const [-1];

  /// Context values 6.2.5.7 reserves for the TPGDON decision, one per
  /// template.
  static const List<int> sltpContexts = [0x9b25, 0x0795, 0x00e5, 0x0195];

  /// The template pixels of 6.2.5.3, most significant bit of the context
  /// first, with the adaptive pixels written as negative markers: -1 is AT1,
  /// -2 is AT2 and so on.
  static const List<List<List<int>>> _templates = [
    // Figure 4, GBTEMPLATE 0: 16 pixels.
    [
      [-4, 0], [-1, -2], [0, -2], [1, -2], [-3, 0], [-2, 0], //
      [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [-1, 0], //
      [-4, 0], [-3, 0], [-2, 0], [-1, 0]
    ],
    // Figure 5, GBTEMPLATE 1: 13 pixels.
    [
      [-1, -2], [0, -2], [1, -2], [2, -2], //
      [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [-1, 0], //
      [-3, 0], [-2, 0], [-1, 0]
    ],
    // Figure 6, GBTEMPLATE 2: 10 pixels.
    [
      [-1, -2], [0, -2], [1, -2], //
      [-2, -1], [-1, -1], [0, -1], [1, -1], [-1, 0], //
      [-2, 0], [-1, 0]
    ],
    // Figure 7, GBTEMPLATE 3: 10 pixels.
    [
      [-3, -1], [-2, -1], [-1, -1], [0, -1], [1, -1], [-1, 0], //
      [-4, 0], [-3, 0], [-2, 0], [-1, 0]
    ],
  ];

  /// Where each template's adaptive pixels sit in the pixel list above; the
  /// entry at index `i` is the position of AT`i+1`.
  static const List<List<int>> _atSlots = [
    [11, 5, 4, 0],
    [9],
    [7],
    [5],
  ];

  /// True when the adaptive pixels are the nominal ones, which lets the fast
  /// path run.
  bool get usesNominalAt {
    final nominalX = nominalAtX(template);
    final nominalY = nominalAtY(template);
    for (var i = 0; i < nominalX.length; i++) {
      if (atX[i] != nominalX[i] || atY[i] != nominalY[i]) return false;
    }
    return true;
  }

  /// Encodes the bitmap and returns the arithmetic codeword.
  Uint8List encode() {
    final encoder = MqEncoder();
    final cx = CX(1 << 16, 0);
    encodeInto(encoder, cx);
    return encoder.flush();
  }

  /// Appends the decisions to an arithmetic stream shared by a segment.
  void encodeInto(MqEncoder encoder, CX cx) {
    final width = bitmap.width;
    final height = bitmap.height;
    final rowStride = bitmap.rowStride;
    final paddedWidth = (width + 7) & -8;
    final fast = template == 0 && usesNominalAt;
    final positions = fast ? const <List<int>>[] : _resolvedTemplate();

    var ltp = 0;
    for (var line = 0; line < height; line++) {
      if (typicalPrediction) {
        final duplicate = line > 0 && _rowsMatch(line, line - 1);
        final wanted = duplicate ? 1 : 0;
        cx.index = sltpContexts[template];
        encoder.encode(cx, ltp ^ wanted);
        ltp = wanted;
        if (ltp == 1) continue;
      }
      if (fast) {
        _encodeLine(encoder, cx, line, width, rowStride, paddedWidth);
      } else {
        _encodeLineGeneric(encoder, cx, line, width, positions);
      }
    }
  }

  /// The template pixel list with the adaptive markers replaced by this
  /// encoder's actual AT positions.
  List<List<int>> _resolvedTemplate() {
    final positions = [
      for (final pixel in _templates[template]) [pixel[0], pixel[1]]
    ];
    final slots = _atSlots[template];
    for (var i = 0; i < slots.length; i++) {
      positions[slots[i]] = [atX[i], atY[i]];
    }
    return positions;
  }

  /// 6.2.5.7 d): gathers the template around every pixel of one row.
  void _encodeLineGeneric(MqEncoder encoder, CX cx, int line, int width,
      List<List<int>> positions) {
    for (var x = 0; x < width; x++) {
      var context = 0;
      for (final pixel in positions) {
        context = (context << 1) | _pixel(x + pixel[0], line + pixel[1]);
      }
      if (_isSkipped(x, line)) continue;
      cx.index = context;
      encoder.encode(cx, bitmap.getPixel(x, line));
    }
  }

  /// 6.2.5.6: a masked pixel costs no decision at all.
  bool _isSkipped(int x, int y) {
    final Bitmap? mask = skip;
    if (mask == null) return false;
    if (x >= mask.width || y >= mask.height) return false;
    return mask.getPixel(x, y) == 1;
  }

  int _pixel(int x, int y) {
    if (x < 0 || y < 0 || x >= bitmap.width || y >= bitmap.height) return 0;
    return bitmap.getPixel(x, y);
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
        final bit = (source >> toShift) & 1;
        if (!_isSkipped(x + minorX, lineNumber)) {
          cx.index = context;
          encoder.encode(cx, bit);
        }
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

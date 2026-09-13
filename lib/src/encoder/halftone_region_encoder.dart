import 'dart:typed_data';

import '../bitmap.dart';
import '../decoder/arithmetic/cx.dart';
import '../util/combination_operator.dart';
import 'generic_region_encoder.dart';
import 'mq_encoder.dart';

/// Encodes a pattern dictionary segment's data part (T.88 clause 6.7 / 7.4.4).
///
/// The patterns are laid side by side into one collective bitmap, which is
/// coded as a generic region whose first adaptive pixel sits at
/// `(-HDPW, 0)` — the previous pattern's matching pixel — exactly as 6.7.5
/// prescribes.
class PatternDictionaryEncoder {
  /// The patterns, all of the same size, index 0 first.
  final List<Bitmap> patterns;

  /// HDTEMPLATE of 7.4.4.1.1.
  final int template;

  PatternDictionaryEncoder(this.patterns, {this.template = 0}) {
    if (patterns.length < 2) {
      throw ArgumentError('6.6.5 needs at least two patterns to index.');
    }
    if (patterns.length > 256) {
      throw ArgumentError('GRAYMAX is written as one collective bitmap; this '
          'encoder stops at 256 patterns.');
    }
    for (final pattern in patterns) {
      if (pattern.width != patternWidth || pattern.height != patternHeight) {
        throw ArgumentError('Every pattern must be the same size.');
      }
    }
    if (patternWidth < 1 || patternWidth > 255) {
      throw ArgumentError('7.4.4.1.2 stores HDPW in one byte.');
    }
    if (patternHeight < 1 || patternHeight > 255) {
      throw ArgumentError('7.4.4.1.3 stores HDPH in one byte.');
    }
  }

  int get patternWidth => patterns.first.width;
  int get patternHeight => patterns.first.height;

  /// GRAYMAX of 7.4.4.1.4: the largest pattern index.
  int get grayMax => patterns.length - 1;

  /// The collective bitmap of 6.7.5, the patterns written left to right.
  Bitmap collectiveBitmap() {
    final collective = Bitmap(patterns.length * patternWidth, patternHeight);
    for (var index = 0; index < patterns.length; index++) {
      final pattern = patterns[index];
      for (var y = 0; y < patternHeight; y++) {
        for (var x = 0; x < patternWidth; x++) {
          collective.writePixel(
              index * patternWidth + x, y, pattern.getPixel(x, y));
        }
      }
    }
    return collective;
  }

  /// The segment data part: the four byte header of 7.4.4.1 followed by the
  /// arithmetic codeword of the collective bitmap.
  Uint8List encode() {
    final body = BytesBuilder();

    // 7.4.4.1.1 flags: bit 0 HDMMR, bits 1-2 HDTEMPLATE, the rest reserved.
    body.addByte((template & 0x03) << 1);
    body.addByte(patternWidth);
    body.addByte(patternHeight);
    body.addByte((grayMax >> 24) & 0xff);
    body.addByte((grayMax >> 16) & 0xff);
    body.addByte((grayMax >> 8) & 0xff);
    body.addByte(grayMax & 0xff);

    // 6.7.5: GBATX1 is -HDPW, the rest of the adaptive pixels stay nominal.
    final atX =
        template == 0 ? <int>[-patternWidth, -3, 2, -2] : <int>[-patternWidth];
    final atY = template == 0 ? const [0, -1, -2, -2] : const [0];

    body.add(GenericRegionEncoder(
      collectiveBitmap(),
      template: template,
      typicalPrediction: false,
      atX: atX,
      atY: atY,
    ).encode());
    return body.takeBytes();
  }
}

/// Encodes a halftone region segment's data part (T.88 clause 6.6 / 7.4.5).
///
/// The grid of pattern indices is coded as the grey-scale image of Annex C:
/// one generic region per bit plane, most significant plane first, each plane
/// after the first carrying the Gray code difference against the plane above
/// it. All the planes share one arithmetic stream and one set of contexts,
/// which is what makes the order and the skipping matter.
class HalftoneRegionEncoder {
  /// The pattern indices, `grid[mg][ng]`, HGH rows of HGW values.
  final List<List<int>> grid;

  /// The dictionary the indices point into.
  final PatternDictionaryEncoder dictionary;

  /// HBW and HBH of 7.4.1: the size of the region the patterns are drawn into.
  final int regionWidth;
  final int regionHeight;

  /// Where the region sits on the page (7.4.1.3 and 7.4.1.4).
  final int x;
  final int y;

  /// HGX and HGY of 7.4.5.1.2, signed fixed point with eight fractional bits.
  final int gridX;
  final int gridY;

  /// HRX and HRY of 7.4.5.1.3, unsigned fixed point with eight fractional
  /// bits. The nominal grid steps one pattern to the right per column.
  final int vectorX;
  final int vectorY;

  /// HTEMPLATE of 7.4.5.1.1.
  final int template;

  /// HENABLESKIP of 7.4.5.1.1: leave the cells whose pattern falls entirely
  /// outside the region uncoded (6.6.5.1).
  final bool enableSkip;

  /// HCOMBOP of 7.4.5.1.1, the operator each pattern is drawn with.
  final CombinationOperator combinationOperator;

  /// HDEFPIXEL of 7.4.5.1.1, the value the region starts out filled with.
  final bool defaultPixelBlack;

  /// The external combination operator of 7.4.1.5.
  final CombinationOperator externalCombinationOperator;

  HalftoneRegionEncoder({
    required this.grid,
    required this.dictionary,
    required this.regionWidth,
    required this.regionHeight,
    this.x = 0,
    this.y = 0,
    this.gridX = 0,
    this.gridY = 0,
    int? vectorX,
    this.vectorY = 0,
    this.template = 0,
    this.enableSkip = false,
    this.combinationOperator = CombinationOperator.OR,
    this.defaultPixelBlack = false,
    this.externalCombinationOperator = CombinationOperator.OR,
  }) : vectorX = vectorX ?? dictionary.patternWidth << 8 {
    if (grid.isEmpty || grid.first.isEmpty) {
      throw ArgumentError('The halftone grid must have at least one cell.');
    }
    for (final row in grid) {
      if (row.length != gridWidth) {
        throw ArgumentError('Every grid row must be the same length.');
      }
      for (final value in row) {
        if (value < 0 || value > dictionary.grayMax) {
          throw ArgumentError('The grid value $value is not a pattern index.');
        }
      }
    }
  }

  int get gridWidth => grid.first.length;
  int get gridHeight => grid.length;

  /// HBPP of 6.6.5 3): the number of bit planes the grid values need.
  int get bitsPerValue {
    var bits = 0;
    while ((1 << bits) < dictionary.patterns.length) {
      bits++;
    }
    return bits;
  }

  /// 6.6.5.1: the cells whose pattern would miss the region entirely.
  Bitmap skipBitmap() {
    final skip = Bitmap(gridWidth, gridHeight);
    for (var mg = 0; mg < gridHeight; mg++) {
      for (var ng = 0; ng < gridWidth; ng++) {
        final cellX = (gridX + mg * vectorY + ng * vectorX) >> 8;
        final cellY = (gridY + mg * vectorX - ng * vectorY) >> 8;
        if (cellX + dictionary.patternWidth <= 0 ||
            cellX >= regionWidth ||
            cellY + dictionary.patternHeight <= 0 ||
            cellY >= regionHeight) {
          skip.setPixel(ng, mg, 1);
        }
      }
    }
    return skip;
  }

  /// The segment data part: the region segment information field of 7.4.1, the
  /// halftone header of 7.4.5.1 and the grey-scale image.
  Uint8List encode() {
    final body = BytesBuilder();

    // 7.4.1 region segment information field.
    _uint32(body, regionWidth);
    _uint32(body, regionHeight);
    _uint32(body, x);
    _uint32(body, y);
    body.addByte(_operatorCode(externalCombinationOperator) & 0x07);

    // 7.4.5.1.1 flags: bit 0 HMMR, bits 1-2 HTEMPLATE, bit 3 HENABLESKIP,
    // bits 4-6 HCOMBOP, bit 7 HDEFPIXEL.
    var flags = (template & 0x03) << 1;
    if (enableSkip) flags |= 0x08;
    flags |= (_operatorCode(combinationOperator) & 0x07) << 4;
    if (defaultPixelBlack) flags |= 0x80;
    body.addByte(flags);

    _uint32(body, gridWidth);
    _uint32(body, gridHeight);
    _uint32(body, gridX);
    _uint32(body, gridY);
    body.addByte((vectorX >> 8) & 0xff);
    body.addByte(vectorX & 0xff);
    body.addByte((vectorY >> 8) & 0xff);
    body.addByte(vectorY & 0xff);

    body.add(_grayScaleImage());
    return body.takeBytes();
  }

  /// Annex C.5 in reverse: turns the grid values into the bit planes a decoder
  /// reads, most significant first.
  Uint8List _grayScaleImage() {
    final bits = bitsPerValue;
    final Bitmap? skip = enableSkip ? skipBitmap() : null;

    // The true planes: bit j of every grid value.
    final planes = List<Bitmap>.generate(bits, (j) {
      final plane = Bitmap(gridWidth, gridHeight);
      for (var mg = 0; mg < gridHeight; mg++) {
        for (var ng = 0; ng < gridWidth; ng++) {
          plane.writePixel(ng, mg, (grid[mg][ng] >> j) & 1);
        }
      }
      return plane;
    });

    // C.5 step 3) has the decoder recover plane j by XORing the coded plane
    // with the plane above it, so the encoder writes that difference.
    final coded = List<Bitmap>.generate(bits, (j) {
      if (j == bits - 1) return planes[j];
      final difference = Bitmap(gridWidth, gridHeight);
      for (var mg = 0; mg < gridHeight; mg++) {
        for (var ng = 0; ng < gridWidth; ng++) {
          difference.writePixel(ng, mg,
              planes[j].getPixel(ng, mg) ^ planes[j + 1].getPixel(ng, mg));
        }
      }
      return difference;
    });

    // 6.2.5.3 nominal adaptive pixels, the ones C.5 hands the generic
    // decoding procedure.
    final atX = <int>[template <= 1 ? 3 : 2, -3, 2, -2];
    final atY = const <int>[-1, -1, -2, -2];

    final encoder = MqEncoder();
    final cx = CX(1 << 16, 0);
    for (var j = bits - 1; j >= 0; j--) {
      GenericRegionEncoder(
        coded[j],
        template: template,
        typicalPrediction: false,
        atX: template == 0 ? atX : <int>[atX[0]],
        atY: template == 0 ? atY : <int>[atY[0]],
        skip: skip,
      ).encodeInto(encoder, cx);
    }
    return encoder.flush();
  }

  static int _operatorCode(CombinationOperator op) {
    switch (op) {
      case CombinationOperator.OR:
        return 0;
      case CombinationOperator.AND:
        return 1;
      case CombinationOperator.XOR:
        return 2;
      case CombinationOperator.XNOR:
        return 3;
      case CombinationOperator.REPLACE:
        return 4;
    }
  }

  static void _uint32(BytesBuilder target, int value) {
    target.addByte((value >> 24) & 0xff);
    target.addByte((value >> 16) & 0xff);
    target.addByte((value >> 8) & 0xff);
    target.addByte(value & 0xff);
  }
}

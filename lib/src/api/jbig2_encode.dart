import 'dart:typed_data';

import '../encoder/generic_region_encoder.dart';
import '../encoder/jbig2_writer.dart';
import 'jbig2_image.dart';

/// How to encode a bi-level image.
class Jbig2EncodeOptions {
  /// Emit typical prediction, so a row identical to the one above costs one
  /// decision instead of a whole row of pixels. Worth keeping on: scanned
  /// pages are mostly white, and the margins alone pay for it.
  final bool typicalPrediction;

  /// Horizontal resolution in pixels per metre, written to the page
  /// information segment. 0 leaves it unstated.
  final int xResolution;

  /// Vertical resolution in pixels per metre.
  final int yResolution;

  const Jbig2EncodeOptions({
    this.typicalPrediction = true,
    this.xResolution = 0,
    this.yResolution = 0,
  });
}

/// Encodes [image] as the embedded segment stream PDF's `/JBIG2Decode` filter
/// expects.
///
/// The result is a page information segment followed by one immediate lossless
/// generic region, with no file header and no end-of-file segment, which is
/// what a PDF image stream carries. The encoding is always lossless.
///
/// ```dart
/// final data = encodeJbig2Embedded(image);
/// // /Filter /JBIG2Decode, /Width, /Height and /BitsPerComponent 1 come from
/// // the image dictionary, not from the stream.
/// ```
Uint8List encodeJbig2Embedded(
  Jbig2Image image, {
  Jbig2EncodeOptions options = const Jbig2EncodeOptions(),
}) {
  final codeword = _codeword(image, options);
  final writer = Jbig2Writer();

  writer.writeSegment(
    number: 0,
    type: Jbig2SegmentType.pageInformation,
    page: 1,
    data: Jbig2Writer.pageInformation(
      width: image.width,
      height: image.height,
      xResolution: options.xResolution,
      yResolution: options.yResolution,
    ),
  );
  writer.writeSegment(
    number: 1,
    type: Jbig2SegmentType.immediateLosslessGenericRegion,
    page: 1,
    data: Jbig2Writer.genericRegion(
      width: image.width,
      height: image.height,
      codeword: codeword,
      typicalPrediction: options.typicalPrediction,
    ),
  );
  return writer.takeBytes();
}

/// Encodes [image] as a standalone JBIG2 file, header and end-of-file segment
/// included.
Uint8List encodeJbig2File(
  Jbig2Image image, {
  Jbig2EncodeOptions options = const Jbig2EncodeOptions(),
}) {
  final codeword = _codeword(image, options);
  final writer = Jbig2Writer()..writeFileHeader(pageCount: 1);

  writer.writeSegment(
    number: 0,
    type: Jbig2SegmentType.pageInformation,
    page: 1,
    data: Jbig2Writer.pageInformation(
      width: image.width,
      height: image.height,
      xResolution: options.xResolution,
      yResolution: options.yResolution,
    ),
  );
  writer.writeSegment(
    number: 1,
    type: Jbig2SegmentType.immediateLosslessGenericRegion,
    page: 1,
    data: Jbig2Writer.genericRegion(
      width: image.width,
      height: image.height,
      codeword: codeword,
      typicalPrediction: options.typicalPrediction,
    ),
  );
  writer.writeSegment(
    number: 2,
    type: Jbig2SegmentType.endOfPage,
    page: 1,
    data: Uint8List(0),
  );
  writer.writeSegment(
    number: 3,
    type: Jbig2SegmentType.endOfFile,
    page: 0,
    data: Uint8List(0),
  );
  return writer.takeBytes();
}

/// Encodes packed rows straight from a PDF 1-bit image.
///
/// PDF stores a 1 bit as white; JBIG2 stores it as black. Set
/// [oneIsBlack] to false for PDF-oriented data so the bits are inverted on the
/// way in, which is the common case when recompressing an existing image.
Uint8List encodeJbig2Packed(
  Uint8List packed, {
  required int width,
  required int height,
  int? rowStride,
  bool oneIsBlack = true,
  Jbig2EncodeOptions options = const Jbig2EncodeOptions(),
  bool asFile = false,
}) {
  final stride = rowStride ?? ((width + 7) >> 3);
  var data = packed;
  if (!oneIsBlack) {
    data = Uint8List(packed.length);
    for (var i = 0; i < packed.length; i++) {
      data[i] = ~packed[i] & 0xff;
    }
  }
  final image = Jbig2Image.fromPacked(
      width: width, height: height, data: data, rowStride: stride);
  return asFile
      ? encodeJbig2File(image, options: options)
      : encodeJbig2Embedded(image, options: options);
}

Uint8List _codeword(Jbig2Image image, Jbig2EncodeOptions options) {
  if (image.width <= 0 || image.height <= 0) {
    throw ArgumentError('An image must have a positive extent.');
  }
  return GenericRegionEncoder(
    image.toBitmap(),
    typicalPrediction: options.typicalPrediction,
  ).encode();
}

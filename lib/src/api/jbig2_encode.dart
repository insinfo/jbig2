import 'dart:typed_data';

import '../encoder/generic_region_encoder.dart';
import '../encoder/jbig2_writer.dart';
import '../encoder/symbol_dictionary_encoder.dart';
import '../encoder/symbol_extractor.dart';
import 'jbig2_image.dart';

enum Jbig2EncodeMode {
  /// Compara os dois resultados e conserva o menor.
  auto,

  /// Codifica a página como uma região genérica.
  genericRegion,

  /// Extrai componentes, deduplica símbolos e os posiciona numa região texto.
  symbolDictionary,
}

/// How to encode a bi-level image.
class Jbig2EncodeOptions {
  final Jbig2EncodeMode mode;

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
    this.mode = Jbig2EncodeMode.auto,
    this.typicalPrediction = true,
    this.xResolution = 0,
    this.yResolution = 0,
  });
}

/// Encodes [image] as the embedded segment stream PDF's `/JBIG2Decode` filter
/// expects.
///
/// In [Jbig2EncodeMode.auto], compares a generic region with a symbol
/// dictionary plus text region and returns the smaller stream. There is no
/// file header or end-of-file segment, which is what a PDF image stream
/// carries. Encoding is always lossless.
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
  if (options.mode != Jbig2EncodeMode.genericRegion) {
    final symbolic = _encodeSymbols(image, options, false);
    if (symbolic != null && options.mode == Jbig2EncodeMode.symbolDictionary) {
      return symbolic;
    }
    if (symbolic != null) {
      final generic = _encodeGeneric(image, options, false);
      return symbolic.length < generic.length ? symbolic : generic;
    }
  }
  return _encodeGeneric(image, options, false);
}

Uint8List _encodeGeneric(
    Jbig2Image image, Jbig2EncodeOptions options, bool asFile) {
  final codeword = _codeword(image, options);
  final writer = Jbig2Writer();
  if (asFile) writer.writeFileHeader(pageCount: 1);

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
  if (asFile) {
    writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0));
    writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.endOfFile,
        page: 0,
        data: Uint8List(0));
  }
  return writer.takeBytes();
}

/// Encodes [image] as a standalone JBIG2 file, header and end-of-file segment
/// included.
Uint8List encodeJbig2File(
  Jbig2Image image, {
  Jbig2EncodeOptions options = const Jbig2EncodeOptions(),
}) {
  if (options.mode != Jbig2EncodeMode.genericRegion) {
    final symbolic = _encodeSymbols(image, options, true);
    if (symbolic != null && options.mode == Jbig2EncodeMode.symbolDictionary) {
      return symbolic;
    }
    if (symbolic != null) {
      final generic = _encodeGeneric(image, options, true);
      return symbolic.length < generic.length ? symbolic : generic;
    }
  }
  return _encodeGeneric(image, options, true);
}

Uint8List? _encodeSymbols(
    Jbig2Image image, Jbig2EncodeOptions options, bool asFile) {
  if (image.width <= 0 || image.height <= 0) {
    throw ArgumentError('An image must have a positive extent.');
  }
  final extracted = SymbolExtractor(image.toBitmap()).extract();
  if (extracted.dictionary.isEmpty) return null;
  final writer = Jbig2Writer();
  if (asFile) writer.writeFileHeader(pageCount: 1);
  writer.writeSegment(
      number: 0,
      type: Jbig2SegmentType.pageInformation,
      page: 1,
      data: Jbig2Writer.pageInformation(
          width: image.width,
          height: image.height,
          xResolution: options.xResolution,
          yResolution: options.yResolution));
  writer.writeSegment(
      number: 1,
      type: Jbig2SegmentType.symbolDictionary,
      page: 1,
      data: Jbig2Writer.symbolDictionary(
          exportedSymbols: extracted.dictionary.length,
          newSymbols: extracted.dictionary.length,
          codeword:
              SymbolDictionaryEncoder.encodeDictionary(extracted.dictionary)));
  writer.writeSegment(
      number: 2,
      type: Jbig2SegmentType.immediateLosslessTextRegion,
      page: 1,
      referredTo: const [1],
      data: Jbig2Writer.textRegion(
          width: image.width,
          height: image.height,
          instances: extracted.instances.length,
          codeword: SymbolDictionaryEncoder.encodeTextRegion(
              extracted.dictionary, extracted.instances)));
  if (asFile) {
    writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.endOfPage,
        page: 1,
        data: Uint8List(0));
    writer.writeSegment(
        number: 4,
        type: Jbig2SegmentType.endOfFile,
        page: 0,
        data: Uint8List(0));
  }
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

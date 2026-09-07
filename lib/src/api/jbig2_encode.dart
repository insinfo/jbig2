import 'dart:typed_data';

import '../bitmap.dart';
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

/// Streams for several PDF image XObjects sharing one `/JBIG2Globals` entry.
class Jbig2EmbeddedPages {
  /// Global symbol dictionary. Empty when generic regions were selected.
  final Uint8List globals;

  /// One embedded JBIG2 segment stream per input image, in the same order.
  final List<Uint8List> pages;

  const Jbig2EmbeddedPages(this.globals, this.pages);

  int get totalLength =>
      globals.length + pages.fold(0, (total, page) => total + page.length);

  bool get usesGlobalDictionary => globals.isNotEmpty;
}

/// Encodes PDF image streams with one symbol dictionary shared by all pages.
///
/// Put [Jbig2EmbeddedPages.globals] in a `/JBIG2Globals` stream referenced by
/// every image's `/DecodeParms`, and use the corresponding item from [pages]
/// as that image's `/JBIG2Decode` data. In `auto` mode the aggregate size,
/// including the globals stream, is compared with independent generic regions.
Jbig2EmbeddedPages encodeJbig2EmbeddedPages(
  List<Jbig2Image> images, {
  Jbig2EncodeOptions options = const Jbig2EncodeOptions(),
}) {
  if (images.isEmpty) {
    throw ArgumentError('At least one image is required.');
  }
  for (final image in images) {
    if (image.width <= 0 || image.height <= 0) {
      throw ArgumentError('Every image must have a positive extent.');
    }
  }
  final generic = Jbig2EmbeddedPages(Uint8List(0),
      [for (final image in images) _encodeGeneric(image, options, false)]);
  if (options.mode == Jbig2EncodeMode.genericRegion) return generic;
  final symbolic = _encodeSharedEmbeddedSymbols(images, options);
  if (options.mode == Jbig2EncodeMode.symbolDictionary) return symbolic;
  return symbolic.totalLength < generic.totalLength ? symbolic : generic;
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

/// Encodes several pages into one standalone JBIG2 file with a shared global
/// symbol dictionary.
///
/// Identical connected components are stored once even when they occur on
/// different pages. Each page gets its own page-information and lossless text
/// region and refers to the page-association-zero dictionary.
Uint8List encodeJbig2Pages(
  List<Jbig2Image> images, {
  Jbig2EncodeOptions options =
      const Jbig2EncodeOptions(mode: Jbig2EncodeMode.symbolDictionary),
}) {
  if (images.isEmpty) {
    throw ArgumentError('At least one image is required.');
  }
  for (final image in images) {
    if (image.width <= 0 || image.height <= 0) {
      throw ArgumentError('Every image must have a positive extent.');
    }
  }
  if (options.mode == Jbig2EncodeMode.genericRegion) {
    return _encodeGenericPages(images, options);
  }
  final symbolic = _encodeSymbolPages(images, options);
  if (options.mode == Jbig2EncodeMode.symbolDictionary) return symbolic;
  final generic = _encodeGenericPages(images, options);
  return symbolic.length < generic.length ? symbolic : generic;
}

Uint8List _encodeSymbolPages(
    List<Jbig2Image> images, Jbig2EncodeOptions options) {
  final dictionary = <Bitmap>[];
  final byShape = <String, List<int>>{};
  final pages = <ExtractedSymbols>[];
  for (final image in images) {
    final extracted = SymbolExtractor(image.toBitmap()).extract();
    final remap = <int, int>{};
    for (var local = 0; local < extracted.dictionary.length; local++) {
      final symbol = extracted.dictionary[local];
      final key = '${symbol.width}x${symbol.height}:${symbol.bitmap.join(',')}';
      var global = -1;
      for (final candidate in byShape[key] ?? const <int>[]) {
        if (_sameSymbol(dictionary[candidate], symbol)) {
          global = candidate;
          break;
        }
      }
      if (global < 0) {
        global = dictionary.length;
        dictionary.add(symbol);
        byShape.putIfAbsent(key, () => <int>[]).add(global);
      }
      remap[local] = global;
    }
    pages.add(ExtractedSymbols(dictionary, <ExtractedSymbolInstance>[
      for (final instance in extracted.instances)
        ExtractedSymbolInstance(
            remap[instance.symbol]!, instance.x, instance.y),
    ]));
  }

  // Dictionary coding requires height/width order. Reorder the shared set and
  // update every page's symbol IDs after cross-page deduplication.
  final order = List<int>.generate(dictionary.length, (index) => index)
    ..sort((a, b) {
      final height = dictionary[a].height.compareTo(dictionary[b].height);
      return height != 0
          ? height
          : dictionary[a].width.compareTo(dictionary[b].width);
    });
  final ordered = <Bitmap>[for (final index in order) dictionary[index]];
  final reorder = <int, int>{};
  for (var index = 0; index < order.length; index++) {
    reorder[order[index]] = index;
  }
  final remappedPages = <List<ExtractedSymbolInstance>>[
    for (final page in pages)
      <ExtractedSymbolInstance>[
        for (final instance in page.instances)
          ExtractedSymbolInstance(
              reorder[instance.symbol]!, instance.x, instance.y),
      ]
  ];

  final writer = Jbig2Writer()..writeFileHeader(pageCount: images.length);
  var segment = 0;
  int? dictionarySegment;
  if (ordered.isNotEmpty) {
    dictionarySegment = segment++;
    writer.writeSegment(
        number: dictionarySegment,
        type: Jbig2SegmentType.symbolDictionary,
        page: 0,
        data: Jbig2Writer.symbolDictionary(
            exportedSymbols: ordered.length,
            newSymbols: ordered.length,
            codeword: SymbolDictionaryEncoder.encodeDictionary(ordered)));
  }
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final page = index + 1;
    writer.writeSegment(
        number: segment++,
        type: Jbig2SegmentType.pageInformation,
        page: page,
        data: Jbig2Writer.pageInformation(
            width: image.width,
            height: image.height,
            xResolution: options.xResolution,
            yResolution: options.yResolution));
    final instances = remappedPages[index];
    if (instances.isNotEmpty) {
      writer.writeSegment(
          number: segment++,
          type: Jbig2SegmentType.immediateLosslessTextRegion,
          page: page,
          referredTo: <int>[dictionarySegment!],
          data: Jbig2Writer.textRegion(
              width: image.width,
              height: image.height,
              instances: instances.length,
              codeword: SymbolDictionaryEncoder.encodeTextRegion(
                  ordered, instances)));
    }
    writer.writeSegment(
        number: segment++,
        type: Jbig2SegmentType.endOfPage,
        page: page,
        data: Uint8List(0));
  }
  writer.writeSegment(
      number: segment,
      type: Jbig2SegmentType.endOfFile,
      page: 0,
      data: Uint8List(0));
  return writer.takeBytes();
}

Uint8List _encodeGenericPages(
    List<Jbig2Image> images, Jbig2EncodeOptions options) {
  final writer = Jbig2Writer()..writeFileHeader(pageCount: images.length);
  var segment = 0;
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final page = index + 1;
    writer.writeSegment(
        number: segment++,
        type: Jbig2SegmentType.pageInformation,
        page: page,
        data: Jbig2Writer.pageInformation(
            width: image.width,
            height: image.height,
            xResolution: options.xResolution,
            yResolution: options.yResolution));
    writer.writeSegment(
        number: segment++,
        type: Jbig2SegmentType.immediateLosslessGenericRegion,
        page: page,
        data: Jbig2Writer.genericRegion(
            width: image.width,
            height: image.height,
            codeword: _codeword(image, options),
            typicalPrediction: options.typicalPrediction));
    writer.writeSegment(
        number: segment++,
        type: Jbig2SegmentType.endOfPage,
        page: page,
        data: Uint8List(0));
  }
  writer.writeSegment(
      number: segment,
      type: Jbig2SegmentType.endOfFile,
      page: 0,
      data: Uint8List(0));
  return writer.takeBytes();
}

bool _sameSymbol(Bitmap a, Bitmap b) {
  if (a.width != b.width || a.height != b.height) return false;
  for (var index = 0; index < a.bitmap.length; index++) {
    if (a.bitmap[index] != b.bitmap[index]) return false;
  }
  return true;
}

Jbig2EmbeddedPages _encodeSharedEmbeddedSymbols(
    List<Jbig2Image> images, Jbig2EncodeOptions options) {
  final dictionary = <Bitmap>[];
  final byShape = <String, List<int>>{};
  final pages = <List<ExtractedSymbolInstance>>[];
  for (final image in images) {
    final extracted = SymbolExtractor(image.toBitmap()).extract();
    final remap = <int, int>{};
    for (var local = 0; local < extracted.dictionary.length; local++) {
      final symbol = extracted.dictionary[local];
      final key = '${symbol.width}x${symbol.height}:${symbol.bitmap.join(',')}';
      var global = -1;
      for (final candidate in byShape[key] ?? const <int>[]) {
        if (_sameSymbol(dictionary[candidate], symbol)) {
          global = candidate;
          break;
        }
      }
      if (global < 0) {
        global = dictionary.length;
        dictionary.add(symbol);
        byShape.putIfAbsent(key, () => <int>[]).add(global);
      }
      remap[local] = global;
    }
    pages.add([
      for (final instance in extracted.instances)
        ExtractedSymbolInstance(
            remap[instance.symbol]!, instance.x, instance.y),
    ]);
  }

  // Symbol dictionaries encode increasing height classes and widths. Keep the
  // shared IDs consistent with that order in every page text region.
  final order = List<int>.generate(dictionary.length, (index) => index)
    ..sort((a, b) {
      final height = dictionary[a].height.compareTo(dictionary[b].height);
      return height != 0
          ? height
          : dictionary[a].width.compareTo(dictionary[b].width);
    });
  final ordered = <Bitmap>[for (final index in order) dictionary[index]];
  final reorder = <int, int>{};
  for (var index = 0; index < order.length; index++) {
    reorder[order[index]] = index;
  }

  final globalWriter = Jbig2Writer();
  if (ordered.isNotEmpty) {
    globalWriter.writeSegment(
        number: 0,
        type: Jbig2SegmentType.symbolDictionary,
        page: 0,
        data: Jbig2Writer.symbolDictionary(
            exportedSymbols: ordered.length,
            newSymbols: ordered.length,
            codeword: SymbolDictionaryEncoder.encodeDictionary(ordered)));
  }

  final streams = <Uint8List>[];
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final writer = Jbig2Writer();
    writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(
            width: image.width,
            height: image.height,
            xResolution: options.xResolution,
            yResolution: options.yResolution));
    final instances = <ExtractedSymbolInstance>[
      for (final instance in pages[index])
        ExtractedSymbolInstance(
            reorder[instance.symbol]!, instance.x, instance.y),
    ];
    if (instances.isNotEmpty) {
      writer.writeSegment(
          number: 2,
          type: Jbig2SegmentType.immediateLosslessTextRegion,
          page: 1,
          referredTo: const [0],
          data: Jbig2Writer.textRegion(
              width: image.width,
              height: image.height,
              instances: instances.length,
              codeword: SymbolDictionaryEncoder.encodeTextRegion(
                  ordered, instances)));
    }
    streams.add(writer.takeBytes());
  }
  return Jbig2EmbeddedPages(globalWriter.takeBytes(), streams);
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

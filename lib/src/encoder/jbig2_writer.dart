import 'dart:typed_data';

/// Segment type numbers of ITU-T T.88 clause 7.3, limited to the ones this
/// package writes.
abstract final class Jbig2SegmentType {
  static const int symbolDictionary = 0;
  static const int immediateLosslessTextRegion = 7;
  static const int immediateGenericRegion = 38;
  static const int immediateLosslessGenericRegion = 39;
  static const int pageInformation = 48;
  static const int endOfPage = 49;
  static const int endOfFile = 51;
}

/// Assembles JBIG2 segments into the two container forms.
///
/// A *standalone* file carries the eight byte header and an end-of-file
/// segment. An *embedded* stream, the form PDF's `/JBIG2Decode` filter takes,
/// carries neither: it is the bare segment sequence, and the PDF image
/// dictionary supplies the dimensions.
class Jbig2Writer {
  final BytesBuilder _bytes = BytesBuilder();

  /// The file header of a standalone JBIG2 file.
  static const List<int> fileHeaderId = [
    0x97, 0x4A, 0x42, 0x32, 0x0D, 0x0A, 0x1A, 0x0A //
  ];

  /// Writes the standalone file header.
  ///
  /// [pageCount] is written when known; passing null marks it unknown, which
  /// is what a streaming writer does.
  void writeFileHeader({int? pageCount, bool sequential = true}) {
    _bytes.add(fileHeaderId);
    // 7.2.1 flags: bit 0 organisation (1 = sequential), bit 1 page count
    // unknown, the rest reserved.
    var flags = 0;
    if (sequential) flags |= 0x01;
    if (pageCount == null) flags |= 0x02;
    _bytes.addByte(flags);
    if (pageCount != null) _writeUint32(_bytes, pageCount);
  }

  /// Writes one segment with its header (7.2) followed by [data].
  void writeSegment({
    required int number,
    required int type,
    required int page,
    required Uint8List data,
    List<int> referredTo = const [],
  }) {
    final header = BytesBuilder();
    _writeUint32(header, number);

    // 7.2.3 flags: bits 0-5 type, bit 6 page association is four bytes.
    final widePage = page > 255;
    header.addByte((type & 0x3f) | (widePage ? 0x40 : 0));

    // 7.2.4 referred-to segment count and retain bits. Up to four referred-to
    // segments fit in the short form.
    if (referredTo.length <= 4) {
      header.addByte((referredTo.length & 0x07) << 5);
    } else {
      _writeUint32(header, 0xe0000000 | referredTo.length);
      // One retain bit per referred-to segment plus one for this segment,
      // rounded up to whole bytes and left clear.
      final retainBytes = (referredTo.length + 8) >> 3;
      header.add(Uint8List(retainBytes));
    }

    // 7.2.5 referred-to segment numbers, sized by this segment's own number.
    for (final referred in referredTo) {
      if (number <= 256) {
        header.addByte(referred & 0xff);
      } else if (number <= 65536) {
        header.addByte((referred >> 8) & 0xff);
        header.addByte(referred & 0xff);
      } else {
        _writeUint32(header, referred);
      }
    }

    // 7.2.6 page association.
    if (widePage) {
      _writeUint32(header, page);
    } else {
      header.addByte(page & 0xff);
    }

    // 7.2.7 data length.
    _writeUint32(header, data.length);

    _bytes.add(header.takeBytes());
    _bytes.add(data);
  }

  /// Builds the 19 byte page information segment body (7.4.8).
  static Uint8List pageInformation({
    required int width,
    required int height,
    int xResolution = 0,
    int yResolution = 0,
    bool lossless = true,
    bool defaultPixelBlack = false,
  }) {
    final body = BytesBuilder();
    _writeUint32(body, width);
    _writeUint32(body, height);
    _writeUint32(body, xResolution);
    _writeUint32(body, yResolution);

    // 7.4.8.5 flags: bit 0 lossless, bit 2 default pixel value, bits 3-4
    // default combination operator (0 = OR), bit 6 operator may be overridden.
    var flags = 0;
    if (lossless) flags |= 0x01;
    if (defaultPixelBlack) flags |= 0x04;
    body.addByte(flags);

    // 7.4.8.6 striping information: the high bit marks a striped page, which
    // this writer never produces.
    body.addByte(0);
    body.addByte(0);
    return body.takeBytes();
  }

  /// Builds a generic region segment body (7.4.6) around [codeword].
  static Uint8List genericRegion({
    required int width,
    required int height,
    required Uint8List codeword,
    int x = 0,
    int y = 0,
    int template = 0,
    bool typicalPrediction = true,
    List<int> atX = const [3, -3, 2, -2],
    List<int> atY = const [-1, -1, -2, -2],
  }) {
    final body = BytesBuilder();

    // 7.4.1 region segment information field.
    _writeUint32(body, width);
    _writeUint32(body, height);
    _writeUint32(body, x);
    _writeUint32(body, y);
    // Bits 3-7 reserved, bits 0-2 external combination operator (0 = OR).
    body.addByte(0);

    // 7.4.6.2 generic region flags: bit 0 MMR, bits 1-2 template,
    // bit 3 TPGDON, bit 4 EXTTEMPLATE.
    var flags = (template & 0x03) << 1;
    if (typicalPrediction) flags |= 0x08;
    body.addByte(flags);

    // 7.4.6.3 adaptive pixels: four pairs for template 0, one for the rest.
    final count = template == 0 ? 4 : 1;
    if (atX.length < count || atY.length < count) {
      throw ArgumentError('Template $template needs $count adaptive pixel(s).');
    }
    for (var i = 0; i < count; i++) {
      body.addByte(atX[i] & 0xff);
      body.addByte(atY[i] & 0xff);
    }

    body.add(codeword);
    return body.takeBytes();
  }

  /// Monta o cabeçalho de um dicionário aritmético sem refinamento.
  static Uint8List symbolDictionary({
    required int exportedSymbols,
    required int newSymbols,
    required Uint8List codeword,
    List<int> atX = const [3, -3, 2, -2],
    List<int> atY = const [-1, -1, -2, -2],
  }) {
    final body = BytesBuilder();
    // SDHUFF=0, SDREFAGG=0, templates e retenção de contextos zero.
    body.add([0, 0]);
    for (var i = 0; i < 4; i++) {
      body.addByte(atX[i] & 0xff);
      body.addByte(atY[i] & 0xff);
    }
    _writeUint32(body, exportedSymbols);
    _writeUint32(body, newSymbols);
    body.add(codeword);
    return body.takeBytes();
  }

  /// Monta uma região de texto aritmética sem refinamento.
  static Uint8List textRegion({
    required int width,
    required int height,
    required int instances,
    required Uint8List codeword,
    int x = 0,
    int y = 0,
  }) {
    final body = BytesBuilder();
    _writeUint32(body, width);
    _writeUint32(body, height);
    _writeUint32(body, x);
    _writeUint32(body, y);
    body.addByte(0); // combinação OR
    body.add([0, 0]); // flags da região de texto
    _writeUint32(body, instances);
    body.add(codeword);
    return body.takeBytes();
  }

  /// The bytes written so far.
  Uint8List takeBytes() => _bytes.takeBytes();

  static void _writeUint32(BytesBuilder target, int value) {
    target.addByte((value >> 24) & 0xff);
    target.addByte((value >> 16) & 0xff);
    target.addByte((value >> 8) & 0xff);
    target.addByte(value & 0xff);
  }
}

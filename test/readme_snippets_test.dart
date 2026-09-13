// The snippets the README shows, compiled.
//
// Nothing here is executed: the point is that the file has to compile, so a
// rename or a signature change in the public API breaks the build the moment
// the README stops matching the package. An example that does not compile is
// worse than no example, because the reader trusts it.
//
// ignore_for_file: unused_local_variable
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';
import 'package:test/test.dart';

void _decoding(
    Uint8List bytes, Uint8List streamData, Uint8List globalsData, int budget) {
  final image = decodeJbig2(bytes);
  print('${image.width}x${image.height}');
  print(image.isBlack(10, 20));

  final embedded = decodeJbig2Embedded(streamData, globals: globalsData);
  final gray = embedded.toGrayscale(); // one byte per pixel, 0 = black
  final pdfRows = embedded.toPdfImageData(); // 1 bit per pixel, PDF polarity

  final info = probeJbig2(bytes);
  if (info.pixelCount > budget) throw StateError('too large');

  decodeJbig2(bytes, options: const Jbig2DecodeOptions(maxPixels: 64 << 20));
}

void _encoding(Jbig2Image image, Uint8List packedRows, Jbig2Image cover,
    Jbig2Image page2, Jbig2Image page3, Jbig2Image scan1, Jbig2Image scan2) {
  final data = encodeJbig2Embedded(image); // for a PDF image stream
  final file = encodeJbig2File(image); // standalone .jb2

  final fromPdf = encodeJbig2Packed(
    packedRows,
    width: 2480,
    height: 3508,
    oneIsBlack: false, // invert PDF polarity on the way in
  );

  final symbols = encodeJbig2Embedded(
    image,
    options: const Jbig2EncodeOptions(mode: Jbig2EncodeMode.symbolDictionary),
  );

  final book = encodeJbig2Pages([cover, page2, page3]);
  final second = decodeJbig2(book, page: 2);

  final encoded = encodeJbig2EmbeddedPages([scan1, scan2]);
  final first = decodeJbig2Embedded(encoded.pages[0], globals: encoded.globals);

  final mmr = encodeJbig2File(
    image,
    options: const Jbig2EncodeOptions(
      mode: Jbig2EncodeMode.genericRegion,
      genericRegionMmr: true,
    ),
  );

  final extended = encodeJbig2File(
    image,
    options: const Jbig2EncodeOptions(
      mode: Jbig2EncodeMode.genericRegion,
      genericRegionExtTemplate: true,
    ),
  );
}

void main() {
  test('the README snippets still name the public API', () {
    // Reaching the functions is enough: they were compiled to get here.
    expect(_decoding, isNotNull);
    expect(_encoding, isNotNull);
  });
}

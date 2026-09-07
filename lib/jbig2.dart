/// Pure Dart JBIG2 codec, published as `package:jbig2`.
///
/// It decodes standalone `.jb2` files and the embedded segment streams PDF's
/// `/JBIG2Decode` filter carries, and encodes bi-level bitmaps back to either
/// form. The public API is byte oriented and never imports `dart:io`, so the
/// package runs unchanged on the Dart VM, `dart2js` and `dart2wasm`.
///
/// ```dart
/// final image = decodeJbig2(bytes);
/// print('${image.width}x${image.height}');
/// print(image.isBlack(10, 20));
/// ```
///
/// For a PDF image whose filter is `/JBIG2Decode`, pass the page's stream data
/// and, when the image dictionary has a `/JBIG2Globals` entry, that stream's
/// bytes as well:
///
/// ```dart
/// final image = decodeJbig2Embedded(streamData, globals: globalsData);
/// ```
library;

export 'src/api/jbig2_decode.dart';
export 'src/api/jbig2_encode.dart';
export 'src/api/jbig2_exceptions.dart';
export 'src/api/jbig2_image.dart';

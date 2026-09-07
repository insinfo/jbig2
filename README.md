# jbig2

Pure Dart JBIG2 codec, published as `package:jbig2`. It **decodes** standalone
`.jb2` files and the embedded segment streams PDF's `/JBIG2Decode` filter
carries, and **encodes** bi-level bitmaps back to either form. The public API
is byte oriented and never imports `dart:io`, so the package runs unchanged on
the Dart VM, `dart2js` and `dart2wasm`.

JBIG2 is the bi-level format scanned documents compress best in: a page of
black-and-white text is routinely twenty to a hundred times smaller than its
raw bitmap, and several times smaller than CCITT Group 4.

## Installation

```bash
dart pub add jbig2
```

## Decoding

```dart
import 'package:jbig2/jbig2.dart';

final image = decodeJbig2(bytes);
print('${image.width}x${image.height}');
print(image.isBlack(10, 20));
```

For an image inside a PDF, pass the stream data and, when the image dictionary
names a `/JBIG2Globals` stream, that stream's bytes too:

```dart
final image = decodeJbig2Embedded(streamData, globals: globalsData);
final gray = image.toGrayscale();          // one byte per pixel, 0 = black
final pdfRows = image.toPdfImageData();    // 1 bit per pixel, PDF polarity
```

`Jbig2Image` fields:

| Field | Meaning |
| --- | --- |
| `width`, `height` | size in pixels |
| `rowStride` | bytes per row, padding included |
| `data` | packed rows, MSB first, **a set bit is black** |

Note the polarity: JBIG2 stores black as 1, PDF stores it as 0.
`toPdfImageData` does that inversion, and also whitens the padding bits at the
end of a row so a viewer cannot draw a black margin.

### Probing without decoding

```dart
final info = probeJbig2(bytes);
if (info.pixelCount > budget) throw StateError('too large');
```

### Budgets and errors

```dart
decodeJbig2(bytes, options: const Jbig2DecodeOptions(maxPixels: 64 << 20));
```

Every input problem is a subtype of the sealed `Jbig2Exception`; API misuse is
an `ArgumentError`.

| Exception | Meaning |
| --- | --- |
| `Jbig2FormatException` | not a JBIG2 file or segment stream |
| `Jbig2TruncatedException` | ends early; a complete copy may work |
| `Jbig2CorruptedException` | violates the standard |
| `Jbig2UnsupportedException` | valid, but uses a feature not implemented here |
| `Jbig2BudgetException` | larger than `maxPixels` / `maxDimension` |

## Encoding

```dart
final data = encodeJbig2Embedded(image);   // for a PDF image stream
final file = encodeJbig2File(image);       // standalone .jb2
```

Straight from a PDF 1-bit image, where a set bit is white:

```dart
final data = encodeJbig2Packed(
  packedRows,
  width: 2480,
  height: 3508,
  oneIsBlack: false,   // invert PDF polarity on the way in
);
```

The encoder writes a generic region with template 0, the nominal adaptive
pixels and typical prediction, which is what general purpose encoders emit for
scanned pages. Encoding is always lossless: the round-trip tests decode every
fixture back and compare it pixel by pixel.

`typicalPrediction` costs one arithmetic decision for a row identical to the
one above instead of a whole row of pixels. Leave it on unless you are
measuring: scanned pages are mostly white, and the margins alone pay for it.

### Not produced

Symbol dictionaries and refinement regions, which pay off only on text with
many repeated glyphs, are **decoded but not encoded**. An encoder that builds a
symbol dictionary beats generic region coding on text pages, and is the next
thing worth adding.

## Development

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
```

`test/architecture/public_facade_imports_test.dart` walks the import graph from
`lib/jbig2.dart` the way pub.dev does and fails if `dart:io` becomes reachable,
which would cost the package its Web and Wasm support — and would take that
support away from every package depending on it. The file-backed
`RandomAccessRead` implementations in `lib/src/io` do use `dart:io`; they stay
outside the facade's graph on purpose.

Fixtures live in `test/resources` and are not published with the package.

## Origin and licences

The decoder — segment parsing, arithmetic and Huffman decoding, MMR, the bitmap
model and the stream readers — is a Dart port of **Apache PDFBox JBIG2
ImageIO**, formerly levigo JBIG2-ImageIO:

<https://github.com/apache/pdfbox-jbig2>

The MQ arithmetic encoder, the generic region encoder, the segment writer and
the public API are new work written for this package.

The whole package is released under the **Apache License 2.0**, the licence of
the code it derives from. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

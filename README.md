# jbig2

[![CI](https://github.com/insinfo/jbig2/actions/workflows/ci.yml/badge.svg)](https://github.com/insinfo/jbig2/actions/workflows/ci.yml)
[![AI Assisted](https://img.shields.io/badge/AI-Assisted-purple.svg)](https://github.com/insinfo/jbig2#built-with-llm-assistance)

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

The encoder compares a generic region with a symbol dictionary and keeps the
smaller representation. Symbol mode extracts 8-connected components,
deduplicates identical glyph bitmaps, writes them into an arithmetic symbol
dictionary, and places every occurrence through a text region. Encoding is
always lossless: round-trip tests decode both containers and compare them pixel
by pixel.

```dart
final symbols = encodeJbig2Embedded(image,
  options: const Jbig2EncodeOptions(mode: Jbig2EncodeMode.symbolDictionary),
);
```

Several standalone pages can share one global dictionary; identical glyphs are
stored once across the whole file:

```dart
final book = encodeJbig2Pages([cover, page2, page3]);
final second = decodeJbig2(book, page: 2);
```

PDFs can keep that sharing while storing every page as a separate image
XObject. `encodeJbig2EmbeddedPages` returns one `globals` stream for
`/DecodeParms /JBIG2Globals` and one embedded stream per input image. `auto`
compares the aggregate size, including the globals stream:

```dart
final encoded = encodeJbig2EmbeddedPages([scan1, scan2]);
final first = decodeJbig2Embedded(encoded.pages[0], globals: encoded.globals);
```

`encodeJbig2Pages` honours the same `mode` option as the single-page encoder.
In `auto` mode it compares complete generic-region and shared-dictionary files;
`genericRegion` can be forced for scanned or photographic bilevel pages.

Generic regions use template 0, nominal adaptive pixels and typical
prediction. Force `Jbig2EncodeMode.genericRegion` when symbol extraction is not
appropriate for the input.

`typicalPrediction` costs one arithmetic decision for a row identical to the
one above instead of a whole row of pixels. Leave it on unless you are
measuring: scanned pages are mostly white, and the margins alone pay for it.

Refinement aggregation is decoded and the encoder emits a base dictionary plus
lossless one-instance refinements when that beats direct symbol coding. Exact
bitmap symbols still deduplicate normally. Standalone multi-page files and PDF
`/JBIG2Globals` streams cluster non-identical symbols across pages and compare
the complete refined and direct representations before keeping the smaller one.

### The other two ways clause 6.2 can code a generic region

Both are off by default. The arithmetic coder with template 0 beats them on
every scanned page we have measured; these exist because the standard has them
and because each wins on material the default does not suit.

```dart
// MMR: the two-dimensional coding of ITU-T T.6, the same one CCITT Group 4
// uses. No adaptive state at all, and no arithmetic coder in the decoder's
// path.
final mmr = encodeJbig2File(image,
  options: const Jbig2EncodeOptions(
    mode: Jbig2EncodeMode.genericRegion,
    genericRegionMmr: true,
  ),
);

// EXTTEMPLATE: template 0 with twelve adaptive pixels instead of four. With
// the nominal positions it produces the very same codeword for twenty-four
// more header bytes; it pays only when the adaptive pixels are moved onto a
// periodic pattern, such as a halftone screen.
final extended = encodeJbig2File(image,
  options: const Jbig2EncodeOptions(
    mode: Jbig2EncodeMode.genericRegion,
    genericRegionExtTemplate: true,
  ),
);
```

Not every JBIG2 decoder in the wild implements EXTTEMPLATE. MMR, by contrast,
every conforming decoder must accept.

## What is not implemented

Read this before depending on the package. The decoder covers ITU-T T.88 as a
whole; most of the gaps are on the encoding side.

- **The encoder never emits Huffman coding.** Symbol dictionaries and text
  regions are always arithmetic (`SDHUFF = 0`, `SBHUFF = 0`). The decoder reads
  both, including the standard tables of Annex B and custom table segments, so
  a Huffman file from another encoder decodes fine — this package just does not
  produce one.
- **Custom Huffman tables are never written.** Segment type 53 is decoded and
  never emitted.
- **Striped pages are read, not written.** The decoder handles striped pages
  and end-of-stripe segments, including the unknown data length of 7.2.7. The
  encoder writes one stripe per page.
- **Halftone regions are decoded, and encoded only through the internal
  API.** `HalftoneRegionEncoder` and the pattern dictionary encoder exist and
  are tested, but no public entry point chooses them: `encodeJbig2*` picks
  between a generic region and a symbol dictionary. Encoding a halftone region
  today means reaching into `package:jbig2/src/`, which is not a stable API.
- **No colour or greyscale.** JBIG2 is a bi-level format and this package
  treats it as one.
- **No incremental or streaming decode.** A page is decoded whole, in memory.
  `probeJbig2` is the way to refuse an oversized image before allocating it.
- **No parallelism.** Decoding is synchronous and single-threaded.
- **The file-backed `RandomAccessRead` implementations in `lib/src/io` use
  `dart:io`** and are therefore not reachable from the public facade. On the
  Web and on Wasm you pass bytes, which is what the public API takes anyway.

## Development

```bash
dart format --output=none --set-exit-if-changed lib test example
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

## Built with LLM assistance

Parts of the code, of the tests and of this documentation were written with the
help of large language models. Everything in the repository passes
`dart analyze` with no errors and no warnings, and the full test suite on every
supported SDK, on Linux, Windows and macOS, before it is merged; the
correctness claims above rest on those tests and on the reference vectors named
with them, not on the provenance of the text.

Say so plainly because it is something anyone depending on the package has a
right to know.

## Origin and licences

The decoder — segment parsing, arithmetic and Huffman decoding, MMR, the bitmap
model and the stream readers — is a Dart port of **Apache PDFBox JBIG2
ImageIO**, formerly levigo JBIG2-ImageIO:

<https://github.com/apache/pdfbox-jbig2>

The MQ and arithmetic integer encoders, the generic region encoder (arithmetic,
extended template and MMR), the symbol dictionary, refinement and halftone
encoders, the segment writer and the public API are new work written for this
package.

The code tables of the Huffman and MMR decoders are transcriptions of tables
published in ITU-T T.88 Annex B and in ITU-T T.4 and T.6; they arrived here
through the Apache port and travel in the package.

The whole package is released under the **Apache License 2.0**, the licence of
the code it derives from. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

The test fixtures under `test/resources` come from the same upstream project
and are not published with the package. Some of them — `sampledata*.jb2`, the
arithmetic coder test sequences and `t88/annex_h.jb2` — are extracts of
ITU-T T.88 that the ITU makes available for non-commercial use only; the terms
are in `test/resources/images/README_SAMPLE_DATA_LICENSING.txt` and the whole
inventory is in `test/resources/PROVENANCE.md`.

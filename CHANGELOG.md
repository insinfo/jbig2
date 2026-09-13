# Changelog

## 1.0.0

First published release.

### Added

- **Public API** in `package:jbig2`, byte oriented and free of `dart:io`, so
  the package runs on the VM, `dart2js` and `dart2wasm`.
- **Decoder**: standalone `.jb2` files and the embedded segment streams PDF's
  `/JBIG2Decode` filter carries, with `/JBIG2Globals` support — generic and
  refinement regions, symbol dictionaries, text regions, halftone regions,
  pattern dictionaries, MMR, and arithmetic and Huffman coding. Ported from
  Apache PDFBox JBIG2 ImageIO.
- **Encoder**: an MQ arithmetic encoder (ITU-T T.88 Annex E) and a generic
  region encoder covering all four templates of 6.2.5.3 with the nominal
  adaptive pixels or any other causal ones, and optional typical prediction,
  emitting either an embedded stream or a standalone file. Encoding is lossless
  and verified by decoding every fixture back and comparing pixel by pixel.
- **Encoder**: the two remaining ways clause 6.2 can code a generic region.
  `genericRegionMmr` writes MMR, the two-dimensional coding of ITU-T T.6 that
  6.2.6 borrows, checked against libtiff's Group 4 decoder as well as against
  this package's own. `genericRegionExtTemplate` writes EXTTEMPLATE, template 0
  with twelve adaptive pixels instead of four. Both are off by default.
- **Budgets and typed errors**: `maxPixels` and `maxDimension` reject an
  oversized image from its page information segment before any allocation, and
  a sealed `Jbig2Exception` hierarchy separates format, truncation, corruption,
  unsupported features and budget failures.
- **Probe**: `probeJbig2` reads size, page count and resolution without
  decoding a pixel.

### Fixed

- The extended template of EXTTEMPLATE put A12 at the wrong context bit when
  that adaptive pixel was moved off its nominal position: the override cleared
  bit 9, which belongs to A3, and then wrote bit 10. A stream coded that way
  decoded to garbage from the first row. The defect came from the Java original
  and was invisible while the twelve adaptive pixels stayed nominal, because
  then the extended template covers exactly the neighbours template 0 covers.

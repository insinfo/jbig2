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
  region encoder using template 0, the nominal adaptive pixels and optional
  typical prediction, emitting either an embedded stream or a standalone file.
  Encoding is lossless and verified by decoding every fixture back and
  comparing pixel by pixel.
- **Budgets and typed errors**: `maxPixels` and `maxDimension` reject an
  oversized image from its page information segment before any allocation, and
  a sealed `Jbig2Exception` hierarchy separates format, truncation, corruption,
  unsupported features and budget failures.
- **Probe**: `probeJbig2` reads size, page count and resolution without
  decoding a pixel.

# Fixture provenance

No file in this folder is our own work, and none of them travels in the
published package: `.pubignore` excludes all of `test/`. The inventory exists so
that the origin and the terms of each file stay on record, rather than in the
memory of whoever downloaded them.

## Common origin

They all came from `src/test/resources` in the **levigo/jbig2-imageio** project,
today **Apache PDFBox JBIG2 ImageIO**, which is the same project the decoder was
ported from:

- <https://github.com/levigo/jbig2-imageio>
- <https://github.com/apache/pdfbox-jbig2>

That project is licensed under the **Apache License 2.0**. The directory layout
was preserved — including `com/levigo/jbig2/github/` — precisely so that the
correspondence with the original stays checkable.

## Inventory

| File | Origin | Licence | In the package |
|---|---|---|---|
| `images/001.jb2` … `007.jb2` | levigo/jbig2-imageio | Apache 2.0 | no |
| `images/042.bmp`, `042_1.jb2` … `042_25.jb2` | levigo/jbig2-imageio; JBIG2 conformance streams from UBC's SPMG | Apache 2.0 as redistributed by the origin project | no |
| `images/amb.bmp`, `amb_1.jb2`, `amb_2.jb2` | idem | idem | no |
| `images/20123110001.jb2` … `20123110010.jb2` | levigo/jbig2-imageio | Apache 2.0 | no |
| `images/sampledata.jb2`, `sampledata_page1.jb2`, `sampledata_page2.jb2`, `sampledata_page3.jb2` | extracts from ITU-T Recommendation **T.88 (2000/02)**, Annex H.1, redistributed by the origin project | **ITU: non-commercial use only.** See `images/README_SAMPLE_DATA_LICENSING.txt` | **no** |
| `images/arith/decoded testsequence`, `images/arith/encoded testsequence` | arithmetic-coder test sequence from **ITU-T T.88 Annex H.2** | same ITU terms as above | **no** |
| `images/README_SAMPLE_DATA_LICENSING.txt` | the ITU notice as redistributed by the Apache PDFBox project | third-party text, do not edit | no |
| `com/levigo/jbig2/github/21.jb2`, `21.glob` | levigo/jbig2-imageio, the issue 21 case | Apache 2.0 | no |
| `t88/annex_h.jb2` | **byte-for-byte copy of `images/sampledata.jb2`** | same ITU terms | **no** |

## Open items

1. `t88/annex_h.jb2` is an exact duplicate of `images/sampledata.jb2` — same
   MD5, same 860 bytes. Pointing `test/conformance/t88_annex_h_test.dart` at
   the existing file and deleting the copy removes a second instance of ITU
   material from the repository without losing any test.
2. The ITU notice in `images/README_SAMPLE_DATA_LICENSING.txt` names only
   `sampledata_pageN.jb2` and `sampledata.jb`. The test sequences in
   `images/arith/` are from the same Annex H and carry the same terms; the
   notice is third-party text and was not edited, which is why the observation
   sits here instead.
3. The ITU's non-commercial restriction applies to the **repository**, not to
   the package: none of this is published. Anyone forking for commercial use
   needs to know these files are here.

Material kept on a development machine for study — reference source trees and
the like — is deliberately not listed here. This inventory covers what the
repository versions, because that is what reaches anyone else.

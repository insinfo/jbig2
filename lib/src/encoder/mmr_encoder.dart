import 'dart:typed_data';

import '../bitmap.dart';
import '../decoder/mmr/mmr_constants.dart';

/// Encodes a bi-level bitmap with the MMR coding ITU-T T.88 clause 6.2.6
/// borrows from ITU-T T.6, the two-dimensional coding of Group 4 fax.
///
/// Every row is coded against the row above it — the first against an
/// imaginary all-white row — in pass, vertical or horizontal mode, exactly as
/// T.6 clause 2.2 describes. No EOL codes are written between rows, which is
/// what MMR means; the stream ends with the EOFB pair and is padded to a byte
/// boundary with zeroes.
///
/// The run-length codes come from [MMRConstants], the same tables the decoder
/// looks up, so the two sides cannot drift apart: a typo would break decoding
/// too, and the round-trip tests would see it.
///
/// MMR does not compete with the arithmetic coder on scanned text — it is
/// several tens of percent larger — but it is in the standard, a decoder is
/// required to accept it, and it costs no adaptive state at all.
class MmrEncoder {
  /// The source image. Set bits are black, as everywhere in this package.
  final Bitmap bitmap;

  /// Whether to close the stream with EOFB, the two consecutive EOL codes of
  /// T.6 clause 2.2.1. Decoders do not need it, but real Group 4 streams carry
  /// it and it makes the end of the data unambiguous.
  final bool writeEofb;

  MmrEncoder(this.bitmap, {this.writeEofb = true});

  /// Run length to `[bitLength, codeWord]`, built once from the decoder's
  /// tables. The sentinel rows those tables carry for EOL, EOF and invalid
  /// codes use a negative run length and are skipped.
  static Map<int, List<int>>? _whiteRuns;
  static Map<int, List<int>>? _blackRuns;

  static Map<int, List<int>> _runTable(List<List<int>> codes) {
    final table = <int, List<int>>{};
    for (final code in codes) {
      if (code[2] < 0) continue;
      table[code[2]] = [code[0], code[1]];
    }
    return table;
  }

  static void _initTables() {
    _whiteRuns ??= _runTable(MMRConstants.WhiteCodes);
    _blackRuns ??= _runTable(MMRConstants.BlackCodes);
  }

  /// The longest run a single make-up code can carry (T.4 table 3).
  static const int _maxMakeUp = 2560;

  final BytesBuilder _out = BytesBuilder();
  int _bitBuffer = 0;
  int _bitCount = 0;

  /// Encodes the whole bitmap and returns the MMR bitstream.
  Uint8List encode() {
    _initTables();

    final width = bitmap.width;
    var reference = const <int>[];

    for (var line = 0; line < bitmap.height; line++) {
      final current = _changes(line);
      _encodeLine(current, reference, width);
      reference = current;
    }

    if (writeEofb) {
      // EOFB: two EOL codes back to back, 000000000001 twice.
      _write(12, 0x001);
      _write(12, 0x001);
    }
    _align();
    return _out.takeBytes();
  }

  /// The changing elements of row [y]: every x where the colour differs from
  /// the pixel to its left, with an imaginary white pixel before x = 0. The
  /// positions alternate colour, so the element at an even index turns the row
  /// black and the one at an odd index turns it white again.
  List<int> _changes(int y) {
    final width = bitmap.width;
    final stride = bitmap.rowStride;
    final data = bitmap.bitmap;
    final base = y * stride;

    final changes = <int>[];
    var colour = 0;
    var x = 0;
    for (var i = 0; i < stride && x < width; i++) {
      final byte = data[base + i];
      // A byte that repeats the current colour holds no changing element, and
      // a scanned page is mostly such bytes.
      if (x + 8 <= width && byte == (colour == 0 ? 0x00 : 0xff)) {
        x += 8;
        continue;
      }
      for (var bit = 7; bit >= 0 && x < width; bit--, x++) {
        final pixel = (byte >> bit) & 1;
        if (pixel != colour) {
          changes.add(x);
          colour = pixel;
        }
      }
    }
    return changes;
  }

  /// T.6 clause 2.2: codes one row against [reference].
  void _encodeLine(List<int> current, List<int> reference, int width) {
    var a0 = -1;
    var colour = 0;
    var currentCursor = 0;
    var referenceCursor = 0;

    while (a0 < width) {
      while (currentCursor < current.length && current[currentCursor] <= a0) {
        currentCursor++;
      }
      final a1 =
          currentCursor < current.length ? current[currentCursor] : width;

      while (referenceCursor < reference.length &&
          reference[referenceCursor] <= a0) {
        referenceCursor++;
      }
      // b1 is the first changing element of the reference line to the right of
      // a0 and of opposite colour to a0. The elements alternate, so when the
      // first one after a0 has the wrong colour the next one has the right
      // one.
      var b1Index = referenceCursor;
      if ((b1Index & 1) != colour) b1Index++;
      final b1 = b1Index < reference.length ? reference[b1Index] : width;
      final b2 =
          b1Index + 1 < reference.length ? reference[b1Index + 1] : width;

      if (b2 < a1) {
        // Pass mode: the run on the reference line ends before the one being
        // coded does, so the colour carries on past b2.
        _writeMode(MMRConstants.CODE_P);
        a0 = b2;
      } else if (a1 - b1 >= -3 && a1 - b1 <= 3) {
        _writeVertical(a1 - b1);
        a0 = a1;
        colour ^= 1;
      } else {
        final a2 = currentCursor + 1 < current.length
            ? current[currentCursor + 1]
            : width;
        _writeMode(MMRConstants.CODE_H);
        // The first run starts at a0, or at the left edge for the first one,
        // which T.6 codes as if a0 sat on pixel 0.
        _writeRun(a1 - (a0 < 0 ? 0 : a0), colour);
        _writeRun(a2 - a1, colour ^ 1);
        a0 = a2;
      }
    }
  }

  /// Writes one of the mode codes of T.6 table 4.
  void _writeMode(int mode) {
    for (final code in MMRConstants.ModeCodes) {
      if (code[2] == mode) {
        _write(code[0], code[1]);
        return;
      }
    }
    throw StateError('MMR mode $mode has no code.');
  }

  /// Vertical mode V(a1 - b1), with [delta] between -3 and 3.
  void _writeVertical(int delta) {
    const modes = [
      MMRConstants.CODE_VL3,
      MMRConstants.CODE_VL2,
      MMRConstants.CODE_VL1,
      MMRConstants.CODE_V0,
      MMRConstants.CODE_VR1,
      MMRConstants.CODE_VR2,
      MMRConstants.CODE_VR3,
    ];
    _writeMode(modes[delta + 3]);
  }

  /// A run of [length] pixels of [colour], as make-up codes followed by one
  /// terminating code (T.4 clause 4.1.2).
  void _writeRun(int length, int colour) {
    final table = colour == 0 ? _whiteRuns! : _blackRuns!;
    var remaining = length;

    // Beyond 2560 + 63 no single make-up code reaches, so the longest one
    // repeats until what is left does fit.
    while (remaining >= _maxMakeUp + 64) {
      final code = table[_maxMakeUp]!;
      _write(code[0], code[1]);
      remaining -= _maxMakeUp;
    }
    if (remaining >= 64) {
      final makeUp = (remaining >> 6) << 6;
      final code = table[makeUp]!;
      _write(code[0], code[1]);
      remaining -= makeUp;
    }
    final code = table[remaining]!;
    _write(code[0], code[1]);
  }

  void _write(int bitLength, int codeWord) {
    for (var i = bitLength - 1; i >= 0; i--) {
      _bitBuffer = (_bitBuffer << 1) | ((codeWord >> i) & 1);
      _bitCount++;
      if (_bitCount == 8) {
        _out.addByte(_bitBuffer & 0xff);
        _bitBuffer = 0;
        _bitCount = 0;
      }
    }
  }

  void _align() {
    if (_bitCount == 0) return;
    _out.addByte((_bitBuffer << (8 - _bitCount)) & 0xff);
    _bitBuffer = 0;
    _bitCount = 0;
  }
}

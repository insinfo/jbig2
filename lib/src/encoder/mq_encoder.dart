import 'dart:typed_data';

import '../decoder/arithmetic/arithmetic_decoder.dart';
import '../decoder/arithmetic/cx.dart';

/// The MQ arithmetic encoder of ITU-T T.88 Annex E.
///
/// It is the exact inverse of [ArithmeticDecoder] and shares that class's `QE`
/// table, so a stream this encoder writes is the one that decoder reads. The
/// probability states live in a [CX], the same structure the decoder uses, so
/// an encoder and a decoder driven by the same context sequence stay in step.
///
/// The register arithmetic follows the software conventions of T.88 Figures
/// E.7 to E.11: `C` is a 32-bit code register whose carry propagates through
/// the byte already written, which is why the output is built with one sentinel
/// byte in front that is dropped at the end.
class MqEncoder {
  static const int _qeIndex = 0;
  static const int _nmpsIndex = 1;
  static const int _nlpsIndex = 2;
  static const int _switchIndex = 3;

  /// Bytes written so far. Index 0 is the sentinel `B` sits on before the
  /// first real byte, so a carry out of the first byte has somewhere to go.
  final List<int> _out = <int>[0];

  /// Index of the byte `B` currently points at.
  int _bp = 0;

  /// Interval register.
  int _a = 0x8000;

  /// Code register.
  int _c = 0;

  /// Bits left before the next byte is written.
  int _ct = 12;

  var _flushed = false;

  MqEncoder();

  /// Encodes one decision [d] (0 or 1) in the context [cx] currently selects.
  void encode(CX cx, int d) {
    if (_flushed) {
      throw StateError('The encoder was already flushed.');
    }
    if (d == cx.mps()) {
      _codeMps(cx);
    } else {
      _codeLps(cx);
    }
  }

  void _codeMps(CX cx) {
    final row = ArithmeticDecoder.QE[cx.cx()];
    final qe = row[_qeIndex];
    _a -= qe;
    if (_a & 0x8000 == 0) {
      if (_a < qe) {
        _a = qe;
      } else {
        _c += qe;
      }
      cx.setCx(row[_nmpsIndex]);
      _renorm();
    } else {
      _c += qe;
    }
  }

  void _codeLps(CX cx) {
    final row = ArithmeticDecoder.QE[cx.cx()];
    final qe = row[_qeIndex];
    _a -= qe;
    // Conditional exchange: when the LPS interval is the larger one, the two
    // sub-intervals swap places.
    if (_a < qe) {
      _c += qe;
    } else {
      _a = qe;
    }
    if (row[_switchIndex] == 1) cx.toggleMps();
    cx.setCx(row[_nlpsIndex]);
    _renorm();
  }

  void _renorm() {
    do {
      _a = (_a << 1) & 0xffff;
      _c = (_c << 1) & 0xffffffff;
      _ct--;
      if (_ct == 0) _byteOut();
    } while (_a & 0x8000 == 0);
  }

  void _byteOut() {
    if (_out[_bp] == 0xff) {
      // The previous byte is a stuffing byte, so only seven bits fit.
      _advance(_c >> 20);
      _c &= 0xfffff;
      _ct = 7;
      return;
    }
    if (_c & 0x8000000 == 0) {
      _advance(_c >> 19);
      _c &= 0x7ffff;
      _ct = 8;
      return;
    }
    // Carry out of bit 27 propagates into the byte already written.
    _out[_bp] = (_out[_bp] + 1) & 0xff;
    if (_out[_bp] == 0xff) {
      _c &= 0x7ffffff;
      _advance(_c >> 20);
      _c &= 0xfffff;
      _ct = 7;
    } else {
      _advance(_c >> 19);
      _c &= 0x7ffff;
      _ct = 8;
    }
  }

  void _advance(int value) {
    _bp++;
    final byte = value & 0xff;
    if (_bp < _out.length) {
      _out[_bp] = byte;
    } else {
      _out.add(byte);
    }
  }

  void _setBits() {
    final temp = _c + _a;
    _c |= 0xffff;
    if (_c >= temp) _c -= 0x8000;
  }

  /// Terminates the stream and returns its bytes.
  ///
  /// The terminating `FF AC` sequence of T.88 Figure E.11 is appended, which
  /// every conforming decoder recognises as the end of the arithmetic data.
  /// Calling this twice throws; the result is stable, so keep it.
  Uint8List flush() {
    if (_flushed) {
      throw StateError('The encoder was already flushed.');
    }
    _flushed = true;

    _setBits();
    _c = (_c << _ct) & 0xffffffff;
    _byteOut();
    _c = (_c << _ct) & 0xffffffff;
    _byteOut();

    if (_out[_bp] != 0xff) {
      _advance(0xff);
    }
    _advance(0xac);

    // Drop the sentinel the code register carried into.
    return Uint8List.fromList(_out.sublist(1, _bp + 1));
  }

  /// Bytes written so far, excluding what the flush would add.
  int get length => _bp;
}

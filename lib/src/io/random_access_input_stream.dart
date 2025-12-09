import 'dart:math' as math;
import 'dart:typed_data';
import 'closeable.dart';
import 'exceptions.dart';
import 'random_access_read.dart';

/// Synchronous input stream facade over a [RandomAccessRead].
class RandomAccessInputStream implements Closeable {
  RandomAccessInputStream(this._input);

  final RandomAccessRead _input;
  int _position = 0;
  bool _closed = false;

  /// Number of bytes that can be read without blocking.
  int available() {
    _ensureOpen();
    final remaining = _input.length - _position;
    if (remaining <= 0) {
      return 0;
    }
    return math.min(remaining, 0x7fffffff);
  }

  /// Reads a single byte, returning -1 on EOF.
  int read() {
    _ensureOpen();
    _restorePosition();
    if (_input.isEOF) {
      return -1;
    }
    final value = _input.read();
    if (value != -1) {
      _position++;
    }
    return value;
  }

  /// Reads up to [length] bytes into [buffer], returning the number of bytes read or -1 on EOF.
  int readInto(Uint8List buffer, [int offset = 0, int? length]) {
    _ensureOpen();
    _restorePosition();
    if (_input.isEOF) {
      return -1;
    }
    final effectiveLength = length ?? (buffer.length - offset);
    final bytesRead = _input.readBuffer(buffer, offset, effectiveLength);
    if (bytesRead > 0) {
      _position += bytesRead;
    }
    return bytesRead;
  }

  /// Skips forward by [count] bytes, returning the number of skipped bytes.
  int skip(int count) {
    _ensureOpen();
    if (count <= 0) {
      return 0;
    }
    _restorePosition();
    final target = _position + count;
    _input.seek(target);
    _position = target;
    return count;
  }

  @override
  @override
  void close() {
    _closed = true;
  }

  void _restorePosition() {
    _input.seek(_position);
  }

  void _ensureOpen() {
    if (_closed) {
      throw IOException('RandomAccessInputStream already closed');
    }
  }
}

import 'dart:typed_data';
import 'exceptions.dart';
import 'random_access_read.dart';
import 'random_access_write.dart';

/// Output stream facade over a [RandomAccessWrite].
class RandomAccessOutputStream {
  RandomAccessOutputStream(this._buffer);

  final RandomAccessWrite _buffer;

  bool _isClosed = false;

  /// Writes a single byte.
  void write(int value) {
    _ensureOpen();
    _buffer.writeByte(value);
  }

  /// Writes [length] bytes from [data] starting at [offset].
  void writeBytes(Uint8List data, [int offset = 0, int? length]) {
    _ensureOpen();
    _buffer.writeBytes(data, offset, length);
  }

  /// Flush is a no-op because the backing buffer is random-access.
  void flush() {
    _ensureOpen();
  }

  /// Closes the underlying buffer if it also implements [RandomAccessRead].
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _buffer.close();
  }

  RandomAccessWrite get target => _buffer;

  void _ensureOpen() {
    if (_isClosed) {
      throw IOException('RandomAccessOutputStream already closed');
    }
  }
}

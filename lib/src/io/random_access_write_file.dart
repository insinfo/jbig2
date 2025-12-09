import 'dart:io';
import 'dart:typed_data';

import 'random_access_write.dart';

/// A RandomAccessWrite implementation that writes to a file.
class RandomAccessWriteFile implements RandomAccessWrite {
  final RandomAccessFile _raf;
  bool _isClosed = false;

  RandomAccessWriteFile(String path)
      : _raf = File(path).openSync(mode: FileMode.write);

  @override
  void writeByte(int value) {
    _checkClosed();
    _raf.writeByteSync(value);
  }

  @override
  void writeBytes(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    final len = length ?? (buffer.length - offset);
    if (offset == 0 && len == buffer.length) {
      _raf.writeFromSync(buffer);
    } else {
      _raf.writeFromSync(buffer, offset, offset + len);
    }
  }

  @override
  void clear() {
    _checkClosed();
    _raf.truncateSync(0);
    _raf.setPositionSync(0);
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _raf.closeSync();
  }

  void _checkClosed() {
    if (_isClosed) {
      throw StateError('RandomAccessWriteFile is closed');
    }
  }
}

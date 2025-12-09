import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'exceptions.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';

/// `RandomAccessRead` backed by a non-seekable synchronous input source.
///
/// It keeps at most three buffers in memory (current/last/next) to allow
/// limited peek/rewind behaviour while avoiding copying the whole input.
class NonSeekableRandomAccessReadInputStream extends RandomAccessRead {
  NonSeekableRandomAccessReadInputStream._(this._source);

  factory NonSeekableRandomAccessReadInputStream.fromBytes(Uint8List data) {
    return NonSeekableRandomAccessReadInputStream._(_MemoryInputSource(data));
  }

  factory NonSeekableRandomAccessReadInputStream.fromRandomAccessFile(
    RandomAccessFile file,
  ) {
    return NonSeekableRandomAccessReadInputStream._(
      _RandomAccessFileInputSource(file),
    );
  }

  static const int _bufferSize = 4096;
  static const int _current = 0;
  static const int _last = 1;
  static const int _next = 2;

  final _SyncInputSource _source;
  final List<Uint8List> _buffers =
      List<Uint8List>.generate(3, (_) => Uint8List(_bufferSize));
  final List<int> _bufferBytes = <int>[-1, -1, -1];

  int _position = 0;
  int _currentBufferPointer = 0;
  int _size = 0;
  bool _isClosed = false;
  bool _isEOF = false;

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _source.close();
  }

  @override
  void seek(int position) {
    throw IOException('${runtimeType.toString()}.seek is not supported.');
  }

  @override
  void skip(int count) {
    if (count <= 0) {
      return;
    }
    for (var i = 0; i < count; i++) {
      if (read() == -1) {
        break;
      }
    }
  }

  @override
  int get position {
    _checkClosed();
    return _position;
  }

  @override
  int read() {
    _checkClosed();
    if (isEOF) {
      return -1;
    }
    if (_currentBufferPointer >= _bufferBytes[_current] && !_fetch()) {
      _isEOF = true;
      return -1;
    }
    _position++;
    return _buffers[_current][_currentBufferPointer++] & 0xff;
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    if (isEOF) {
      return -1;
    }
    final requested = length ?? (buffer.length - offset);
    if (requested <= 0) {
      return 0;
    }
    var remaining = requested;
    var totalRead = 0;
    var targetOffset = offset;
    while (remaining > 0) {
      if (_currentBufferPointer >= _bufferBytes[_current] && !_fetch()) {
        _isEOF = true;
        break;
      }
      final availableInBuffer = _bufferBytes[_current] - _currentBufferPointer;
      if (availableInBuffer <= 0) {
        break;
      }
      final toCopy = math.min(remaining, availableInBuffer);
      buffer.setRange(
        targetOffset,
        targetOffset + toCopy,
        _buffers[_current],
        _currentBufferPointer,
      );
      _currentBufferPointer += toCopy;
      _position += toCopy;
      totalRead += toCopy;
      targetOffset += toCopy;
      remaining -= toCopy;
    }

    if (totalRead == 0) {
      return -1;
    }
    return totalRead;
  }

  @override
  int get length {
    _checkClosed();
    return _size;
  }

  @override
  void rewind(int bytes) {
    if (bytes <= 0) {
      return;
    }
    if (_position < bytes) {
      throw IOException('Not enough bytes available to perform rewind of $bytes');
    }
    if (_currentBufferPointer >= bytes) {
      _currentBufferPointer -= bytes;
      _position -= bytes;
      _isEOF = false;
      return;
    }
    if (_bufferBytes[_last] > 0) {
      final remaining = bytes - _currentBufferPointer;
      _switchBuffers(_current, _next);
      _switchBuffers(_current, _last);
      _bufferBytes[_last] = -1;
      _currentBufferPointer = _bufferBytes[_current] - remaining;
      if (_currentBufferPointer < 0) {
        throw IOException('Not enough buffered bytes to rewind $bytes');
      }
      _position -= bytes;
      _isEOF = false;
      return;
    }
    throw IOException('Not enough bytes available to perform rewind of $bytes');
  }

  @override
  bool get isClosed => _isClosed;

  @override
  bool get isEOF {
    _checkClosed();
    return _isEOF;
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    throw IOException('${runtimeType.toString()}.createView is not supported.');
  }

  bool _fetch() {
    _checkClosed();
    _currentBufferPointer = 0;
    if (_bufferBytes[_next] > -1) {
      _switchBuffers(_current, _last);
      _switchBuffers(_current, _next);
      _bufferBytes[_next] = -1;
      return true;
    }

    if (_bufferBytes[_last] == _bufferSize &&
        _bufferBytes[_current] > 0 &&
        _bufferBytes[_current] < _bufferSize) {
      final last = _buffers[_last];
      final current = _buffers[_current];
      final shift = _bufferSize - _bufferBytes[_current];
      last.setRange(0, shift, last, _bufferBytes[_current]);
      last.setRange(shift, shift + _bufferBytes[_current], current, 0);
      _bufferBytes[_last] = _bufferSize;
    } else {
      _switchBuffers(_current, _last);
    }

    final read = _source.readInto(_buffers[_current], 0, _bufferSize);
    if (read <= 0) {
      _bufferBytes[_current] = -1;
      return false;
    }
    _bufferBytes[_current] = read;
    _size += read;
    _isEOF = false;
    return true;
  }

  void _switchBuffers(int first, int second) {
    final tmpBuffer = _buffers[first];
    _buffers[first] = _buffers[second];
    _buffers[second] = tmpBuffer;
    final tmpBytes = _bufferBytes[first];
    _bufferBytes[first] = _bufferBytes[second];
    _bufferBytes[second] = tmpBytes;
  }

  void _checkClosed() {
    if (_isClosed) {
      throw IOException('${runtimeType.toString()} already closed');
    }
  }
}

abstract class _SyncInputSource {
  int readInto(Uint8List buffer, int offset, int length);
  void close();
}

class _MemoryInputSource implements _SyncInputSource {
  _MemoryInputSource(this._data);

  final Uint8List _data;
  int _position = 0;
  bool _closed = false;

  @override
  int readInto(Uint8List buffer, int offset, int length) {
    if (_closed) {
      return -1;
    }
    final remaining = _data.length - _position;
    if (remaining <= 0) {
      return -1;
    }
    final toCopy = math.min(length, remaining);
    buffer.setRange(offset, offset + toCopy, _data, _position);
    _position += toCopy;
    return toCopy;
  }

  @override
  void close() {
    _closed = true;
  }
}

class _RandomAccessFileInputSource implements _SyncInputSource {
  _RandomAccessFileInputSource(this._file);

  final RandomAccessFile _file;
  bool _closed = false;

  @override
  int readInto(Uint8List buffer, int offset, int length) {
    if (_closed) {
      return -1;
    }
    final end = math.min(buffer.length, offset + length);
    return _file.readIntoSync(buffer, offset, end);
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _file.closeSync();
  }
}

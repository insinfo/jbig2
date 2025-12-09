import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'exceptions.dart';
import 'random_access.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';

class RandomAccessReadBuffer extends RandomAccessRead {
  static const int defaultChunkSize4KB = 1 << 12;

  RandomAccessReadBuffer([int chunkSize = defaultChunkSize4KB])
      : chunkSize = math.max(1, chunkSize),
        _bufferList = <Uint8List>[],
        _pointer = 0,
        _currentBufferPointer = 0,
        _size = 0,
        _bufferListIndex = 0,
        _bufferListMaxIndex = 0,
        _isClosed = false {
    final buffer = Uint8List(this.chunkSize);
    _currentBuffer = buffer;
    _bufferList.add(buffer);
  }

  RandomAccessReadBuffer.fromBytes(Uint8List input)
      : chunkSize = input.isEmpty ? defaultChunkSize4KB : input.length,
        _bufferList = <Uint8List>[],
        _pointer = 0,
        _currentBufferPointer = 0,
        _size = input.length,
        _bufferListIndex = 0,
        _bufferListMaxIndex = 0,
        _isClosed = false {
    if (input.isEmpty) {
      final buffer = Uint8List(chunkSize);
      _currentBuffer = buffer;
      _bufferList.add(buffer);
    } else {
      final view = Uint8List.view(input.buffer, input.offsetInBytes, input.length);
      _currentBuffer = view;
      _bufferList.add(view);
    }
    _bufferListMaxIndex = _bufferList.length - 1;
  }

  factory RandomAccessReadBuffer._clone(RandomAccessReadBuffer parent) {
    final clone = RandomAccessReadBuffer(parent.chunkSize);
    clone._bufferList
      ..clear()
      ..addAll(parent._bufferList
          .map((buffer) => Uint8List.view(buffer.buffer, buffer.offsetInBytes, buffer.lengthInBytes)));
    clone._currentBuffer = clone._bufferList.isNotEmpty ? clone._bufferList[0] : null;
    clone._size = parent._size;
    clone._pointer = 0;
    clone._currentBufferPointer = 0;
    clone._bufferListIndex = 0;
    clone._bufferListMaxIndex = clone._bufferList.length - 1;
    clone._isClosed = parent._isClosed;
    return clone;
  }

  static Future<RandomAccessReadBuffer> createBufferFromStream(Stream<List<int>> stream,
      {int chunkSize = defaultChunkSize4KB}) async {
    final writable = RandomAccessReadWriteBuffer(chunkSize);
    await for (final chunk in stream) {
      if (chunk.isEmpty) {
        continue;
      }
      writable.writeBytes(Uint8List.fromList(chunk));
    }
    writable.seek(0);
    return writable;
  }

  final int chunkSize;
  final List<Uint8List> _bufferList;
  Uint8List? _currentBuffer;
  int _pointer;
  int _currentBufferPointer;
  int _size;
  int _bufferListIndex;
  int _bufferListMaxIndex;
  bool _isClosed;

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _currentBuffer = null;
    _bufferList.clear();
  }

  @override
  int read() {
    checkClosed();
    if (_pointer >= _size) {
      return -1;
    }
    if (_currentBufferPointer >= _currentBuffer!.length) {
      if (_bufferListIndex >= _bufferListMaxIndex) {
        return -1;
      }
      _nextBuffer();
    }
    _pointer++;
    return _currentBuffer![_currentBufferPointer++];
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    checkClosed();
    final requested = length ?? (buffer.length - offset);
    if (requested <= 0) {
      return 0;
    }
    var bytesRead = _readRemaining(buffer, offset, requested);
    if (bytesRead == -1) {
      if (available() > 0) {
        bytesRead = 0;
      } else {
        return -1;
      }
    }
    while (bytesRead < requested && available() > 0) {
      if (_currentBufferPointer == _currentBuffer!.length) {
        _nextBuffer();
      }
      bytesRead += _readRemaining(buffer, offset + bytesRead, requested - bytesRead);
    }
    return bytesRead;
  }

  int _readRemaining(Uint8List target, int offset, int length) {
    if (_pointer >= _size) {
      return -1;
    }
    final remainingInStream = _size - _pointer;
    final safeLength = math.min(length, remainingInStream);
    if (safeLength <= 0) {
      return -1;
    }
    final remainingInChunk = _currentBuffer!.length - _currentBufferPointer;
    if (remainingInChunk <= 0) {
      return -1;
    }
    final toCopy = math.min(safeLength, remainingInChunk);
    final view = Uint8List.view(_currentBuffer!.buffer,
        _currentBuffer!.offsetInBytes + _currentBufferPointer, toCopy);
    target.setRange(offset, offset + toCopy, view);
    _currentBufferPointer += toCopy;
    _pointer += toCopy;
    return toCopy;
  }

  @override
  void seek(int position) {
    checkClosed();
    if (position < 0) {
      throw IOException('Invalid position $position');
    }
    if (position < _size) {
      _pointer = position;
      final safeChunkSize = chunkSize;
      _bufferListIndex = safeChunkSize > 0 ? position ~/ safeChunkSize : 0;
      _currentBufferPointer = safeChunkSize > 0 ? position % safeChunkSize : 0;
      _currentBuffer = _bufferList[_bufferListIndex];
      if (_currentBufferPointer > _currentBuffer!.length) {
        _currentBufferPointer = _currentBuffer!.length;
      }
    } else {
      _pointer = _size;
      _bufferListIndex = _bufferListMaxIndex;
      _currentBuffer = _bufferList[_bufferListIndex];
      _currentBufferPointer = chunkSize > 0 ? _size % chunkSize : 0;
      if (_currentBufferPointer > _currentBuffer!.length) {
        _currentBufferPointer = _currentBuffer!.length;
      }
    }
  }

  @override
  int get position {
    checkClosed();
    return _pointer;
  }

  @override
  int get length {
    checkClosed();
    return _size;
  }

  @override
  bool get isClosed => _isClosed || _currentBuffer == null;

  @override
  bool get isEOF {
    checkClosed();
    return _pointer >= _size;
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    checkClosed();
    return RandomAccessReadView(RandomAccessReadBuffer._clone(this), startPosition, streamLength);
  }

  void checkClosed() {
    if (isClosed) {
      throw IOException('RandomAccessReadBuffer already closed');
    }
  }

  void resetBuffers() {
    if (_bufferList.isEmpty) {
      final buffer = Uint8List(chunkSize);
      _bufferList.add(buffer);
    }
    _size = 0;
    _pointer = 0;
    _currentBufferPointer = 0;
    _bufferListIndex = 0;
    _bufferListMaxIndex = _bufferList.length - 1;
    _currentBuffer = _bufferList[0];
    if (_bufferList.length > 1) {
      _bufferList.removeRange(1, _bufferList.length);
      _bufferListMaxIndex = 0;
    }
  }

  void expandBuffer() {
    if (_bufferListMaxIndex > _bufferListIndex) {
      _nextBuffer();
      return;
    }
    final buffer = Uint8List(chunkSize);
    _bufferList.add(buffer);
    _currentBuffer = buffer;
    _currentBufferPointer = 0;
    _bufferListIndex = _bufferList.length - 1;
    _bufferListMaxIndex = _bufferListIndex;
  }

  void _nextBuffer() {
    if (_bufferListIndex >= _bufferListMaxIndex) {
      throw IOException('No more chunks available, end of buffer reached');
    }
    _bufferListIndex++;
    _currentBufferPointer = 0;
    _currentBuffer = _bufferList[_bufferListIndex];
  }
}

class RandomAccessReadWriteBuffer extends RandomAccessReadBuffer implements RandomAccess {
  RandomAccessReadWriteBuffer([int chunkSize = RandomAccessReadBuffer.defaultChunkSize4KB])
      : super(chunkSize);

  RandomAccessReadWriteBuffer.withChunkSize(int chunkSize) : super(chunkSize);

  @override
  void clear() {
    checkClosed();
    resetBuffers();
  }

  @override
  void writeByte(int value) {
    checkClosed();
    _ensureWriteCapacity(1);
    _currentBuffer![_currentBufferPointer] = value & 0xff;
    _currentBufferPointer++;
    _pointer++;
    if (_pointer > _size) {
      _size = _pointer;
    }
  }

  @override
  void writeBytes(Uint8List buffer, [int offset = 0, int? length]) {
    checkClosed();
    final writeLength = length ?? (buffer.length - offset);
    if (writeLength < 0) {
      throw IOException('Invalid length $writeLength');
    }
    var remaining = writeLength;
    var currentOffset = offset;
    while (remaining > 0) {
      _ensureWriteCapacity(1);
      final availableInChunk = _currentBuffer!.length - _currentBufferPointer;
      final toWrite = math.min(remaining, availableInChunk);
      final view = Uint8List.view(buffer.buffer, buffer.offsetInBytes + currentOffset, toWrite);
      _currentBuffer!.setRange(
          _currentBufferPointer, _currentBufferPointer + toWrite, view);
      _currentBufferPointer += toWrite;
      _pointer += toWrite;
      if (_pointer > _size) {
        _size = _pointer;
      }
      remaining -= toWrite;
      currentOffset += toWrite;
    }
  }

  void _ensureWriteCapacity(int minimumSpace) {
    while (_currentBuffer!.length - _currentBufferPointer < minimumSpace) {
      expandBuffer();
    }
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'exceptions.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';

/// Aggregates multiple [RandomAccessRead] instances and exposes them as a single reader.
class SequenceRandomAccessRead extends RandomAccessRead {
  SequenceRandomAccessRead(List<RandomAccessRead> inputs)
      : _readerList = <RandomAccessRead>[] {
    if (inputs.isEmpty) {
      throw ArgumentError('Input list must not be empty');
    }
    for (final reader in inputs) {
      try {
        if (reader.length > 0) {
          _readerList.add(reader);
        }
      } on IOException catch (e) {
  throw ArgumentError('Problematic reader list: $e');
      }
    }
    if (_readerList.isEmpty) {
      throw ArgumentError('Input list must contain at least one non-empty reader');
    }
  _numberOfReaders = _readerList.length;
    _startPositions = List<int>.filled(_numberOfReaders, 0);
    _endPositions = List<int>.filled(_numberOfReaders, -1);

    for (var i = 0; i < _numberOfReaders; i++) {
      _startPositions[i] = _totalLength;
      _totalLength += _readerList[i].length;
      _endPositions[i] = _totalLength == 0 ? -1 : _totalLength - 1;
    }

    _currentReader = _readerList[_currentIndex];
  }

  final List<RandomAccessRead> _readerList;
  late final List<int> _startPositions;
  late final List<int> _endPositions;
  late final int _numberOfReaders;
  RandomAccessRead? _currentReader;
  int _currentIndex = 0;
  int _currentPosition = 0;
  int _totalLength = 0;
  bool _isClosed = false;

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    IOException? exception;
    for (final reader in _readerList) {
      try {
        reader.close();
      } on IOException catch (e) {
        exception ??= e;
      }
    }
    _readerList.clear();
    _currentReader = null;
    _isClosed = true;
    if (exception != null) {
      throw exception;
    }
  }

  @override
  int read() {
    _checkClosed();
    if (_readerList.isEmpty) {
      return -1;
    }
    while (true) {
      final reader = _ensureCurrentReader();
      final value = reader.read();
      if (value > -1) {
        _currentPosition++;
        return value;
      }
      if (_currentIndex >= _numberOfReaders - 1) {
        return -1;
      }
      // advance to next reader and try again
      _advanceReader();
    }
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    if (_readerList.isEmpty) {
      return -1;
    }
    final requested = length ?? (buffer.length - offset);
    if (requested == 0) {
      return 0;
    }
    final maxAvailable = math.min(available(), requested);
    if (maxAvailable == 0) {
      return -1;
    }

    var totalRead = 0;
    var targetOffset = offset;
    while (totalRead < maxAvailable) {
      final reader = _ensureCurrentReader();
      final readNow = reader.readBuffer(buffer, targetOffset, maxAvailable - totalRead);
      if (readNow <= 0) {
        if (_currentIndex >= _numberOfReaders - 1) {
          break;
        }
        _advanceReader();
        if (readNow == -1) {
          continue;
        }
        break;
      }
      totalRead += readNow;
      targetOffset += readNow;
    }
    if (totalRead == 0) {
      return -1;
    }
    _currentPosition += totalRead;
    return totalRead;
  }

  @override
  int get position {
    _checkClosed();
    return _currentPosition;
  }

  @override
  void seek(int position) {
    _checkClosed();
    if (position < 0) {
      throw IOException('Invalid position $position');
    }
    if (position >= _totalLength) {
      _currentIndex = _numberOfReaders - 1;
      _currentPosition = _totalLength;
      _currentReader = _readerList[_currentIndex];
      _currentReader!.seek(_readerList[_currentIndex].length);
      return;
    }

    final increment = position < _currentPosition ? -1 : 1;
    var idx = _currentIndex;
    while (idx >= 0 && idx < _numberOfReaders) {
      final start = _startPositions[idx];
      final end = _endPositions[idx];
      if (position >= start && position <= end) {
        _currentIndex = idx;
        break;
      }
      idx += increment;
    }
    _currentPosition = position;
    _currentReader = _readerList[_currentIndex];
    final relative = position - _startPositions[_currentIndex];
    _currentReader!.seek(relative);
  }

  @override
  int get length {
    _checkClosed();
    return _totalLength;
  }

  @override
  bool get isClosed => _isClosed;

  @override
  bool get isEOF {
    _checkClosed();
    return _currentPosition >= _totalLength;
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    throw UnsupportedError('${runtimeType.toString()}.createView is not supported.');
  }

  RandomAccessRead _ensureCurrentReader() {
    if (_currentReader == null) {
      throw IOException('No available readers');
    }
    if (_currentReader!.isEOF && _currentIndex < _numberOfReaders - 1) {
      _advanceReader();
    }
    return _currentReader!;
  }

  void _advanceReader() {
    if (_currentIndex >= _numberOfReaders - 1) {
      return;
    }
    _currentIndex++;
    _currentReader = _readerList[_currentIndex];
    _currentReader!.seek(0);
  }

  void _checkClosed() {
    if (_isClosed) {
      throw IOException('SequenceRandomAccessRead already closed');
    }
  }
}

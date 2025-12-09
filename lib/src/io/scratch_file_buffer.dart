part of 'scratch_file.dart';

class ScratchFileBuffer extends RandomAccessRead implements RandomAccess {
  ScratchFileBuffer(this._pageHandler)
      : _pageSize = _pageHandler.getPageSize(),
        _pageIndexes = List<int>.filled(16, -1) {
    _addPage();
  }

  final ScratchFile _pageHandler;
  final int _pageSize;
  List<int> _pageIndexes;
  int _pageCount = 0;

  Uint8List _currentPage = Uint8List(0);
  int _currentPageIndex = -1;
  int _positionInPage = 0;
  int _currentPageOffset = 0;
  bool _currentPageDirty = false;
  int _size = 0;

  void _checkClosed() {
    if (_pageHandler.isClosed || _pageIndexes.isEmpty) {
      throw IOException('Buffer already closed');
    }
  }

  void _addPage() {
    if (_pageCount + 1 >= _pageIndexes.length) {
      var newLength = _pageIndexes.length * 2;
      if (newLength <= _pageIndexes.length) {
        newLength = _pageIndexes.length == 0 ? 16 : _pageIndexes.length * 2;
      }
      final newIndexes = List<int>.filled(newLength, -1);
      for (var i = 0; i < _pageCount; i++) {
        newIndexes[i] = _pageIndexes[i];
      }
      _pageIndexes = newIndexes;
    }

    final newPageIdx = _pageHandler.getNewPage();
    _pageIndexes[_pageCount] = newPageIdx;
    _currentPageIndex = _pageCount;
    _currentPageOffset = _pageCount * _pageSize;
    _pageCount++;
    _currentPage = Uint8List(_pageSize);
    _positionInPage = 0;
    _currentPageDirty = false;
  }

  bool _ensureAvailableBytes(bool allowAddPage) {
    if (_positionInPage < _pageSize) {
      return true;
    }

    if (_currentPageDirty) {
      _pageHandler.writePage(_pageIndexes[_currentPageIndex], _currentPage);
      _currentPageDirty = false;
    }

    if (_currentPageIndex + 1 < _pageCount) {
      _currentPageIndex++;
      _currentPageOffset = _currentPageIndex * _pageSize;
      _currentPage = _pageHandler.readPage(_pageIndexes[_currentPageIndex]);
      _positionInPage = 0;
      return true;
    }

    if (!allowAddPage) {
      return false;
    }

    _addPage();
    return true;
  }

  @override
  void clear() {
    _checkClosed();
    if (_pageCount > 0) {
      if (_pageCount > 1) {
        _pageHandler.markPagesAsFree(_pageIndexes, 1, _pageCount - 1);
      }
      _pageCount = 1;
      _currentPageIndex = 0;
      _currentPageOffset = 0;
      _currentPage = Uint8List(_pageSize);
    }
    _positionInPage = 0;
    _size = 0;
    _currentPageDirty = false;
  }

  @override
  void close() {
    closeInternal();
  }

  void closeInternal({bool removeBuffer = true}) {
    if (_pageIndexes.isEmpty) {
      return;
    }
    if (_pageCount > 0) {
      _pageHandler.markPagesAsFree(_pageIndexes, 0, _pageCount);
    }
    if (removeBuffer) {
      _pageHandler.removeBuffer(this);
    }
    _pageIndexes = <int>[];
    _currentPage = Uint8List(0);
    _currentPageIndex = -1;
    _currentPageOffset = 0;
    _positionInPage = 0;
    _pageCount = 0;
    _size = 0;
    _currentPageDirty = false;
  }

  @override
  int get length {
    _checkClosed();
    return _size;
  }

  @override
  int get position {
    _checkClosed();
    return _currentPageOffset + _positionInPage;
  }

  @override
  void seek(int position) {
    _checkClosed();
    if (position < 0) {
      throw IOException('Negative seek offset: $position');
    }
    if (position > _size) {
      throw EofException('Seek beyond end of buffer');
    }

    var targetPage = position ~/ _pageSize;
    var offsetInPage = position % _pageSize;

    if (position % _pageSize == 0 && position == _size && position != 0) {
      targetPage = targetPage - 1;
      offsetInPage = _pageSize;
    }

    if (_currentPageDirty) {
      _pageHandler.writePage(_pageIndexes[_currentPageIndex], _currentPage);
      _currentPageDirty = false;
    }

    if (targetPage != _currentPageIndex) {
      _currentPageIndex = targetPage;
      _currentPageOffset = _currentPageIndex * _pageSize;
      _currentPage = _pageHandler.readPage(_pageIndexes[_currentPageIndex]);
    }

    _positionInPage = offsetInPage;
  }

  @override
  bool get isClosed => _pageIndexes.isEmpty || _pageHandler.isClosed;

  @override
  bool get isEOF {
    _checkClosed();
    return _currentPageOffset + _positionInPage >= _size;
  }

  @override
  int read() {
    _checkClosed();
    if (_currentPageOffset + _positionInPage >= _size) {
      return -1;
    }
    if (!_ensureAvailableBytes(false)) {
      throw IOException('Unexpectedly no bytes available for read in buffer.');
    }
    return _currentPage[_positionInPage++] & 0xff;
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    if (_currentPageOffset + _positionInPage >= _size) {
      return -1;
    }
    final requested = length ?? (buffer.length - offset);
    var remain = requested;
    var totalRead = 0;
    var targetOffset = offset;

    while (remain > 0) {
      if (!_ensureAvailableBytes(false)) {
        throw IOException('Unexpectedly no bytes available for read in buffer.');
      }
      final available = (_pageSize - _positionInPage);
      final toRead = remain < available ? remain : available;
      buffer.setRange(
        targetOffset,
        targetOffset + toRead,
        _currentPage,
        _positionInPage,
      );
      _positionInPage += toRead;
      totalRead += toRead;
      targetOffset += toRead;
      remain -= toRead;
      if (_currentPageOffset + _positionInPage >= _size) {
        break;
      }
    }
    return totalRead;
  }

  @override
  void writeByte(int value) {
    _checkClosed();
    _ensureAvailableBytes(true);
    _currentPage[_positionInPage++] = value & 0xff;
    _currentPageDirty = true;
    final absolutePos = _currentPageOffset + _positionInPage;
    if (absolutePos > _size) {
      _size = absolutePos;
    }
  }

  @override
  void writeBytes(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    final writeLength = length ?? (buffer.length - offset);
    var remain = writeLength;
    var srcOffset = offset;
    while (remain > 0) {
      _ensureAvailableBytes(true);
      final available = _pageSize - _positionInPage;
      final toWrite = remain < available ? remain : available;
      _currentPage.setRange(
        _positionInPage,
        _positionInPage + toWrite,
        buffer,
        srcOffset,
      );
      _positionInPage += toWrite;
      srcOffset += toWrite;
      remain -= toWrite;
      _currentPageDirty = true;
    }
    final absolutePos = _currentPageOffset + _positionInPage;
    if (absolutePos > _size) {
      _size = absolutePos;
    }
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    throw UnsupportedError('${runtimeType.toString()}.createView is not supported.');
  }
}

import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'exceptions.dart';
import 'io_utils.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';

class RandomAccessReadBufferedFile extends RandomAccessRead {
  RandomAccessReadBufferedFile(String path)
      : _path = path,
        _raf = File(path).openSync(mode: FileMode.read),
        _fileLength = File(path).lengthSync() {
    seek(0);
  }

  factory RandomAccessReadBufferedFile.fromFile(File file) {
    return RandomAccessReadBufferedFile(file.path);
  }

  static const int _pageSizeShift = 12;
  static const int _pageSize = 1 << _pageSizeShift;
  static const int _pageOffsetMask = -1 << _pageSizeShift;
  static const int _maxCachedPages = 1000;

  final Map<int, RandomAccessReadBufferedFile> _rafCopies = {};
  Uint8List? _lastRemovedCachePage;
  final LinkedHashMap<int, Uint8List> _pageCache = LinkedHashMap<int, Uint8List>();

  final String _path;
  final RandomAccessFile _raf;
  final int _fileLength;
  int _fileOffset = 0;
  int _currentPageOffset = -1;
  Uint8List? _currentPage;
  int _offsetWithinPage = 0;
  bool _isClosed = false;

  @override
  int get position {
    _checkClosed();
    return _fileOffset;
  }

  @override
  void seek(int position) {
    _checkClosed();
    if (position < 0) {
      throw IOException('Invalid position $position');
    }
    final newPageOffset = position & _pageOffsetMask;
    if (newPageOffset != _currentPageOffset) {
      final page = _getOrCreatePage(newPageOffset);
      _currentPageOffset = newPageOffset;
      _currentPage = page;
    }

    if (position <= 0) {
      _fileOffset = 0;
    } else if (position >= _fileLength) {
      _fileOffset = _fileLength;
    } else {
      _fileOffset = position;
    }
    _offsetWithinPage = _fileOffset - _currentPageOffset;
    if (_offsetWithinPage < 0) {
      _offsetWithinPage = 0;
    } else if (_offsetWithinPage > _pageSize) {
      _offsetWithinPage = _pageSize;
    }
  }

  @override
  int read() {
    _checkClosed();
    if (_fileOffset >= _fileLength) {
      return -1;
    }
    if (_offsetWithinPage == _pageSize) {
      seek(_fileOffset);
    }
    _fileOffset++;
    return _currentPage![_offsetWithinPage++] & 0xff;
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    _checkClosed();
    if (_fileOffset >= _fileLength) {
      return -1;
    }
    final len = length ?? (buffer.length - offset);
    if (_offsetWithinPage == _pageSize) {
      seek(_fileOffset);
    }
    var availableInPage = _pageSize - _offsetWithinPage;
    var bytesToRead = len < availableInPage ? len : availableInPage;
    final remainingFileBytes = _fileLength - _fileOffset;
    if (remainingFileBytes < _pageSize) {
      if (bytesToRead > remainingFileBytes) {
        bytesToRead = remainingFileBytes;
      }
    }
    if (bytesToRead <= 0) {
      return 0;
    }
    final page = _currentPage!;
    buffer.setRange(offset, offset + bytesToRead, page, _offsetWithinPage);
    _offsetWithinPage += bytesToRead;
    _fileOffset += bytesToRead;
    return bytesToRead;
  }

  @override
  int get length => _fileLength;

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _rafCopies.values.forEach(IOUtils.closeQuietly);
    _rafCopies.clear();
    _raf.closeSync();
    _pageCache.clear();
    _currentPage = null;
  }

  @override
  bool get isClosed => _isClosed;

  @override
  bool get isEOF => peek() == -1;

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    _checkClosed();
    final isolateId = Isolate.current.hashCode;
    var copy = _rafCopies[isolateId];
    if (copy == null || copy.isClosed) {
      copy = RandomAccessReadBufferedFile(_path);
      _rafCopies[isolateId] = copy;
    }
    return RandomAccessReadView(copy, startPosition, streamLength);
  }

  void _checkClosed() {
    if (_isClosed) {
      throw IOException('${runtimeType.toString()} already closed');
    }
  }

  Uint8List _getOrCreatePage(int pageOffset) {
    final existing = _pageCache.remove(pageOffset);
    if (existing != null) {
      _pageCache[pageOffset] = existing;
      return existing;
    }

    if (_pageCache.length >= _maxCachedPages) {
      final oldestKey = _pageCache.keys.first;
      _lastRemovedCachePage = _pageCache.remove(oldestKey);
    }

    final page = _readPage(pageOffset);
    _pageCache[pageOffset] = page;
    return page;
  }

  Uint8List _readPage(int pageOffset) {
    final buffer = _lastRemovedCachePage;
    final page = buffer != null && buffer.length == _pageSize
        ? buffer
        : Uint8List(_pageSize);
    _lastRemovedCachePage = null;

    _raf.setPositionSync(pageOffset);
    var totalRead = 0;
    while (totalRead < _pageSize) {
      final bytesRead = _raf.readIntoSync(page, totalRead, _pageSize);
      if (bytesRead <= 0) {
        break;
      }
      totalRead += bytesRead;
    }
    if (totalRead < _pageSize) {
      page.fillRange(totalRead, page.length, 0);
    }
    return page;
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'exceptions.dart';
import 'memory_usage_setting.dart';
import 'random_access.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';
import 'random_access_stream_cache.dart';
part 'scratch_file_buffer.dart';

class ScratchFile implements RandomAccessStreamCache {
  static bool _factoryRegistered = _registerFactory();

  static bool _registerFactory() {
    MemoryUsageSetting.registerScratchFileFactory((setting) => ScratchFile(setting));
    return true;
  }

  ScratchFile(MemoryUsageSetting setting)
      : _maxMainMemoryIsRestricted =
            !setting.useMainMemory() || setting.isMainMemoryRestricted(),
        _useScratchFile =
            (!setting.useMainMemory() || setting.isMainMemoryRestricted()) && setting.useTempFile(),
  _scratchFileDirectory = setting.useTempFile() ? setting.getTempDir() : null,
        _inMemoryMaxPageCount = setting.useMainMemory()
            ? (setting.isMainMemoryRestricted()
                ? _safePageCount(setting.getMaxMainMemoryBytes())
                : _unrestrictedPageLimit)
            : 0,
        _maxPageCount = setting.isStorageRestricted()
            ? _safePageCount(setting.getMaxStorageBytes())
            : _unrestrictedPageLimit {
    assert(_factoryRegistered, 'ScratchFile factory registration failed');
    if (_scratchFileDirectory != null && !_scratchFileDirectory.existsSync()) {
      throw IOException('Scratch file directory does not exist: ${_scratchFileDirectory.path}');
    }
  }

  static const int _pageSize = 4096;
  static const int _enlargePageCount = 16;
  static const int _initUnrestrictedMainMemPageCount = 100000;
  static const int _unrestrictedPageLimit = 0x7fffffff;

  final Directory? _scratchFileDirectory;
  final bool _maxMainMemoryIsRestricted;
  final bool _useScratchFile;
  final int _inMemoryMaxPageCount;
  final int _maxPageCount;

  File? _file;
  RandomAccessFile? _raf;
  int _pageCount = 0;
  bool _closed = false;

  List<bool> _freePages = <bool>[];
  List<Uint8List?>? _inMemoryPages;
  final List<ScratchFileBuffer> _buffers = <ScratchFileBuffer>[];

  static int _scratchFileId = 0;

  static int _safePageCount(int bytes) {
    if (bytes <= 0) {
      return 0;
    }
    final result = bytes ~/ _pageSize;
    if (result <= 0) {
      return 0;
    }
    return result > _unrestrictedPageLimit ? _unrestrictedPageLimit : result;
  }

  @override
  RandomAccess createBuffer() {
    _checkClosed();
    final buffer = ScratchFileBuffer(this);
    _buffers.add(buffer);
    return buffer;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;

    for (final buffer in List<ScratchFileBuffer>.from(_buffers)) {
      buffer.closeInternal(removeBuffer: false);
    }
    _buffers.clear();

    final raf = _raf;
    if (raf != null) {
      try {
        raf.closeSync();
      } on FileSystemException catch (e) {
        throw IOException(e.message);
      }
    }

    final file = _file;
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } on FileSystemException catch (e) {
        throw IOException('Error deleting scratch file: ${file.path}: ${e.message}');
      }
    }

    _raf = null;
    _file = null;
    _freePages.clear();
    _pageCount = 0;
    _inMemoryPages = null;
  }

  bool get isClosed => _closed;

  void _checkClosed() {
    if (_closed) {
      throw IOException('Scratch file already closed');
    }
  }

  int getPageSize() => _pageSize;

  void removeBuffer(ScratchFileBuffer buffer) {
    _buffers.remove(buffer);
  }

  int getNewPage() {
    _checkClosed();
    _initPages();
    var idx = _nextFreePage(0);
    if (idx < 0) {
      _enlarge();
      idx = _nextFreePage(0);
      if (idx < 0) {
        throw IOException('Maximum allowed scratch file memory exceeded.');
      }
    }
    _setFree(idx, false);
    if (idx >= _pageCount) {
      _pageCount = idx + 1;
    }
    return idx;
  }

  Uint8List readPage(int pageIdx) {
    if (pageIdx < 0 || pageIdx >= _pageCount) {
      _checkClosed();
      throw IOException('Page index out of range: $pageIdx. Max value: ${_pageCount - 1}');
    }

    final inMemoryPages = _inMemoryPages;
    if (inMemoryPages != null && pageIdx < inMemoryPages.length) {
      final page = inMemoryPages[pageIdx];
      if (page == null) {
        _checkClosed();
        throw IOException('Requested page with index $pageIdx was not written before.');
      }
      return Uint8List.fromList(page);
    }

    final raf = _ensureScratchFile();
    final page = Uint8List(_pageSize);
    final fileOffset = (pageIdx - _inMemoryMaxPageCount) * _pageSize;
    raf.setPositionSync(fileOffset);
    var totalRead = 0;
    while (totalRead < _pageSize) {
      final bytesRead = raf.readIntoSync(page, totalRead, totalRead + (_pageSize - totalRead));
      if (bytesRead <= 0) {
        break;
      }
      totalRead += bytesRead;
    }
    return page;
  }

  void writePage(int pageIdx, Uint8List page) {
    if (pageIdx < 0 || pageIdx >= _pageCount) {
      _checkClosed();
      throw IOException('Page index out of range: $pageIdx. Max value: ${_pageCount - 1}');
    }
    if (page.length != _pageSize) {
      throw IOException('Wrong page size to write: ${page.length}. Expected: $_pageSize');
    }

    if (pageIdx < _inMemoryMaxPageCount || !_maxMainMemoryIsRestricted) {
      _ensureInMemoryCapacity(pageIdx + 1);
      _inMemoryPages![pageIdx] = Uint8List.fromList(page);
      return;
    }

    final raf = _ensureScratchFile();
    final fileOffset = (pageIdx - _inMemoryMaxPageCount) * _pageSize;
    raf.setPositionSync(fileOffset);
    raf.writeFromSync(page, 0, page.length);
  }

  void markPagesAsFree(List<int> pageIndexes, int start, int count) {
    if (count <= 0) {
      return;
    }
    final end = start + count;
    for (var idx = start; idx < end && idx < pageIndexes.length; idx++) {
      final pageIdx = pageIndexes[idx];
      if (pageIdx < 0 || pageIdx >= _pageCount) {
        continue;
      }
      if (!_freePages[pageIdx]) {
        _setFree(pageIdx, true);
        if (_inMemoryPages != null && pageIdx < _inMemoryPages!.length) {
          _inMemoryPages![pageIdx] = null;
        }
      }
    }
  }

  void _initPages() {
    if (_inMemoryPages != null) {
      return;
    }
    final initialLength = _maxMainMemoryIsRestricted
        ? _inMemoryMaxPageCount
        : _initUnrestrictedMainMemPageCount;
    final capacity = initialLength > 0 ? initialLength : _enlargePageCount;
    _inMemoryPages = List<Uint8List?>.filled(capacity, null, growable: !_maxMainMemoryIsRestricted);
    _freePages = List<bool>.filled(capacity, true, growable: true);
  }

  void _ensureInMemoryCapacity(int desired) {
    if (_inMemoryPages == null) {
      _initPages();
    }
    if (_inMemoryPages == null) {
      return;
    }
    if (_inMemoryPages!.length >= desired) {
      return;
    }
    if (_maxMainMemoryIsRestricted) {
      return;
    }
    var newLength = _inMemoryPages!.length;
    while (newLength < desired && newLength < _unrestrictedPageLimit) {
      newLength = (newLength * 2).clamp(0, _unrestrictedPageLimit);
      if (newLength == _unrestrictedPageLimit) {
        break;
      }
    }
    if (newLength > _inMemoryPages!.length) {
      final oldLength = _inMemoryPages!.length;
      _inMemoryPages!.length = newLength;
      _freePages.length = newLength;
      for (var i = oldLength; i < newLength; i++) {
        _freePages[i] = true;
      }
    }
  }

  void _enlarge() {
    if (_pageCount >= _maxPageCount) {
      return;
    }

    if (_useScratchFile) {
      _ensureScratchFile();
      final pagesToAdd = _computePagesToAdd();
      if (pagesToAdd <= 0) {
        return;
      }
      final start = _freePages.length;
      _freePages.length = start + pagesToAdd;
      for (var i = start; i < _freePages.length; i++) {
        _freePages[i] = true;
      }
    } else if (!_maxMainMemoryIsRestricted) {
      _ensureInMemoryCapacity(_inMemoryPages!.length * 2);
    }
  }

  int _computePagesToAdd() {
    final remaining = _maxPageCount - _pageCount;
    if (remaining <= 0) {
      return 0;
    }
    return remaining < _enlargePageCount ? remaining : _enlargePageCount;
  }

  RandomAccessFile _ensureScratchFile() {
    if (!_useScratchFile) {
      throw IOException('Scratch file usage not enabled');
    }
    var raf = _raf;
    if (raf != null) {
      return raf;
    }
    final dir = _scratchFileDirectory ?? Directory.systemTemp;
    dir.createSync(recursive: true);
    File file;
    do {
      final name = 'pdfbox_${DateTime.now().microsecondsSinceEpoch}_${_scratchFileId++}.tmp';
      file = File('${dir.path}${Platform.pathSeparator}$name');
    } while (file.existsSync());

    file.createSync();
    raf = file.openSync(mode: FileMode.write);
    _file = file;
    _raf = raf;
    return raf;
  }

  int _nextFreePage(int start) {
    for (var i = start; i < _freePages.length; i++) {
      if (_freePages[i]) {
        return i;
      }
    }
    return -1;
  }

  void _setFree(int index, bool value) {
    if (index >= _freePages.length) {
      _freePages.length = index + 1;
      for (var i = 0; i < _freePages.length; i++) {
        _freePages[i] = i >= index ? value : _freePages[i];
      }
    } else {
      _freePages[index] = value;
    }
  }
}

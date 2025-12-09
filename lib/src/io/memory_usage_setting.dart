import 'dart:io';
import 'random_access_stream_cache.dart';
import 'random_access_stream_cache_impl.dart';

class MemoryUsageSetting {
  MemoryUsageSetting._internal({
    required bool useMainMemory,
    required bool useTempFile,
    required int maxMainMemoryBytes,
    required int maxStorageBytes,
  })
      : _useTempFile = useTempFile,
        _normalized = _normalize(useMainMemory, useTempFile, maxMainMemoryBytes, maxStorageBytes) {
    streamCache = () => _scratchFileFactory(this);
  }

  factory MemoryUsageSetting.setupMainMemoryOnly([int maxMainMemoryBytes = -1]) {
    return MemoryUsageSetting._internal(
      useMainMemory: true,
      useTempFile: false,
      maxMainMemoryBytes: maxMainMemoryBytes,
      maxStorageBytes: maxMainMemoryBytes,
    );
  }

  factory MemoryUsageSetting.setupTempFileOnly([int maxStorageBytes = -1]) {
    return MemoryUsageSetting._internal(
      useMainMemory: false,
      useTempFile: true,
      maxMainMemoryBytes: 0,
      maxStorageBytes: maxStorageBytes,
    );
  }

  factory MemoryUsageSetting.setupMixed(int maxMainMemoryBytes, [int maxStorageBytes = -1]) {
    return MemoryUsageSetting._internal(
      useMainMemory: true,
      useTempFile: true,
      maxMainMemoryBytes: maxMainMemoryBytes,
      maxStorageBytes: maxStorageBytes,
    );
  }

  static void registerScratchFileFactory(
    RandomAccessStreamCache Function(MemoryUsageSetting setting) factory,
  ) {
    _scratchFileFactory = factory;
  }

  late final StreamCacheCreateFunction streamCache;

  bool useMainMemory() => _normalized.useMainMemory;

  bool useTempFile() => _useTempFile;

  bool isMainMemoryRestricted() => _normalized.maxMainMemoryBytes >= 0;

  bool isStorageRestricted() => _normalized.maxStorageBytes > 0;

  int getMaxMainMemoryBytes() => _normalized.maxMainMemoryBytes;

  int getMaxStorageBytes() => _normalized.maxStorageBytes;

  Directory? getTempDir() => _tempDir;

  MemoryUsageSetting setTempDir(Directory? dir) {
    _tempDir = dir;
    return this;
  }

  @override
  String toString() {
    final maxMem = _normalized.maxMainMemoryBytes;
    final maxStorage = _normalized.maxStorageBytes;
    if (useMainMemory()) {
      if (useTempFile()) {
        final storageDesc = isStorageRestricted()
            ? ' and max. of $maxStorage storage bytes'
            : ' and unrestricted scratch file size';
        return 'Mixed mode with max. of $maxMem main memory bytes$storageDesc';
      }
      return isMainMemoryRestricted()
          ? 'Main memory only with max. of $maxMem bytes'
          : 'Main memory only with no size restriction';
    }
    return isStorageRestricted()
        ? 'Scratch file only with max. of $maxStorage bytes'
        : 'Scratch file only with no size restriction';
  }

  Directory? _tempDir;
  final bool _useTempFile;
  final _NormalizedConfig _normalized;

  static _NormalizedConfig _normalize(
    bool useMainMemory,
    bool useTempFile,
    int maxMainMemoryBytes,
    int maxStorageBytes,
  ) {
    var locUseMainMemory = !useTempFile || useMainMemory;
    var locMaxMainMemoryBytes = useMainMemory ? maxMainMemoryBytes : -1;
    var locMaxStorageBytes = maxStorageBytes > 0 ? maxStorageBytes : -1;

    if (locMaxMainMemoryBytes < -1) {
      locMaxMainMemoryBytes = -1;
    }

    if (locUseMainMemory && locMaxMainMemoryBytes == 0) {
      if (useTempFile) {
        locUseMainMemory = false;
      } else {
        locMaxMainMemoryBytes = locMaxStorageBytes;
      }
    }

    if (locUseMainMemory && locMaxStorageBytes > -1) {
      if (locMaxMainMemoryBytes == -1 || locMaxMainMemoryBytes > locMaxStorageBytes) {
        locMaxStorageBytes = locMaxMainMemoryBytes;
      }
    }

    final normalizedMaxMainMem = locUseMainMemory
        ? (locMaxMainMemoryBytes == 0 ? -1 : locMaxMainMemoryBytes)
        : -1;

    return _NormalizedConfig(
      useMainMemory: locUseMainMemory,
      maxMainMemoryBytes: normalizedMaxMainMem,
      maxStorageBytes: locMaxStorageBytes,
    );
  }

  static RandomAccessStreamCache Function(MemoryUsageSetting) _scratchFileFactory =
      (setting) => RandomAccessStreamCacheImpl();
}

class _NormalizedConfig {
  const _NormalizedConfig({
    required this.useMainMemory,
    required this.maxMainMemoryBytes,
    required this.maxStorageBytes,
  });

  final bool useMainMemory;
  final int maxMainMemoryBytes;
  final int maxStorageBytes;
}

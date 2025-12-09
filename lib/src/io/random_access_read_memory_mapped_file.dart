import 'dart:io';
import 'dart:typed_data';
import 'random_access_read.dart';
import 'random_access_read_buffered_file.dart';
import 'random_access_read_view.dart';

/// Simplified stand-in for PDFBox's memory-mapped reader.
///
/// Dart does not expose a cross-platform memory-mapping API, so this class
/// proxies all calls to [RandomAccessReadBufferedFile], relying on the OS
/// page cache for performance.
class RandomAccessReadMemoryMappedFile extends RandomAccessRead {
  RandomAccessReadMemoryMappedFile(String path)
      : _delegate = RandomAccessReadBufferedFile(path);

  factory RandomAccessReadMemoryMappedFile.fromFile(File file) {
    return RandomAccessReadMemoryMappedFile(file.path);
  }

  final RandomAccessReadBufferedFile _delegate;

  @override
  void close() => _delegate.close();

  @override
  int read() => _delegate.read();

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    return _delegate.readBuffer(buffer, offset, length);
  }

  @override
  void seek(int position) => _delegate.seek(position);

  @override
  int get position => _delegate.position;

  @override
  int get length => _delegate.length;

  @override
  bool get isClosed => _delegate.isClosed;

  @override
  bool get isEOF => _delegate.isEOF;

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    return _delegate.createView(startPosition, streamLength);
  }
}

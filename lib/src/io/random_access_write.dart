import 'dart:typed_data';
import 'closeable.dart';

/// Dart counterpart of PDFBox's RandomAccessWrite.
abstract class RandomAccessWrite implements Closeable {
  /// Writes a single byte to the sink.
  void writeByte(int value);

  /// Writes up to [length] bytes from [buffer] starting at [offset].
  void writeBytes(Uint8List buffer, [int offset = 0, int? length]);

  /// Clears all accumulated data.
  void clear();
}

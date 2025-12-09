import 'dart:math' as math;
import 'dart:typed_data';
import 'closeable.dart';
import 'exceptions.dart';
import 'random_access_read_view.dart';

/// Dart counterpart of PDFBox's RandomAccessRead.
abstract class RandomAccessRead implements Closeable {
  /// Reads a single byte from the source. Returns -1 on EOF.
  int read();

  /// Reads up to [length] bytes from the source into [buffer].
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]);

  /// Offset of the next byte that would be returned by [read].
  int get position;

  /// Moves the read cursor to [position].
  void seek(int position);

  /// Total number of readable bytes.
  int get length;

  /// Whether the source has been closed.
  bool get isClosed;

  /// Whether the cursor has reached EOF.
  bool get isEOF;

  /// Creates a view starting at [startPosition] with [streamLength] bytes.
  RandomAccessReadView createView(int startPosition, int streamLength);

  /// Reads up to [buffer.length] bytes into [buffer].
  int readInto(Uint8List buffer) => readBuffer(buffer, 0, buffer.length);

  /// Peeks the next byte without advancing the cursor.
  int peek() {
    final result = read();
    if (result != -1) {
      rewind(1);
    }
    return result;
  }

  /// Moves backwards by [bytes].
  void rewind(int bytes) => seek(position - bytes);

  /// Estimated number of bytes that can be read without blocking.
  int available() {
    if (isClosed) {
      throw IOException('RandomAccessRead already closed');
    }
    final remaining = length - position;
    if (remaining <= 0) {
      return 0;
    }
    return math.min(remaining, 0x7fffffff);
  }

  /// Skips forward by [count] bytes.
  void skip(int count) => seek(position + count);

  /// Reads [buffer.length] bytes, throwing if not enough data.
  void readFully(Uint8List buffer, [int offset = 0, int? requestedLength]) {
    final lengthToRead = requestedLength ?? (buffer.length - offset);
    if (length - position < lengthToRead) {
      throw EofException('Premature end of buffer reached');
    }
    var total = 0;
    while (total < lengthToRead) {
      final readNow = readBuffer(buffer, offset + total, lengthToRead - total);
      if (readNow <= 0) {
        throw EofException('EOF, should have been detected earlier');
      }
      total += readNow;
    }
  }
}

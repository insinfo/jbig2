/// Everything wrong with the input is one of these; API misuse is an
/// [ArgumentError] instead.
///
/// The split matters to a caller: a truncated stream may succeed on retry with
/// the complete bytes, a corrupted one never will, and an unsupported one is a
/// gap in this package rather than a defect in the file.
sealed class Jbig2Exception implements Exception {
  final String message;
  const Jbig2Exception(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The bytes are not a JBIG2 file or an embedded JBIG2 segment stream.
class Jbig2FormatException extends Jbig2Exception {
  const Jbig2FormatException(super.message);
}

/// The stream ends before the data a segment declared.
class Jbig2TruncatedException extends Jbig2Exception {
  const Jbig2TruncatedException(super.message);
}

/// The stream violates the standard in a way decoding cannot recover from.
class Jbig2CorruptedException extends Jbig2Exception {
  const Jbig2CorruptedException(super.message);
}

/// The stream is valid but uses a feature this package does not implement.
class Jbig2UnsupportedException extends Jbig2Exception {
  const Jbig2UnsupportedException(super.message);
}

/// The image is larger than the budget the caller set.
class Jbig2BudgetException extends Jbig2Exception {
  /// Which budget was exceeded, e.g. `maxPixels`.
  final String budget;

  /// The limit the caller set.
  final int limit;

  /// What the stream declared.
  final int actual;

  const Jbig2BudgetException(this.budget, this.limit, this.actual)
      : super('$budget is $limit but the image declares $actual');
}

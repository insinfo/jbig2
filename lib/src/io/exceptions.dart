class IOException implements Exception {
  final String message;

  IOException(this.message);

  @override
  String toString() => 'IOException: $message';
}

class EofException extends IOException {
  EofException(super.message);

  @override
  String toString() => 'EofException: $message';
}

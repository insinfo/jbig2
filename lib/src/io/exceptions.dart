class IOException implements Exception {
  final String message;

  IOException(this.message);

  @override
  String toString() => 'IOException: $message';
}

class EofException extends IOException {
  EofException(String message) : super(message);

  @override
  String toString() => 'EofException: $message';
}

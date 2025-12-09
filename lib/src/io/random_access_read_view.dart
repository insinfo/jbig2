import 'dart:math' as math;
import 'dart:typed_data';
import 'exceptions.dart';
import 'random_access_read.dart';

/// View that exposes a clipped window over another [RandomAccessRead].
class RandomAccessReadView extends RandomAccessRead {
  RandomAccessRead? _randomAccessRead;
  final int _startPosition;
  final int _streamLength;
  final bool _closeInput;
  int _currentPosition = 0;

  RandomAccessReadView(RandomAccessRead randomAccessRead, int startPosition, int streamLength)
      : this._(randomAccessRead, startPosition, streamLength, false);

  RandomAccessReadView._(RandomAccessRead randomAccessRead, int startPosition, int streamLength,
      bool closeInput)
      : _randomAccessRead = randomAccessRead,
        _startPosition = startPosition,
        _streamLength = streamLength,
        _closeInput = closeInput;

  RandomAccessReadView.withCloseControl(
      RandomAccessRead randomAccessRead, int startPosition, int streamLength, bool closeInput)
      : this._(randomAccessRead, startPosition, streamLength, closeInput);

  RandomAccessRead? get _delegate => _randomAccessRead;

  @override
  int get position {
    _checkClosed();
    return _currentPosition;
  }

  @override
  void seek(int position) {
    _checkClosed();
    if (position < 0) {
      throw IOException('Invalid position $position');
    }
    _delegate!.seek(_startPosition + math.min(position, _streamLength));
    _currentPosition = position;
  }

  @override
  int read() {
    if (isEOF) {
      return -1;
    }
    _restorePosition();
    final value = _delegate!.read();
    if (value > -1) {
      _currentPosition++;
    }
    return value;
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    if (isEOF) {
      return -1;
    }
    _restorePosition();
    final effectiveLength = length ?? (buffer.length - offset);
    final bytesRead =
        _delegate!.readBuffer(buffer, offset, math.min(effectiveLength, available()));
    _currentPosition += bytesRead;
    return bytesRead;
  }

  @override
  int get length {
    _checkClosed();
    return _streamLength;
  }

  @override
  void close() {
    if (_closeInput && _delegate != null) {
      _delegate!.close();
    }
    _randomAccessRead = null;
  }

  @override
  bool get isClosed => _delegate == null || _delegate!.isClosed;

  @override
  bool get isEOF {
    _checkClosed();
    return _currentPosition >= _streamLength;
  }

  @override
  void rewind(int bytes) {
    _checkClosed();
    _restorePosition();
    _delegate!.rewind(bytes);
    _currentPosition -= bytes;
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    throw IOException('${runtimeType.toString()}.createView is not supported.');
  }

  void _restorePosition() {
    _delegate!.seek(_startPosition + _currentPosition);
  }

  void _checkClosed() {
    if (isClosed) {
      throw IOException('RandomAccessReadView already closed');
    }
  }
}

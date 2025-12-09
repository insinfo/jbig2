import 'dart:math' as math;
import 'dart:typed_data';

import 'exceptions.dart';
import 'random_access_read.dart';
import 'random_access_read_view.dart';

/// [RandomAccessRead] view that exposes only the bytes inside the provided
/// ranges of an in-memory buffer. This mirrors the behaviour of
/// PDFBox's COSFilterInputStream used during external signing.
class RangeFilteredRandomAccessRead extends RandomAccessRead {
  RangeFilteredRandomAccessRead(Uint8List data, List<int> ranges)
      : _data = Uint8List.view(data.buffer, data.offsetInBytes, data.length) {
    if (ranges.length.isOdd) {
      throw ArgumentError.value(ranges.length, 'ranges', 'Must contain begin/length pairs');
    }
    if (ranges.isEmpty) {
      _segments = const <_Segment>[];
      _length = 0;
      return;
    }

    final segments = <_Segment>[];
    var cumulative = 0;
    for (var i = 0; i < ranges.length; i += 2) {
      final start = ranges[i];
      final length = ranges[i + 1];
      if (start < 0 || length < 0) {
        throw ArgumentError('Invalid range [$start, $length]');
      }
      final end = start + length;
      if (end > data.length) {
        throw ArgumentError('Range [$start, $length] exceeds buffer length ${data.length}');
      }
      if (length == 0) {
        continue;
      }
      segments.add(_Segment(start, length, cumulative));
      cumulative += length;
    }
    _segments = segments;
    _length = cumulative;
  }

  final Uint8List _data;
  late final List<_Segment> _segments;
  late final int _length;
  int _position = 0;
  int _segmentIndex = 0;
  bool _closed = false;

  @override
  int read() {
    _ensureOpen();
    if (_position >= _length) {
      return -1;
    }
    final segment = _locateSegment(_position);
    final offset = segment.start + (_position - segment.cumulativeStart);
    final value = _data[offset];
    _position++;
    if (_position >= segment.cumulativeStart + segment.length) {
      _segmentIndex = math.min(_segmentIndex + 1, _segments.length);
    }
    return value;
  }

  @override
  int readBuffer(Uint8List buffer, [int offset = 0, int? length]) {
    _ensureOpen();
    if (_position >= _length) {
      return -1;
    }
    final requested = length ?? (buffer.length - offset);
    if (requested <= 0) {
      return 0;
    }

    var remaining = math.min(requested, _length - _position);
    var written = 0;
    while (remaining > 0) {
      final segment = _locateSegment(_position);
      final segmentOffset = _position - segment.cumulativeStart;
      final available = segment.length - segmentOffset;
      final toCopy = math.min(available, remaining);
      final sourceOffset = segment.start + segmentOffset;
      final slice = Uint8List.sublistView(_data, sourceOffset, sourceOffset + toCopy);
      buffer.setRange(offset + written, offset + written + toCopy, slice);

      written += toCopy;
      remaining -= toCopy;
      _position += toCopy;
      if (_position >= segment.cumulativeStart + segment.length) {
        _segmentIndex = math.min(_segmentIndex + 1, _segments.length);
      }
    }
    return written;
  }

  @override
  int get position {
    _ensureOpen();
    return _position;
  }

  @override
  void seek(int position) {
    _ensureOpen();
    if (position < 0) {
      throw IOException('Invalid position $position');
    }
    _position = math.min(position, _length);
    _segmentIndex = 0;
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      if (_position < segment.cumulativeStart + segment.length) {
        _segmentIndex = i;
        break;
      }
    }
  }

  @override
  int get length {
    _ensureOpen();
    return _length;
  }

  @override
  bool get isClosed => _closed;

  @override
  bool get isEOF {
    _ensureOpen();
    return _position >= _length;
  }

  @override
  void close() {
    _closed = true;
  }

  @override
  RandomAccessReadView createView(int startPosition, int streamLength) {
    throw IOException('${runtimeType.toString()}.createView is not supported.');
  }

  _Segment _locateSegment(int globalPosition) {
    if (_segments.isEmpty) {
      throw IOException('No data available');
    }
    while (_segmentIndex < _segments.length) {
      final segment = _segments[_segmentIndex];
      if (globalPosition >= segment.cumulativeStart &&
          globalPosition < segment.cumulativeStart + segment.length) {
        return segment;
      }
      _segmentIndex++;
    }
    return _segments.last;
  }

  void _ensureOpen() {
    if (_closed) {
      throw IOException('RangeFilteredRandomAccessRead already closed');
    }
  }
}

class _Segment {
  _Segment(this.start, this.length, this.cumulativeStart);

  final int start;
  final int length;
  final int cumulativeStart;
}

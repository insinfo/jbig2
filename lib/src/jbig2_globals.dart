import 'segment_header.dart';

class JBIG2Globals {
  final Map<int, SegmentHeader> _globalSegments = {};

  SegmentHeader? getSegment(int segmentNr) {
    return _globalSegments[segmentNr];
  }

  void addSegment(int segmentNumber, SegmentHeader segment) {
    _globalSegments[segmentNumber] = segment;
  }
}

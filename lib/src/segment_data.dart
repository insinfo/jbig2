import 'segment_header.dart';
import 'io/sub_input_stream.dart';

abstract class SegmentData {
  void init(SegmentHeader? header, SubInputStream sis);
}

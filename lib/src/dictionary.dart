import 'bitmap.dart';
import 'segment_data.dart';

abstract class Dictionary implements SegmentData {
  List<Bitmap> getDictionary();
}

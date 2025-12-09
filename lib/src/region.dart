import 'segment_data.dart';
import 'bitmap.dart';
import 'segments/region_segment_information.dart';

abstract class Region implements SegmentData {
  Bitmap getRegionBitmap();
  RegionSegmentInformation getRegionInfo();
}

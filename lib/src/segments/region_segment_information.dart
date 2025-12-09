import '../segment_data.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';
import '../util/combination_operator.dart';

class RegionSegmentInformation implements SegmentData {
  SubInputStream? subInputStream;

  /** Region segment bitmap width, 7.4.1.1 */
  int bitmapWidth = 0;

  /** Region segment bitmap height, 7.4.1.2 */
  int bitmapHeight = 0;

  /** Region segment bitmap X location, 7.4.1.3 */
  int xLocation = 0;

  /** Region segment bitmap Y location, 7.4.1.4 */
  int yLocation = 0;

  /** Region segment flags, 7.4.1.5 */
  CombinationOperator combinationOperator = CombinationOperator.OR;

  RegionSegmentInformation([this.subInputStream]);

  void parseHeader() {
    if (subInputStream == null) return;
    
    bitmapWidth = subInputStream!.readBits(32);
    bitmapHeight = subInputStream!.readBits(32);
    xLocation = _toSigned32(subInputStream!.readBits(32));
    yLocation = _toSigned32(subInputStream!.readBits(32));

    /* Bit 3-7 */
    subInputStream!.readBits(5); // Dirty read... reserved bits are 0

    /* Bit 0-2 */
    readCombinationOperator();
  }

  int _toSigned32(int val) {
    if (val >= 0x80000000) {
      return val - 0x100000000;
    }
    return val;
  }

  void readCombinationOperator() {
    if (subInputStream == null) return;
    combinationOperator = CombinationOperator.translateOperatorCodeToEnum(
        subInputStream!.readBits(3) & 0xf);
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    // Do nothing? Java implementation does nothing.
  }

  void setBitmapWidth(int bitmapWidth) {
    this.bitmapWidth = bitmapWidth;
  }

  int getBitmapWidth() {
    return bitmapWidth;
  }

  void setBitmapHeight(int bitmapHeight) {
    this.bitmapHeight = bitmapHeight;
  }

  int getBitmapHeight() {
    return bitmapHeight;
  }

  int getXLocation() {
    return xLocation;
  }

  int getYLocation() {
    return yLocation;
  }

  CombinationOperator getCombinationOperator() {
    return combinationOperator;
  }
}

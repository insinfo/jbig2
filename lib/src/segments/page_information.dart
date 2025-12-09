import 'package:jbig2/src/segment_data.dart';
import 'package:jbig2/src/segment_header.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/util/combination_operator.dart';

class PageInformation implements SegmentData {
  late SubInputStream subInputStream;

  /** Page bitmap width, four byte, 7.4.8.1 */
  int bitmapWidth = 0;

  /** Page bitmap height, four byte, 7.4.8.2 */
  int bitmapHeight = 0;

  /** Page X resolution, four byte, 7.4.8.3 */
  int resolutionX = 0;

  /** Page Y resolution, four byte, 7.4.8.4 */
  int resolutionY = 0;

  /** Page segment flags, one byte, 7.4.8.5 */
  bool combinationOperatorOverrideAllowed = false;
  CombinationOperator combinationOperator = CombinationOperator.OR; // Default?
  bool requiresAuxiliaryBuffer = false;
  int defaultPixelValue = 0;
  bool mightContainRefinements = false;
  bool isLossless = false;

  /** Page striping information, two byte, 7.4.8.6 */
  bool isStriped = false;
  int maxStripeSize = 0;

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    subInputStream = sis;
    parseHeader();
  }

  void parseHeader() {
    readWidthAndHeight();
    readResolution();

    /* Bit 7 */
    subInputStream.readBit(); // dirty read

    /* Bit 6 */
    readCombinationOperatorOverrideAllowed();

    /* Bit 5 */
    readRequiresAuxiliaryBuffer();

    /* Bit 3-4 */
    readCombinationOperator();

    /* Bit 2 */
    readDefaultPixelvalue();

    /* Bit 1 */
    readContainsRefinement();

    /* Bit 0 */
    readIsLossless();

    /* Bit 15 */
    readIsStriped();

    /* Bit 0-14 */
    readMaxStripeSize();

    checkInput();
  }

  void readResolution() {
    resolutionX = subInputStream.readBits(32) & 0xffffffff;
    resolutionY = subInputStream.readBits(32) & 0xffffffff;
  }

  void checkInput() {
    if (bitmapHeight == 0xffffffff) {
      if (!isStriped) {
        // log.info("isStriped should contaion the value true");
        // print("isStriped should contaion the value true");
      }
    }
  }

  void readCombinationOperatorOverrideAllowed() {
    /* Bit 6 */
    if (subInputStream.readBit() == 1) {
      combinationOperatorOverrideAllowed = true;
    }
  }

  void readRequiresAuxiliaryBuffer() {
    /* Bit 5 */
    if (subInputStream.readBit() == 1) {
      requiresAuxiliaryBuffer = true;
    }
  }

  void readCombinationOperator() {
    /* Bit 3-4 */
    combinationOperator = CombinationOperator.translateOperatorCodeToEnum(
        subInputStream.readBits(2) & 0xf);
  }

  void readDefaultPixelvalue() {
    /* Bit 2 */
    defaultPixelValue = subInputStream.readBit();
  }

  void readContainsRefinement() {
    /* Bit 1 */
    if (subInputStream.readBit() == 1) {
      mightContainRefinements = true;
    }
  }

  void readIsLossless() {
    /* Bit 0 */
    if (subInputStream.readBit() == 1) {
      isLossless = true;
    }
  }

  void readIsStriped() {
    /* Bit 15 */
    if (subInputStream.readBit() == 1) {
      isStriped = true;
    }
  }

  void readMaxStripeSize() {
    /* Bit 0-14 */
    maxStripeSize = subInputStream.readBits(15) & 0xffff;
  }

  void readWidthAndHeight() {
    bitmapWidth = subInputStream.readBits(32); // & 0xffffffff;
    bitmapHeight = subInputStream.readBits(32); // & 0xffffffff;
  }

  int getWidth() {
    return bitmapWidth;
  }

  int getHeight() {
    return bitmapHeight;
  }

  int getResolutionX() {
    return resolutionX;
  }

  int getResolutionY() {
    return resolutionY;
  }

  int getDefaultPixelValue() {
    return defaultPixelValue;
  }

  bool isCombinationOperatorOverrideAllowed() {
    return combinationOperatorOverrideAllowed;
  }

  CombinationOperator getCombinationOperator() {
    return combinationOperator;
  }

  bool getIsStriped() {
    return isStriped;
  }

  int getMaxStripeSize() {
    return maxStripeSize;
  }

  bool isAuxiliaryBufferRequired() {
    return requiresAuxiliaryBuffer;
  }

  bool getMightContainRefinements() {
    return mightContainRefinements;
  }

  bool getIsLossless() {
    return isLossless;
  }
}

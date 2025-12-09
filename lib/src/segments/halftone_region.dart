import 'dart:math';

import '../region.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';
import '../bitmap.dart';
import '../image/bitmaps.dart';
import 'region_segment_information.dart';
import '../util/combination_operator.dart';
import '../util/log.dart';
import 'pattern_dictionary.dart';
import 'generic_region.dart';

class HalftoneRegion implements Region {
  SubInputStream? _subInputStream;
  SegmentHeader? _segmentHeader;
  int _dataHeaderOffset = 0;
  int _dataHeaderLength = 0;
  int _dataOffset = 0;
  int _dataLength = 0;

  late RegionSegmentInformation _regionInfo;

  // Halftone segment information field
  int _hDefaultPixel = 0;
  CombinationOperator _hCombinationOperator = CombinationOperator.OR;
  bool _hSkipEnabled = false;
  int _hTemplate = 0;
  bool _isMMREncoded = false;

  // Halftone grid position and size
  int _hGridWidth = 0;
  int _hGridHeight = 0;
  int _hGridX = 0;
  int _hGridY = 0;

  // Halftone grid vector
  int _hRegionX = 0;
  int _hRegionY = 0;

  // Decoded data
  Bitmap? _halftoneRegionBitmap;

  // Previously decoded data from other regions or dictionaries
  List<Bitmap>? _patterns;

  HalftoneRegion([this._subInputStream, this._segmentHeader]) {
    if (_subInputStream != null) {
      _regionInfo = RegionSegmentInformation(_subInputStream);
    }
  }

  void _parseHeader() {
    _regionInfo.parseHeader();

    _hDefaultPixel = _subInputStream!.readBit();
    _hCombinationOperator = CombinationOperator.translateOperatorCodeToEnum(_subInputStream!.readBits(3) & 0xf);

    if (_subInputStream!.readBit() == 1) {
      _hSkipEnabled = true;
    }

    _hTemplate = _subInputStream!.readBits(2) & 0xf;

    if (_subInputStream!.readBit() == 1) {
      _isMMREncoded = true;
    }

    _hGridWidth = _subInputStream!.readBits(32) & 0xffffffff;
    _hGridHeight = _subInputStream!.readBits(32) & 0xffffffff;

    _hGridX = _subInputStream!.readBits(32); // Signed? Java reads 32 bits.
    // Java: hGridX = (int) subInputStream.readBits(32);
    // Dart readBits returns int. If it's signed 32-bit in Java, it might be negative.
    // My readBits returns unsigned value if I don't sign extend.
    // Wait, readBits returns int. If I read 32 bits, it's a positive integer in Dart (64-bit).
    // I need to sign extend if it's supposed to be signed 32-bit.
    // Java (int) cast does sign extension if the 32nd bit is set.
    _hGridX = _toSigned32(_hGridX);
    
    _hGridY = _subInputStream!.readBits(32);
    _hGridY = _toSigned32(_hGridY);

    _hRegionX = _subInputStream!.readBits(16) & 0xffff;
    _hRegionX = _toSigned16(_hRegionX); // Java: (int) subInputStream.readBits(16) & 0xffff; -> This is unsigned 16 bit in Java int.
    // Wait, Java: hRegionX = (int) subInputStream.readBits(16) & 0xffff;
    // readBits returns long in Java? No, int or long.
    // If readBits returns long, & 0xffff keeps it positive.
    // So hRegionX is unsigned 16-bit.
    // My readBits returns int.
    
    _hRegionY = _subInputStream!.readBits(16) & 0xffff;
    // Same here.

    _computeSegmentDataStructure();
    _checkInput();
  }
  
  int _toSigned32(int val) {
    if (val >= 0x80000000) return val - 0x100000000;
    return val;
  }
  
  int _toSigned16(int val) {
      // Java code uses & 0xffff, so it treats it as unsigned 16-bit integer stored in int.
      // So I don't need to sign extend.
      return val;
  }

  void _computeSegmentDataStructure() {
    _dataOffset = _subInputStream!.getStreamPosition();
    _dataHeaderLength = _dataOffset - _dataHeaderOffset;
    _dataLength = _subInputStream!.length - _dataHeaderLength;
  }

  void _checkInput() {
    if (_isMMREncoded) {
      if (_hTemplate != 0) {
        Logger.info("hTemplate = $_hTemplate (should contain the value 0)");
      }
      if (_hSkipEnabled) {
        Logger.info("hSkipEnabled 0 $_hSkipEnabled (should contain the value false)");
      }
    }
  }

  @override
  Bitmap getRegionBitmap() {
    if (_halftoneRegionBitmap == null) {
      _halftoneRegionBitmap = Bitmap(_regionInfo.bitmapWidth, _regionInfo.bitmapHeight);

      if (_patterns == null) {
        _patterns = _getPatterns();
      }

      if (_hDefaultPixel == 1) {
        // Fill with 0xff
        for(int i=0; i<_halftoneRegionBitmap!.getByteArray().length; i++) {
            _halftoneRegionBitmap!.getByteArray()[i] = 0xff;
        }
      }

      final int bitsPerValue = (log(_patterns!.length) / log(2)).ceil();
      final List<List<int>> grayScaleValues = _grayScaleDecoding(bitsPerValue);
      _renderPattern(grayScaleValues);
    }
    return _halftoneRegionBitmap!;
  }

  void _renderPattern(final List<List<int>> grayScaleValues) {
    int x = 0, y = 0;
    for (int m = 0; m < _hGridHeight; m++) {
      for (int n = 0; n < _hGridWidth; n++) {
        x = _computeX(m, n);
        y = _computeY(m, n);
        final Bitmap patternBitmap = _patterns![grayScaleValues[m][n]];
        Bitmaps.blit(patternBitmap, _halftoneRegionBitmap!, (x + _hGridX), (y + _hGridY), _hCombinationOperator);
      }
    }
  }

  List<Bitmap> _getPatterns() {
    final List<Bitmap> patterns = [];
    if (_segmentHeader != null) {
      for (SegmentHeader s in _segmentHeader!.rtSegments) {
        final PatternDictionary patternDictionary = s.getSegmentData() as PatternDictionary;
        patterns.addAll(patternDictionary.getDictionary());
      }
    }
    return patterns;
  }

  List<List<int>> _grayScaleDecoding(final int bitsPerValue) {
    List<int>? gbAtX;
    List<int>? gbAtY;

    if (!_isMMREncoded) {
      gbAtX = List.filled(4, 0);
      gbAtY = List.filled(4, 0);
      if (_hTemplate <= 1) {
        gbAtX[0] = 3;
      } else if (_hTemplate >= 2) {
        gbAtX[0] = 2;
      }
      gbAtY[0] = -1;
      gbAtX[1] = -3;
      gbAtY[1] = -1;
      gbAtX[2] = 2;
      gbAtY[2] = -2;
      gbAtX[3] = -2;
      gbAtY[3] = -2;
    }

    List<Bitmap?> grayScalePlanes = List.filled(bitsPerValue, null);

    GenericRegion genericRegion = GenericRegion(_subInputStream!);
    genericRegion.setParametersForPattern(_isMMREncoded, _dataOffset, _dataLength, _hGridHeight, _hGridWidth, _hTemplate, false,
        _hSkipEnabled, gbAtX!, gbAtY!);

    int j = bitsPerValue - 1;
    grayScalePlanes[j] = genericRegion.getRegionBitmap();

    while (j > 0) {
      j--;
      genericRegion.resetBitmap();
      grayScalePlanes[j] = genericRegion.getRegionBitmap();
      _combineGrayScalePlanes(grayScalePlanes, j);
    }

    return _computeGrayScaleValues(grayScalePlanes, bitsPerValue);
  }

  void _combineGrayScalePlanes(List<Bitmap?> grayScalePlanes, int j) {
    int byteIndex = 0;
    for (int y = 0; y < grayScalePlanes[j]!.height; y++) {
      for (int x = 0; x < grayScalePlanes[j]!.width; x += 8) {
        final int newValue = grayScalePlanes[j + 1]!.getByte(byteIndex);
        final int oldValue = grayScalePlanes[j]!.getByte(byteIndex);
        grayScalePlanes[j]!.setByte(byteIndex++, Bitmaps.combineBytes(oldValue, newValue, CombinationOperator.XOR));
      }
    }
  }

  List<List<int>> _computeGrayScaleValues(final List<Bitmap?> grayScalePlanes, final int bitsPerValue) {
    final List<List<int>> grayScaleValues = List.generate(_hGridHeight, (_) => List.filled(_hGridWidth, 0));

    for (int y = 0; y < _hGridHeight; y++) {
      for (int x = 0; x < _hGridWidth; x += 8) {
        final int minorWidth = _hGridWidth - x > 8 ? 8 : _hGridWidth - x;
        int byteIndex = grayScalePlanes[0]!.getByteIndex(x, y);

        for (int minorX = 0; minorX < minorWidth; minorX++) {
          final int i = minorX + x;
          grayScaleValues[y][i] = 0;

          for (int j = 0; j < bitsPerValue; j++) {
            grayScaleValues[y][i] += ((grayScalePlanes[j]!.getByte(byteIndex) >> (7 - i & 7)) & 1) * (1 << j);
          }
        }
      }
    }
    return grayScaleValues;
  }

  int _computeX(final int m, final int n) {
    return _shiftAndFill((_hGridX + m * _hRegionY + n * _hRegionX));
  }

  int _computeY(final int m, final int n) {
    return _shiftAndFill((_hGridY + m * _hRegionX - n * _hRegionY));
  }

  int _shiftAndFill(int value) {
    value >>= 8;
    if (value < 0) {
      // In Java: Integer.highestOneBit(value)
      // Dart doesn't have highestOneBit directly on int?
      // I can implement it.
      // But wait, value is negative, so highest bit is 1 (sign bit).
      // Java's highestOneBit returns the highest one bit in the two's complement representation.
      // If value is negative, it's a large positive number in unsigned sense?
      // No, Java int is signed.
      // If value is -1 (0xFFFFFFFF), highestOneBit is 0x80000000 (min value).
      // Math.log(0x80000000) is 31.
      // 31 - 31 = 0. Loop doesn't run.
      
      // Let's look at Java code again.
      /*
      final int bitPosition = (int) (Math.log(Integer.highestOneBit(value)) / Math.log(2));
      for (int i = 1; i < 31 - bitPosition; i++) {
        value |= 1 << (31 - i);
      }
      */
      // This logic seems to be doing sign extension or filling 1s?
      // If value was shifted right by 8, and it was negative, the top 8 bits are 1s (arithmetic shift).
      // But if it was logical shift (>>>), top bits are 0.
      // Java code uses >>= which is arithmetic shift. So top bits are already 1s if it was negative.
      // So why this loop?
      
      // Maybe hGridX etc are treated as fixed point?
      // "7.4.5.1.2.3 Horizontal offset of the grid ... 4 bytes ... signed integer"
      // "7.4.5.1.3.1 Horizontal coordinate of the halftone grid vector ... 2 bytes ... signed integer"
      
      // The formula for x is: x = (HGX + m * HRY + n * HRX) >> 8
      // This looks like fixed point arithmetic with 8 fractional bits.
      
      // If I use Dart's >> operator, it preserves sign.
      // So `value >>= 8` should be correct for arithmetic shift.
      
      // The Java code `shiftAndFill` seems to be trying to replicate arithmetic shift behavior if the input was somehow not sign extended correctly or if they want to fill more bits?
      // Or maybe `value` passed to `shiftAndFill` is the result of the calculation.
      
      // Let's assume Dart's `>>` is sufficient for arithmetic shift.
      // But I should check if `value` passed to `shiftAndFill` can be negative.
      // Yes.
      
      // If I just return `value`, it should be fine?
      // Let's check what the Java code actually does.
      // `Integer.highestOneBit(value)` for a negative number returns `Integer.MIN_VALUE` (0x80000000).
      // `Math.log(2^31) / Math.log(2)` is 31.
      // `31 - 31` is 0. Loop `i < 0` is false.
      // So for negative numbers, the loop does nothing?
      // Wait, `Integer.highestOneBit(-1)` is `0x80000000`.
      // `Integer.highestOneBit(-100)` is `0x80000000`.
      // So for any negative number, `bitPosition` is 31.
      // So the loop never runs.
      
      // What if `value` is positive but was supposed to be negative?
      // No, `value < 0` check prevents that.
      
      // Maybe `value` is not fully sign extended?
      // If `value` comes from `hGridX` (32-bit signed) + ...
      // It is a 32-bit signed integer.
      
      // I suspect the Java code might be redundant or I am missing something about `highestOneBit`.
      // `highestOneBit(i)`: "Returns an int value with at most a single one-bit, in the position of the highest-order ("leftmost") one-bit in the specified int value."
      
      // If I just use `>> 8`, it should be fine.
    }
    return value;
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _segmentHeader = header;
    _subInputStream = sis;
    _regionInfo = RegionSegmentInformation(_subInputStream);
    _parseHeader();
  }

  @override
  RegionSegmentInformation getRegionInfo() {
    return _regionInfo;
  }

  bool get isMMREncoded => _isMMREncoded;
  int get hTemplate => _hTemplate;
  bool get isHSkipEnabled => _hSkipEnabled;
  CombinationOperator get combinationOperator => _hCombinationOperator;
  int get hDefaultPixel => _hDefaultPixel;
  int get hGridWidth => _hGridWidth;
  int get hGridHeight => _hGridHeight;
  int get hGridX => _hGridX;
  int get hGridY => _hGridY;
  int get hRegionX => _hRegionX;
  int get hRegionY => _hRegionY;
}

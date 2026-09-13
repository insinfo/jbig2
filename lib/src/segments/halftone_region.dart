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
  final int _dataHeaderOffset = 0;
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
    _hCombinationOperator = CombinationOperator.translateOperatorCodeToEnum(
        _subInputStream!.readBits(3) & 0xf);

    if (_subInputStream!.readBit() == 1) {
      _hSkipEnabled = true;
    }

    _hTemplate = _subInputStream!.readBits(2) & 0xf;

    if (_subInputStream!.readBit() == 1) {
      _isMMREncoded = true;
    }

    _hGridWidth = _subInputStream!.readBits(32) & 0xffffffff;
    _hGridHeight = _subInputStream!.readBits(32) & 0xffffffff;

    // 7.4.5.1.2: HGX and HGY are signed 32 bit fixed point values with eight
    // fractional bits.
    _hGridX = _subInputStream!.readBits(32).toSigned(32);
    _hGridY = _subInputStream!.readBits(32).toSigned(32);

    // 7.4.5.1.3: HRX and HRY are unsigned 16 bit fixed point values.
    _hRegionX = _subInputStream!.readBits(16) & 0xffff;
    _hRegionY = _subInputStream!.readBits(16) & 0xffff;

    _computeSegmentDataStructure();
    _checkInput();
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
        Logger.info(
            "hSkipEnabled 0 $_hSkipEnabled (should contain the value false)");
      }
    }
  }

  @override
  Bitmap getRegionBitmap() {
    if (_halftoneRegionBitmap == null) {
      _halftoneRegionBitmap =
          Bitmap(_regionInfo.bitmapWidth, _regionInfo.bitmapHeight);

      _patterns ??= _getPatterns();

      if (_hDefaultPixel == 1) {
        // Fill with 0xff
        for (int i = 0; i < _halftoneRegionBitmap!.getByteArray().length; i++) {
          _halftoneRegionBitmap!.getByteArray()[i] = 0xff;
        }
      }

      /* 6.6.5 2) */
      final Bitmap? skip = _hSkipEnabled ? _computeSkipBitmap() : null;

      /* 6.6.5 3) */
      final int bitsPerValue = (log(_patterns!.length) / log(2)).ceil();

      /* 6.6.5 4) and 5) */
      final List<List<int>> grayScaleValues =
          _grayScaleDecoding(bitsPerValue, skip);
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
        // 6.6.5.2 draws the pattern at (x, y). _computeX and _computeY already
        // fold HGX and HGY in and apply the >>A 8, so adding them a second
        // time here would both double the origin and mix the fixed point value
        // into a pixel coordinate. A stream with HGX = HGY = 0 hides the
        // mistake, which is why only a shifted grid exposes it.
        Bitmaps.blit(patternBitmap, _halftoneRegionBitmap!, x, y,
            _hCombinationOperator);
      }
    }
  }

  List<Bitmap> _getPatterns() {
    final List<Bitmap> patterns = [];
    if (_segmentHeader != null) {
      for (SegmentHeader s in _segmentHeader!.rtSegments) {
        final PatternDictionary patternDictionary =
            s.getSegmentData() as PatternDictionary;
        patterns.addAll(patternDictionary.getDictionary());
      }
    }
    return patterns;
  }

  /// 6.6.5.1: HSKIP marks the halftone grid cells whose pattern would fall
  /// entirely outside the region. Those cells are not coded at all, so the
  /// generic decoding procedure must skip them rather than read a decision for
  /// them; getting this wrong desynchronises the arithmetic decoder for the
  /// whole rest of the grey-scale image.
  Bitmap _computeSkipBitmap() {
    final int patternWidth = _patterns!.first.width;
    final int patternHeight = _patterns!.first.height;
    final Bitmap skip = Bitmap(_hGridWidth, _hGridHeight);

    for (int mg = 0; mg < _hGridHeight; mg++) {
      for (int ng = 0; ng < _hGridWidth; ng++) {
        final int x = _computeX(mg, ng);
        final int y = _computeY(mg, ng);
        if (x + patternWidth <= 0 ||
            x >= _regionInfo.bitmapWidth ||
            y + patternHeight <= 0 ||
            y >= _regionInfo.bitmapHeight) {
          skip.setPixel(ng, mg, 1);
        }
      }
    }
    return skip;
  }

  List<List<int>> _grayScaleDecoding(
      final int bitsPerValue, final Bitmap? skip) {
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
    genericRegion.setParametersForPattern(
        _isMMREncoded,
        _dataOffset,
        _dataLength,
        _hGridHeight,
        _hGridWidth,
        _hTemplate,
        false,
        skip,
        // Nulos quando a região é MMR, exatamente como na implementação de
        // referência: a decodificação MMR não consulta pixels adaptativos.
        gbAtX,
        gbAtY);

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
        grayScalePlanes[j]!.setByte(byteIndex++,
            Bitmaps.combineBytes(oldValue, newValue, CombinationOperator.XOR));
      }
    }
  }

  List<List<int>> _computeGrayScaleValues(
      final List<Bitmap?> grayScalePlanes, final int bitsPerValue) {
    final List<List<int>> grayScaleValues =
        List.generate(_hGridHeight, (_) => List.filled(_hGridWidth, 0));

    for (int y = 0; y < _hGridHeight; y++) {
      for (int x = 0; x < _hGridWidth; x += 8) {
        final int minorWidth = _hGridWidth - x > 8 ? 8 : _hGridWidth - x;
        int byteIndex = grayScalePlanes[0]!.getByteIndex(x, y);

        for (int minorX = 0; minorX < minorWidth; minorX++) {
          final int i = minorX + x;
          grayScaleValues[y][i] = 0;

          for (int j = 0; j < bitsPerValue; j++) {
            grayScaleValues[y][i] +=
                ((grayScalePlanes[j]!.getByte(byteIndex) >> (7 - i & 7)) & 1) *
                    (1 << j);
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

  /// The `>>A 8` of 6.6.5.1 and 6.6.5.2: an arithmetic shift that keeps the
  /// sign, which is what Dart's `>>` already does on an `int`.
  int _shiftAndFill(int value) {
    return value >> 8;
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

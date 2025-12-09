import '../dictionary.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';
import '../bitmap.dart';
import '../image/bitmaps.dart';
import '../util/rectangle.dart';
import '../util/log.dart';
import 'generic_region.dart';

class PatternDictionary implements Dictionary {
  SubInputStream? _subInputStream;

  // Segment data structure (only necessary if MMR is used)
  int _dataHeaderOffset = 0;
  int _dataHeaderLength = 0;
  int _dataOffset = 0;
  int _dataLength = 0;

  List<int>? _gbAtX;
  List<int>? _gbAtY;

  // Pattern dictionary flags
  bool _isMMREncoded = false;
  int _hdTemplate = 0;

  // Width of the patterns in the pattern dictionary
  int _hdpWidth = 0;

  // Height of the patterns in the pattern dictionary
  int _hdpHeight = 0;

  // Decoded bitmaps
  List<Bitmap>? _patterns;

  // Largest gray-scale value
  int _grayMax = 0;

  PatternDictionary([this._subInputStream]);

  void _parseHeader() {
    _subInputStream!.readBits(5); // Dirty read

    _readTemplate();
    _readIsMMREncoded();
    _readPatternWidthAndHeight();
    _readGrayMax();
    _computeSegmentDataStructure();
    _checkInput();
  }

  void _readTemplate() {
    _hdTemplate = _subInputStream!.readBits(2);
  }

  void _readIsMMREncoded() {
    if (_subInputStream!.readBit() == 1) {
      _isMMREncoded = true;
    }
  }

  void _readPatternWidthAndHeight() {
    _hdpWidth = _subInputStream!.read();
    _hdpHeight = _subInputStream!.read();
  }

  void _readGrayMax() {
    _grayMax = _subInputStream!.readBits(32) & 0xffffffff;
  }

  void _computeSegmentDataStructure() {
    _dataOffset = _subInputStream!.getStreamPosition();
    _dataHeaderLength = _dataOffset - _dataHeaderOffset;
    _dataLength = _subInputStream!.length - _dataHeaderLength;
  }

  void _checkInput() {
    if (_hdpHeight < 1 || _hdpWidth < 1) {
      throw Exception("Width/Height must be greater than zero.");
    }

    if (_isMMREncoded) {
      if (_hdTemplate != 0) {
        Logger.info("hdTemplate should contain the value 0");
      }
    }
  }

  @override
  List<Bitmap> getDictionary() {
    if (_patterns == null) {
      if (!_isMMREncoded) {
        _setGbAtPixels();
      }

      final GenericRegion genericRegion = GenericRegion(_subInputStream!);
      genericRegion.setParametersForPattern(
          _isMMREncoded,
          _dataOffset,
          _dataLength,
          _hdpHeight,
          (_grayMax + 1) * _hdpWidth,
          _hdTemplate,
          false,
          false,
          _gbAtX!,
          _gbAtY!);

      final Bitmap collectiveBitmap = genericRegion.getRegionBitmap();
      _extractPatterns(collectiveBitmap);
    }
    return _patterns!;
  }

  void _extractPatterns(Bitmap collectiveBitmap) {
    int gray = 0;
    _patterns = []; // Size hint not available in Dart List constructor like Java ArrayList

    while (gray <= _grayMax) {
      final Rectangle roi = Rectangle(_hdpWidth * gray, 0, _hdpWidth, _hdpHeight);
      final Bitmap patternBitmap = Bitmaps.extract(roi, collectiveBitmap);
      _patterns!.add(patternBitmap);
      gray++;
    }
  }

  void _setGbAtPixels() {
    if (_hdTemplate == 0) {
      _gbAtX = List.filled(4, 0);
      _gbAtY = List.filled(4, 0);
      _gbAtX![0] = -_hdpWidth;
      _gbAtY![0] = 0;
      _gbAtX![1] = -3;
      _gbAtY![1] = -1;
      _gbAtX![2] = 2;
      _gbAtY![2] = -2;
      _gbAtX![3] = -2;
      _gbAtY![3] = -2;
    } else {
      _gbAtX = List.filled(1, 0);
      _gbAtY = List.filled(1, 0);
      _gbAtX![0] = -_hdpWidth;
      _gbAtY![0] = 0;
    }
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _subInputStream = sis;
    _parseHeader();
  }

  bool get isMMREncoded => _isMMREncoded;
  int get hdTemplate => _hdTemplate;
  int get hdpWidth => _hdpWidth;
  int get hdpHeight => _hdpHeight;
  int get grayMax => _grayMax;
}

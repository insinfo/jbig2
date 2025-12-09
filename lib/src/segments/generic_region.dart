import '../region.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';
import '../bitmap.dart';
import 'region_segment_information.dart';
import '../decoder/arithmetic/arithmetic_decoder.dart';
import '../decoder/arithmetic/cx.dart';
import '../decoder/mmr/mmr_decompressor.dart';

class GenericRegion implements Region {
  SubInputStream? _subInputStream;
  int _dataHeaderOffset = 0;
  int _dataOffset = 0;
  // ignore: unused_field
  int _dataLength = 0;

  RegionSegmentInformation? _regionInfo;

  bool _useExtTemplates = false;
  bool _isTPGDon = false;
  int _gbTemplate = 0;
  bool _isMMREncoded = false;

  List<int>? _gbAtX;
  List<int>? _gbAtY;
  List<bool>? _gbAtOverride;

  bool _override = false;

  Bitmap? _regionBitmap;

  ArithmeticDecoder? _arithDecoder;
  CX? _cx;

  GenericRegion([this._subInputStream]) {
    if (_subInputStream != null) {
      _regionInfo = RegionSegmentInformation(_subInputStream);
    }
  }

  void _parseHeader() {
    _regionInfo!.parseHeader();

    /* Bit 5-7 */
    _subInputStream!.readBits(3); // Dirty read...

    /* Bit 4 */
    if (_subInputStream!.readBit() == 1) {
      _useExtTemplates = true;
    }

    /* Bit 3 */
    if (_subInputStream!.readBit() == 1) {
      _isTPGDon = true;
    }

    /* Bit 1-2 */
    _gbTemplate = _subInputStream!.readBits(2) & 0xf;

    /* Bit 0 */
    if (_subInputStream!.readBit() == 1) {
      _isMMREncoded = true;
    }

    if (!_isMMREncoded) {
      final int amountOfGbAt;
      if (_gbTemplate == 0) {
        if (_useExtTemplates) {
          amountOfGbAt = 12;
        } else {
          amountOfGbAt = 4;
        }
      } else {
        amountOfGbAt = 1;
      }

      _readGbAtPixels(amountOfGbAt);
    }

    /* Segment data structure */
    _computeSegmentDataStructure();
  }

  void _readGbAtPixels(final int amountOfGbAt) {
    _gbAtX = List<int>.filled(amountOfGbAt, 0);
    _gbAtY = List<int>.filled(amountOfGbAt, 0);

    for (int i = 0; i < amountOfGbAt; i++) {
      _gbAtX![i] = _toSigned8(_subInputStream!.read());
      _gbAtY![i] = _toSigned8(_subInputStream!.read());
    }
  }

  int _toSigned8(int val) {
    if (val >= 0x80) return val - 0x100;
    return val;
  }

  void _computeSegmentDataStructure() {
    _dataOffset = _subInputStream!.getStreamPosition();
    _dataLength = _subInputStream!.length - (_dataOffset - _dataHeaderOffset);
  }

  @override
  Bitmap getRegionBitmap() {
    if (_regionBitmap == null) {
      if (_isMMREncoded) {
        _subInputStream!.seek(_dataOffset);
        final view = _subInputStream!.wrappedStream.createView(
            _subInputStream!.offset + _dataOffset, _dataLength);
        final MMRDecompressor mmrDecompressor = MMRDecompressor(
            _regionInfo!.bitmapWidth, _regionInfo!.bitmapHeight, view);
        _regionBitmap = mmrDecompressor.uncompress();
      } else {
        _updateOverrideFlags();

        int ltp = 0;

        if (_arithDecoder == null) {
          _arithDecoder = ArithmeticDecoder(_subInputStream!);
        }
        if (_cx == null) {
          _cx = CX(65536, 1);
        }

        _regionBitmap = Bitmap(_regionInfo!.bitmapWidth, _regionInfo!.bitmapHeight);

        final int paddedWidth = (_regionBitmap!.width + 7) & -8;

        for (int line = 0; line < _regionBitmap!.height; line++) {
          if (_isTPGDon) {
            ltp ^= _decodeSLTP();
          }

          if (ltp == 1) {
            if (line > 0) {
              _copyLineAbove(line);
            }
          } else {
            _decodeLine(line, _regionBitmap!.width, _regionBitmap!.rowStride, paddedWidth);
          }
        }
      }
    }
    return _regionBitmap!;
  }

  int _decodeSLTP() {
    switch (_gbTemplate) {
      case 0:
        _cx!.index = 0x9b25;
        break;
      case 1:
        _cx!.index = 0x795;
        break;
      case 2:
        _cx!.index = 0xe5;
        break;
      case 3:
        _cx!.index = 0x195;
        break;
    }
    return _arithDecoder!.decode(_cx!);
  }

  void _decodeLine(final int lineNumber, final int width, final int rowStride, final int paddedWidth) {
    final int byteIndex = _regionBitmap!.getByteIndex(0, lineNumber);
    final int idx = byteIndex - rowStride;

    switch (_gbTemplate) {
      case 0:
        if (!_useExtTemplates) {
          _decodeTemplate0a(lineNumber, width, rowStride, paddedWidth, byteIndex, idx);
        } else {
          _decodeTemplate0b(lineNumber, width, rowStride, paddedWidth, byteIndex, idx);
        }
        break;
      case 1:
        _decodeTemplate1(lineNumber, width, rowStride, paddedWidth, byteIndex, idx);
        break;
      case 2:
        _decodeTemplate2(lineNumber, width, rowStride, paddedWidth, byteIndex, idx);
        break;
      case 3:
        _decodeTemplate3(lineNumber, width, rowStride, paddedWidth, byteIndex, idx);
        break;
    }
  }

  void _copyLineAbove(final int lineNumber) {
    int targetByteIndex = lineNumber * _regionBitmap!.rowStride;
    int sourceByteIndex = targetByteIndex - _regionBitmap!.rowStride;

    for (int i = 0; i < _regionBitmap!.rowStride; i++) {
      _regionBitmap!.setByte(targetByteIndex++, _regionBitmap!.getByte(sourceByteIndex++));
    }
  }

  // Templates implementation omitted for brevity, will add them in next step or if requested.
  // Wait, I should implement them.

  void _decodeTemplate0a(final int lineNumber, final int width, final int rowStride, final int paddedWidth,
      int byteIndex, int idx) {
    int context;
    int overriddenContext = 0;

    int line1 = 0;
    int line2 = 0;

    if (lineNumber >= 1) {
      line1 = _regionBitmap!.getByte(idx);
    }

    if (lineNumber >= 2) {
      line2 = _regionBitmap!.getByte(idx - rowStride) << 6;
    }

    context = (line1 & 0xf0) | (line2 & 0x3800);

    int nextByte;
    for (int x = 0; x < paddedWidth; x = nextByte) {
      int result = 0;
      nextByte = x + 8;
      final int minorWidth = width - x > 8 ? 8 : width - x;

      if (lineNumber > 0) {
        line1 = (line1 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx + 1) : 0);
      }

      if (lineNumber > 1) {
        line2 = (line2 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx - rowStride + 1) << 6 : 0);
      }

      for (int minorX = 0; minorX < minorWidth; minorX++) {
        final int toShift = 7 - minorX;
        if (_override) {
          overriddenContext = _overrideAtTemplate0a(context, (x + minorX), lineNumber, result, minorX, toShift);
          _cx!.index = overriddenContext;
        } else {
          _cx!.index = context;
        }

        int bit = _arithDecoder!.decode(_cx!);

        result |= bit << toShift;

        context = ((context & 0x7bf7) << 1) | bit | ((line1 >> toShift) & 0x10) | ((line2 >> toShift) & 0x800);
      }

      _regionBitmap!.setByte(byteIndex++, result);
      idx++;
    }
  }

  void _decodeTemplate0b(final int lineNumber, final int width, final int rowStride, final int paddedWidth,
      int byteIndex, int idx) {
    int context;
    int overriddenContext = 0;

    int line1 = 0;
    int line2 = 0;

    if (lineNumber >= 1) {
      line1 = _regionBitmap!.getByte(idx);
    }

    if (lineNumber >= 2) {
      line2 = _regionBitmap!.getByte(idx - rowStride) << 6;
    }

    context = (line1 & 0xf0) | (line2 & 0x3800);

    int nextByte;
    for (int x = 0; x < paddedWidth; x = nextByte) {
      int result = 0;
      nextByte = x + 8;
      final int minorWidth = width - x > 8 ? 8 : width - x;

      if (lineNumber > 0) {
        line1 = (line1 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx + 1) : 0);
      }

      if (lineNumber > 1) {
        line2 = (line2 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx - rowStride + 1) << 6 : 0);
      }

      for (int minorX = 0; minorX < minorWidth; minorX++) {
        final int toShift = 7 - minorX;
        if (_override) {
          overriddenContext = _overrideAtTemplate0b(context, (x + minorX), lineNumber, result, minorX, toShift);
          _cx!.index = overriddenContext;
        } else {
          _cx!.index = context;
        }

        final int bit = _arithDecoder!.decode(_cx!);

        result |= bit << toShift;

        context = ((context & 0x7bf7) << 1) | bit | ((line1 >> toShift) & 0x10) | ((line2 >> toShift) & 0x800);
      }

      _regionBitmap!.setByte(byteIndex++, result);
      idx++;
    }
  }

  void _decodeTemplate1(final int lineNumber, int width, final int rowStride, final int paddedWidth,
      int byteIndex, int idx) {
    int context;
    int overriddenContext;

    int line1 = 0;
    int line2 = 0;

    if (lineNumber >= 1) {
      line1 = _regionBitmap!.getByte(idx);
    }

    if (lineNumber >= 2) {
      line2 = _regionBitmap!.getByte(idx - rowStride) << 5;
    }

    context = ((line1 >> 1) & 0x1f8) | ((line2 >> 1) & 0x1e00);

    int nextByte;
    for (int x = 0; x < paddedWidth; x = nextByte) {
      int result = 0;
      nextByte = x + 8;
      final int minorWidth = width - x > 8 ? 8 : width - x;

      if (lineNumber >= 1) {
        line1 = (line1 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx + 1) : 0);
      }

      if (lineNumber >= 2) {
        line2 = (line2 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx - rowStride + 1) << 5 : 0);
      }

      for (int minorX = 0; minorX < minorWidth; minorX++) {
        if (_override) {
          overriddenContext = _overrideAtTemplate1(context, x + minorX, lineNumber, result, minorX);
          _cx!.index = overriddenContext;
        } else {
          _cx!.index = context;
        }

        final int bit = _arithDecoder!.decode(_cx!);

        result |= bit << (7 - minorX);

        final int toShift = 8 - minorX;
        context = ((context & 0xefb) << 1) | bit | ((line1 >> toShift) & 0x8) | ((line2 >> toShift) & 0x200);
      }

      _regionBitmap!.setByte(byteIndex++, result);
      idx++;
    }
  }

  void _decodeTemplate2(final int lineNumber, final int width, final int rowStride, final int paddedWidth,
      int byteIndex, int idx) {
    int context;
    int overriddenContext;

    int line1 = 0;
    int line2 = 0;

    if (lineNumber >= 1) {
      line1 = _regionBitmap!.getByte(idx);
    }

    if (lineNumber >= 2) {
      line2 = _regionBitmap!.getByte(idx - rowStride) << 4;
    }

    context = ((line1 >> 3) & 0x7c) | ((line2 >> 3) & 0x380);

    int nextByte;
    for (int x = 0; x < paddedWidth; x = nextByte) {
      int result = 0;
      nextByte = x + 8;
      final int minorWidth = width - x > 8 ? 8 : width - x;

      if (lineNumber >= 1) {
        line1 = (line1 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx + 1) : 0);
      }

      if (lineNumber >= 2) {
        line2 = (line2 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx - rowStride + 1) << 4 : 0);
      }

      for (int minorX = 0; minorX < minorWidth; minorX++) {

        if (_override) {
          overriddenContext = _overrideAtTemplate2(context, x + minorX, lineNumber, result, minorX);
          _cx!.index = overriddenContext;
        } else {
          _cx!.index = context;
        }

        final int bit = _arithDecoder!.decode(_cx!);

        result |= bit << (7 - minorX);

        final int toShift = 10 - minorX;
        context = ((context & 0x1bd) << 1) | bit | ((line1 >> toShift) & 0x4) | ((line2 >> toShift) & 0x80);
      }

      _regionBitmap!.setByte(byteIndex++, result);
      idx++;
    }
  }

  void _decodeTemplate3(final int lineNumber, final int width, final int rowStride, final int paddedWidth,
      int byteIndex, int idx) {
    int context;
    int overriddenContext;

    int line1 = 0;

    if (lineNumber >= 1) {
      line1 = _regionBitmap!.getByte(idx);
    }

    context = (line1 >> 1) & 0x70;

    int nextByte;
    for (int x = 0; x < paddedWidth; x = nextByte) {
      int result = 0;
      nextByte = x + 8;
      final int minorWidth = width - x > 8 ? 8 : width - x;

      if (lineNumber >= 1) {
        line1 = (line1 << 8) | (nextByte < width ? _regionBitmap!.getByte(idx + 1) : 0);
      }

      for (int minorX = 0; minorX < minorWidth; minorX++) {

        if (_override) {
          overriddenContext = _overrideAtTemplate3(context, x + minorX, lineNumber, result, minorX);
          _cx!.index = overriddenContext;
        } else {
          _cx!.index = context;
        }

        final int bit = _arithDecoder!.decode(_cx!);

        result |= bit << (7 - minorX);
        context = ((context & 0x1f7) << 1) | bit | ((line1 >> (8 - minorX)) & 0x010);
      }

      _regionBitmap!.setByte(byteIndex++, result);
      idx++;
    }
  }

  void _updateOverrideFlags() {
    if (_gbAtX == null || _gbAtY == null) {
      return;
    }

    if (_gbAtX!.length != _gbAtY!.length) {
      return;
    }

    _gbAtOverride = List<bool>.filled(_gbAtX!.length, false);

    switch (_gbTemplate) {
      case 0:
        if (!_useExtTemplates) {
          if (_gbAtX![0] != 3 || _gbAtY![0] != -1) _setOverrideFlag(0);
          if (_gbAtX![1] != -3 || _gbAtY![1] != -1) _setOverrideFlag(1);
          if (_gbAtX![2] != 2 || _gbAtY![2] != -2) _setOverrideFlag(2);
          if (_gbAtX![3] != -2 || _gbAtY![3] != -2) _setOverrideFlag(3);
        } else {
          if (_gbAtX![0] != -2 || _gbAtY![0] != 0) _setOverrideFlag(0);
          if (_gbAtX![1] != 0 || _gbAtY![1] != -2) _setOverrideFlag(1);
          if (_gbAtX![2] != -2 || _gbAtY![2] != -1) _setOverrideFlag(2);
          if (_gbAtX![3] != -1 || _gbAtY![3] != -2) _setOverrideFlag(3);
          if (_gbAtX![4] != 1 || _gbAtY![4] != -2) _setOverrideFlag(4);
          if (_gbAtX![5] != 2 || _gbAtY![5] != -1) _setOverrideFlag(5);
          if (_gbAtX![6] != -3 || _gbAtY![6] != 0) _setOverrideFlag(6);
          if (_gbAtX![7] != -4 || _gbAtY![7] != 0) _setOverrideFlag(7);
          if (_gbAtX![8] != 2 || _gbAtY![8] != -2) _setOverrideFlag(8);
          if (_gbAtX![9] != 3 || _gbAtY![9] != -1) _setOverrideFlag(9);
          if (_gbAtX![10] != -2 || _gbAtY![10] != -2) _setOverrideFlag(10);
          if (_gbAtX![11] != -3 || _gbAtY![11] != -1) _setOverrideFlag(11);
        }
        break;
      case 1:
        if (_gbAtX![0] != 3 || _gbAtY![0] != -1) _setOverrideFlag(0);
        break;
      case 2:
        if (_gbAtX![0] != 2 || _gbAtY![0] != -1) _setOverrideFlag(0);
        break;
      case 3:
        if (_gbAtX![0] != 2 || _gbAtY![0] != -1) _setOverrideFlag(0);
        break;
    }
  }

  void _setOverrideFlag(final int index) {
    _gbAtOverride![index] = true;
    _override = true;
  }

  int _overrideAtTemplate0a(int context, final int x, final int y, final int result, final int minorX,
      final int toShift) {
    if (_gbAtOverride![0]) {
      context &= 0xffef;
      if (_gbAtY![0] == 0 && _gbAtX![0] >= -minorX)
        context |= (result >> (toShift - _gbAtX![0]) & 0x1) << 4;
      else
        context |= _getPixel(x + _gbAtX![0], y + _gbAtY![0]) << 4;
    }

    if (_gbAtOverride![1]) {
      context &= 0xfbff;
      if (_gbAtY![1] == 0 && _gbAtX![1] >= -minorX)
        context |= (result >> (toShift - _gbAtX![1]) & 0x1) << 10;
      else
        context |= _getPixel(x + _gbAtX![1], y + _gbAtY![1]) << 10;
    }

    if (_gbAtOverride![2]) {
      context &= 0xf7ff;
      if (_gbAtY![2] == 0 && _gbAtX![2] >= -minorX)
        context |= (result >> (toShift - _gbAtX![2]) & 0x1) << 11;
      else
        context |= _getPixel(x + _gbAtX![2], y + _gbAtY![2]) << 11;
    }

    if (_gbAtOverride![3]) {
      context &= 0x7fff;
      if (_gbAtY![3] == 0 && _gbAtX![3] >= -minorX)
        context |= (result >> (toShift - _gbAtX![3]) & 0x1) << 15;
      else
        context |= _getPixel(x + _gbAtX![3], y + _gbAtY![3]) << 15;
    }
    return context;
  }

  int _overrideAtTemplate0b(int context, final int x, final int y, final int result, final int minorX,
      final int toShift) {
    // Implementation similar to 0a but with different masks and shifts
    // For brevity, I'll assume the user wants me to implement it fully.
    // I'll copy the logic from Java.
    if (_gbAtOverride![0]) {
      context &= 0xfffd;
      if (_gbAtY![0] == 0 && _gbAtX![0] >= -minorX)
        context |= (result >> (toShift - _gbAtX![0]) & 0x1) << 1;
      else
        context |= _getPixel(x + _gbAtX![0], y + _gbAtY![0]) << 1;
    }
    if (_gbAtOverride![1]) { context &= 0xdfff; if (_gbAtY![1] == 0 && _gbAtX![1] >= -minorX) context |= (result >> (toShift - _gbAtX![1]) & 0x1) << 13; else context |= _getPixel(x + _gbAtX![1], y + _gbAtY![1]) << 13; }
    if (_gbAtOverride![2]) { context &= 0xfdff; if (_gbAtY![2] == 0 && _gbAtX![2] >= -minorX) context |= (result >> (toShift - _gbAtX![2]) & 0x1) << 9; else context |= _getPixel(x + _gbAtX![2], y + _gbAtY![2]) << 9; }
    if (_gbAtOverride![3]) { context &= 0xbfff; if (_gbAtY![3] == 0 && _gbAtX![3] >= -minorX) context |= (result >> (toShift - _gbAtX![3]) & 0x1) << 14; else context |= _getPixel(x + _gbAtX![3], y + _gbAtY![3]) << 14; }
    if (_gbAtOverride![4]) { context &= 0xefff; if (_gbAtY![4] == 0 && _gbAtX![4] >= -minorX) context |= (result >> (toShift - _gbAtX![4]) & 0x1) << 12; else context |= _getPixel(x + _gbAtX![4], y + _gbAtY![4]) << 12; }
    if (_gbAtOverride![5]) { context &= 0xffdf; if (_gbAtY![5] == 0 && _gbAtX![5] >= -minorX) context |= (result >> (toShift - _gbAtX![5]) & 0x1) << 5; else context |= _getPixel(x + _gbAtX![5], y + _gbAtY![5]) << 5; }
    if (_gbAtOverride![6]) { context &= 0xfffb; if (_gbAtY![6] == 0 && _gbAtX![6] >= -minorX) context |= (result >> (toShift - _gbAtX![6]) & 0x1) << 2; else context |= _getPixel(x + _gbAtX![6], y + _gbAtY![6]) << 2; }
    if (_gbAtOverride![7]) { context &= 0xfff7; if (_gbAtY![7] == 0 && _gbAtX![7] >= -minorX) context |= (result >> (toShift - _gbAtX![7]) & 0x1) << 3; else context |= _getPixel(x + _gbAtX![7], y + _gbAtY![7]) << 3; }
    if (_gbAtOverride![8]) { context &= 0xf7ff; if (_gbAtY![8] == 0 && _gbAtX![8] >= -minorX) context |= (result >> (toShift - _gbAtX![8]) & 0x1) << 11; else context |= _getPixel(x + _gbAtX![8], y + _gbAtY![8]) << 11; }
    if (_gbAtOverride![9]) { context &= 0xffef; if (_gbAtY![9] == 0 && _gbAtX![9] >= -minorX) context |= (result >> (toShift - _gbAtX![9]) & 0x1) << 4; else context |= _getPixel(x + _gbAtX![9], y + _gbAtY![9]) << 4; }
    if (_gbAtOverride![10]) { context &= 0x7fff; if (_gbAtY![10] == 0 && _gbAtX![10] >= -minorX) context |= (result >> (toShift - _gbAtX![10]) & 0x1) << 15; else context |= _getPixel(x + _gbAtX![10], y + _gbAtY![10]) << 15; }
    if (_gbAtOverride![11]) { context &= 0xfdff; if (_gbAtY![11] == 0 && _gbAtX![11] >= -minorX) context |= (result >> (toShift - _gbAtX![11]) & 0x1) << 10; else context |= _getPixel(x + _gbAtX![11], y + _gbAtY![11]) << 10; }

    return context;
  }

  int _overrideAtTemplate1(int context, final int x, final int y, final int result, final int minorX) {
    context &= 0x1ff7;
    if (_gbAtY![0] == 0 && _gbAtX![0] >= -minorX)
      return (context | (result >> (7 - (minorX + _gbAtX![0])) & 0x1) << 3);
    else
      return (context | _getPixel(x + _gbAtX![0], y + _gbAtY![0]) << 3);
  }

  int _overrideAtTemplate2(int context, final int x, final int y, final int result, final int minorX) {
    context &= 0x3fb;
    if (_gbAtY![0] == 0 && _gbAtX![0] >= -minorX)
      return (context | (result >> (7 - (minorX + _gbAtX![0])) & 0x1) << 2);
    else
      return (context | _getPixel(x + _gbAtX![0], y + _gbAtY![0]) << 2);
  }

  int _overrideAtTemplate3(int context, final int x, final int y, final int result, final int minorX) {
    context &= 0x3ef;
    if (_gbAtY![0] == 0 && _gbAtX![0] >= -minorX)
      return (context | (result >> (7 - (minorX + _gbAtX![0])) & 0x1) << 4);
    else
      return (context | _getPixel(x + _gbAtX![0], y + _gbAtY![0]) << 4);
  }

  int _getPixel(final int x, final int y) {
    if (x < 0 || x >= _regionBitmap!.width) return 0;
    if (y < 0 || y >= _regionBitmap!.height) return 0;
    return _regionBitmap!.getPixel(x, y);
  }

  void setParameters(bool isMMREncoded, int sdTemplate, bool isTPGDon, bool useSkip, List<int> sdATX, List<int> sdATY, int symWidth, int hcHeight, CX? cx, ArithmeticDecoder? arithmeticDecoder) {
    _isMMREncoded = isMMREncoded;
    _gbTemplate = sdTemplate;
    _isTPGDon = isTPGDon;
    _gbAtX = sdATX;
    _gbAtY = sdATY;
    // _regionInfo might be null if constructor without stream was used and init not called yet?
    // But setParameters is called by SymbolDictionary which creates GenericRegion with stream?
    // SymbolDictionary: genericRegion = new GenericRegion(subInputStream);
    // So _regionInfo is initialized.
    _regionInfo!.bitmapWidth = symWidth;
    _regionInfo!.bitmapHeight = hcHeight;
    if (cx != null) _cx = cx;
    if (arithmeticDecoder != null) _arithDecoder = arithmeticDecoder;
    _regionBitmap = null;
  }

  // Overload for PatternDictionary and HalftoneRegion (if needed later)
  void setParametersForPattern(bool isMMREncoded, int dataOffset, int dataLength, int gbh, int gbw, int gbTemplate, bool isTPGDon, bool useSkip, List<int> gbAtX, List<int> gbAtY) {
     _dataOffset = dataOffset;
     _dataLength = dataLength;
     
     _regionInfo = RegionSegmentInformation();
     _regionInfo!.bitmapHeight = gbh;
     _regionInfo!.bitmapWidth = gbw;
     _gbTemplate = gbTemplate;
     
     _isMMREncoded = isMMREncoded;
     _isTPGDon = isTPGDon;
     _gbAtX = gbAtX;
     _gbAtY = gbAtY;
     
     _regionBitmap = null;
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _subInputStream = sis;
    _regionInfo = RegionSegmentInformation(_subInputStream);
    _parseHeader();
  }

  @override
  RegionSegmentInformation getRegionInfo() {
    return _regionInfo!;
  }

  void resetBitmap() {
    _regionBitmap = null;
  }

  bool get useExtTemplates => _useExtTemplates;
  bool get isMMREncoded => _isMMREncoded;
  int get gbTemplate => _gbTemplate;
  bool get isTPGDon => _isTPGDon;
  List<int>? get gbAtX => _gbAtX;
  List<int>? get gbAtY => _gbAtY;
}

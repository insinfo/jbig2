import 'dart:math';

import '../dictionary.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';
import '../bitmap.dart';
import '../image/bitmaps.dart';
import '../util/rectangle.dart';
import '../decoder/arithmetic/arithmetic_decoder.dart';
import '../decoder/arithmetic/arithmetic_integer_decoder.dart';
import '../decoder/arithmetic/cx.dart';
import '../decoder/huffman/encoded_table.dart';
import '../decoder/huffman/huffman_table.dart';
import '../decoder/huffman/standard_tables.dart';
import 'text_region.dart';
import 'generic_region.dart';
import 'generic_refinement_region.dart';
import 'table.dart';
import '../region.dart';
import '../util/log.dart';

class SymbolDictionary implements Dictionary {
  SubInputStream? _subInputStream;
  SegmentHeader? _segmentHeader;

  // Symbol dictionary flags
  int _sdrTemplate = 0;
  int _sdTemplate = 0;
  bool _isCodingContextRetained = false;
  bool _isCodingContextUsed = false;
  int _sdHuffAggInstanceSelection = 0;
  int _sdHuffBMSizeSelection = 0;
  int _sdHuffDecodeWidthSelection = 0;
  int _sdHuffDecodeHeightSelection = 0;
  bool _useRefinementAggregation = false;
  bool _isHuffmanEncoded = false;

  // Symbol dictionary AT flags
  List<int>? _sdATX;
  List<int>? _sdATY;

  // Symbol dictionary refinement AT flags
  List<int>? _sdrATX;
  List<int>? _sdrATY;

  int _amountOfExportSymbols = 0;
  int _amountOfNewSymbols = 0;

  int _amountOfImportedSymbols = 0;
  List<Bitmap> _importSymbols = [];
  int _amountOfDecodedSymbols = 0;
  List<Bitmap?> _newSymbols = [];

  HuffmanTable? _dhTable;
  HuffmanTable? _dwTable;
  HuffmanTable? _bmSizeTable;
  HuffmanTable? _aggInstTable;

  List<Bitmap>? _exportSymbols;
  List<Bitmap> _sbSymbols = [];

  ArithmeticDecoder? _arithmeticDecoder;
  ArithmeticIntegerDecoder? _integerDecoder;

  TextRegion? _textRegion;
  GenericRegion? _genericRegion;
  GenericRefinementRegion? _genericRefinementRegion;
  CX? _cx;

  CX? _cxIADH;
  CX? _cxIADW;
  CX? _cxIAAI;
  CX? _cxIAEX;
  CX? _cxIARDX;
  CX? _cxIARDY;
  CX? _cxIADT;

  CX? cxIAID;
  int _sbSymCodeLen = 0;

  SymbolDictionary([this._subInputStream, this._segmentHeader]);

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _subInputStream = sis;
    _segmentHeader = header;
    _parseHeader();
  }

  void _parseHeader() {
    _readRegionFlags();
    _setAtPixels();
    _setRefinementAtPixels();
    _readAmountOfExportedSymbols();
    _readAmountOfNewSymbols();
    _setInSyms();

    if (_isCodingContextUsed) {
      final List<SegmentHeader> rtSegments = _segmentHeader!.rtSegments;
      for (int i = rtSegments.length - 1; i >= 0; i--) {
        if (rtSegments[i].segmentType == 0) {
          final SymbolDictionary symbolDictionary = rtSegments[i].getSegmentData() as SymbolDictionary;
          if (symbolDictionary._isCodingContextRetained) {
            _setRetainedCodingContexts(symbolDictionary);
          }
          break;
        }
      }
    }
    _checkInput();
  }

  void _readRegionFlags() {
    _subInputStream!.readBits(3); // Dirty read
    _sdrTemplate = _subInputStream!.readBit();
    _sdTemplate = _subInputStream!.readBits(2) & 0xf;
    if (_subInputStream!.readBit() == 1) _isCodingContextRetained = true;
    if (_subInputStream!.readBit() == 1) _isCodingContextUsed = true;
    _sdHuffAggInstanceSelection = _subInputStream!.readBit();
    _sdHuffBMSizeSelection = _subInputStream!.readBit();
    _sdHuffDecodeWidthSelection = _subInputStream!.readBits(2) & 0xf;
    _sdHuffDecodeHeightSelection = _subInputStream!.readBits(2) & 0xf;
    if (_subInputStream!.readBit() == 1) _useRefinementAggregation = true;
    if (_subInputStream!.readBit() == 1) _isHuffmanEncoded = true;
  }

  void _setAtPixels() {
    if (!_isHuffmanEncoded) {
      if (_sdTemplate == 0) {
        _readAtPixels(4);
      } else {
        _readAtPixels(1);
      }
    }
  }

  void _setRefinementAtPixels() {
    if (_useRefinementAggregation && _sdrTemplate == 0) {
      _readRefinementAtPixels(2);
    }
  }

  void _readAtPixels(final int amountOfPixels) {
    _sdATX = List.filled(amountOfPixels, 0);
    _sdATY = List.filled(amountOfPixels, 0);
    for (int i = 0; i < amountOfPixels; i++) {
      _sdATX![i] = _subInputStream!.read();
      _sdATY![i] = _subInputStream!.read();
    }
  }

  void _readRefinementAtPixels(final int amountOfAtPixels) {
    _sdrATX = List.filled(amountOfAtPixels, 0);
    _sdrATY = List.filled(amountOfAtPixels, 0);
    for (int i = 0; i < amountOfAtPixels; i++) {
      _sdrATX![i] = _subInputStream!.read();
      _sdrATY![i] = _subInputStream!.read();
    }
  }

  void _readAmountOfExportedSymbols() {
    _amountOfExportSymbols = _subInputStream!.readBits(32);
  }

  void _readAmountOfNewSymbols() {
    _amountOfNewSymbols = _subInputStream!.readBits(32);
  }

  void _setInSyms() {
    if (_segmentHeader!.rtSegments.isNotEmpty) {
      _retrieveImportSymbols();
    } else {
      _importSymbols = [];
    }
  }

  void _setRetainedCodingContexts(final SymbolDictionary sd) {
    _arithmeticDecoder = sd._arithmeticDecoder;
    _isHuffmanEncoded = sd._isHuffmanEncoded;
    _useRefinementAggregation = sd._useRefinementAggregation;
    _sdTemplate = sd._sdTemplate;
    _sdrTemplate = sd._sdrTemplate;
    _sdATX = sd._sdATX;
    _sdATY = sd._sdATY;
    _sdrATX = sd._sdrATX;
    _sdrATY = sd._sdrATY;
    _cx = sd._cx;
  }

  void _checkInput() {
    if (_sdHuffDecodeHeightSelection == 2) Logger.info("sdHuffDecodeHeightSelection = $_sdHuffDecodeHeightSelection (value not permitted)");
    if (_sdHuffDecodeWidthSelection == 2) Logger.info("sdHuffDecodeWidthSelection = $_sdHuffDecodeWidthSelection (value not permitted)");
    if (_isHuffmanEncoded) {
      if (_sdTemplate != 0) { Logger.info("sdTemplate = $_sdTemplate (should be 0)"); _sdTemplate = 0; }
      if (!_useRefinementAggregation) {
        if (_isCodingContextRetained) { Logger.info("isCodingContextRetained = $_isCodingContextRetained (should be 0)"); _isCodingContextRetained = false; }
        if (_isCodingContextUsed) { Logger.info("isCodingContextUsed = $_isCodingContextUsed (should be 0)"); _isCodingContextUsed = false; }
      }
    } else {
      if (_sdHuffBMSizeSelection != 0) { Logger.info("sdHuffBMSizeSelection should be 0"); _sdHuffBMSizeSelection = 0; }
      if (_sdHuffDecodeWidthSelection != 0) { Logger.info("sdHuffDecodeWidthSelection should be 0"); _sdHuffDecodeWidthSelection = 0; }
      if (_sdHuffDecodeHeightSelection != 0) { Logger.info("sdHuffDecodeHeightSelection should be 0"); _sdHuffDecodeHeightSelection = 0; }
    }
    if (!_useRefinementAggregation) {
      if (_sdrTemplate != 0) { Logger.info("sdrTemplate = $_sdrTemplate (should be 0)"); _sdrTemplate = 0; }
    }
    if (!_isHuffmanEncoded || !_useRefinementAggregation) {
      if (_sdHuffAggInstanceSelection != 0) { Logger.info("sdHuffAggInstanceSelection = $_sdHuffAggInstanceSelection (should be 0)"); _sdHuffAggInstanceSelection = 0; }
    }
  }

  @override
  List<Bitmap> getDictionary() {
    if (_exportSymbols == null) {
      if (_useRefinementAggregation) _sbSymCodeLen = _getSbSymCodeLen();
      if (!_isHuffmanEncoded) _setCodingStatistics();

      _newSymbols = List.filled(_amountOfNewSymbols, null);
      List<int>? newSymbolsWidths;
      if (_isHuffmanEncoded && !_useRefinementAggregation) {
        newSymbolsWidths = List.filled(_amountOfNewSymbols, 0);
      }

      _setSymbolsArray();

      int heightClassHeight = 0;
      _amountOfDecodedSymbols = 0;

      while (_amountOfDecodedSymbols < _amountOfNewSymbols) {
        heightClassHeight += _decodeHeightClassDeltaHeight();
        int symbolWidth = 0;
        int totalWidth = 0;
        final int heightClassFirstSymbolIndex = _amountOfDecodedSymbols;

        while (true) {
          final int differenceWidth = _decodeDifferenceWidth();
          if (differenceWidth == 0x7fffffffffffffff) break; // OOB check

          symbolWidth += differenceWidth;
          totalWidth += symbolWidth;

          if (!_isHuffmanEncoded || _useRefinementAggregation) {
            if (!_useRefinementAggregation) {
              _decodeDirectlyThroughGenericRegion(symbolWidth, heightClassHeight);
            } else {
              _decodeAggregate(symbolWidth, heightClassHeight);
            }
          } else if (_isHuffmanEncoded && !_useRefinementAggregation) {
            if (_amountOfDecodedSymbols < _amountOfNewSymbols) {
              newSymbolsWidths![_amountOfDecodedSymbols] = symbolWidth;
            }
          }
          _amountOfDecodedSymbols++;
        }

        if (_isHuffmanEncoded && !_useRefinementAggregation) {
          final int bmSize;
          if (_sdHuffBMSizeSelection == 0) {
            bmSize = StandardTables.getTable(1).decode(_subInputStream!);
          } else {
            bmSize = _huffDecodeBmSize();
          }
          _subInputStream!.skipBits();
          final Bitmap heightClassCollectiveBitmap = _decodeHeightClassCollectiveBitmap(bmSize, heightClassHeight, totalWidth);
          if (bmSize != 0) {
            _subInputStream!.seek(_subInputStream!.getStreamPosition() + bmSize);
          }
          _subInputStream!.skipBits();
          _decodeHeightClassBitmap(heightClassCollectiveBitmap, heightClassFirstSymbolIndex, heightClassHeight, newSymbolsWidths!);
        }
      }
      final List<int> exFlags = _getToExportFlags();
      _setExportedSymbols(exFlags);
    }
    return _exportSymbols!;
  }

  void _setCodingStatistics() {
    if (_cxIADT == null) _cxIADT = CX(512, 1);
    if (_cxIADH == null) _cxIADH = CX(512, 1);
    if (_cxIADW == null) _cxIADW = CX(512, 1);
    if (_cxIAAI == null) _cxIAAI = CX(512, 1);
    if (_cxIAEX == null) _cxIAEX = CX(512, 1);
    if (_useRefinementAggregation && cxIAID == null) {
      cxIAID = CX(1 << _sbSymCodeLen, 1);
      _cxIARDX = CX(512, 1);
      _cxIARDY = CX(512, 1);
    }
    if (_cx == null) _cx = CX(65536, 1);
    if (_arithmeticDecoder == null) _arithmeticDecoder = ArithmeticDecoder(_subInputStream!);
    if (_integerDecoder == null) _integerDecoder = ArithmeticIntegerDecoder(_arithmeticDecoder!);
  }

  void _decodeHeightClassBitmap(final Bitmap heightClassCollectiveBitmap, final int heightClassFirstSymbol, final int heightClassHeight, final List<int> newSymbolsWidths) {
    for (int i = heightClassFirstSymbol; i < _amountOfDecodedSymbols && i < _amountOfNewSymbols; i++) {
      int startColumn = 0;
      for (int j = heightClassFirstSymbol; j <= i - 1; j++) {
        startColumn += newSymbolsWidths[j];
      }
      final Rectangle roi = Rectangle(startColumn, 0, newSymbolsWidths[i], heightClassHeight);
      final Bitmap symbolBitmap = Bitmaps.extract(roi, heightClassCollectiveBitmap);
      _newSymbols[i] = symbolBitmap;
      _sbSymbols.add(symbolBitmap);
    }
  }

  void _decodeAggregate(final int symbolWidth, final int heightClassHeight) {
    final int amountOfRefinementAggregationInstances;
    if (_isHuffmanEncoded) {
      amountOfRefinementAggregationInstances = _huffDecodeRefAggNInst();
    } else {
      amountOfRefinementAggregationInstances = _integerDecoder!.decode(_cxIAAI!);
    }

    if (amountOfRefinementAggregationInstances > 1) {
      _decodeThroughTextRegion(symbolWidth, heightClassHeight, amountOfRefinementAggregationInstances);
    } else if (amountOfRefinementAggregationInstances == 1) {
      _decodeRefinedSymbol(symbolWidth, heightClassHeight);
    }
  }

  int _huffDecodeRefAggNInst() {
    if (_sdHuffAggInstanceSelection == 0) {
      return StandardTables.getTable(1).decode(_subInputStream!);
    } else if (_sdHuffAggInstanceSelection == 1) {
      if (_aggInstTable == null) {
        int aggregationInstanceNumber = 0;
        if (_sdHuffDecodeHeightSelection == 3) aggregationInstanceNumber++;
        if (_sdHuffDecodeWidthSelection == 3) aggregationInstanceNumber++;
        if (_sdHuffBMSizeSelection == 3) aggregationInstanceNumber++;
        _aggInstTable = _getUserTable(aggregationInstanceNumber);
      }
      return _aggInstTable!.decode(_subInputStream!);
    }
    return 0;
  }

  void _decodeThroughTextRegion(final int symbolWidth, final int heightClassHeight, final int amountOfRefinementAggregationInstances) {
    if (_textRegion == null) {
      _textRegion = TextRegion(_subInputStream, null);
      _textRegion!.setContexts(_cx!, CX(512, 1), CX(512, 1), CX(512, 1), CX(512, 1), cxIAID!, CX(512, 1), CX(512, 1), CX(512, 1), CX(512, 1));
    }
    _setSymbolsArray();
    _textRegion!.setParameters(_arithmeticDecoder!, _integerDecoder!, _isHuffmanEncoded, true, symbolWidth, heightClassHeight,
        amountOfRefinementAggregationInstances, 1, (_amountOfImportedSymbols + _amountOfDecodedSymbols), 0,
        0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, _sdrTemplate, _sdrATX!, _sdrATY!, _sbSymbols, _sbSymCodeLen);
    _addSymbol(_textRegion!);
  }

  void _decodeRefinedSymbol(final int symbolWidth, final int heightClassHeight) {
    final int id;
    final int rdx;
    final int rdy;
    if (_isHuffmanEncoded) {
      id = _subInputStream!.readBits(_sbSymCodeLen);
      rdx = StandardTables.getTable(15).decode(_subInputStream!);
      rdy = StandardTables.getTable(15).decode(_subInputStream!);
      StandardTables.getTable(1).decode(_subInputStream!);
      _subInputStream!.skipBits();
    } else {
      id = _integerDecoder!.decodeIAID(cxIAID!, _sbSymCodeLen);
      rdx = _integerDecoder!.decode(_cxIARDX!);
      rdy = _integerDecoder!.decode(_cxIARDY!);
    }
    _setSymbolsArray();
    final Bitmap ibo = _sbSymbols[id];
    _decodeNewSymbols(symbolWidth, heightClassHeight, ibo, rdx, rdy);
    if (_isHuffmanEncoded) {
      _subInputStream!.skipBits();
    }
  }

  void _decodeNewSymbols(final int symWidth, final int hcHeight, final Bitmap ibo, final int rdx, final int rdy) {
    if (_genericRefinementRegion == null) {
      _genericRefinementRegion = GenericRefinementRegion(_subInputStream!);
      if (_arithmeticDecoder == null) _arithmeticDecoder = ArithmeticDecoder(_subInputStream!);
      if (_cx == null) _cx = CX(65536, 1);
    }
    _genericRefinementRegion!.setParameters(_cx, _arithmeticDecoder, _sdrTemplate, symWidth, hcHeight, ibo, rdx, rdy, false, _sdrATX!, _sdrATY!);
    _addSymbol(_genericRefinementRegion!);
  }

  void _decodeDirectlyThroughGenericRegion(final int symWidth, final int hcHeight) {
    if (_genericRegion == null) {
      _genericRegion = GenericRegion(_subInputStream!);
    }
    _genericRegion!.setParameters(false, _sdTemplate, false, false, _sdATX!, _sdATY!, symWidth, hcHeight, _cx, _arithmeticDecoder);
    _addSymbol(_genericRegion!);
  }

  void _addSymbol(final Region region) {
    final Bitmap symbol = region.getRegionBitmap();
    _newSymbols[_amountOfDecodedSymbols] = symbol;
    _sbSymbols.add(symbol);
  }

  int _decodeDifferenceWidth() {
    if (_isHuffmanEncoded) {
      switch (_sdHuffDecodeWidthSelection) {
        case 0: return StandardTables.getTable(2).decode(_subInputStream!);
        case 1: return StandardTables.getTable(3).decode(_subInputStream!);
        case 3:
          if (_dwTable == null) {
            int dwNr = 0;
            if (_sdHuffDecodeHeightSelection == 3) dwNr++;
            _dwTable = _getUserTable(dwNr);
          }
          return _dwTable!.decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIADW!);
    }
    return 0;
  }

  int _decodeHeightClassDeltaHeight() {
    if (_isHuffmanEncoded) {
      return _decodeHeightClassDeltaHeightWithHuffman();
    } else {
      return _integerDecoder!.decode(_cxIADH!);
    }
  }

  int _decodeHeightClassDeltaHeightWithHuffman() {
    switch (_sdHuffDecodeHeightSelection) {
      case 0: return StandardTables.getTable(4).decode(_subInputStream!);
      case 1: return StandardTables.getTable(5).decode(_subInputStream!);
      case 3:
        if (_dhTable == null) _dhTable = _getUserTable(0);
        return _dhTable!.decode(_subInputStream!);
    }
    return 0;
  }

  Bitmap _decodeHeightClassCollectiveBitmap(final int bmSize, final int heightClassHeight, final int totalWidth) {
    if (bmSize == 0) {
      final Bitmap heightClassCollectiveBitmap = Bitmap(totalWidth, heightClassHeight);
      for (int i = 0; i < heightClassCollectiveBitmap.getByteArray().length; i++) {
        heightClassCollectiveBitmap.setByte(i, _subInputStream!.read());
      }
      return heightClassCollectiveBitmap;
    } else {
      if (_genericRegion == null) _genericRegion = GenericRegion(_subInputStream!);
      _genericRegion!.setParametersForPattern(true, _subInputStream!.getStreamPosition(), bmSize, heightClassHeight, totalWidth, 0, false, false, [], []);
      return _genericRegion!.getRegionBitmap();
    }
  }

  void _setExportedSymbols(List<int> toExportFlags) {
    _exportSymbols = [];
    for (int i = 0; i < _amountOfImportedSymbols + _amountOfNewSymbols; i++) {
      if (toExportFlags[i] == 1) {
        if (i < _amountOfImportedSymbols) {
          _exportSymbols!.add(_importSymbols[i]);
        } else {
          _exportSymbols!.add(_newSymbols[i - _amountOfImportedSymbols]!);
        }
      }
    }
  }

  List<int> _getToExportFlags() {
    int currentExportFlag = 0;
    int exRunLength = 0;
    final List<int> exportFlags = List.filled(_amountOfImportedSymbols + _amountOfNewSymbols, 0);
    for (int exportIndex = 0; exportIndex < _amountOfImportedSymbols + _amountOfNewSymbols; exportIndex += exRunLength) {
      if (_isHuffmanEncoded) {
        exRunLength = StandardTables.getTable(1).decode(_subInputStream!);
      } else {
        exRunLength = _integerDecoder!.decode(_cxIAEX!);
      }
      if (exRunLength != 0) {
        for (int index = exportIndex; index < exportIndex + exRunLength; index++) {
          if (index < exportFlags.length) {
            exportFlags[index] = currentExportFlag;
          }
        }
      }
      currentExportFlag = (currentExportFlag == 0) ? 1 : 0;
    }
    return exportFlags;
  }

  int _huffDecodeBmSize() {
    if (_bmSizeTable == null) {
      int bmNr = 0;
      if (_sdHuffDecodeHeightSelection == 3) bmNr++;
      if (_sdHuffDecodeWidthSelection == 3) bmNr++;
      _bmSizeTable = _getUserTable(bmNr);
    }
    return _bmSizeTable!.decode(_subInputStream!);
  }

  int _getSbSymCodeLen() {
    if (_isHuffmanEncoded) {
      return max((log(_amountOfImportedSymbols + _amountOfNewSymbols) / log(2)).ceil(), 1);
    } else {
      return (log(_amountOfImportedSymbols + _amountOfNewSymbols) / log(2)).ceil();
    }
  }

  void _setSymbolsArray() {
    if (_importSymbols.isEmpty && _segmentHeader!.rtSegments.isNotEmpty) {
      _retrieveImportSymbols();
    }
    if (_sbSymbols.isEmpty) {
      _sbSymbols.addAll(_importSymbols);
    }
  }

  void _retrieveImportSymbols() {
    _importSymbols = [];
    for (final SegmentHeader referredToSegmentHeader in _segmentHeader!.rtSegments) {
      if (referredToSegmentHeader.segmentType == 0) {
        final SymbolDictionary sd = referredToSegmentHeader.getSegmentData() as SymbolDictionary;
        _importSymbols.addAll(sd.getDictionary());
        _amountOfImportedSymbols += sd._amountOfExportSymbols;
      }
    }
  }

  HuffmanTable? _getUserTable(final int tablePosition) {
    int tableCounter = 0;
    for (final SegmentHeader referredToSegmentHeader in _segmentHeader!.rtSegments) {
      if (referredToSegmentHeader.segmentType == 53) {
        if (tableCounter == tablePosition) {
          final Table t = referredToSegmentHeader.getSegmentData() as Table;
          return EncodedTable(t);
        } else {
          tableCounter++;
        }
      }
    }
    return null;
  }
}

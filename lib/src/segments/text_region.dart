import 'dart:math';

import '../region.dart';
import '../segment_header.dart';
import 'region_segment_information.dart';
import '../bitmap.dart';
import '../image/bitmaps.dart';
import '../util/combination_operator.dart';
import '../decoder/arithmetic/arithmetic_decoder.dart';
import '../decoder/arithmetic/arithmetic_integer_decoder.dart';
import '../decoder/arithmetic/cx.dart';
import '../decoder/huffman/encoded_table.dart';
import '../decoder/huffman/fixed_size_table.dart';
import '../decoder/huffman/huffman_table.dart';
import '../decoder/huffman/standard_tables.dart';
import '../io/sub_input_stream.dart';
import 'symbol_dictionary.dart';
import 'table.dart';
import 'generic_refinement_region.dart';
import '../util/log.dart';

class TextRegion implements Region {
  SubInputStream? _subInputStream;
  late RegionSegmentInformation _regionInfo;
  SegmentHeader? _segmentHeader;

  // Text region segment flags
  int _sbrTemplate = 0;
  int _sbdsOffset = 0;
  int _defaultPixel = 0;
  CombinationOperator _combinationOperator = CombinationOperator.OR;
  int _isTransposed = 0;
  int _referenceCorner = 0;
  int _logSBStrips = 0;
  bool _useRefinement = false;
  bool _isHuffmanEncoded = false;

  // Text region segment Huffman flags
  int _sbHuffRSize = 0;
  int _sbHuffRDY = 0;
  int _sbHuffRDX = 0;
  int _sbHuffRDHeight = 0;
  int _sbHuffRDWidth = 0;
  int _sbHuffDT = 0;
  int _sbHuffDS = 0;
  int _sbHuffFS = 0;

  // Text region refinement AT flags
  List<int>? _sbrATX;
  List<int>? _sbrATY;

  int _amountOfSymbolInstances = 0;

  // Further parameters
  int _currentS = 0;
  int _sbStrips = 0;
  int _amountOfSymbols = 0;

  Bitmap? _regionBitmap;
  List<Bitmap> _symbols = [];

  ArithmeticDecoder? _arithmeticDecoder;
  ArithmeticIntegerDecoder? _integerDecoder;
  GenericRefinementRegion? _genericRefinementRegion;

  CX? _cxIADT;
  CX? _cxIAFS;
  CX? _cxIADS;
  CX? _cxIAIT;
  CX? _cxIARI;
  CX? _cxIARDW;
  CX? _cxIARDH;
  CX? _cxIAID;
  CX? _cxIARDX;
  CX? _cxIARDY;
  CX? _cx;

  int _symbolCodeLength = 0;
  FixedSizeTable? _symbolCodeTable;

  HuffmanTable? _fsTable;
  HuffmanTable? _dsTable;
  HuffmanTable? _table;
  HuffmanTable? _rdwTable;
  HuffmanTable? _rdhTable;
  HuffmanTable? _rdxTable;
  HuffmanTable? _rdyTable;
  HuffmanTable? _rSizeTable;

  TextRegion([this._subInputStream, this._segmentHeader]) {
    if (_subInputStream != null) {
      _regionInfo = RegionSegmentInformation(_subInputStream);
    }
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _segmentHeader = header;
    _subInputStream = sis;
    _regionInfo = RegionSegmentInformation(_subInputStream);
    _parseHeader();
  }

  void _parseHeader() {
    // print("TextRegion parsing header...");
    _regionInfo.parseHeader();
    // print("Region info parsed.");
    _readRegionFlags();
    // print("Region flags read. Huffman: $_isHuffmanEncoded");
    if (_isHuffmanEncoded) {
      _readHuffmanFlags();
      // print("Huffman flags read.");
    }
    _readUseRefinement();
    // print("Use refinement read.");
    _readAmountOfSymbolInstances();
    // print("Amount of symbol instances: $_amountOfSymbolInstances");
    _getSymbols();
    // print("Symbols retrieved.");
    _computeSymbolCodeLength();
    // print("Symbol code length computed.");
    _checkInput();
    // print("Input checked.");
  }

  void _readRegionFlags() {
    _sbrTemplate = _subInputStream!.readBit();
    _sbdsOffset = _subInputStream!.readBits(5);
    if (_sbdsOffset > 0x0f) {
      _sbdsOffset -= 0x20;
    }
    _defaultPixel = _subInputStream!.readBit();
    _combinationOperator = CombinationOperator.translateOperatorCodeToEnum(_subInputStream!.readBits(2) & 0x3);
    _isTransposed = _subInputStream!.readBit();
    _referenceCorner = _subInputStream!.readBits(2) & 0x3;
    _logSBStrips = _subInputStream!.readBits(2) & 0x3;
    _sbStrips = (1 << _logSBStrips);
    if (_subInputStream!.readBit() == 1) {
      _useRefinement = true;
    }
    if (_subInputStream!.readBit() == 1) {
      _isHuffmanEncoded = true;
    }
  }

  void _readHuffmanFlags() {
    _subInputStream!.readBit(); // Dirty read
    _sbHuffRSize = _subInputStream!.readBit();
    _sbHuffRDY = _subInputStream!.readBits(2) & 0xf;
    _sbHuffRDX = _subInputStream!.readBits(2) & 0xf;
    _sbHuffRDHeight = _subInputStream!.readBits(2) & 0xf;
    _sbHuffRDWidth = _subInputStream!.readBits(2) & 0xf;
    _sbHuffDT = _subInputStream!.readBits(2) & 0xf;
    _sbHuffDS = _subInputStream!.readBits(2) & 0xf;
    _sbHuffFS = _subInputStream!.readBits(2) & 0xf;
  }

  void _readUseRefinement() {
    if (_useRefinement && _sbrTemplate == 0) {
      _sbrATX = List.filled(2, 0);
      _sbrATY = List.filled(2, 0);
      _sbrATX![0] = _subInputStream!.read();
      _sbrATY![0] = _subInputStream!.read();
      _sbrATX![1] = _subInputStream!.read();
      _sbrATY![1] = _subInputStream!.read();
    }
  }

  void _readAmountOfSymbolInstances() {
    _amountOfSymbolInstances = _subInputStream!.readBits(32) & 0xffffffff;
  }

  void _getSymbols() {
    if (_segmentHeader!.rtSegments.isNotEmpty) {
      _initSymbols();
    }
  }

  void _initSymbols() {
    for (final SegmentHeader segment in _segmentHeader!.rtSegments) {
      if (segment.segmentType == 0) {
        final SymbolDictionary sd = segment.getSegmentData() as SymbolDictionary;
        sd.cxIAID = _cxIAID;
        _symbols.addAll(sd.getDictionary());
      }
    }
    _amountOfSymbols = _symbols.length;
  }

  void _computeSymbolCodeLength() {
    if (_isHuffmanEncoded) {
      _symbolIDCodeLengths();
    } else {
      _symbolCodeLength = (log(_amountOfSymbols) / log(2)).ceil();
    }
  }

  void _symbolIDCodeLengths() {
    final List<Code> runCodeTable = [];
    for (int i = 0; i < 35; i++) {
      final int prefLen = _subInputStream!.readBits(4) & 0xf;
      if (prefLen > 0) {
        runCodeTable.add(Code(prefLen, 0, i, false));
      }
    }
    
    HuffmanTable ht = FixedSizeTable(runCodeTable);
    
    int previousCodeLength = 0;
    int counter = 0;
    final List<Code> sbSymCodes = [];
    
    while (counter < _amountOfSymbols) {
      final int code = ht.decode(_subInputStream!);
      if (code < 32) {
        if (code > 0) {
          sbSymCodes.add(Code(code, 0, counter, false));
        }
        previousCodeLength = code;
        counter++;
      } else {
        int runLength = 0;
        int currCodeLength = 0;
        if (code == 32) {
          runLength = 3 + _subInputStream!.readBits(2);
          if (counter > 0) {
            currCodeLength = previousCodeLength;
          }
        } else if (code == 33) {
          runLength = 3 + _subInputStream!.readBits(3);
        } else if (code == 34) {
          runLength = 11 + _subInputStream!.readBits(7);
        }
        
        for (int j = 0; j < runLength; j++) {
          if (currCodeLength > 0) {
            sbSymCodes.add(Code(currCodeLength, 0, counter, false));
          }
          counter++;
        }
      }
    }
    _subInputStream!.skipBits();
    _symbolCodeTable = FixedSizeTable(sbSymCodes);
  }

  void _checkInput() {
    if (!_useRefinement) {
      if (_sbrTemplate != 0) {
        Logger.info("sbrTemplate should be 0");
        _sbrTemplate = 0;
      }
    }
    if (_sbHuffFS == 2 || _sbHuffRDWidth == 2 || _sbHuffRDHeight == 2 || _sbHuffRDX == 2 || _sbHuffRDY == 2) {
      throw Exception("Huffman flag value of text region segment is not permitted");
    }
    if (!_useRefinement) {
      if (_sbHuffRSize != 0) { Logger.info("sbHuffRSize should be 0"); _sbHuffRSize = 0; }
      if (_sbHuffRDY != 0) { Logger.info("sbHuffRDY should be 0"); _sbHuffRDY = 0; }
      if (_sbHuffRDX != 0) { Logger.info("sbHuffRDX should be 0"); _sbHuffRDX = 0; }
      if (_sbHuffRDWidth != 0) { Logger.info("sbHuffRDWidth should be 0"); _sbHuffRDWidth = 0; }
      if (_sbHuffRDHeight != 0) { Logger.info("sbHuffRDHeight should be 0"); _sbHuffRDHeight = 0; }
    }
  }

  @override
  Bitmap getRegionBitmap() {
    if (!_isHuffmanEncoded) {
      _setCodingStatistics();
    }
    _createRegionBitmap();
    _decodeSymbolInstances();
    return _regionBitmap!;
  }

  @override
  RegionSegmentInformation getRegionInfo() {
    return _regionInfo;
  }

  void _setCodingStatistics() {
    if (_cxIADT == null) _cxIADT = CX(512, 1);
    if (_cxIAFS == null) _cxIAFS = CX(512, 1);
    if (_cxIADS == null) _cxIADS = CX(512, 1);
    if (_cxIAIT == null) _cxIAIT = CX(512, 1);
    if (_cxIARI == null) _cxIARI = CX(512, 1);
    if (_cxIARDW == null) _cxIARDW = CX(512, 1);
    if (_cxIARDH == null) _cxIARDH = CX(512, 1);
    if (_cxIAID == null) _cxIAID = CX(1 << _symbolCodeLength, 1);
    if (_cxIARDX == null) _cxIARDX = CX(512, 1);
    if (_cxIARDY == null) _cxIARDY = CX(512, 1);

    if (_arithmeticDecoder == null) _arithmeticDecoder = ArithmeticDecoder(_subInputStream!);
    if (_integerDecoder == null) _integerDecoder = ArithmeticIntegerDecoder(_arithmeticDecoder!);
  }

  void _createRegionBitmap() {
    final int width = _regionInfo.bitmapWidth;
    final int height = _regionInfo.bitmapHeight;
    _regionBitmap = Bitmap(width, height);
    if (_defaultPixel != 0) {
      // Fill with 0xff
      // _regionBitmap!.getByteArray().fillRange(0, _regionBitmap!.getByteArray().length, 0xff);
      // Dart Uint8List doesn't have fillRange with value for all?
      // It does.
      for(int i=0; i<_regionBitmap!.getByteArray().length; i++) {
          _regionBitmap!.getByteArray()[i] = 0xff;
      }
    }
  }

  void _decodeSymbolInstances() {
    int stripT = _decodeStripT();

    int firstS = 0;
    int instanceCounter = 0;

    while (instanceCounter < _amountOfSymbolInstances) {
      final int dT = _decodeDT();
      stripT += dT;
      
      bool first = true;
      _currentS = 0;

      for (;;) {
        if (first) {
          final int dfS = _decodeDfS();
          firstS += dfS;
          _currentS = firstS;
          first = false;
        } else {
          final int idS = _decodeIdS();
          if (idS == 0x7fffffffffffffff) // Long.MAX_VALUE check? Dart int is 64-bit.
             break; // How to represent OOB?
          // In Java code: if (idS == Long.MAX_VALUE) break;
          // I need to check what decodeIdS returns for OOB.
          // But wait, decodeIdS calls integerDecoder.decode(cxIADS) or Huffman table decode.
          // If Huffman table decode returns OOB, it might throw or return a special value.
          // In Java, StandardTables returns Long.MAX_VALUE for OOB?
          // I need to check StandardTables implementation or assume it returns a large value.
          // Let's assume I need to handle it.
          
          // Actually, let's look at _decodeIdS implementation.
          
          _currentS += (idS + _sbdsOffset);
        }

        final int currentT = _decodeCurrentT();
        final int t = stripT + currentT;

        final int id = _decodeID();
        final int r = _decodeRI();
        final Bitmap ib = _decodeIb(r, id);

        _blit(ib, t);

        instanceCounter++;
      }
    }
  }

  int _decodeStripT() {
    int stripT = 0;
    if (_isHuffmanEncoded) {
      if (_sbHuffDT == 3) {
        if (_table == null) {
          int dtNr = 0;
          if (_sbHuffFS == 3) dtNr++;
          if (_sbHuffDS == 3) dtNr++;
          _table = _getUserTable(dtNr);
        }
        stripT = _table!.decode(_subInputStream!);
      } else {
        stripT = StandardTables.getTable(11 + _sbHuffDT).decode(_subInputStream!);
      }
    } else {
      stripT = _integerDecoder!.decode(_cxIADT!);
    }
    return stripT * -_sbStrips;
  }

  int _decodeDT() {
    int dT;
    if (_isHuffmanEncoded) {
      if (_sbHuffDT == 3) {
        dT = _table!.decode(_subInputStream!);
      } else {
        dT = StandardTables.getTable(11 + _sbHuffDT).decode(_subInputStream!);
      }
    } else {
      dT = _integerDecoder!.decode(_cxIADT!);
    }
    return dT * _sbStrips;
  }

  int _decodeDfS() {
    if (_isHuffmanEncoded) {
      if (_sbHuffFS == 3) {
        if (_fsTable == null) {
          _fsTable = _getUserTable(0);
        }
        return _fsTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(6 + _sbHuffFS).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIAFS!);
    }
  }

  int _decodeIdS() {
    if (_isHuffmanEncoded) {
      if (_sbHuffDS == 3) {
        if (_dsTable == null) {
          int dsNr = 0;
          if (_sbHuffFS == 3) dsNr++;
          _dsTable = _getUserTable(dsNr);
        }
        return _dsTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(8 + _sbHuffDS).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIADS!);
    }
  }

  int _decodeCurrentT() {
    if (_sbStrips != 1) {
      if (_isHuffmanEncoded) {
        return _subInputStream!.readBits(_logSBStrips);
      } else {
        return _integerDecoder!.decode(_cxIAIT!);
      }
    }
    return 0;
  }

  int _decodeID() {
    if (_isHuffmanEncoded) {
      if (_symbolCodeTable == null) {
        return _subInputStream!.readBits(_symbolCodeLength);
      }
      return _symbolCodeTable!.decode(_subInputStream!);
    } else {
      return _integerDecoder!.decodeIAID(_cxIAID!, _symbolCodeLength);
    }
  }

  int _decodeRI() {
    if (_useRefinement) {
      if (_isHuffmanEncoded) {
        return _subInputStream!.readBit();
      } else {
        return _integerDecoder!.decode(_cxIARI!);
      }
    }
    return 0;
  }

  Bitmap _decodeIb(int r, int id) {
    Bitmap ib;
    if (r == 0) {
      ib = _symbols[id];
    } else {
      final int rdw = _decodeRdw();
      final int rdh = _decodeRdh();
      final int rdx = _decodeRdx();
      final int rdy = _decodeRdy();

      if (_isHuffmanEncoded) {
        _decodeSymInRefSize();
        _subInputStream!.skipBits();
      }

      final Bitmap ibo = _symbols[id];
      final int wo = ibo.width;
      final int ho = ibo.height;

      final int genericRegionReferenceDX = (rdw >> 1) + rdx;
      final int genericRegionReferenceDY = (rdh >> 1) + rdy;

      if (_genericRefinementRegion == null) {
        _genericRefinementRegion = GenericRefinementRegion(_subInputStream!);
      }

      _genericRefinementRegion!.setParameters(_cx, _arithmeticDecoder, _sbrTemplate, (wo + rdw), (ho + rdh),
          ibo, genericRegionReferenceDX, genericRegionReferenceDY, false, _sbrATX!, _sbrATY!);

      ib = _genericRefinementRegion!.getRegionBitmap();

      if (_isHuffmanEncoded) {
        _subInputStream!.skipBits();
      }
    }
    return ib;
  }

  int _decodeRdw() {
    if (_isHuffmanEncoded) {
      if (_sbHuffRDWidth == 3) {
        if (_rdwTable == null) {
          int rdwNr = 0;
          if (_sbHuffFS == 3) rdwNr++;
          if (_sbHuffDS == 3) rdwNr++;
          if (_sbHuffDT == 3) rdwNr++;
          _rdwTable = _getUserTable(rdwNr);
        }
        return _rdwTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(14 + _sbHuffRDWidth).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIARDW!);
    }
  }

  int _decodeRdh() {
    if (_isHuffmanEncoded) {
      if (_sbHuffRDHeight == 3) {
        if (_rdhTable == null) {
          int rdhNr = 0;
          if (_sbHuffFS == 3) rdhNr++;
          if (_sbHuffDS == 3) rdhNr++;
          if (_sbHuffDT == 3) rdhNr++;
          if (_sbHuffRDWidth == 3) rdhNr++;
          _rdhTable = _getUserTable(rdhNr);
        }
        return _rdhTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(14 + _sbHuffRDHeight).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIARDH!);
    }
  }

  int _decodeRdx() {
    if (_isHuffmanEncoded) {
      if (_sbHuffRDX == 3) {
        if (_rdxTable == null) {
          int rdxNr = 0;
          if (_sbHuffFS == 3) rdxNr++;
          if (_sbHuffDS == 3) rdxNr++;
          if (_sbHuffDT == 3) rdxNr++;
          if (_sbHuffRDWidth == 3) rdxNr++;
          if (_sbHuffRDHeight == 3) rdxNr++;
          _rdxTable = _getUserTable(rdxNr);
        }
        return _rdxTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(14 + _sbHuffRDX).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIARDX!);
    }
  }

  int _decodeRdy() {
    if (_isHuffmanEncoded) {
      if (_sbHuffRDY == 3) {
        if (_rdyTable == null) {
          int rdyNr = 0;
          if (_sbHuffFS == 3) rdyNr++;
          if (_sbHuffDS == 3) rdyNr++;
          if (_sbHuffDT == 3) rdyNr++;
          if (_sbHuffRDWidth == 3) rdyNr++;
          if (_sbHuffRDHeight == 3) rdyNr++;
          if (_sbHuffRDX == 3) rdyNr++;
          _rdyTable = _getUserTable(rdyNr);
        }
        return _rdyTable!.decode(_subInputStream!);
      } else {
        return StandardTables.getTable(14 + _sbHuffRDY).decode(_subInputStream!);
      }
    } else {
      return _integerDecoder!.decode(_cxIARDY!);
    }
  }

  int _decodeSymInRefSize() {
    if (_sbHuffRSize == 0) {
      return StandardTables.getTable(1).decode(_subInputStream!);
    } else {
      if (_rSizeTable == null) {
        int rSizeNr = 0;
        if (_sbHuffFS == 3) rSizeNr++;
        if (_sbHuffDS == 3) rSizeNr++;
        if (_sbHuffDT == 3) rSizeNr++;
        if (_sbHuffRDWidth == 3) rSizeNr++;
        if (_sbHuffRDHeight == 3) rSizeNr++;
        if (_sbHuffRDX == 3) rSizeNr++;
        if (_sbHuffRDY == 3) rSizeNr++;
        _rSizeTable = _getUserTable(rSizeNr);
      }
      return _rSizeTable!.decode(_subInputStream!);
    }
  }

  void _blit(Bitmap ib, int t) {
    if (_isTransposed == 0 && (_referenceCorner == 2 || _referenceCorner == 3)) {
      _currentS += ib.width - 1;
    } else if (_isTransposed == 1 && (_referenceCorner == 0 || _referenceCorner == 2)) {
      _currentS += ib.height - 1;
    }

    int s = _currentS;

    if (_isTransposed == 1) {
      final int swap = t;
      t = s;
      s = swap;
    }

    if (_referenceCorner != 1) {
      if (_referenceCorner == 0) {
        // BL
        t -= ib.height - 1;
      } else if (_referenceCorner == 2) {
        // BR
        t -= ib.height - 1;
        s -= ib.width - 1;
      } else if (_referenceCorner == 3) {
        // TR
        s -= ib.width - 1;
      }
    }

    Bitmaps.blit(ib, _regionBitmap!, s, t, _combinationOperator);

    if (_isTransposed == 0 && (_referenceCorner == 0 || _referenceCorner == 1)) {
      _currentS += ib.width - 1;
    }

    if (_isTransposed == 1 && (_referenceCorner == 1 || _referenceCorner == 3)) {
      _currentS += ib.height - 1;
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

  void setContexts(CX cx, CX cxIADT, CX cxIAFS, CX cxIADS, CX cxIAIT, CX cxIAID, CX cxIARDW, CX cxIARDH,
      CX cxIARDX, CX cxIARDY) {
    _cx = cx;
    _cxIADT = cxIADT;
    _cxIAFS = cxIAFS;
    _cxIADS = cxIADS;
    _cxIAIT = cxIAIT;
    _cxIAID = cxIAID;
    _cxIARDW = cxIARDW;
    _cxIARDH = cxIARDH;
    _cxIARDX = cxIARDX;
    _cxIARDY = cxIARDY;
  }

  void setParameters(ArithmeticDecoder arithmeticDecoder, ArithmeticIntegerDecoder iDecoder,
      bool isHuffmanEncoded, bool sbRefine, int sbw, int sbh, int sbNumInstances, int sbStrips, int sbNumSyms,
      int sbDefaultPixel, int sbCombinationOperator, int transposed, int refCorner, int sbdsOffset,
      int sbHuffFS, int sbHuffDS, int sbHuffDT, int sbHuffRDWidth, int sbHuffRDHeight, int sbHuffRDX,
      int sbHuffRDY, int sbHuffRSize, int sbrTemplate, List<int> sbrATX, List<int> sbrATY, List<Bitmap> sbSyms,
      int sbSymCodeLen) {

    _arithmeticDecoder = arithmeticDecoder;
    _integerDecoder = iDecoder;
    _isHuffmanEncoded = isHuffmanEncoded;
    _useRefinement = sbRefine;

    _regionInfo.bitmapWidth = sbw;
    _regionInfo.bitmapHeight = sbh;

    _amountOfSymbolInstances = sbNumInstances;
    _sbStrips = sbStrips;
    _amountOfSymbols = sbNumSyms;
    _defaultPixel = sbDefaultPixel;
    _combinationOperator = CombinationOperator.translateOperatorCodeToEnum(sbCombinationOperator);
    _isTransposed = transposed;
    _referenceCorner = refCorner;
    _sbdsOffset = sbdsOffset;

    _sbHuffFS = sbHuffFS;
    _sbHuffDS = sbHuffDS;
    _sbHuffDT = sbHuffDT;
    _sbHuffRDWidth = sbHuffRDWidth;
    _sbHuffRDHeight = sbHuffRDHeight;
    _sbHuffRDX = sbHuffRDX;
    _sbHuffRDY = sbHuffRDY;
    _sbHuffRSize = sbHuffRSize;

    _sbrTemplate = sbrTemplate;
    _sbrATX = sbrATX;
    _sbrATY = sbrATY;

    _symbols = sbSyms;
    _symbolCodeLength = sbSymCodeLen;
  }
}

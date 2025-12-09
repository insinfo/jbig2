import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/jbig2_page.dart';
import 'package:jbig2/src/segment_data.dart';
import 'package:jbig2/src/segments/page_information.dart';
import 'package:jbig2/src/segments/end_of_stripe.dart';
import 'package:jbig2/src/segments/symbol_dictionary.dart';
import 'package:jbig2/src/segments/text_region.dart';
import 'package:jbig2/src/segments/pattern_dictionary.dart';
import 'package:jbig2/src/segments/halftone_region.dart';
import 'package:jbig2/src/segments/generic_region.dart';
import 'package:jbig2/src/segments/generic_refinement_region.dart';
import 'package:jbig2/src/segments/table.dart';

class SegmentHeader {
  // static final Logger log = LoggerFactory.getLogger(SegmentHeader.class);

  static final Map<int, SegmentData Function()> segmentTypeMap = {
    48: () => PageInformation(),
    50: () => EndOfStripe(),
    0: () => SymbolDictionary(),
    4: () => TextRegion(),
    6: () => TextRegion(),
    7: () => TextRegion(),
    16: () => PatternDictionary(),
    20: () => HalftoneRegion(),
    22: () => HalftoneRegion(),
    23: () => HalftoneRegion(),
    36: () => GenericRegion(),
    38: () => GenericRegion(),
    39: () => GenericRegion(),
    40: () => GenericRefinementRegion(),
    42: () => GenericRefinementRegion(),
    43: () => GenericRefinementRegion(),
    // 52: () => Profiles(),
    53: () => Table(),
  };

  int segmentNr = 0;
  int segmentType = 0;
  int retainFlag = 0;
  int pageAssociation = 0;
  int pageAssociationFieldSize = 0;
  List<SegmentHeader> rtSegments = [];
  int segmentHeaderLength = 0;
  int segmentDataLength = 0;
  int segmentDataStartOffset = 0;
  final SubInputStream subInputStream;
  final JBIG2Document document;

  SegmentData? _segmentData;

  SegmentHeader(
      this.document, this.subInputStream, int offset, int organisationType) {
    parse(document, subInputStream, offset, organisationType);
  }

  void parse(JBIG2Document document, SubInputStream subInputStream, int offset,
      int organisationType) {
    // print("Segment parsing started.");

    subInputStream.seek(offset);
    // print("|-Seeked to offset: $offset");

    /* 7.2.2 Segment number */
    readSegmentNumber(subInputStream);

    /* 7.2.3 Segment header flags */
    readSegmentHeaderFlag(subInputStream);

    /* 7.2.4 Amount of referred-to segments */
    int countOfRTS = readAmountOfReferredToSegments(subInputStream);

    /* 7.2.5 Referred-to segments numbers */
    List<int> rtsNumbers =
        readReferredToSegmentsNumbers(subInputStream, countOfRTS);

    /* 7.2.6 Segment page association (Checks how big the page association field is.) */
    readSegmentPageAssociation(
        document, subInputStream, countOfRTS, rtsNumbers);

    /* 7.2.7 Segment data length (Contains the length of the data part (in bytes).) */
    readSegmentDataLength(subInputStream);

    readDataStartOffset(subInputStream, organisationType);
    readSegmentHeaderLength(subInputStream, offset);
  }

  void readSegmentNumber(SubInputStream subInputStream) {
    segmentNr = subInputStream.readBits(32) & 0xffffffff;
    // print("|-Segment Nr: $segmentNr");
  }

  void readSegmentHeaderFlag(SubInputStream subInputStream) {
    // Bit 7: Retain Flag, if 1, this segment is flagged as retained;
    retainFlag = subInputStream.readBit();
    // print("|-Retain flag: $retainFlag");

    // Bit 6: Size of the page association field. One byte if 0, four bytes if 1;
    pageAssociationFieldSize = subInputStream.readBit();
    // print("|-Page association field size=$pageAssociationFieldSize");

    // Bit 5-0: Contains the values (between 0 and 62 with gaps) for segment types, specified in 7.3
    segmentType = subInputStream.readBits(6) & 0xff;
    // print("|-Segment type=$segmentType");
  }

  int readAmountOfReferredToSegments(SubInputStream subInputStream) {
    int countOfRTS = subInputStream.readBits(3) & 0xf;
    // print("|-RTS count: $countOfRTS");

    // print("  |-Stream position before RTS: ${subInputStream.getStreamPosition()}");

    if (countOfRTS <= 4) {
      /* short format */
      for (int i = 0; i <= 4; i++) {
        subInputStream.readBit(); // retainBit
      }
    } else {
      /* long format */
      countOfRTS = subInputStream.readBits(29) & 0xffffffff;

      int arrayLength = (countOfRTS + 8) >> 3;
      int totalBits = arrayLength << 3;
      for (int i = 0; i < totalBits; i++) {
        subInputStream.readBit();
      }
    }

    // print("  |-Stream position after RTS: ${subInputStream.getStreamPosition()}");

    return countOfRTS;
  }

  List<int> readReferredToSegmentsNumbers(
      SubInputStream subInputStream, int countOfRTS) {
    List<int> rtsNumbers = List.filled(countOfRTS, 0);

    if (countOfRTS > 0) {
      int rtsSize = 1;
      if (segmentNr > 256) {
        rtsSize = 2;
        if (segmentNr > 65536) {
          rtsSize = 4;
        }
      }

      // rtSegments = List.filled(countOfRTS, SegmentHeader(document, subInputStream, 0, 0)); 
      rtSegments = [];  

      // print("|-Length of RT segments list: $countOfRTS");

      for (int i = 0; i < countOfRTS; i++) {
        rtsNumbers[i] = subInputStream.readBits(rtsSize << 3) & 0xffffffff;
      }
    }

    return rtsNumbers;
  }

  void readSegmentPageAssociation(JBIG2Document document,
      SubInputStream subInputStream, int countOfRTS, List<int> rtsNumbers) {
    if (pageAssociationFieldSize == 0) {
      // Short format
      pageAssociation = subInputStream.readBits(8) & 0xff;
    } else {
      // Long format
      pageAssociation = subInputStream.readBits(32) & 0xffffffff;
    }

    if (countOfRTS > 0) {
      final JBIG2Page? page = document.getPage(pageAssociation);
      for (int i = 0; i < countOfRTS; i++) {
        SegmentHeader? seg = (page != null
            ? page.getSegment(rtsNumbers[i])
            : document.getGlobalSegment(rtsNumbers[i]));
        if (seg != null) {
            rtSegments.add(seg);
        }
      }
    }
  }

  void readSegmentDataLength(SubInputStream subInputStream) {
    segmentDataLength = subInputStream.readBits(32) & 0xffffffff;
    // print("|-Data length: $segmentDataLength");
  }

  void readDataStartOffset(
      SubInputStream subInputStream, int organisationType) {
    if (organisationType == JBIG2Document.SEQUENTIAL) {
      // print("|-Organization is sequential.");
      segmentDataStartOffset = subInputStream.getStreamPosition();
    }
  }

  void readSegmentHeaderLength(SubInputStream subInputStream, int offset) {
    segmentHeaderLength = subInputStream.getStreamPosition() - offset;
    // print("|-Segment header length: $segmentHeaderLength");
  }

  SubInputStream getDataInputStream() {
    return SubInputStream(
        subInputStream.wrappedStream, subInputStream.offset + segmentDataStartOffset, segmentDataLength);
  }

  SegmentData? getSegmentData() {
    if (_segmentData != null) {
      return _segmentData;
    }

    try {
      var factory = segmentTypeMap[segmentType];
      if (factory == null) {
        // throw ArgumentError("No segment class for type $segmentType");
        return null; // Return null for now as we haven't implemented all segments
      }

      // print("Initializing segment type: $segmentType");
      _segmentData = factory();
      _segmentData!.init(this, getDataInputStream());
    } catch (e) {
      // print("Error initializing segment type: $segmentType (Segment Nr: $segmentNr)");
      // print(e);
      // print(stackTrace);
      throw Exception("Can't instantiate segment class: $e");
    }

    return _segmentData;
  }

  void cleanSegmentData() {
    _segmentData = null;
  }
  
  @override
  String toString() {
      return "SegmentNr: $segmentNr, Type: $segmentType, Page: $pageAssociation";
  }
}

import 'dart:collection';
import 'package:jbig2/src/io/random_access_read.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/jbig2_globals.dart';
import 'package:jbig2/src/jbig2_page.dart';
import 'package:jbig2/src/segment_header.dart';

class JBIG2Document {
  static const int RANDOM = 0;
  static const int SEQUENTIAL = 1;

  final Map<int, JBIG2Page> pages = SplayTreeMap();
  
  final List<int> FILE_HEADER_ID = [
      0x97, 0x4A, 0x42, 0x32, 0x0D, 0x0A, 0x1A, 0x0A
  ];

  int fileHeaderLength = 9;
  int organisationType = SEQUENTIAL;
  bool amountOfPagesUnknown = true;
  int amountOfPages = 0;
  bool gbUseExtTemplate = false;
  
  late SubInputStream subInputStream;
  JBIG2Globals? globalSegments;

  JBIG2Document(RandomAccessRead input, [this.globalSegments]) {
    subInputStream = SubInputStream(input, 0, input.length);
    mapStream();
  }

  SegmentHeader? getGlobalSegment(int segmentNr) {
    if (globalSegments != null) {
      return globalSegments!.getSegment(segmentNr);
    }
    return null;
  }

  JBIG2Page getPage(int pageNumber) {
    return pages[pageNumber]!;
  }
  
  JBIG2Page? getPageOrNull(int pageNumber) {
      return pages[pageNumber];
  }

  int getAmountOfPages() {
    if (amountOfPagesUnknown || amountOfPages == 0) {
      if (pages.isEmpty) {
        mapStream();
      }
      return pages.length;
    } else {
      return amountOfPages;
    }
  }

  void mapStream() {
    final List<SegmentHeader> segments = [];
    int offset = 0;
    int segmentType = 0;

    if (isFileHeaderPresent()) {
      parseFileHeader();
      offset += fileHeaderLength;
    }

    if (globalSegments == null) {
      globalSegments = JBIG2Globals();
    }

    JBIG2Page? page;

    while (segmentType != 51 && !reachedEndOfStream(offset)) {
      SegmentHeader segment = SegmentHeader(this, subInputStream, offset, organisationType);
      
      final int associatedPage = segment.pageAssociation;
      segmentType = segment.segmentType;

      if (associatedPage != 0) {
        page = getPageOrNull(associatedPage);
        if (page == null) {
          page = JBIG2Page(this, associatedPage);
          pages[associatedPage] = page;
        }
        page.add(segment);
      } else {
        globalSegments!.addSegment(segment.segmentNr, segment);
      }
      segments.add(segment);
      
      offset = subInputStream.getStreamPosition();
      
      if (organisationType == SEQUENTIAL) {
        offset += segment.segmentDataLength;
      }
    }
    
    determineRandomDataOffsets(segments, offset);
  }

  bool isFileHeaderPresent() {
    int pos = subInputStream.getStreamPosition();
    
    for (int magicByte in FILE_HEADER_ID) {
      if (magicByte != subInputStream.read()) {
        subInputStream.seek(pos);
        return false;
      }
    }
    
    subInputStream.seek(pos);
    return true;
  }

  void determineRandomDataOffsets(List<SegmentHeader> segments, int offset) {
    if (organisationType == RANDOM) {
      for (SegmentHeader s in segments) {
        s.segmentDataStartOffset = offset;
        offset += s.segmentDataLength;
      }
    }
  }

  void parseFileHeader() {
    subInputStream.seek(0);
    
    // Skip ID string
    for(int i=0; i<8; i++) subInputStream.read();
    
    // Header flag
    subInputStream.readBits(5); // Reserved
    
    if (subInputStream.readBit() == 1) {
      gbUseExtTemplate = true;
    }
    
    if (subInputStream.readBit() != 1) {
      amountOfPagesUnknown = false;
    }
    
    organisationType = subInputStream.readBit();
    
    if (!amountOfPagesUnknown) {
      amountOfPages = subInputStream.readBits(32); // readUnsignedInt
      fileHeaderLength = 13;
    }
  }

  bool reachedEndOfStream(int offset) {
    try {
      if (offset >= subInputStream.length) return true;
      subInputStream.seek(offset);
      // Try to read 32 bits to check if we are at EOF or close to it?
      // Java code: subInputStream.readBits(32);
      // If it fails, it returns true.
      // But reading 32 bits advances the stream.
      // Java code does:
      /*
      try {
        subInputStream.seek(offset);
        subInputStream.readBits(32);
        return false;
      } catch (EOFException e) {
        return true;
      }
      */
      // It seeks back? No, it just checks if it CAN read.
      // But mapStream loop uses offset.
      // If I read here, I change position.
      // But mapStream does:
      // SegmentHeader segment = new SegmentHeader(this, subInputStream, offset, organisationType);
      // SegmentHeader constructor seeks to offset.
      // So it's fine if I change position here.
      
      // However, subInputStream.readBits(32) might throw if not enough bits.
      // My readBits throws Exception.
      // I'll implement similar logic.
      
      // But wait, if I read 32 bits, I might consume the start of the next segment.
      // That's fine because SegmentHeader constructor seeks to offset.
      
      // But what if there are fewer than 32 bits left but it's valid data?
      // The loop condition is `!reachedEndOfStream(offset)`.
      // If there are fewer than 32 bits, it returns true (EOF reached), loop terminates.
      // Is it possible to have a segment header < 32 bits?
      // Segment header starts with Segment Number (32 bits).
      // So yes, if we can't read 32 bits, we can't read a segment number.
      
      subInputStream.readBits(32);
      return false;
    } catch (e) {
      return true;
    }
  }
}

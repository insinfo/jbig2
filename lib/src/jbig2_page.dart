import 'dart:collection';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/segment_header.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/segment_data.dart';
import 'package:jbig2/src/segments/page_information.dart';
import 'package:jbig2/src/region.dart';
import 'package:jbig2/src/segments/end_of_stripe.dart';
import 'package:jbig2/src/segments/region_segment_information.dart';
import 'package:jbig2/src/util/combination_operator.dart';
import 'package:jbig2/src/image/bitmaps.dart';

class JBIG2Page {
  final Map<int, SegmentHeader> segments = SplayTreeMap();
  final int pageNumber;
  final JBIG2Document document;

  Bitmap? pageBitmap;
  int finalHeight = 0;
  int finalWidth = 0;
  int resolutionX = 0;
  int resolutionY = 0;

  JBIG2Page(this.document, this.pageNumber);

  SegmentHeader? getSegment(int number) {
    SegmentHeader? s = segments[number];

    if (s != null) {
      return s;
    }

    return document.getGlobalSegment(number);
  }

  SegmentHeader? getPageInformationSegment() {
    for (SegmentHeader s in segments.values) {
      if (s.segmentType == 48) {
        return s;
      }
    }
    // print("Page information segment not found.");
    return null;
  }

  Bitmap getBitmap() {
    if (pageBitmap == null) {
      composePageBitmap();
    }
    return pageBitmap!;
  }

  void composePageBitmap() {
    if (pageNumber > 0) {
      SegmentHeader? pageInfoSeg = getPageInformationSegment();
      if (pageInfoSeg != null) {
        PageInformation pageInformation =
            pageInfoSeg.getSegmentData() as PageInformation;
        createPage(pageInformation);
        clearSegmentData();
      }
    }
  }

  void createPage(PageInformation pageInformation) {
    if (!pageInformation.isStriped || pageInformation.getHeight() != -1) {
      createNormalPage(pageInformation);
    } else {
      createStripedPage(pageInformation);
    }
  }

  void createNormalPage(PageInformation pageInformation) {
    pageBitmap =
        Bitmap(pageInformation.getWidth(), pageInformation.getHeight());

    // If default pixel value is not 0, byte will be filled with 0xff
    if (pageInformation.getDefaultPixelValue() != 0) {
      // Arrays.fill(pageBitmap.getByteArray(), (byte) 0xff);
      pageBitmap!.bitmap.fillRange(0, pageBitmap!.bitmap.length, 0xff);
    }

    for (SegmentHeader s in segments.values) {
      switch (s.segmentType) {
        case 6: // Immediate text region
        case 7: // Immediate lossless text region
        case 22: // Immediate halftone region
        case 23: // Immediate lossless halftone region
        case 38: // Immediate generic region
        case 39: // Immediate lossless generic region
        case 42: // Immediate generic refinement region
        case 43: // Immediate lossless generic refinement region
          final Region r = s.getSegmentData() as Region;
          final Bitmap regionBitmap = r.getRegionBitmap();

          if (fitsPage(pageInformation, regionBitmap)) {
            pageBitmap = regionBitmap;
          } else {
            final RegionSegmentInformation regionInfo = r.getRegionInfo();
            final CombinationOperator op = getCombinationOperator(
                pageInformation, regionInfo.getCombinationOperator());
            Bitmaps.blit(regionBitmap, pageBitmap!, regionInfo.getXLocation(),
                regionInfo.getYLocation(), op);
          }
          break;
      }
    }
  }

  bool fitsPage(PageInformation pageInformation, Bitmap regionBitmap) {
    return countRegions() == 1 &&
        pageInformation.getDefaultPixelValue() == 0 &&
        pageInformation.getWidth() == regionBitmap.width &&
        pageInformation.getHeight() == regionBitmap.height;
  }

  void createStripedPage(PageInformation pageInformation) {
    final List<SegmentData> pageStripes = collectPageStripes();

    pageBitmap = Bitmap(pageInformation.getWidth(), finalHeight);

    int startLine = 0;
    for (SegmentData sd in pageStripes) {
      if (sd is EndOfStripe) {
        startLine = sd.getLineNumber() + 1;
      } else {
        final Region r = sd as Region;
        final RegionSegmentInformation regionInfo = r.getRegionInfo();
        final CombinationOperator op = getCombinationOperator(
            pageInformation, regionInfo.getCombinationOperator());
        Bitmaps.blit(r.getRegionBitmap(), pageBitmap!,
            regionInfo.getXLocation(), startLine, op);
      }
    }
  }

  List<SegmentData> collectPageStripes() {
    final List<SegmentData> pageStripes = [];
    for (SegmentHeader s in segments.values) {
      switch (s.segmentType) {
        case 6: // Immediate text region
        case 7: // Immediate lossless text region
        case 22: // Immediate halftone region
        case 23: // Immediate lossless halftone region
        case 38: // Immediate generic region
        case 39: // Immediate lossless generic region
        case 42: // Immediate generic refinement region
        case 43: // Immediate lossless generic refinement region
          Region r = s.getSegmentData() as Region;
          pageStripes.add(r);
          break;

        case 50: // End of stripe
          EndOfStripe eos = s.getSegmentData() as EndOfStripe;
          pageStripes.add(eos);
          finalHeight = eos.getLineNumber() + 1;
          break;
      }
    }
    return pageStripes;
  }

  int countRegions() {
    int regionCount = 0;

    for (SegmentHeader s in segments.values) {
      switch (s.segmentType) {
        case 6: // Immediate text region
        case 7: // Immediate lossless text region
        case 22: // Immediate halftone region
        case 23: // Immediate lossless halftone region
        case 38: // Immediate generic region
        case 39: // Immediate lossless generic region
        case 42: // Immediate generic refinement region
        case 43: // Immediate lossless generic refinement region
          regionCount++;
      }
    }

    return regionCount;
  }

  CombinationOperator getCombinationOperator(
      PageInformation pi, CombinationOperator newOperator) {
    if (pi.isCombinationOperatorOverrideAllowed()) {
      return newOperator;
    } else {
      return pi.getCombinationOperator();
    }
  }

  void add(SegmentHeader segment) {
    segments[segment.segmentNr] = segment;
  }

  void clearSegmentData() {
    for (SegmentHeader s in segments.values) {
      s.cleanSegmentData();
    }
  }

  void clearPageData() {
    pageBitmap = null;
  }

  int getHeight() {
    if (finalHeight == 0) {
      SegmentHeader? pageInfoSeg = getPageInformationSegment();
      if (pageInfoSeg != null) {
        PageInformation pi = pageInfoSeg.getSegmentData() as PageInformation;
        if (pi.getHeight() == 0xffffffff) {
          getBitmap();
        } else {
          finalHeight = pi.getHeight();
        }
      }
    }
    return finalHeight;
  }

  int getWidth() {
    if (finalWidth == 0) {
      SegmentHeader? pageInfoSeg = getPageInformationSegment();
      if (pageInfoSeg != null) {
        PageInformation pi = pageInfoSeg.getSegmentData() as PageInformation;
        finalWidth = pi.getWidth();
      }
    }
    return finalWidth;
  }

  int getResolutionX() {
    if (resolutionX == 0) {
      SegmentHeader? pageInfoSeg = getPageInformationSegment();
      if (pageInfoSeg != null) {
        PageInformation pi = pageInfoSeg.getSegmentData() as PageInformation;
        resolutionX = pi.getResolutionX();
      }
    }
    return resolutionX;
  }

  int getResolutionY() {
    if (resolutionY == 0) {
      SegmentHeader? pageInfoSeg = getPageInformationSegment();
      if (pageInfoSeg != null) {
        PageInformation pi = pageInfoSeg.getSegmentData() as PageInformation;
        resolutionY = pi.getResolutionY();
      }
    }
    return resolutionY;
  }

  @override
  String toString() {
    return "JBIG2Page (Page number: $pageNumber)";
  }
}

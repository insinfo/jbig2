import 'dart:collection';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/segment_header.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/segment_data.dart';
import 'package:jbig2/src/segments/page_information.dart';
import 'package:jbig2/src/region.dart';
import 'package:jbig2/src/segments/end_of_stripe.dart';
import 'package:jbig2/src/segments/generic_refinement_region.dart';
import 'package:jbig2/src/segments/region_segment_information.dart';
import 'package:jbig2/src/util/rectangle.dart';
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

    /* 8.2 3) Fill the page buffer with the page's default pixel value. */
    fillDefaultPixelValue(pageInformation);

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
          /* 8.2 5) c) A refinement region referring to no other segment
           * refines the page buffer itself. */
          if (refinesThePageBuffer(s)) {
            refinePageBuffer(s.getSegmentData() as GenericRefinementRegion);
            break;
          }

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

  /// 8.2 3): a page buffer starts out filled with the default pixel value its
  /// page information segment declares (7.4.8.5).
  void fillDefaultPixelValue(PageInformation pageInformation) {
    if (pageInformation.getDefaultPixelValue() != 0) {
      pageBitmap!.bitmap.fillRange(0, pageBitmap!.bitmap.length, 0xff);
    }
  }

  /// True in the case of 8.2 5) c): an immediate generic refinement region
  /// segment that refers to no intermediate region, and so refines the part of
  /// the page buffer its region segment information field points at rather
  /// than an auxiliary buffer an intermediate region left behind.
  bool refinesThePageBuffer(SegmentHeader s) {
    if (s.segmentType != 42 && s.segmentType != 43) return false;
    for (final SegmentHeader referred in s.rtSegments) {
      switch (referred.segmentType) {
        case 4: // Intermediate text region
        case 20: // Intermediate halftone region
        case 36: // Intermediate generic region
        case 40: // Intermediate generic refinement region
          return false;
      }
    }
    return true;
  }

  /// 8.2 5) c): refines a rectangle of the page buffer in place.
  ///
  /// The reference bitmap is the part of the page the region covers, and the
  /// refined result replaces it. The page combination operator plays no part,
  /// because the standard says the refinement "replaces a part of the page
  /// buffer".
  void refinePageBuffer(GenericRefinementRegion region) {
    final RegionSegmentInformation regionInfo = region.getRegionInfo();
    final Rectangle roi = Rectangle(
        regionInfo.getXLocation(),
        regionInfo.getYLocation(),
        regionInfo.bitmapWidth,
        regionInfo.bitmapHeight);
    region.setPageAsReference(Bitmaps.extract(roi, pageBitmap!));
    Bitmaps.blit(region.getRegionBitmap(), pageBitmap!, roi.x, roi.y,
        CombinationOperator.REPLACE);
  }

  bool fitsPage(PageInformation pageInformation, Bitmap regionBitmap) {
    return countRegions() == 1 &&
        pageInformation.getDefaultPixelValue() == 0 &&
        pageInformation.getWidth() == regionBitmap.width &&
        pageInformation.getHeight() == regionBitmap.height;
  }

  /// 8.2 2): a page that left its height unknown (0xFFFFFFFF in 7.4.8.2) takes
  /// it from the end of stripe segments, which 7.4.9 defines as the Y
  /// coordinate of each stripe's last row.
  void createStripedPage(PageInformation pageInformation) {
    final List<SegmentData> pageStripes = collectPageStripes();

    if (finalHeight == 0) {
      // 7.4.9 requires at least one end of stripe segment on a page of unknown
      // height. Without one, fall back to the bottom of the lowest region so
      // the page is still usable instead of being zero rows tall.
      for (final SegmentData sd in pageStripes) {
        if (sd is Region) {
          final RegionSegmentInformation info = sd.getRegionInfo();
          final int bottom = info.getYLocation() + info.bitmapHeight;
          if (bottom > finalHeight) finalHeight = bottom;
        }
      }
    }

    pageBitmap = Bitmap(pageInformation.getWidth(), finalHeight);

    /* 8.2 3) Fill the page buffer with the page's default pixel value. */
    fillDefaultPixelValue(pageInformation);

    /* 8.2 5): every region goes to the location its own region segment
     * information field gives, stripe or no stripe. */
    for (SegmentData sd in pageStripes) {
      if (sd is EndOfStripe) continue;
      final Region r = sd as Region;
      final RegionSegmentInformation regionInfo = r.getRegionInfo();
      final CombinationOperator op = getCombinationOperator(
          pageInformation, regionInfo.getCombinationOperator());
      Bitmaps.blit(r.getRegionBitmap(), pageBitmap!, regionInfo.getXLocation(),
          regionInfo.getYLocation(), op);
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
        // Na referência este teste é `== 0xffffffff`, porque lá o literal é um
        // `int` de 32 bits e vale -1. Em Dart o mesmo literal vale
        // 4294967295, então a comparação tem de ser explícita.
        if (pi.getHeight() == -1) {
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

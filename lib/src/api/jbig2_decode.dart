import 'dart:typed_data';

import '../io/exceptions.dart';
import '../io/random_access_read_buffer.dart';
import '../jbig2_document.dart';
import '../jbig2_globals.dart';
import '../segments/page_information.dart';
import 'jbig2_exceptions.dart';
import 'jbig2_image.dart';

/// Limits and diagnostics for a decode.
class Jbig2DecodeOptions {
  /// Reject an image with more than this many pixels before allocating for it.
  final int? maxPixels;

  /// Reject an image whose width or height exceeds this, before allocating.
  final int? maxDimension;

  /// Receives non-fatal diagnostics. Nothing is ever printed.
  final void Function(String message)? onWarning;

  const Jbig2DecodeOptions({
    this.maxPixels,
    this.maxDimension,
    this.onWarning,
  });
}

/// The eight byte magic every standalone JBIG2 file starts with.
const List<int> jbig2FileHeader = [
  0x97,
  0x4A,
  0x42,
  0x32,
  0x0D,
  0x0A,
  0x1A,
  0x0A
];

/// True when [bytes] begins with the standalone JBIG2 file header.
///
/// An embedded stream, the form PDF's `/JBIG2Decode` filter carries, has no
/// header, so a false answer does not mean the bytes are not JBIG2.
bool isJbig2File(Uint8List bytes) {
  if (bytes.length < jbig2FileHeader.length) return false;
  for (var i = 0; i < jbig2FileHeader.length; i++) {
    if (bytes[i] != jbig2FileHeader[i]) return false;
  }
  return true;
}

/// Decodes a standalone JBIG2 file, or an embedded segment stream.
///
/// [page] is 1-based, as JBIG2 numbers its pages.
Jbig2Image decodeJbig2(
  Uint8List bytes, {
  int page = 1,
  Jbig2DecodeOptions options = const Jbig2DecodeOptions(),
}) {
  return _decode(bytes, null, page, options);
}

/// Decodes the segment stream a PDF `/JBIG2Decode` filter carries.
///
/// [globals] is the content of the `/JBIG2Globals` stream named by the image
/// dictionary's decode parms, when there is one. A PDF embedded stream always
/// holds exactly one page, numbered 1.
Jbig2Image decodeJbig2Embedded(
  Uint8List data, {
  Uint8List? globals,
  Jbig2DecodeOptions options = const Jbig2DecodeOptions(),
}) {
  return _decode(data, globals, 1, options);
}

/// Reads the dimensions, page count and resolution without decoding pixels.
Jbig2ImageInfo probeJbig2(Uint8List bytes, {Uint8List? globals, int page = 1}) {
  return _guard(() {
    final document = _document(bytes, globals);
    final pageCount = document.getAmountOfPages();
    final target = document.getPageOrNull(page);
    if (target == null) {
      throw Jbig2FormatException(
          'The stream has $pageCount page(s); page $page was requested.');
    }
    final header = target.getPageInformationSegment();
    if (header == null) {
      throw const Jbig2CorruptedException(
          'The page has no page information segment.');
    }
    final information = header.getSegmentData() as PageInformation;
    return Jbig2ImageInfo(
      width: information.getWidth(),
      height: information.getHeight(),
      pageCount: pageCount,
      xResolution: information.resolutionX,
      yResolution: information.resolutionY,
    );
  });
}

Jbig2Image _decode(
  Uint8List bytes,
  Uint8List? globals,
  int page,
  Jbig2DecodeOptions options,
) {
  return _guard(() {
    final document = _document(bytes, globals);
    final target = document.getPageOrNull(page);
    if (target == null) {
      throw Jbig2FormatException('The stream has no page $page.');
    }

    // Apply the budget from the declared size, before the bitmap is allocated.
    final header = target.getPageInformationSegment();
    if (header != null) {
      final information = header.getSegmentData() as PageInformation;
      _checkBudget(information.getWidth(), information.getHeight(), options);
    }

    final bitmap = target.getBitmap();
    _checkBudget(bitmap.width, bitmap.height, options);
    return Jbig2Image.fromBitmap(bitmap);
  });
}

void _checkBudget(int width, int height, Jbig2DecodeOptions options) {
  final maxDimension = options.maxDimension;
  if (maxDimension != null && (width > maxDimension || height > maxDimension)) {
    throw Jbig2BudgetException(
        'maxDimension', maxDimension, width > height ? width : height);
  }
  final maxPixels = options.maxPixels;
  if (maxPixels != null && width * height > maxPixels) {
    throw Jbig2BudgetException('maxPixels', maxPixels, width * height);
  }
}

JBIG2Document _document(Uint8List bytes, Uint8List? globals) {
  if (bytes.isEmpty) {
    throw const Jbig2FormatException('The input has no bytes.');
  }
  JBIG2Globals? parsed;
  if (globals != null && globals.isNotEmpty) {
    // Segments in the globals stream carry page association 0, so mapping it
    // as its own document collects them into that document's globals.
    parsed =
        JBIG2Document(RandomAccessReadBuffer.fromBytes(globals)).globalSegments;
  }
  return JBIG2Document(RandomAccessReadBuffer.fromBytes(bytes), parsed);
}

/// Translates the codec's internal failures into the public sealed hierarchy.
T _guard<T>(T Function() body) {
  try {
    return body();
  } on Jbig2Exception {
    rethrow;
  } on EofException catch (error) {
    throw Jbig2TruncatedException(error.message);
  } on IOException catch (error) {
    throw Jbig2CorruptedException(error.message);
  } on RangeError catch (error) {
    throw Jbig2CorruptedException('The stream reads outside its bounds: '
        '${error.message}');
  } on UnsupportedError catch (error) {
    throw Jbig2UnsupportedException(
        error.message?.toString() ?? 'unsupported feature');
  } on TypeError {
    // A segment resolving to the wrong data type means the stream disagrees
    // with the segment header that introduced it.
    throw const Jbig2CorruptedException(
        'A segment does not hold the data its header declares.');
  } on StateError catch (error) {
    throw Jbig2CorruptedException(error.message);
  } on FormatException catch (error) {
    throw Jbig2CorruptedException(error.message);
  }
}

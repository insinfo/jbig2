import 'dart:math';
import '../bitmap.dart';
import '../util/combination_operator.dart';
import '../util/rectangle.dart';

class Bitmaps {
  static Bitmap extract(Rectangle roi, Bitmap src) {
    final dst = Bitmap(roi.width, roi.height);

    final int upShift = roi.x & 0x07;
    final int downShift = 8 - upShift;
    int dstLineStartIdx = 0;

    final int padding = (8 - dst.width & 0x07);
    int srcLineStartIdx = src.getByteIndex(roi.x, roi.y);
    int srcLineEndIdx = src.getByteIndex(roi.x + roi.width - 1, roi.y);
    final bool usePadding = dst.rowStride == srcLineEndIdx + 1 - srcLineStartIdx;

    for (int y = roi.y; y < roi.maxY; y++) {
      int srcIdx = srcLineStartIdx;
      int dstIdx = dstLineStartIdx;

      if (srcLineStartIdx == srcLineEndIdx) {
        final int pixels = (src.getByte(srcIdx) << upShift) & 0xFF;
        dst.setByte(dstIdx, unpad(padding, pixels));
      } else if (upShift == 0) {
        for (int x = srcLineStartIdx; x <= srcLineEndIdx; x++) {
          int value = src.getByte(srcIdx++);

          if (x == srcLineEndIdx && usePadding) {
            value = unpad(padding, value);
          }

          dst.setByte(dstIdx++, value);
        }
      } else {
        copyLine(src, dst, upShift, downShift, padding, srcLineStartIdx, srcLineEndIdx, usePadding, srcIdx, dstIdx);
      }

      srcLineStartIdx += src.rowStride;
      srcLineEndIdx += src.rowStride;
      dstLineStartIdx += dst.rowStride;
    }

    return dst;
  }

  static void copyLine(Bitmap src, Bitmap dst, int sourceUpShift, int sourceDownShift, int padding,
      int firstSourceByteOfLine, int lastSourceByteOfLine, bool usePadding, int sourceOffset, int targetOffset) {
    for (int x = firstSourceByteOfLine; x < lastSourceByteOfLine; x++) {

      if (sourceOffset + 1 < src.getByteArray().length) {
        final bool isLastByte = x + 1 == lastSourceByteOfLine;
        int val1 = (src.getByte(sourceOffset++) << sourceUpShift) & 0xFF;
        int val2 = (src.getByte(sourceOffset) & 0xFF) >> sourceDownShift;
        int value = (val1 | val2) & 0xFF;

        if (isLastByte && !usePadding) {
          value = unpad(padding, value);
        }

        dst.setByte(targetOffset++, value);

        if (isLastByte && usePadding) {
          value = unpad(padding, ((src.getByte(sourceOffset) & 0xFF) << sourceUpShift) & 0xFF);
          dst.setByte(targetOffset, value);
        }

      } else {
        final int value = (src.getByte(sourceOffset++) << sourceUpShift) & 0xFF;
        dst.setByte(targetOffset++, value);
      }
    }
  }

  static int combineBytes(int value1, int value2, CombinationOperator op) {
    switch (op) {
      case CombinationOperator.OR:
        return (value2 | value1) & 0xff;
      case CombinationOperator.AND:
        return (value2 & value1) & 0xff;
      case CombinationOperator.XOR:
        return (value2 ^ value1) & 0xff;
      case CombinationOperator.XNOR:
        return ~(value1 ^ value2) & 0xff;
      case CombinationOperator.REPLACE:
        return value2;
    }
  }

  static void blit(Bitmap src, Bitmap dst, int x, int y,
      CombinationOperator combinationOperator) {
    int startLine = 0;
    int srcStartIdx = 0;
    int srcEndIdx = (src.rowStride - 1);

    // Ignore those parts of the source bitmap which would be placed outside the target bitmap.
    if (x < 0) {
      srcStartIdx = -x;
      x = 0;
    } else if (x + src.width > dst.width) {
      srcEndIdx -= (src.width + x - dst.width);
    }

    if (y < 0) {
      startLine = -y;
      y = 0;
      srcStartIdx += src.rowStride;
      srcEndIdx += src.rowStride;
    } else if (y + src.height > dst.height) {
      startLine = src.height + y - dst.height;
    }

    final int shiftVal1 = x & 0x07;
    final int shiftVal2 = 8 - shiftVal1;

    final int padding = src.width & 0x07;
    final int toShift = shiftVal2 - padding;

    final bool useShift = (shiftVal2 & 0x07) != 0;
    final bool specialCase =
        src.width <= ((srcEndIdx - srcStartIdx) << 3) + shiftVal2;

    final int dstStartIdx = dst.getByteIndex(x, y);

    final int lastLine = min(src.height, startLine + dst.height);

    if (!useShift) {
      blitUnshifted(src, dst, startLine, lastLine, dstStartIdx, srcStartIdx,
          srcEndIdx, combinationOperator);
    } else if (specialCase) {
      blitSpecialShifted(src, dst, startLine, lastLine, dstStartIdx,
          srcStartIdx, srcEndIdx, toShift, shiftVal1, shiftVal2,
          combinationOperator);
    } else {
      blitShifted(src, dst, startLine, lastLine, dstStartIdx, srcStartIdx,
          srcEndIdx, toShift, shiftVal1, shiftVal2, combinationOperator,
          padding);
    }
  }

  static void blitUnshifted(
      Bitmap src,
      Bitmap dst,
      int startLine,
      int lastLine,
      int dstStartIdx,
      int srcStartIdx,
      int srcEndIdx,
      CombinationOperator op) {
    for (int dstLine = startLine;
        dstLine < lastLine;
        dstLine++,
        dstStartIdx += dst.rowStride,
        srcStartIdx += src.rowStride,
        srcEndIdx += src.rowStride) {
      int dstIdx = dstStartIdx;

      // Go through the bytes in a line of the Symbol
      for (int srcIdx = srcStartIdx; srcIdx <= srcEndIdx; srcIdx++) {
        int oldByte = dst.getByte(dstIdx);
        int newByte = src.getByte(srcIdx);
        dst.setByte(dstIdx++, combineBytes(oldByte, newByte, op));
      }
    }
  }

  static void blitSpecialShifted(
      Bitmap src,
      Bitmap dst,
      int startLine,
      int lastLine,
      int dstStartIdx,
      int srcStartIdx,
      int srcEndIdx,
      int toShift,
      int shiftVal1,
      int shiftVal2,
      CombinationOperator op) {
    for (int dstLine = startLine;
        dstLine < lastLine;
        dstLine++,
        dstStartIdx += dst.rowStride,
        srcStartIdx += src.rowStride,
        srcEndIdx += src.rowStride) {
      int register = 0;
      int dstIdx = dstStartIdx;

      // Go through the bytes in a line of the Symbol
      for (int srcIdx = srcStartIdx; srcIdx <= srcEndIdx; srcIdx++) {
        int oldByte = dst.getByte(dstIdx);
        register = ((register | src.getByte(srcIdx)) << shiftVal2) & 0xffff; // Keep it within reasonable bounds, though int is 64bit
        int newByte = (register >> 8) & 0xff;

        if (srcIdx == srcEndIdx) {
          newByte = unpad(toShift, newByte);
        }

        dst.setByte(dstIdx++, combineBytes(oldByte, newByte, op));
        register <<= shiftVal1;
        register &= 0xffff; // Mask to simulate short behavior if needed, but here we just need bits
      }
    }
  }

  static void blitShifted(
      Bitmap src,
      Bitmap dst,
      int startLine,
      int lastLine,
      int dstStartIdx,
      int srcStartIdx,
      int srcEndIdx,
      int toShift,
      int shiftVal1,
      int shiftVal2,
      CombinationOperator op,
      int padding) {
    for (int dstLine = startLine;
        dstLine < lastLine;
        dstLine++,
        dstStartIdx += dst.rowStride,
        srcStartIdx += src.rowStride,
        srcEndIdx += src.rowStride) {
      int register = 0;
      int dstIdx = dstStartIdx;

      // Go through the bytes in a line of the symbol
      for (int srcIdx = srcStartIdx; srcIdx <= srcEndIdx; srcIdx++) {
        int oldByte = dst.getByte(dstIdx);
        register = ((register | src.getByte(srcIdx)) << shiftVal2) & 0xffff;

        int newByte = (register >> 8) & 0xff;
        dst.setByte(dstIdx++, combineBytes(oldByte, newByte, op));

        register <<= shiftVal1;
        register &= 0xffff;

        if (srcIdx == srcEndIdx) {
          newByte = (register >> (8 - shiftVal2)) & 0xff;

          if (padding != 0) {
            newByte = unpad(8 + toShift, newByte);
          }

          oldByte = dst.getByte(dstIdx);
          dst.setByte(dstIdx, combineBytes(oldByte, newByte, op));
        }
      }
    }
  }

  static int unpad(int padding, int value) {
    // Java: (byte) (value >> padding << padding)
    // If value is 0-255.
    // If padding is positive.
    // In Java, if value is negative (e.g. 0xFF = -1), >> propagates sign.
    // But here we work with 0-255.
    // We want to clear the lower 'padding' bits.
    // (value >> padding) << padding works for unsigned too.
    return ((value >> padding) << padding) & 0xff;
  }
}

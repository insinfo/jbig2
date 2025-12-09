import 'dart:typed_data';
import 'dart:math';

import '../../bitmap.dart';

import '../../io/random_access_read.dart';
import 'mmr_constants.dart';

class MMRDecompressor {
  int width;
  int height;
  late RunData data;

  static const int FIRST_LEVEL_TABLE_SIZE = 8;
  static const int FIRST_LEVEL_TABLE_MASK = (1 << FIRST_LEVEL_TABLE_SIZE) - 1;
  static const int SECOND_LEVEL_TABLE_SIZE = 5;
  static const int SECOND_LEVEL_TABLE_MASK = (1 << SECOND_LEVEL_TABLE_SIZE) - 1;

  static List<Code?>? whiteTable;
  static List<Code?>? blackTable;
  static List<Code?>? modeTable;

  MMRDecompressor(this.width, this.height, RandomAccessRead stream) {
    data = RunData(stream);
    initTables();
  }

  static void initTables() {
    if (whiteTable == null) {
      whiteTable = createLittleEndianTable(MMRConstants.WhiteCodes);
      blackTable = createLittleEndianTable(MMRConstants.BlackCodes);
      modeTable = createLittleEndianTable(MMRConstants.ModeCodes);
    }
  }

  Bitmap uncompress() {
    final Bitmap result = Bitmap(width, height);

    List<int> currentOffsets = List.filled(width + 5, 0);
    List<int> referenceOffsets = List.filled(width + 5, 0);
    referenceOffsets[0] = width;
    int refRunLength = 1;

    int count = 0;

    for (int line = 0; line < height; line++) {
      count = uncompress2D(data, referenceOffsets, refRunLength, currentOffsets, width);

      if (count == MMRConstants.EOF) {
        break;
      }

      if (count > 0) {
        fillBitmap(result, line, currentOffsets, count);
      }

      // Swap lines
      List<int> tempOffsets = referenceOffsets;
      referenceOffsets = currentOffsets;
      currentOffsets = tempOffsets;
      refRunLength = count;
    }

    detectAndSkipEOL();

    data.align();

    return result;
  }

  void detectAndSkipEOL() {
    while (true) {
      Code? code = data.uncompressGetCode(modeTable!);
      if (code != null && code.runLength == MMRConstants.EOL) {
        data.offset += code.bitLength;
      } else {
        break;
      }
    }
  }

  void fillBitmap(Bitmap result, int line, List<int> currentOffsets, int count) {
    int x = 0;
    int targetByte = result.getByteIndex(0, line);
    int targetByteValue = 0;
    for (int index = 0; index < count; index++) {
      final int offset = currentOffsets[index];
      int value;

      if ((index & 1) == 0) {
        value = 0;
      } else {
        value = 1;
      }

      while (x < offset) {
        targetByteValue = (targetByteValue << 1) | value;
        x++;

        if ((x & 7) == 0) {
          result.setByte(targetByte++, targetByteValue);
          targetByteValue = 0;
        }
      }
    }

    if ((x & 7) != 0) {
      targetByteValue <<= 8 - (x & 7);
      result.setByte(targetByte, targetByteValue);
    }
  }

  int uncompress2D(RunData runData, List<int> referenceOffsets, int refRunLength, List<int> runOffsets, int width) {
    int referenceBufferOffset = 0;
    int currentBufferOffset = 0;
    int currentLineBitPosition = 0;

    bool whiteRun = true; // Always start with a white run
    Code? code; // Storage var for current code being processed

    referenceOffsets[refRunLength] = referenceOffsets[refRunLength + 1] = width;
    referenceOffsets[refRunLength + 2] = referenceOffsets[refRunLength + 3] = width + 1;

    try {
      decodeLoop:
      while (currentLineBitPosition < width) {
        // Get the mode code
        code = runData.uncompressGetCode(modeTable!);

        if (code == null) {
          runData.offset++;
          break decodeLoop;
        }

        // Add the code length to the bit offset
        runData.offset += code.bitLength;

        switch (code.runLength) {
          case MMRConstants.CODE_V0:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset];
            break;

          case MMRConstants.CODE_VR1:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] + 1;
            break;

          case MMRConstants.CODE_VL1:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] - 1;
            break;

          case MMRConstants.CODE_H:
            for (int ever = 1; ever > 0;) {
              code = runData.uncompressGetCode(whiteRun == true ? whiteTable! : blackTable!);

              if (code == null) break decodeLoop;

              runData.offset += code.bitLength;
              if (code.runLength < 64) {
                if (code.runLength < 0) {
                  runOffsets[currentBufferOffset++] = currentLineBitPosition;
                  code = null;
                  break decodeLoop;
                }
                currentLineBitPosition += code.runLength;
                runOffsets[currentBufferOffset++] = currentLineBitPosition;
                break;
              }
              currentLineBitPosition += code.runLength;
            }

            final int firstHalfBitPos = currentLineBitPosition;
            for (int ever1 = 1; ever1 > 0;) {
              code = runData.uncompressGetCode(whiteRun != true ? whiteTable! : blackTable!);
              if (code == null) break decodeLoop;

              runData.offset += code.bitLength;
              if (code.runLength < 64) {
                if (code.runLength < 0) {
                  runOffsets[currentBufferOffset++] = currentLineBitPosition;
                  break decodeLoop;
                }
                currentLineBitPosition += code.runLength;
                // don't generate 0-length run at EOL for cases where the line ends in an H-run.
                if (currentLineBitPosition < width || currentLineBitPosition != firstHalfBitPos) {
                  runOffsets[currentBufferOffset++] = currentLineBitPosition;
                }
                break;
              }
              currentLineBitPosition += code.runLength;
            }

            while (currentLineBitPosition < width && referenceOffsets[referenceBufferOffset] <= currentLineBitPosition) {
              referenceBufferOffset += 2;
            }
            continue decodeLoop;

          case MMRConstants.CODE_P:
            referenceBufferOffset++;
            currentLineBitPosition = referenceOffsets[referenceBufferOffset++];
            continue decodeLoop;

          case MMRConstants.CODE_VR2:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] + 2;
            break;

          case MMRConstants.CODE_VL2:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] - 2;
            break;

          case MMRConstants.CODE_VR3:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] + 3;
            break;

          case MMRConstants.CODE_VL3:
            currentLineBitPosition = referenceOffsets[referenceBufferOffset] - 3;
            break;

          case MMRConstants.EOL:
          default:
            print("Should not happen!");
            // Possibly MMR Decoded
            if (runData.offset == 12 && code.runLength == MMRConstants.EOL) {
              runData.offset = 0;
              uncompress1D(runData, referenceOffsets, width);
              runData.offset++;
              uncompress1D(runData, runOffsets, width);
              int retCode = uncompress1D(runData, referenceOffsets, width);
              runData.offset++;
              return retCode;
            }
            currentLineBitPosition = width;
            continue decodeLoop;
        }

        // Only vertical modes get this far
        if (currentLineBitPosition <= width) {
          whiteRun = !whiteRun;

          runOffsets[currentBufferOffset++] = currentLineBitPosition;

          if (referenceBufferOffset > 0) {
            referenceBufferOffset--;
          } else {
            referenceBufferOffset++;
          }

          while (currentLineBitPosition < width && referenceOffsets[referenceBufferOffset] <= currentLineBitPosition) {
            referenceBufferOffset += 2;
          }
        }
      }
    } catch (t) {
      StringBuffer strBuf = StringBuffer();
      strBuf.write("whiteRun           = ");
      strBuf.write(whiteRun);
      strBuf.write("\n");
      strBuf.write("code               = ");
      strBuf.write(code);
      strBuf.write("\n");
      strBuf.write("refOffset          = ");
      strBuf.write(referenceBufferOffset);
      strBuf.write("\n");
      strBuf.write("curOffset          = ");
      strBuf.write(currentBufferOffset);
      strBuf.write("\n");
      strBuf.write("bitPos             = ");
      strBuf.write(currentLineBitPosition);
      strBuf.write("\n");
      strBuf.write("runData.offset = ");
      strBuf.write(runData.offset);
      strBuf.write(" ( byte:");
      strBuf.write(runData.offset ~/ 8);
      strBuf.write(", bit:");
      strBuf.write(runData.offset & 0x07);
      strBuf.write(" )");

      print(strBuf.toString());

      return MMRConstants.EOF;
    }

    if (runOffsets[currentBufferOffset] != width) {
      runOffsets[currentBufferOffset] = width;
    }

    if (code == null) {
      return MMRConstants.EOL;
    }
    return currentBufferOffset;
  }

  int uncompress1D(RunData runData, List<int> runOffsets, int width) {
    bool whiteRun = true;
    int iBitPos = 0;
    Code? code;
    int refOffset = 0;

    loop:
    while (iBitPos < width) {
      while (true) {
        if (whiteRun) {
          code = runData.uncompressGetCode(whiteTable!);
        } else {
          code = runData.uncompressGetCode(blackTable!);
        }

        if (code == null) break loop;

        runData.offset += code.bitLength;

        if (code.runLength < 0) {
          break loop;
        }

        iBitPos += code.runLength;

        if (code.runLength < 64) {
          whiteRun = !whiteRun;
          runOffsets[refOffset++] = iBitPos;
          break;
        }
      }
    }

    if (runOffsets[refOffset] != width) {
      runOffsets[refOffset] = width;
    }

    return code != null && code.runLength != MMRConstants.EOL ? refOffset : MMRConstants.EOL;
  }

  static List<Code?> createLittleEndianTable(List<List<int>> codes) {
    final List<Code?> firstLevelTable = List.filled(FIRST_LEVEL_TABLE_MASK + 1, null);
    for (int i = 0; i < codes.length; i++) {
      final Code code = Code(codes[i]);

      if (code.bitLength <= FIRST_LEVEL_TABLE_SIZE) {
        final int variantLength = FIRST_LEVEL_TABLE_SIZE - code.bitLength;
        final int baseWord = code.codeWord << variantLength;

        for (int variant = (1 << variantLength) - 1; variant >= 0; variant--) {
          final int index = baseWord | variant;
          firstLevelTable[index] = code;
        }
      } else {
        // init second level table
        final int firstLevelIndex = code.codeWord >>> (code.bitLength - FIRST_LEVEL_TABLE_SIZE);

        if (firstLevelTable[firstLevelIndex] == null) {
          final Code firstLevelCode = Code([0, 0, 0]); // Dummy
          firstLevelCode.subTable = List.filled(SECOND_LEVEL_TABLE_MASK + 1, null);
          firstLevelTable[firstLevelIndex] = firstLevelCode;
        }

        // fill second level table
        if (code.bitLength <= FIRST_LEVEL_TABLE_SIZE + SECOND_LEVEL_TABLE_SIZE) {
          final List<Code?> secondLevelTable = firstLevelTable[firstLevelIndex]!.subTable!;
          final int variantLength = FIRST_LEVEL_TABLE_SIZE + SECOND_LEVEL_TABLE_SIZE - code.bitLength;
          final int baseWord = (code.codeWord << variantLength) & SECOND_LEVEL_TABLE_MASK;

          for (int variant = (1 << variantLength) - 1; variant >= 0; variant--) {
            secondLevelTable[baseWord | variant] = code;
          }
        } else {
          throw ArgumentError("Code table overflow in MMRDecompressor");
        }
      }
    }
    return firstLevelTable;
  }
}

class RunData {
  static const int MAX_RUN_DATA_BUFFER = 1024 << 7; // 1024 * 128
  static const int MIN_RUN_DATA_BUFFER = 3; // min. bytes to decompress
  static const int CODE_OFFSET = 24;

  RandomAccessRead stream;

  int offset = 0;
  int lastOffset = 0;
  int lastCode = 0;

  late Uint8List buffer;
  int bufferBase = 0;
  int bufferTop = 0;

  RunData(this.stream) {
    offset = 0;
    lastOffset = 1;

    try {
      int len = stream.length;

      len = min(max(MIN_RUN_DATA_BUFFER, len), MAX_RUN_DATA_BUFFER);

      buffer = Uint8List(len);
      fillBuffer(0);
    } catch (e) {
      buffer = Uint8List(10);
      print(e);
    }
  }

  Code? uncompressGetCode(List<Code?> table) {
    return uncompressGetCodeLittleEndian(table);
  }

  Code? uncompressGetCodeLittleEndian(List<Code?> table) {
    final int code = uncompressGetNextCodeLittleEndian() & 0xffffff;
    Code? result = table[code >> (CODE_OFFSET - MMRDecompressor.FIRST_LEVEL_TABLE_SIZE)];

    // perform second-level lookup
    if (result != null && result.subTable != null) {
      result = result.subTable![(code >> (CODE_OFFSET - MMRDecompressor.FIRST_LEVEL_TABLE_SIZE - MMRDecompressor.SECOND_LEVEL_TABLE_SIZE)) &
          MMRDecompressor.SECOND_LEVEL_TABLE_MASK];
    }

    return result;
  }

  int uncompressGetNextCodeLittleEndian() {
    try {
      // the number of bits to fill (offset difference)
      int bitsToFill = offset - lastOffset;

      // check whether we can refill, or need to fill in absolute mode
      if (bitsToFill < 0 || bitsToFill > 24) {
        // refill at absolute offset
        int byteOffset = (offset >> 3) - bufferBase; // offset>>3 is equivalent to offset/8

        if (byteOffset >= bufferTop) {
          byteOffset += bufferBase;
          fillBuffer(byteOffset);
          byteOffset -= bufferBase;
        }

        lastCode = (buffer[byteOffset] & 0xff) << 16 | (buffer[byteOffset + 1] & 0xff) << 8 | (buffer[byteOffset + 2] & 0xff);

        int bitOffset = offset & 7; // equivalent to offset%8
        lastCode <<= bitOffset;
      } else {
        // the offset to the next byte boundary as seen from the last offset
        int bitOffset = lastOffset & 7;
        final int avail = 7 - bitOffset;

        // check whether there are enough bits in the "queue"
        if (bitsToFill <= avail) {
          lastCode <<= bitsToFill;
        } else {
          int byteOffset = (lastOffset >> 3) + 3 - bufferBase;

          if (byteOffset >= bufferTop) {
            byteOffset += bufferBase;
            fillBuffer(byteOffset);
            byteOffset -= bufferBase;
          }

          bitOffset = 8 - bitOffset;
          do {
            lastCode <<= bitOffset;
            lastCode |= buffer[byteOffset] & 0xff;
            bitsToFill -= bitOffset;
            byteOffset++;
            bitOffset = 8;
          } while (bitsToFill >= 8);

          lastCode <<= bitsToFill; // shift the rest
        }
      }
      lastOffset = offset;

      return lastCode;
    } catch (e) {
      throw RangeError("Corrupted RLE data caused by an IOException while reading raw data: $e");
    }
  }

  void fillBuffer(int byteOffset) {
    bufferBase = byteOffset;
    try {
      stream.seek(byteOffset);
      // bufferTop = stream.read(buffer); // RandomAccessRead doesn't have read(buffer) returning count directly like Java InputStream
      // It has readBuffer(buffer)
      bufferTop = stream.readBuffer(buffer);
    } catch (e) {
      // you never know which kind of EOF will kick in
      bufferTop = -1;
    }
    // check filling degree
    if (bufferTop > -1 && bufferTop < 3) {
      // CK: if filling degree is too small,
      // smoothly fill up to the next three bytes or substitute with with
      // empty bytes
      int read = 0;
      while (bufferTop < 3) {
        try {
          read = stream.read();
        } catch (e) {
          read = -1;
        }
        buffer[bufferTop++] = read == -1 ? 0 : (read & 0xff);
      }
    }
    
    // leave some room, in order to save a few tests in the calling code
    bufferTop -= 3;

    if (bufferTop < 0) {
      // if we're at EOF, just supply zero-bytes
      buffer.fillRange(0, buffer.length, 0);
      bufferTop = buffer.length - 3;
    }
  }

  void align() {
    offset = ((offset + 7) >> 3) << 3;
  }
}

class Code {
  List<Code?>? subTable;

  final int bitLength;
  final int codeWord;
  final int runLength;

  Code(List<int> codeData)
      : bitLength = codeData[0],
        codeWord = codeData[1],
        runLength = codeData[2];

  @override
  String toString() {
    return "$bitLength/$codeWord/$runLength";
  }

  @override
  bool operator ==(Object other) {
    return (other is Code) && other.bitLength == bitLength && other.codeWord == codeWord && other.runLength == runLength;
  }
  
  @override
  int get hashCode => Object.hash(bitLength, codeWord, runLength);
}

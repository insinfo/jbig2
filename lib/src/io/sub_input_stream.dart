import 'dart:typed_data';
import 'random_access_read.dart';

class SubInputStream {
  final RandomAccessRead wrappedStream;
  final int offset;
  final int length;

  int _bitOffset = 0;
  int _streamPos = 0; // Relative position

  SubInputStream(this.wrappedStream, this.offset, this.length);

  int read() {
    if (_streamPos >= length) {
      return -1;
    }

    // Synchronize position
    if (wrappedStream.position != offset + _streamPos) {
      wrappedStream.seek(offset + _streamPos);
    }

    int val = wrappedStream.read();
    if (val != -1) {
      _streamPos++;
      _bitOffset = 0; // Reset bit offset on byte read
    }
    return val;
  }

  int readBit() {
    if (_streamPos >= length && _bitOffset == 0) {
      return -1; // EOF
    }

    // Ensure we are at the right byte
    if (wrappedStream.position != offset + _streamPos) {
      wrappedStream.seek(offset + _streamPos);
    }

    // We need to peek the current byte without advancing if we are in the middle of it
    // But RandomAccessRead doesn't support peeking at current position easily without read+seek back
    // Or we can cache the current byte.
    
    // Let's read the byte.
    int val = wrappedStream.peek();
    if (val == -1) return -1;

    int bit = (val >> (7 - _bitOffset)) & 1;
    
    _bitOffset++;
    if (_bitOffset == 8) {
      _bitOffset = 0;
      wrappedStream.read(); // Consume the byte
      _streamPos++;
    }
    
    return bit;
  }

  int readBits(int numBits) {
    if (numBits == 0) return 0;
    if (numBits < 0 || numBits > 64) throw ArgumentError("numBits must be between 0 and 64");
    
    int result = 0;
    for (int i = 0; i < numBits; i++) {
      int bit = readBit();
      if (bit == -1) {
        throw Exception("EOF reached while reading bits");
      }
      result = (result << 1) | bit;
    }
    return result;
  }

  void seek(int pos) {
    if (pos < 0 || pos > length) {
      throw RangeError("Position out of bounds");
    }
    _streamPos = pos;
    _bitOffset = 0;
    wrappedStream.seek(offset + pos);
  }

  int getStreamPosition() {
    return _streamPos;
  }
  
  int getBitOffset() {
    return _bitOffset;
  }

  void skipBits() {
    if (_bitOffset != 0) {
      _bitOffset = 0;
      _streamPos++;
      wrappedStream.read(); // Consume the partial byte
    }
  }
  
  int available() {
      return length - _streamPos;
  }
  
  void readFully(Uint8List buffer) {
      int len = buffer.length;
      if (_streamPos + len > length) {
          throw Exception("EOF");
      }
      if (wrappedStream.position != offset + _streamPos) {
          wrappedStream.seek(offset + _streamPos);
      }
      wrappedStream.readFully(buffer);
      _streamPos += len;
      _bitOffset = 0;
  }
}

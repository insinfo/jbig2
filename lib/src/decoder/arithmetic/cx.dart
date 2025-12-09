import 'dart:typed_data';

class CX {
  int index;

  final Uint8List cxList;
  final Uint8List mpsList;

  CX(int size, this.index)
      : cxList = Uint8List(size),
        mpsList = Uint8List(size);

  int cx() {
    return cxList[index] & 0x7f;
  }

  void setCx(int value) {
    cxList[index] = value & 0x7f;
  }

  int mps() {
    return mpsList[index];
  }

  void toggleMps() {
    mpsList[index] ^= 1;
  }

  int getIndex() {
    return index;
  }

  void setIndex(int index) {
    this.index = index;
  }
}

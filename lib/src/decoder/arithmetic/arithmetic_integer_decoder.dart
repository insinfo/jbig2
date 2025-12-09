import 'package:jbig2/src/decoder/arithmetic/arithmetic_decoder.dart';
import 'package:jbig2/src/decoder/arithmetic/cx.dart';

class ArithmeticIntegerDecoder {
  final ArithmeticDecoder decoder;

  int prev = 0;

  ArithmeticIntegerDecoder(this.decoder);

  int decode(CX? cxIAx) {
    int v = 0;
    int d, s;

    int bitsToRead;
    int offset;

    CX cx = cxIAx ?? CX(512, 1);

    prev = 1;

    cx.setIndex(prev);
    s = decoder.decode(cx);
    setPrev(s);

    cx.setIndex(prev);
    d = decoder.decode(cx);
    setPrev(d);

    if (d == 1) {
      cx.setIndex(prev);
      d = decoder.decode(cx);
      setPrev(d);

      if (d == 1) {
        cx.setIndex(prev);
        d = decoder.decode(cx);
        setPrev(d);

        if (d == 1) {
          cx.setIndex(prev);
          d = decoder.decode(cx);
          setPrev(d);

          if (d == 1) {
            cx.setIndex(prev);
            d = decoder.decode(cx);
            setPrev(d);

            if (d == 1) {
              bitsToRead = 32;
              offset = 4436;
            } else {
              bitsToRead = 12;
              offset = 340;
            }
          } else {
            bitsToRead = 8;
            offset = 84;
          }
        } else {
          bitsToRead = 6;
          offset = 20;
        }
      } else {
        bitsToRead = 4;
        offset = 4;
      }
    } else {
      bitsToRead = 2;
      offset = 0;
    }

    for (int i = 0; i < bitsToRead; i++) {
      cx.setIndex(prev);
      d = decoder.decode(cx);
      setPrev(d);
      v = (v << 1) | d;
    }

    v += offset;

    if (s == 0) {
      return v;
    } else if (s == 1 && v > 0) {
      return -v;
    }

    return 9223372036854775807;
  }

  void setPrev(int bit) {
    if (prev < 256) {
      prev = ((prev << 1) | bit) & 0x1ff;
    } else {
      prev = ((((prev << 1) | bit) & 511) | 256) & 0x1ff;
    }
  }

  int decodeIAID(CX cxIAID, int symCodeLen) {
    // A.3 1)
    prev = 1;

    // A.3 2)
    for (int i = 0; i < symCodeLen; i++) {
      cxIAID.setIndex(prev);
      prev = (prev << 1) | decoder.decode(cxIAID);
    }

    // A.3 3) & 4)
    return (prev - (1 << symCodeLen));
  }
}

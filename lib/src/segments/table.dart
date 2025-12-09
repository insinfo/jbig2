import '../segment_data.dart';
import '../segment_header.dart';
import '../io/sub_input_stream.dart';

class Table implements SegmentData {
  late SubInputStream _subInputStream;

  int _htOutOfBand = 0;
  int _htPS = 0;
  int _htRS = 0;
  int _htLow = 0;
  int _htHigh = 0;

  void _parseHeader() {
    int bit;

    /* Bit 7 */
    if ((bit = _subInputStream.readBit()) == 1) {
      throw FormatException("B.2.1 Code table flags: Bit 7 must be zero, but was $bit");
    }

    /* Bit 4-6 */
    _htRS = (_subInputStream.readBits(3) + 1) & 0xf;

    /* Bit 1-3 */
    _htPS = (_subInputStream.readBits(3) + 1) & 0xf;

    /* Bit 0 */
    _htOutOfBand = _subInputStream.readBit();

    _htLow = _toSigned32(_subInputStream.readBits(32));
    _htHigh = _toSigned32(_subInputStream.readBits(32));
  }

  int _toSigned32(int val) {
    if (val >= 0x80000000) {
      return val - 0x100000000;
    }
    return val;
  }

  @override
  void init(SegmentHeader? header, SubInputStream sis) {
    _subInputStream = sis;
    _parseHeader();
  }

  int get htOOB => _htOutOfBand;
  int get htPS => _htPS;
  int get htRS => _htRS;
  int get htLow => _htLow;
  int get htHigh => _htHigh;
  SubInputStream get subInputStream => _subInputStream;
}

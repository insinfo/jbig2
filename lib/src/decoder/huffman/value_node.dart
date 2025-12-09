import '../../io/sub_input_stream.dart';
import 'huffman_table.dart';
import 'node.dart';

class ValueNode extends Node {
  late final int _rangeLen;
  late final int _rangeLow;
  late final bool _isLowerRange;

  ValueNode(Code c) {
    _rangeLen = c.rangeLength;
    _rangeLow = c.rangeLow;
    _isLowerRange = c.isLowerRange;
  }

  @override
  int decode(SubInputStream iis) {
    if (_isLowerRange) {
      /* B.4 4) */
      return (_rangeLow - iis.readBits(_rangeLen));
    } else {
      /* B.4 5) */
      return _rangeLow + iis.readBits(_rangeLen);
    }
  }

  static String bitPattern(int v, int len) {
    final result = List<String>.filled(len, '');
    for (int i = 1; i <= len; i++) {
      result[i - 1] = (v >> (len - i) & 1) != 0 ? '1' : '0';
    }

    return result.join();
  }
}

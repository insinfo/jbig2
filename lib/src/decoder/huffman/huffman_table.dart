import 'dart:math';

import '../../io/sub_input_stream.dart';
import 'internal_node.dart';
import 'value_node.dart';

class Code {
  final int prefixLength;
  final int rangeLength;
  final int rangeLow;
  final bool isLowerRange;
  int code = -1;

  Code(this.prefixLength, this.rangeLength, this.rangeLow, this.isLowerRange);

  @override
  String toString() {
    return '${code != -1 ? ValueNode.bitPattern(code, prefixLength) : "?"}/$prefixLength/$rangeLength/$rangeLow';
  }
}

abstract class HuffmanTable {
  final InternalNode _rootNode = InternalNode();

  void initTree(List<Code> codeTable) {
    preprocessCodes(codeTable);

    for (var c in codeTable) {
      _rootNode.append(c);
    }
  }

  int decode(SubInputStream iis) {
    return _rootNode.decode(iis);
  }

  @override
  String toString() {
    return '$_rootNode\n';
  }

  static String codeTableToString(List<Code> codeTable) {
    final sb = StringBuffer();

    for (var c in codeTable) {
      sb.writeln(c.toString());
    }

    return sb.toString();
  }

  void preprocessCodes(List<Code> codeTable) {
    /* Annex B.3 1) - build the histogram */
    int maxPrefixLength = 0;

    for (var c in codeTable) {
      maxPrefixLength = max(maxPrefixLength, c.prefixLength);
    }

    final lenCount = List<int>.filled(maxPrefixLength + 1, 0);
    for (var c in codeTable) {
      lenCount[c.prefixLength]++;
    }

    int curCode;
    final firstCode = List<int>.filled(lenCount.length + 1, 0);
    lenCount[0] = 0;

    /* Annex B.3 3) */
    for (int curLen = 1; curLen < lenCount.length; curLen++) {
      firstCode[curLen] = (firstCode[curLen - 1] + (lenCount[curLen - 1]) << 1);
      curCode = firstCode[curLen];
      for (var code in codeTable) {
        if (code.prefixLength == curLen) {
          code.code = curCode;
          curCode++;
        }
      }
    }

    // if (JBIG2ImageReader.DEBUG)
    //   print(codeTableToString(codeTable));
  }
}

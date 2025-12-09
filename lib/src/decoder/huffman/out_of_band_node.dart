import '../../io/sub_input_stream.dart';
import 'huffman_table.dart';
import 'node.dart';

class OutOfBandNode extends Node {
  OutOfBandNode(Code c);

  @override
  int decode(SubInputStream iis) {
    return 9223372036854775807; // Long.MAX_VALUE in Java (64-bit signed)
  }
}

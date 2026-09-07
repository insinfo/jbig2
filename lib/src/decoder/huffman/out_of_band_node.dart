import '../../io/sub_input_stream.dart';
import 'huffman_table.dart';
import 'node.dart';

class OutOfBandNode extends Node {
  OutOfBandNode(Code c);

  @override
  int decode(SubInputStream iis) {
    return 0x1fffffffffffff; // Sentinela OOB exato também em JavaScript.
  }
}

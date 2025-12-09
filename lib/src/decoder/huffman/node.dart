import '../../io/sub_input_stream.dart';

abstract class Node {
  int decode(SubInputStream iis);
}

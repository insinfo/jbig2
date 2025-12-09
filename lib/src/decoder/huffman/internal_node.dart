import '../../io/sub_input_stream.dart';
import 'huffman_table.dart';
import 'node.dart';
import 'out_of_band_node.dart';
import 'value_node.dart';

class InternalNode extends Node {
  final int _depth;
  Node? _zero;
  Node? _one;

  InternalNode([this._depth = 0]);

  void append(Code c) {
    // ignore unused codes
    if (c.prefixLength == 0) return;

    int shift = c.prefixLength - 1 - _depth;

    if (shift < 0) {
      throw ArgumentError("Negative shifting is not possible.");
    }

    int bit = (c.code >> shift) & 1;
    if (shift == 0) {
      if (c.rangeLength == -1) {
        // the child will be a OutOfBand
        if (bit == 1) {
          if (_one != null) {
            throw StateError("already have a OOB for $c");
          }
          _one = OutOfBandNode(c);
        } else {
          if (_zero != null) {
            throw StateError("already have a OOB for $c");
          }
          _zero = OutOfBandNode(c);
        }
      } else {
        // the child will be a ValueNode
        if (bit == 1) {
          if (_one != null) {
            throw StateError("already have a ValueNode for $c");
          }
          _one = ValueNode(c);
        } else {
          if (_zero != null) {
            throw StateError("already have a ValueNode for $c");
          }
          _zero = ValueNode(c);
        }
      }
    } else {
      // the child will be an InternalNode
      if (bit == 1) {
        if (_one == null) {
          _one = InternalNode(_depth + 1);
        }
        (_one as InternalNode).append(c);
      } else {
        if (_zero == null) {
          _zero = InternalNode(_depth + 1);
        }
        (_zero as InternalNode).append(c);
      }
    }
  }

  @override
  int decode(SubInputStream iis) {
    int b = iis.readBit();
    Node? n = b == 0 ? _zero : _one;
    if (n == null) {
      throw StateError("Incomplete Huffman tree or invalid data");
    }
    return n.decode(iis);
  }

  @override
  String toString() {
    final sb = StringBuffer("\n");

    _pad(sb);
    sb.writeln("0: $_zero");
    _pad(sb);
    sb.writeln("1: $_one");

    return sb.toString();
  }

  void _pad(StringBuffer sb) {
    for (int i = 0; i < _depth; i++) {
      sb.write("   ");
    }
  }
}

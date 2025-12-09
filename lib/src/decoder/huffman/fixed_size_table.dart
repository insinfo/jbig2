import 'huffman_table.dart';

class FixedSizeTable extends HuffmanTable {
  FixedSizeTable(List<Code> runCodeTable) {
    initTree(runCodeTable);
  }
}

import '../../segments/table.dart';
import 'huffman_table.dart';

class EncodedTable extends HuffmanTable {
  final Table _table;

  EncodedTable(this._table) {
    _parseTable();
  }

  void _parseTable() {
    final sis = _table.subInputStream;
    final codeTable = <Code>[];

    int prefLen, rangeLen, rangeLow;
    int curRangeLow = _table.htLow;

    /* Annex B.2 5) - decode table lines */
    while (curRangeLow < _table.htHigh) {
      prefLen = sis.readBits(_table.htPS);
      rangeLen = sis.readBits(_table.htRS);
      rangeLow = curRangeLow;

      codeTable.add(Code(prefLen, rangeLen, rangeLow, false));

      curRangeLow += 1 << rangeLen;
    }

    /* Annex B.2 6) */
    prefLen = sis.readBits(_table.htPS);

    /*
     * Annex B.2 7) - lower range table line
     */
    rangeLen = 32;
    rangeLow = _table.htHigh - 1;
    codeTable.add(Code(prefLen, rangeLen, rangeLow, true));

    /* Annex B.2 8) */
    prefLen = sis.readBits(_table.htPS);

    /* Annex B.2 9) - upper range table line */
    rangeLen = 32;
    rangeLow = _table.htHigh;
    codeTable.add(Code(prefLen, rangeLen, rangeLow, false));

    /* Annex B.2 10) - out-of-band table line */
    if (_table.htOOB == 1) {
      prefLen = sis.readBits(_table.htPS);
      codeTable.add(Code(prefLen, -1, -1, false));
    }

    initTree(codeTable);
  }
}

import 'package:test/test.dart';
import 'package:jbig2/src/image/bitmaps.dart';
import 'package:jbig2/src/util/combination_operator.dart';

void main() {
  group('BitmapsByteCombinationTest', () {
    const int value1 = 0xA;
    const int value2 = 0xD;

    test('OR', () {
      expect(Bitmaps.combineBytes(value1, value2, CombinationOperator.OR), 0xF);
    });

    test('AND', () {
      expect(Bitmaps.combineBytes(value1, value2, CombinationOperator.AND), 0x8);
    });

    test('XOR', () {
      expect(Bitmaps.combineBytes(value1, value2, CombinationOperator.XOR), 0x7);
    });

    test('XNOR', () {
      // Java expects -8, which is 0xF8 in unsigned byte
      expect(Bitmaps.combineBytes(value1, value2, CombinationOperator.XNOR), 0xF8);
    });

    test('REPLACE', () {
      expect(Bitmaps.combineBytes(value1, value2, CombinationOperator.REPLACE), value2);
    });
  });
}

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/jbig2_writer.dart';
import 'package:jbig2/src/encoder/symbol_dictionary_encoder.dart';
import 'package:jbig2/src/encoder/symbol_extractor.dart';
import 'package:test/test.dart';

Bitmap _bitmap(List<String> rows) {
  final bitmap = Bitmap(rows.first.length, rows.length);
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] == '#') bitmap.setPixel(x, y, 1);
    }
  }
  return bitmap;
}

void main() {
  test('refinement dictionary reproduces a non-identical symbol losslessly',
      () {
    final base = _bitmap(<String>[
      '.###.',
      '#...#',
      '#####',
      '#...#',
      '#...#',
    ]);
    final refined = _bitmap(<String>[
      '.###.',
      '#...#',
      '#####',
      '#..##',
      '#...#',
    ]);
    final writer = Jbig2Writer();
    writer.writeSegment(
        number: 0,
        type: Jbig2SegmentType.pageInformation,
        page: 1,
        data: Jbig2Writer.pageInformation(width: 5, height: 5));
    writer.writeSegment(
        number: 1,
        type: Jbig2SegmentType.symbolDictionary,
        page: 1,
        data: Jbig2Writer.symbolDictionary(
            exportedSymbols: 1,
            newSymbols: 1,
            codeword:
                SymbolDictionaryEncoder.encodeDictionary(<Bitmap>[base])));
    writer.writeSegment(
        number: 2,
        type: Jbig2SegmentType.symbolDictionary,
        page: 1,
        referredTo: const <int>[1],
        data: Jbig2Writer.refinementSymbolDictionary(
            exportedSymbols: 1,
            newSymbols: 1,
            codeword: SymbolDictionaryEncoder.encodeRefinementDictionary(
                <Bitmap>[base], <RefinedSymbol>[RefinedSymbol(refined, 0)])));
    writer.writeSegment(
        number: 3,
        type: Jbig2SegmentType.immediateLosslessTextRegion,
        page: 1,
        referredTo: const <int>[2],
        data: Jbig2Writer.textRegion(
            width: 5,
            height: 5,
            instances: 1,
            codeword: SymbolDictionaryEncoder.encodeTextRegion(<Bitmap>[
              refined
            ], const <ExtractedSymbolInstance>[
              ExtractedSymbolInstance(0, 0, 0)
            ])));

    final decoded = decodeJbig2Embedded(writer.takeBytes());
    expect(decoded.width, 5);
    expect(decoded.height, 5);
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        expect(decoded.isBlack(x, y), refined.getPixel(x, y) == 1,
            reason: 'pixel ($x, $y)');
      }
    }
  });
}

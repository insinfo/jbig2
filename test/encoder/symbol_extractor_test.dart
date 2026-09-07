import 'package:jbig2/src/bitmap.dart';
import 'package:jbig2/src/encoder/symbol_extractor.dart';
import 'package:test/test.dart';

void _rect(Bitmap bitmap, int x, int y, int width, int height) {
  for (var py = y; py < y + height; py++) {
    for (var px = x; px < x + width; px++) {
      bitmap.setPixel(px, py, 1);
    }
  }
}

void main() {
  test('deduplica componentes iguais e reconstrói todos os pixels', () {
    final source = Bitmap(40, 20);
    _rect(source, 2, 3, 3, 5);
    _rect(source, 12, 3, 3, 5);
    _rect(source, 25, 2, 5, 7);

    final extracted = SymbolExtractor(source).extract();
    expect(extracted.dictionary, hasLength(2));
    expect(extracted.instances, hasLength(3));
    expect(extracted.instances.map((i) => i.symbol).toSet(), hasLength(2));
    expect(extracted.instances.where((i) => i.symbol == 0), hasLength(2));
    expect(extracted.reconstruct(source.width, source.height).bitmap,
        source.bitmap);
  });

  test('diagonais pertencem ao mesmo componente 8-conectado', () {
    final source = Bitmap(8, 8)
      ..setPixel(1, 1, 1)
      ..setPixel(2, 2, 1)
      ..setPixel(6, 6, 1);
    final extracted = SymbolExtractor(source).extract();
    expect(extracted.dictionary, hasLength(2));
    expect(
        extracted.dictionary.any((s) => s.width == 2 && s.height == 2), isTrue);
    expect(extracted.reconstruct(8, 8).bitmap, source.bitmap);
  });

  test('imagem vazia produz dicionário e instâncias vazios', () {
    final extracted = SymbolExtractor(Bitmap(17, 9)).extract();
    expect(extracted.dictionary, isEmpty);
    expect(extracted.instances, isEmpty);
  });
}

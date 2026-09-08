import 'dart:math' as math;
import 'dart:typed_data';

import '../bitmap.dart';
import '../decoder/arithmetic/cx.dart';
import 'arithmetic_integer_encoder.dart';
import 'generic_region_encoder.dart';
import 'generic_refinement_region_encoder.dart';
import 'mq_encoder.dart';
import 'symbol_extractor.dart';

class SymbolDictionaryEncoder {
  static Uint8List encodeDictionary(List<Bitmap> symbols) {
    if (symbols.isEmpty) {
      throw ArgumentError('A symbol dictionary cannot be empty.');
    }
    final mq = MqEncoder();
    final integers = ArithmeticIntegerEncoder(mq);
    final iaDh = CX(512, 1);
    final iaDw = CX(512, 1);
    final iaEx = CX(512, 1);
    final bitmapContext = CX(1 << 16, 0);
    var previousHeight = 0;
    var index = 0;
    while (index < symbols.length) {
      final height = symbols[index].height;
      integers.encode(iaDh, height - previousHeight);
      previousHeight = height;
      var previousWidth = 0;
      while (index < symbols.length && symbols[index].height == height) {
        final symbol = symbols[index];
        integers.encode(iaDw, symbol.width - previousWidth);
        previousWidth = symbol.width;
        GenericRegionEncoder(symbol, typicalPrediction: false)
            .encodeInto(mq, bitmapContext);
        index++;
      }
      integers.encode(iaDw, null);
    }
    // A lista de exportação começa em 0: corrida vazia, depois todos em 1.
    integers.encode(iaEx, 0);
    integers.encode(iaEx, symbols.length);
    return mq.flush();
  }

  static Uint8List encodeTextRegion(
      List<Bitmap> symbols, List<ExtractedSymbolInstance> instances) {
    final mq = MqEncoder();
    final integers = ArithmeticIntegerEncoder(mq);
    final iaDt = CX(512, 1);
    final iaFs = CX(512, 1);
    final iaDs = CX(512, 1);
    final codeLength =
        symbols.length <= 1 ? 0 : (math.log(symbols.length) / math.ln2).ceil();
    final iaId = CX(1 << codeLength, 1);
    integers.encode(iaDt, 0); // STRIPT inicial
    var stripT = 0;
    var firstS = 0;
    for (final instance in instances) {
      final t = instance.y + symbols[instance.symbol].height - 1;
      integers.encode(iaDt, t - stripT);
      stripT = t;
      integers.encode(iaFs, instance.x - firstS);
      firstS = instance.x;
      integers.encodeIAID(iaId, codeLength, instance.symbol);
      integers.encode(iaDs, null); // uma instância por faixa
    }
    return mq.flush();
  }

  /// Encodes new symbols as one-instance refinements of imported symbols.
  static Uint8List encodeRefinementDictionary(
      List<Bitmap> imported, List<RefinedSymbol> symbols) {
    if (imported.isEmpty || symbols.isEmpty) {
      throw ArgumentError('Refinement needs imported and new symbols.');
    }
    final mq = MqEncoder();
    final integers = ArithmeticIntegerEncoder(mq);
    final iaDh = CX(512, 1);
    final iaDw = CX(512, 1);
    final iaAi = CX(512, 1);
    final iaEx = CX(512, 1);
    final iaId = CX(1 << _codeLength(imported.length + symbols.length), 1);
    final iaRdx = CX(512, 1);
    final iaRdy = CX(512, 1);
    final bitmapContext = CX(1 << 16, 1);
    var previousHeight = 0;
    var index = 0;
    while (index < symbols.length) {
      final height = symbols[index].bitmap.height;
      integers.encode(iaDh, height - previousHeight);
      previousHeight = height;
      var previousWidth = 0;
      while (index < symbols.length && symbols[index].bitmap.height == height) {
        final symbol = symbols[index];
        if (symbol.reference < 0 || symbol.reference >= imported.length) {
          throw RangeError.index(symbol.reference, imported, 'reference');
        }
        integers.encode(iaDw, symbol.bitmap.width - previousWidth);
        previousWidth = symbol.bitmap.width;
        integers.encode(iaAi, 1);
        integers.encodeIAID(iaId, _codeLength(imported.length + symbols.length),
            symbol.reference);
        integers.encode(iaRdx, symbol.referenceDX);
        integers.encode(iaRdy, symbol.referenceDY);
        GenericRefinementRegionEncoder(
                symbol.bitmap, imported[symbol.reference],
                referenceDX: symbol.referenceDX,
                referenceDY: symbol.referenceDY)
            .encodeInto(mq, bitmapContext);
        index++;
      }
      integers.encode(iaDw, null);
    }
    // Imported symbols remain private; all newly refined symbols are exported.
    integers.encode(iaEx, imported.length);
    integers.encode(iaEx, symbols.length);
    return mq.flush();
  }

  static int _codeLength(int symbols) =>
      symbols <= 1 ? 0 : (math.log(symbols) / math.ln2).ceil();
}

class RefinedSymbol {
  final Bitmap bitmap;
  final int reference;
  final int referenceDX;
  final int referenceDY;

  const RefinedSymbol(this.bitmap, this.reference,
      {this.referenceDX = 0, this.referenceDY = 0});
}

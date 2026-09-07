import '../decoder/arithmetic/cx.dart';
import 'mq_encoder.dart';

/// Codifica inteiros pelo procedimento aritmético do Anexo A de T.88.
///
/// A instância não guarda estado além do [MqEncoder]; os contextos e a cadeia
/// `PREV` são reiniciados para cada inteiro, exatamente como no decoder.
class ArithmeticIntegerEncoder {
  final MqEncoder encoder;

  ArithmeticIntegerEncoder(this.encoder);

  /// Codifica [value]. Null representa o valor OOB usado para terminar listas.
  void encode(CX context, int? value) {
    var prev = 1;

    void bit(int decision) {
      context.index = prev;
      encoder.encode(context, decision);
      prev = _nextPrev(prev, decision);
    }

    if (value == null) {
      // S=1 e magnitude zero é a representação reservada para OOB.
      bit(1);
      bit(0);
      bit(0);
      bit(0);
      return;
    }

    bit(value < 0 ? 1 : 0);
    final magnitude = value.abs();
    late final int bits;
    late final int offset;
    if (magnitude < 4) {
      bit(0);
      bits = 2;
      offset = 0;
    } else if (magnitude < 20) {
      bit(1);
      bit(0);
      bits = 4;
      offset = 4;
    } else if (magnitude < 84) {
      bit(1);
      bit(1);
      bit(0);
      bits = 6;
      offset = 20;
    } else if (magnitude < 340) {
      bit(1);
      bit(1);
      bit(1);
      bit(0);
      bits = 8;
      offset = 84;
    } else if (magnitude < 4436) {
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bit(0);
      bits = 12;
      offset = 340;
    } else {
      if (magnitude - 4436 > 0xffffffff) {
        throw RangeError.value(value, 'value', 'does not fit the JBIG2 code');
      }
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bits = 32;
      offset = 4436;
    }

    final payload = magnitude - offset;
    for (var shift = bits - 1; shift >= 0; shift--) {
      bit((payload >> shift) & 1);
    }
  }

  /// Codifica um identificador de símbolo de largura fixa pelo Anexo A.3.
  void encodeIAID(CX context, int symbolCodeLength, int value) {
    if (symbolCodeLength < 0 || value < 0 || value >= (1 << symbolCodeLength)) {
      throw RangeError.value(value, 'value', 'does not fit symbolCodeLength');
    }
    var prev = 1;
    for (var shift = symbolCodeLength - 1; shift >= 0; shift--) {
      context.index = prev;
      final decision = (value >> shift) & 1;
      encoder.encode(context, decision);
      prev = (prev << 1) | decision;
    }
  }

  static int _nextPrev(int prev, int bit) => prev < 256
      ? ((prev << 1) | bit) & 0x1ff
      : ((((prev << 1) | bit) & 0x1ff) | 0x100) & 0x1ff;
}

import 'package:jbig2/src/decoder/arithmetic/arithmetic_decoder.dart';
import 'package:jbig2/src/decoder/arithmetic/arithmetic_integer_decoder.dart';
import 'package:jbig2/src/decoder/arithmetic/cx.dart';
import 'package:jbig2/src/encoder/arithmetic_integer_encoder.dart';
import 'package:jbig2/src/encoder/mq_encoder.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:test/test.dart';

void main() {
  test('inteiros atravessam todas as classes de magnitude', () {
    const values = <int?>[
      0,
      3,
      4,
      19,
      20,
      83,
      84,
      339,
      340,
      4435,
      4436,
      -1,
      -19,
      -340,
      -100000,
      null,
    ];
    final mq = MqEncoder();
    final arithmetic = ArithmeticIntegerEncoder(mq);
    final writeContext = CX(512, 1);
    for (final value in values) {
      arithmetic.encode(writeContext, value);
    }
    final bytes = mq.flush();
    final stream = SubInputStream(
        RandomAccessReadBuffer.fromBytes(bytes), 0, bytes.length);
    final decoder = ArithmeticIntegerDecoder(ArithmeticDecoder(stream));
    final readContext = CX(512, 1);
    for (final value in values) {
      final decoded = decoder.decode(readContext);
      expect(decoded, value ?? 0x1fffffffffffff);
    }
  });

  test('IAID preserva identificadores de largura fixa', () {
    const length = 5;
    const values = [0, 1, 7, 16, 31];
    final mq = MqEncoder();
    final arithmetic = ArithmeticIntegerEncoder(mq);
    final writeContext = CX(1 << length, 1);
    for (final value in values) {
      arithmetic.encodeIAID(writeContext, length, value);
    }
    final bytes = mq.flush();
    final stream = SubInputStream(
        RandomAccessReadBuffer.fromBytes(bytes), 0, bytes.length);
    final decoder = ArithmeticIntegerDecoder(ArithmeticDecoder(stream));
    final readContext = CX(1 << length, 1);
    for (final value in values) {
      expect(decoder.decodeIAID(readContext, length), value);
    }
  });

  test('rejeita inteiro fora dos 32 bits de payload e IAID inválido', () {
    final arithmetic = ArithmeticIntegerEncoder(MqEncoder());
    expect(() => arithmetic.encode(CX(512, 1), 0x100000000 + 4436),
        throwsRangeError);
    expect(() => arithmetic.encodeIAID(CX(8, 1), 3, 8), throwsRangeError);
  });
}

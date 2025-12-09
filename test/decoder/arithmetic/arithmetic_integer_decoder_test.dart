import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/decoder/arithmetic/arithmetic_decoder.dart';
import 'package:jbig2/src/decoder/arithmetic/arithmetic_integer_decoder.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  test('ArithmeticIntegerDecoder decodeTest', () {
    final file = File('test/resources/images/arith/encoded testsequence');
    if (!file.existsSync()) {
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    final sis = SubInputStream(rar, 0, bytes.length);

    final ad = ArithmeticDecoder(sis);
    final aid = ArithmeticIntegerDecoder(ad);

    final result = aid.decode(null);

    expect(result, 1);
  });
}

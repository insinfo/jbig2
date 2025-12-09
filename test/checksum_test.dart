import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  group('ChecksumTest', () {
    test('compareChecksum 042_1.jb2', () {
      final filepath = 'test/resources/images/042_1.jb2';
      final checksum = "69-26-6629-1793-107941058147-58-79-37-31-79";
      
      final file = File(filepath);
      if (!file.existsSync()) {
        fail('Test resource not found: ${file.path}');
      }
      final bytes = file.readAsBytesSync();
      final rar = RandomAccessReadBuffer.fromBytes(bytes);
      
      final doc = JBIG2Document(rar);
      final bitmap = doc.getPage(1).getBitmap();
      
      final digest = md5.convert(bitmap.getByteArray()).bytes;
      final sb = StringBuffer();
      for (var b in digest) {
        // Java byte is signed, Dart byte is unsigned (0-255).
        // Java code: sb.append(toAppend);
        // If toAppend is -1 (0xFF), it appends "-1".
        // If toAppend is 1, it appends "1".
        // So I need to convert Dart unsigned byte to Java signed byte string representation.
        int val = b;
        if (val > 127) val -= 256;
        sb.write(val);
      }
      
      expect(sb.toString(), checksum);
    });
  });
}

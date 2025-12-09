import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  group('JBIG2ImageReaderTest', () {
    test('read 042_1.jb2', () {
      final filepath = 'test/resources/images/042_1.jb2';
      final file = File(filepath);
      if (!file.existsSync()) fail('File not found: $filepath');

      final rar = RandomAccessReadBuffer.fromBytes(file.readAsBytesSync());
      final doc = JBIG2Document(rar);
      
      // JBIG2 pages are 1-based
      final page = doc.getPage(1);
      final bitmap = page.getBitmap();
      
      expect(bitmap, isNotNull);
      expect(bitmap.width, greaterThan(0));
      expect(bitmap.height, greaterThan(0));
    });

    test('getNumImages 002.jb2', () {
      final filepath = 'test/resources/images/002.jb2';
      final file = File(filepath);
      if (!file.existsSync()) fail('File not found: $filepath');

      final rar = RandomAccessReadBuffer.fromBytes(file.readAsBytesSync());
      final doc = JBIG2Document(rar);
      
      final numImages = doc.getAmountOfPages();
      expect(numImages, 17);
    });
  });
}

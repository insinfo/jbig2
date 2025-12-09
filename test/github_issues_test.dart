import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:jbig2/src/jbig2_document.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  group('GithubIssuesTest', () {
    test('issue21', () {
      final imagePath = 'test/resources/com/levigo/jbig2/github/21.jb2';
      final globalsPath = 'test/resources/com/levigo/jbig2/github/21.glob';
      
      // Java: 83, 74, -69, -60, -122, -99, 21, 126, -115, 13, 9, 107, -31, -109, 77, -119
      final md5Expected = [
        83, 74, 187, 196, 134, 157, 21, 126, 141, 13, 9, 107, 225, 147, 77, 137
      ];

      final globalsFile = File(globalsPath);
      final imageFile = File(imagePath);
      
      if (!globalsFile.existsSync()) fail('Globals file not found: $globalsPath');
      if (!imageFile.existsSync()) fail('Image file not found: $imagePath');

      final globalsRar = RandomAccessReadBuffer.fromBytes(globalsFile.readAsBytesSync());
      final globalsDoc = JBIG2Document(globalsRar);
      
      final globals = globalsDoc.globalSegments;
      
      final imageRar = RandomAccessReadBuffer.fromBytes(imageFile.readAsBytesSync());
      final doc = JBIG2Document(imageRar, globals);
      
      final page = doc.getPage(1);
      final bitmap = page.getBitmap();
      
      final digest = md5.convert(bitmap.getByteArray()).bytes;
      
      expect(digest, md5Expected);
    });
  });
}

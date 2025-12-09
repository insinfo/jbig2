import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/segments/pattern_dictionary.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  test('PatternDictionary parseHeaderTest', () {
    final file = File('test/resources/images/sampledata.jb2');
    if (!file.existsSync()) {
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    // Sixth Segment (number 5)
    final sis = SubInputStream(rar, 245, 45);
    
    final pd = PatternDictionary();
    pd.init(null, sis);
    
    expect(pd.isMMREncoded, true);
    expect(pd.hdTemplate, 0);
    expect(pd.hdpWidth, 4);
    expect(pd.hdpHeight, 4);
    expect(pd.grayMax, 15);
  });
}

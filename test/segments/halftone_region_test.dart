import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/segments/halftone_region.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:jbig2/src/util/combination_operator.dart';

void main() {
  test('HalftoneRegion parseHeaderTest', () {
    final file = File('test/resources/images/sampledata.jb2');
    if (!file.existsSync()) {
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    // Seventh Segment (number 6)
    final sis = SubInputStream(rar, 302, 87);
    
    final hr = HalftoneRegion(sis);
    hr.init(null, sis);
    
    expect(hr.isMMREncoded, true);
    expect(hr.hTemplate, 0);
    expect(hr.isHSkipEnabled, false);
    expect(hr.combinationOperator, CombinationOperator.OR);
    expect(hr.hDefaultPixel, 0);
    
    expect(hr.hGridWidth, 8);
    expect(hr.hGridHeight, 9);
    expect(hr.hGridX, 0);
    expect(hr.hGridY, 0);
    expect(hr.hRegionX, 1024);
    expect(hr.hRegionY, 0);
  });
}

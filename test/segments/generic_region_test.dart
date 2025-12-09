import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/segments/generic_region.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:jbig2/src/util/combination_operator.dart';

void main() {
  test('GenericRegion parseHeaderTest', () {
    final file = File('test/resources/images/sampledata.jb2');
    if (!file.existsSync()) {
      // Try relative to workspace root if running from IDE might be different
      // But usually tests run from project root.
      // If not found, fail with clear message.
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    final sis = SubInputStream(rar, 523, 35);
    
    final gr = GenericRegion(sis);
    
    // We pass null for header as in the Java test.
    gr.init(null, sis);
    
    expect(gr.getRegionInfo().bitmapWidth, 54);
    expect(gr.getRegionInfo().bitmapHeight, 44);
    expect(gr.getRegionInfo().getXLocation(), 4);
    expect(gr.getRegionInfo().getYLocation(), 11);
    expect(gr.getRegionInfo().getCombinationOperator(), CombinationOperator.OR);

    expect(gr.useExtTemplates, false);
    expect(gr.isMMREncoded, false);
    expect(gr.gbTemplate, 0);
    expect(gr.isTPGDon, true);
    expect(gr.gbAtX, equals([3, -3, 2, -2]));
    expect(gr.gbAtY, equals([-1, -1, -2, -2]));
  });
}

import 'dart:io';
import 'package:test/test.dart';
import 'package:jbig2/src/segments/page_information.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:jbig2/src/util/combination_operator.dart';

void main() {
  test('PageInformation parseHeaderCompleteTest', () {
    final file = File('test/resources/images/sampledata.jb2');
    if (!file.existsSync()) {
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    
    // Second Segment (number 1)
    final sis = SubInputStream(rar, 59, 19);
    final pi = PageInformation();
    pi.init(null, sis);
    
    expect(pi.getWidth(), 64);
    expect(pi.getHeight(), 56);
    expect(pi.getResolutionX(), 0);
    expect(pi.getResolutionY(), 0);
    expect(pi.getIsLossless(), true);
    expect(pi.getMightContainRefinements(), false);
    expect(pi.getDefaultPixelValue(), 0);
    expect(pi.getCombinationOperator(), CombinationOperator.OR);
    expect(pi.isAuxiliaryBufferRequired(), false);
    expect(pi.isCombinationOperatorOverrideAllowed(), false);
    expect(pi.getIsStriped(), false);
    expect(pi.getMaxStripeSize(), 0);
  });
}

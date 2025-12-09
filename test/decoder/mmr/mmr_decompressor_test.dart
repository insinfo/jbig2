import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jbig2/src/decoder/mmr/mmr_decompressor.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';

void main() {
  test('MMRDecompressor mmrDecodingTest', () {
    final expected = Int8List.fromList([
        0, 0, 2, 34, 38, 102, -17, -1, 2, 102, 102, //
        -18, -18, -17, -1, -1, 0, 2, 102, 102, 127, //
        -1, -1, -1, 0, 0, 0, 4, 68, 102, 102, 127
    ]);
    // Convert expected to Uint8List for comparison as Bitmap uses Uint8List
    final expectedUint8 = Uint8List.fromList(expected.map((e) => e & 0xff).toList());

    final file = File('test/resources/images/sampledata.jb2');
    if (!file.existsSync()) {
      fail('Test resource not found: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final rar = RandomAccessReadBuffer.fromBytes(bytes);
    
    // Sixth Segment (number 5)
    // Java: new SubInputStream(iis, 252, 38);
    // final sis = SubInputStream(rar, 252, 38);
    
    // We need to pass a RandomAccessRead view to MMRDecompressor
    // In GenericRegion we did:
    // final view = _subInputStream!.wrappedStream.createView(
    //        _subInputStream!.offset + _dataOffset, _dataLength);
    // Here we are passing the SubInputStream directly in Java test, but MMRDecompressor in Java takes ImageInputStream.
    // In my Dart port, MMRDecompressor takes RandomAccessRead.
    // SubInputStream wraps RandomAccessRead but doesn't implement it.
    // So I should create a view from the underlying RAR.
    
    final view = rar.createView(252, 38);

    final mmrd = MMRDecompressor(16 * 4, 4, view);

    final b = mmrd.uncompress();
    final actual = b.getByteArray();

    expect(actual, equals(expectedUint8));
  });
}

import 'dart:io';

import 'package:jbig2/jbig2.dart';
import 'package:jbig2/src/decoder/arithmetic/arithmetic_decoder.dart';
import 'package:jbig2/src/decoder/arithmetic/cx.dart';
import 'package:jbig2/src/encoder/mq_encoder.dart';
import 'package:jbig2/src/io/random_access_read_buffer.dart';
import 'package:jbig2/src/io/sub_input_stream.dart';
import 'package:test/test.dart';

/// Conformance against the two reference vectors ITU-T T.88 publishes in
/// Annex H.
///
/// H.1 is a complete three page file that, in the standard's own words,
/// "exercises a large number of the features of JBIG2". Pages 1 and 2 encode
/// the *same* bitmap, page 1 entirely with Huffman and MMR coding and page 2
/// entirely with arithmetic coding, so decoding both and comparing them checks
/// the two halves of the standard against each other. Page 3 adds a symbol
/// dictionary that builds its symbols by refinement and aggregation from
/// another dictionary, plus a text region that refines one instance as it
/// places it.
///
/// H.2 is the arithmetic coder test sequence: 256 decisions and the exact 30
/// bytes a conforming encoder must produce for them.

const _page1 = <String>[
  '................................................................',
  '.....####....####...####....####....####........................',
  '....#....#.......#..#...#.......#..#....#.......................',
  '....#........#####..#...#...#####..#............................',
  '....#.......#....#..#...#..#....#..#............................',
  '....#....#..#....#..####...#....#..#....#.......................',
  '.....####....#####..#.......#####...####........................',
  '....................#...........................................',
  '....................#...........................................',
  '................................................................',
  '................................................................',
  '....######################################################......',
  '....######################################################......',
  '....##..................................................##......',
  '....##..................................................##......',
  '....##................................#...#...#.........##......',
  '....##................#..##..##..##..##.###.###.........##......',
  '....##........................#..##..##..##..##.........##......',
  '....##.......................................#..........##......',
  '....##............................#...#...#...#.........##......',
  '....##............#..##..##..##..##.###.###.###.........##......',
  '....##....................#..##..##..##..##..###........##......',
  '....##...................................#...#..........##......',
  '....##........................#...#...#...#..##.........##......',
  '....##...........##..##..##..##.###.###.###.###.........##......',
  '....##................#..##..##..##..##..#######........##......',
  '....##...............................#...#...#..........##......',
  '....##....................#...#...#...#..##..##.........##......',
  '....##...........##..##..##.###.###.###.###.###.........##......',
  '....##............#..##..##..##..##..###########........##......',
  '....##...........................#...#...#...##.........##......',
  '....##................#...#...#...#..##..##..##.........##......',
  '....##...........##..##.###.###.###.###.###.####........##......',
  '....##...........##..##..##..##..###############........##......',
  '....##.......................#...#...#...##..##.........##......',
  '....##............#...#...#...#..##..##..##.###.........##......',
  '....##...........##.###.###.###.###.###.########........##......',
  '....##...........##..##..##..###################........##......',
  '....##...................#...#...#...##..##..##.........##......',
  '....##............#...#...#..##..##..##.###.####........##......',
  '....##..........###.###.###.###.###.############........##......',
  '....##...........##..##..#######################........##......',
  '....##...............#...#...#...##..##..##..##.........##......',
  '....##............#...#..##..##..##.###.########........##......',
  '....##..........###.###.###.###.################........##......',
  '....##...........##..###########################........##......',
  '....##...........#...#...#...##..##..##..##..###........##......',
  '....##............#..##..##..##.###.############........##......',
  '....##..........###.###.###.####################........##......',
  '....##...........###############################........##......',
  '....##...........#...#...##..##..##..##..#######........##......',
  '....##..................................................##......',
  '....##..................................................##......',
  '....######################################################......',
  '....######################################################......',
  '................................................................',
];
const _page3 = <String>[
  '.####....####...####....####....####.',
  '#....#.......#..#...#.......#..#....#',
  '#........#####..#...#...#####..#.....',
  '#.......#....#..#...#..#....#..#.....',
  '#....#..#....#..####...#....#..#....#',
  '.####....#####..#.......#####...####.',
  '................#....................',
  '................#....................',
];

/// Renders a decoded image as one string per row, `#` for a black pixel, the
/// notation Annex H itself uses for its figures.
List<String> _rows(Jbig2Image image) {
  return List<String>.generate(image.height, (y) {
    final row = StringBuffer();
    for (var x = 0; x < image.width; x++) {
      row.write(image.isBlack(x, y) ? '#' : '.');
    }
    return row.toString();
  });
}

/// The rectangle of [rows] at [x], [y] with the given size.
List<String> _crop(List<String> rows, int x, int y, int width, int height) {
  return List<String>.generate(
      height, (i) => rows[y + i].substring(x, x + width));
}

void main() {
  final stream = File('test/resources/t88/annex_h.jb2').readAsBytesSync();

  group('T.88 H.1 datastream example', () {
    test('the file header announces three pages', () {
      expect(isJbig2File(stream), isTrue);
      final info = probeJbig2(stream);
      expect(info.pageCount, equals(3));
      expect(info.width, equals(64));
      expect(info.height, equals(56));
    });

    test('page 1 decodes to the bitmap of Figure H.1', () {
      expect(_rows(decodeJbig2(stream, page: 1)), equals(_page1));
    });

    test(
        'page 2, coded arithmetically, equals page 1, coded with Huffman and '
        'MMR', () {
      final huffman = decodeJbig2(stream, page: 1);
      final arithmetic = decodeJbig2(stream, page: 2);
      expect(arithmetic.width, equals(huffman.width));
      expect(arithmetic.height, equals(huffman.height));
      for (var y = 0; y < huffman.height; y++) {
        for (var x = 0; x < huffman.width; x++) {
          if (arithmetic.isBlack(x, y) != huffman.isBlack(x, y)) {
            fail('pixel ($x, $y) differs between the Huffman/MMR page 1 and '
                'the arithmetic page 2');
          }
        }
      }
    });

    test('the three regions of page 1 land where their segment headers say',
        () {
      final rows = _rows(decodeJbig2(stream, page: 1));

      // Segment 3, an immediate lossless text region, 37 x 8 at (4, 1).
      expect(
          _crop(rows, 4, 1, 37, 8).every((row) => row.contains('#')), isTrue);
      // Nothing above it: the text region is the topmost region on the page.
      expect(rows[0], equals('.' * 64));

      // Segment 4, an immediate lossless generic region coded with MMR,
      // 54 x 44 at (4, 11). Its first two rows are the solid top of the frame.
      expect(_crop(rows, 4, 11, 54, 1).single, equals('#' * 54));
      expect(_crop(rows, 4, 12, 54, 1).single, equals('#' * 54));
      expect(_crop(rows, 4, 53, 54, 1).single, equals('#' * 54));

      // Segment 6, an immediate lossless halftone region, 32 x 36 at (16, 15),
      // drawn inside the frame.
      final halftone = _crop(rows, 16, 15, 32, 36);
      expect(halftone.where((row) => row.contains('#')).length, equals(36));
    });

    test('page 3 places four symbol instances, one of them refined', () {
      final rows = _rows(decodeJbig2(stream, page: 3));
      expect(rows, equals(_page3));

      // H.1 step 39 xxi): the text region draws Figure H.12 b) at (0, 0),
      // Figure H.12 a) at (8, 0), Figure H.2 at (16, 0) and Figure H.12 c) at
      // (23, 0). The gaps between those instances must be blank columns.
      for (final x in [6, 7, 14, 15, 21, 22]) {
        expect(rows.every((row) => row[x] == '.'), isTrue,
            reason: 'column $x should separate two symbol instances');
      }
    });

    test('the refined instance on page 3 reproduces Figure H.2', () {
      // The third instance on page 3 is decoded by refining a 6 x 6 symbol into
      // a 5 x 8 one; H.1 states the result is Figure H.2, the symbol the very
      // first symbol dictionary defines with MMR and that page 1 also draws.
      final page1 = _rows(decodeJbig2(stream, page: 1));
      final page3 = _rows(decodeJbig2(stream, page: 3));
      final figureH2 = _crop(page3, 16, 0, 5, 8);
      expect(figureH2, equals(_crop(page1, 20, 1, 5, 8)));
      expect(
          figureH2,
          equals(<String>[
            '####.',
            '#...#',
            '#...#',
            '#...#',
            '####.',
            '#....',
            '#....',
            '#....',
          ]));
    });
  });

  group('T.88 H.2 arithmetic coder test sequence', () {
    final decisions = File('test/resources/images/arith/decoded testsequence')
        .readAsBytesSync();
    final encoded = File('test/resources/images/arith/encoded testsequence')
        .readAsBytesSync();

    test('the encoder produces the 30 reference bytes', () {
      final mq = MqEncoder();
      final cx = CX(1, 0);
      for (final byte in decisions) {
        for (var bit = 7; bit >= 0; bit--) {
          mq.encode(cx, (byte >> bit) & 1);
        }
      }
      expect(mq.flush(), equals(encoded));
    });

    test('the decoder recovers the 32 decision bytes', () {
      final sis = SubInputStream(
          RandomAccessReadBuffer.fromBytes(encoded), 0, encoded.length);
      final decoder = ArithmeticDecoder(sis);
      final cx = CX(1, 0);
      final recovered = <int>[];
      for (var i = 0; i < decisions.length; i++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          byte = (byte << 1) | decoder.decode(cx);
        }
        recovered.add(byte);
      }
      expect(recovered, equals(decisions));
    });
  });
}

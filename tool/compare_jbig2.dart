// Decodifica cada .jb2 com `package:jbig2` e compara pixel a pixel com o PGM
// que o jbig2-imageio (Java, do projeto PDFBox) produziu para o mesmo arquivo.
//
// As duas implementações não têm parentesco de código, e boa parte dos fluxos
// vem da própria Recomendação ITU-T T.88. Concordarem é evidência de
// conformidade, não apenas de estabilidade.
import 'dart:io';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';

void main(List<String> args) {
  final jbig2Dir = Directory(args[0]);
  final pgmDir = Directory(args[1]);

  final files = jbig2Dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jb2'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var agreed = 0;
  var mismatched = 0;
  var dartFailed = 0;
  var noOracle = 0;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final base = name.substring(0, name.length - 4);
    final pgm = File('${pgmDir.path}/$base.pgm');

    Jbig2Image? image;
    String? error;
    try {
      image = decodeJbig2(file.readAsBytesSync());
    } catch (e) {
      error = '${e.runtimeType}: $e';
    }

    if (!pgm.existsSync()) {
      // Sem oráculo não há o que comparar. Ainda assim vale registrar se o
      // Dart conseguiu ou não, porque um arquivo que só o Dart lê é notícia.
      noOracle++;
      print('SEM-ORACULO  ${name.padRight(22)} '
          '${error == null ? 'dart decodificou ${image!.width}x${image.height}' : 'dart falhou: $error'}');
      continue;
    }

    if (error != null) {
      dartFailed++;
      print('DART-FALHOU  ${name.padRight(22)} $error');
      continue;
    }

    final reference = _readPgm(pgm);
    final result = _compare(image!, reference);
    if (result.identical) {
      agreed++;
      print('IGUAL        ${name.padRight(22)} '
          '${image.width}x${image.height}');
    } else {
      mismatched++;
      print('DIFERE       ${name.padRight(22)} ${result.detail}');
    }
  }

  print('');
  print('=' * 70);
  print('idênticos ao oráculo Java : $agreed');
  print('divergentes               : $mismatched');
  print('falha só no Dart          : $dartFailed');
  print('sem oráculo               : $noOracle');
  print('total                     : ${files.length}');
  if (mismatched > 0 || dartFailed > 0) exitCode = 1;
}

class _Pgm {
  final int width;
  final int height;
  final Uint8List gray;
  const _Pgm(this.width, this.height, this.gray);
}

_Pgm _readPgm(File file) {
  final bytes = file.readAsBytesSync();
  var offset = 0;
  final fields = <int>[];
  // Cabeçalho: P5, largura, altura, valor máximo — separados por espaços.
  while (fields.length < 4 && offset < bytes.length) {
    while (offset < bytes.length && _isSpace(bytes[offset])) {
      offset++;
    }
    final start = offset;
    while (offset < bytes.length && !_isSpace(bytes[offset])) {
      offset++;
    }
    final token = String.fromCharCodes(bytes.sublist(start, offset));
    if (fields.isEmpty) {
      if (token != 'P5') throw FormatException('não é PGM binário: $token');
      fields.add(0);
    } else {
      fields.add(int.parse(token));
    }
  }
  offset++; // o único byte de espaço depois do maxval
  return _Pgm(fields[1], fields[2], bytes.sublist(offset));
}

bool _isSpace(int b) => b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09;

class _Result {
  final bool identical;
  final String detail;
  const _Result(this.identical, this.detail);
}

_Result _compare(Jbig2Image image, _Pgm reference) {
  if (image.width != reference.width || image.height != reference.height) {
    return _Result(
        false,
        'dimensões: dart ${image.width}x${image.height} '
        'vs java ${reference.width}x${reference.height}');
  }

  var differing = 0;
  int? firstX, firstY;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      // No PGM do oráculo, preto é 0. No Jbig2Image, bit setado é preto.
      final javaBlack = reference.gray[y * reference.width + x] < 128;
      final dartBlack = image.isBlack(x, y);
      if (javaBlack != dartBlack) {
        differing++;
        firstX ??= x;
        firstY ??= y;
      }
    }
  }

  if (differing == 0) return const _Result(true, '');
  final total = image.width * image.height;
  final percent = (differing / total * 100).toStringAsFixed(4);
  return _Result(
      false,
      '$differing de $total pixels ($percent%), '
      'primeiro em ($firstX,$firstY)');
}

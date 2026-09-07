import 'dart:io';

import 'package:test/test.dart';

/// Walks the import graph from `lib/jbig2.dart` the way pub.dev does.
///
/// Reaching `dart:io` from the public facade would cost the package its Web
/// and Wasm support, and would take that support away from every package that
/// depends on it. The file-backed `RandomAccessRead` implementations in
/// `lib/src/io` do use `dart:io` on purpose; they simply must stay outside the
/// graph the facade pulls in.
void main() {
  test('the public facade never reaches dart:io', () {
    final visited = <String>{};
    final trail = <String, String>{};

    String? offender;
    void walk(String path) {
      if (!visited.add(path)) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      final directives =
          RegExp(r'''(?:import|export|part)\s+(?:'([^']+)'|"([^"]+)")''')
              .allMatches(source);
      for (final match in directives) {
        final uri = match.group(1) ?? match.group(2)!;
        if (uri == 'dart:io') {
          offender ??= path;
          continue;
        }
        if (uri.startsWith('dart:')) continue;

        final String target;
        if (uri.startsWith('package:jbig2/')) {
          target = uri.replaceFirst('package:jbig2/', 'lib/');
        } else if (uri.startsWith('package:')) {
          continue;
        } else {
          target = _normalize('${_directory(path)}/$uri');
        }
        trail.putIfAbsent(target, () => path);
        walk(target);
      }
    }

    walk('lib/jbig2.dart');

    expect(visited, isNotEmpty, reason: 'the facade resolved to nothing');
    expect(
      offender,
      isNull,
      reason: 'dart:io is reachable from lib/jbig2.dart through $offender '
          '(imported by ${trail[offender]})',
    );
  });
}

String _directory(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '.' : path.substring(0, index);
}

/// Collapses `a/b/../c` to `a/c`, which is all the relative directives need.
String _normalize(String path) {
  final parts = <String>[];
  for (final segment in path.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

import 'dart:collection';

import '../bitmap.dart';
import '../image/bitmaps.dart';
import '../util/combination_operator.dart';

class ExtractedSymbolInstance {
  final int symbol;
  final int x;
  final int y;

  const ExtractedSymbolInstance(this.symbol, this.x, this.y);
}

class ExtractedSymbols {
  final List<Bitmap> dictionary;
  final List<ExtractedSymbolInstance> instances;

  const ExtractedSymbols(this.dictionary, this.instances);

  Bitmap reconstruct(int width, int height) {
    final result = Bitmap(width, height);
    for (final instance in instances) {
      Bitmaps.blit(dictionary[instance.symbol], result, instance.x, instance.y,
          CombinationOperator.OR);
    }
    return result;
  }
}

/// Separa componentes pretos 8-conectados e deduplica glifos idênticos.
class SymbolExtractor {
  final Bitmap bitmap;

  const SymbolExtractor(this.bitmap);

  ExtractedSymbols extract() {
    final visited = List<bool>.filled(bitmap.width * bitmap.height, false);
    final rawSymbols = <Bitmap>[];
    final rawInstances = <({int raw, int x, int y})>[];
    final byShape = <String, List<int>>{};

    for (var y = 0; y < bitmap.height; y++) {
      for (var x = 0; x < bitmap.width; x++) {
        final start = y * bitmap.width + x;
        if (visited[start] || bitmap.getPixel(x, y) == 0) continue;
        final points = <int>[];
        final queue = Queue<int>()..add(start);
        visited[start] = true;
        var left = x, right = x, top = y, bottom = y;
        while (queue.isNotEmpty) {
          final point = queue.removeLast();
          points.add(point);
          final px = point % bitmap.width;
          final py = point ~/ bitmap.width;
          if (px < left) left = px;
          if (px > right) right = px;
          if (py < top) top = py;
          if (py > bottom) bottom = py;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = px + dx, ny = py + dy;
              if (nx < 0 ||
                  ny < 0 ||
                  nx >= bitmap.width ||
                  ny >= bitmap.height) {
                continue;
              }
              final next = ny * bitmap.width + nx;
              if (!visited[next] && bitmap.getPixel(nx, ny) != 0) {
                visited[next] = true;
                queue.add(next);
              }
            }
          }
        }

        final symbol = Bitmap(right - left + 1, bottom - top + 1);
        for (final point in points) {
          symbol.setPixel(
              point % bitmap.width - left, point ~/ bitmap.width - top, 1);
        }
        final key =
            '${symbol.width}x${symbol.height}:${symbol.bitmap.join(',')}';
        var raw = -1;
        for (final candidate in byShape[key] ?? const <int>[]) {
          if (_same(rawSymbols[candidate], symbol)) {
            raw = candidate;
            break;
          }
        }
        if (raw < 0) {
          raw = rawSymbols.length;
          rawSymbols.add(symbol);
          byShape.putIfAbsent(key, () => []).add(raw);
        }
        rawInstances.add((raw: raw, x: left, y: top));
      }
    }

    final order = List<int>.generate(rawSymbols.length, (i) => i)
      ..sort((a, b) {
        final height = rawSymbols[a].height.compareTo(rawSymbols[b].height);
        return height != 0
            ? height
            : rawSymbols[a].width.compareTo(rawSymbols[b].width);
      });
    final remap = <int, int>{};
    for (var i = 0; i < order.length; i++) {
      remap[order[i]] = i;
    }
    final dictionary = [for (final i in order) rawSymbols[i]];
    final instances = [
      for (final instance in rawInstances)
        ExtractedSymbolInstance(remap[instance.raw]!, instance.x, instance.y)
    ]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    return ExtractedSymbols(dictionary, instances);
  }

  static bool _same(Bitmap a, Bitmap b) {
    if (a.width != b.width || a.height != b.height) return false;
    for (var i = 0; i < a.bitmap.length; i++) {
      if (a.bitmap[i] != b.bitmap[i]) return false;
    }
    return true;
  }
}

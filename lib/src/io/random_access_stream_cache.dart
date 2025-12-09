import 'closeable.dart';
import 'random_access.dart';

typedef StreamCacheCreateFunction = RandomAccessStreamCache Function();

abstract class RandomAccessStreamCache implements Closeable {
  RandomAccess createBuffer();
}

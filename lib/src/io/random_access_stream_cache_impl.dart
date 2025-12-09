import 'random_access.dart';
import 'random_access_read_buffer.dart';
import 'random_access_stream_cache.dart';

class RandomAccessStreamCacheImpl implements RandomAccessStreamCache {
  @override
  void close() {}

  @override
  RandomAccess createBuffer() => RandomAccessReadWriteBuffer();
}

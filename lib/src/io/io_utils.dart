import 'package:logging/logging.dart';

import 'closeable.dart';
import 'exceptions.dart';
import 'random_access_stream_cache.dart';
import 'random_access_stream_cache_impl.dart';
import 'memory_usage_setting.dart';

class IOUtils {
  static final Logger _logger = Logger('IOUtils');

  IOUtils._();

  static void closeQuietly(Closeable? closeable) {
    if (closeable == null) {
      return;
    }
    try {
      closeable.close();
    } catch (e, s) {
      _logger.fine('Ignoring exception while closing resource: $e\n$s');
    }
  }

  static IOException? closeAndLogException(
    Closeable closeable,
    Logger logger,
    String resourceName, [
    IOException? initialException,
  ]) {
    try {
      closeable.close();
    } catch (e) {
      final ioe = e is IOException ? e : IOException(e.toString());
      logger.warning('Error closing $resourceName', ioe);
      if (initialException == null) {
        return ioe;
      }
    }
    return initialException;
  }

  static StreamCacheCreateFunction createMemoryOnlyStreamCache() {
    return () => RandomAccessStreamCacheImpl();
  }

  static StreamCacheCreateFunction createTempFileOnlyStreamCache() {
    return MemoryUsageSetting.setupTempFileOnly().streamCache;
  }
}

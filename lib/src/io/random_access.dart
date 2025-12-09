import 'random_access_read.dart';
import 'random_access_write.dart';

/// Combines read and write capabilities for random-access buffers.
abstract class RandomAccess implements RandomAccessRead, RandomAccessWrite {}

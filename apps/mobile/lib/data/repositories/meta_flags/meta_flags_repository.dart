import '../../../domain/models/meta_flags.dart';

/// Reads the server flags in `meta/flags` (see [MetaFlags]). Readable before
/// sign-in: the build gate has to run before anyone signs in.
abstract class MetaFlagsRepository {
  /// One read. Null when the flags can't be read (offline, [timeout],
  /// permission error, missing document): callers fail open for the build
  /// gate and closed for video uploads.
  Future<MetaFlags?> read({Duration timeout = const Duration(seconds: 3)});

  /// The flags as they change; null for a failed read, never an error.
  Stream<MetaFlags?> watch();
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the user picked, before its bytes are read.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    required this.read,
    this.path,
  });

  final String name;

  /// Size in bytes, or null when the platform didn't report it.
  final int? size;

  final Future<Uint8List> Function() read;

  /// On-disk path, for uploads too big to read into memory; null where the
  /// platform gives none (web).
  final String? path;
}

/// Wraps the platform file dialogs.
class FilePickerService {
  /// Lets the user pick files; [imagesOnly] limits it to photos. Empty when
  /// cancelled.
  Future<List<PickedFile>> pick({bool imagesOnly = false}) async {
    final files = await FilePicker.pickFiles(
      type: imagesOnly ? FileType.image : FileType.any,
    );
    return [
      for (final f in files)
        PickedFile(
          name: f.name,
          size: f.lengthSync() ?? await f.length(),
          read: f.readAsBytes,
          path: f.path,
        ),
    ];
  }

  /// Lets the user pick one video file with one of the [extensions];
  /// null when cancelled.
  Future<PickedFile?> pickVideo(List<String> extensions) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final f = files.firstOrNull;
    if (f == null) return null;
    return PickedFile(
      name: f.name,
      size: f.lengthSync() ?? await f.length(),
      read: f.readAsBytes,
      path: f.path,
    );
  }

  /// Asks where to save [bytes] as [fileName]. False when cancelled.
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async =>
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      ) !=
      null;
}

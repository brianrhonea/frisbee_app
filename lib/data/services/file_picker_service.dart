import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/models/chat.dart';
import 'device_permissions.dart';
import 'feature_flags.dart';
import 'image_compressor.dart';

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

/// Wraps the platform file dialogs, and the camera on phones.
class FilePickerService {
  FilePickerService({
    ImageCompressor compressor = const ImageCompressor(),
    FeatureFlags? flags,
    ImagePicker? camera,
    DevicePermissions permissions = const DevicePermissions(),
  }) : _compressor = compressor,
       _flags = flags,
       _camera = camera,
       _permissions = permissions;

  final DevicePermissions _permissions;

  final ImageCompressor _compressor;
  final FeatureFlags? _flags;
  ImagePicker? _camera;

  ImagePicker get _images => _camera ??= ImagePicker();

  /// Longest video the camera records for a message. Half a minute keeps
  /// a phone's full-quality recording under maxVideoBytes.
  static const maxVideoLength = Duration(seconds: 30);

  /// Whether this device can take photos and videos here (phones; desktop
  /// and web pick files instead).
  bool get canUseCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Opens the camera for a photo; null when cancelled. Throws
  /// [AccessDeniedException] if camera access was refused.
  Future<PickedFile?> takePhoto() => _withCamera(
    () => _images.pickImage(
      source: ImageSource.camera,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 88,
    ),
  );

  /// Opens the camera to record a video with sound, up to
  /// [maxVideoLength]; null when cancelled.
  Future<PickedFile?> recordVideo() => _withCamera(
    () => _images.pickVideo(
      source: ImageSource.camera,
      maxDuration: maxVideoLength,
    ),
  );

  Future<PickedFile?> _withCamera(Future<XFile?> Function() open) async {
    // Android won't open the camera for an app that declares the camera
    // permission (meetings do) until it's granted; iOS asks by itself.
    if (defaultTargetPlatform == TargetPlatform.android &&
        await _permissions.request(DeviceAccess.camera) !=
            AccessStatus.allowed) {
      throw const AccessDeniedException(DeviceAccess.camera);
    }
    final XFile? x;
    try {
      x = await open();
    } on PlatformException catch (e) {
      if (e.code.contains('access_denied')) {
        throw const AccessDeniedException(DeviceAccess.camera);
      }
      rethrow;
    }
    return x == null ? null : _fromX(x);
  }

  static Future<PickedFile> _fromX(XFile x) async => PickedFile(
    name: x.name,
    size: await x.length(),
    read: x.readAsBytes,
    path: kIsWeb ? null : x.path,
  );

  /// Shrinks picked photos before they're attached, unless the
  /// `compress_images` kill switch is off.
  ImageCompressor get compressor => _flags?.compressImages ?? true
      ? _compressor
      : const ImageCompressor(enabled: false);

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

/// Reads [file] into an attachment, shrinking photos with the picker's
/// [ImageCompressor]. Null when the file is too big to even read.
Future<NewAttachment?> readAttachment(
  FilePickerService picker,
  PickedFile file,
) async {
  final type = contentTypeFor(file.name);
  final isImage = type.startsWith('image/');
  final limit = isImage ? maxPickedImageBytes : maxBytesFor(type);
  if ((file.size ?? 0) > limit) return null;
  final bytes = await file.read();
  if (!isImage) return NewAttachment(name: file.name, bytes: bytes);
  final shrunk = await picker.compressor.shrink(file.name, bytes);
  return NewAttachment(name: shrunk.name, bytes: shrunk.bytes);
}

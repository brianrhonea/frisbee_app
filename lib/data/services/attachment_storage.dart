import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/models/chat.dart';

/// Message attachments in Cloud Storage, for team chat and direct messages.
/// storage.rules decides who can read and write each folder.
class AttachmentStorage {
  AttachmentStorage({FirebaseStorage? storage}) : _override = storage;

  final FirebaseStorage? _override;

  // Resolved lazily so the app starts even where Storage isn't set up.
  FirebaseStorage get _storage => _override ?? FirebaseStorage.instance;

  /// Uploads [attachments] into [folder]. If one fails, the ones already
  /// uploaded are removed before rethrowing.
  Future<List<ChatAttachment>> upload(
    String folder,
    List<NewAttachment> attachments,
  ) async {
    final uploaded = <ChatAttachment>[];
    String? current;
    try {
      for (final (i, a) in attachments.indexed) {
        final path = current = '$folder/$i-${_safeName(a.name)}';
        await _storage
            .ref(path)
            .putData(a.bytes, SettableMetadata(contentType: a.contentType));
        uploaded.add(
          ChatAttachment(
            path: path,
            name: a.name,
            contentType: a.contentType,
            size: a.size,
          ),
        );
      }
      return uploaded;
    } catch (_) {
      // A failed step may still have stored the file, so remove that too.
      await delete({
        ...uploaded.map((a) => a.path),
        ?current,
      }).catchError((Object _) => <void>[]);
      rethrow;
    }
  }

  /// Deletes files; ones already gone are skipped.
  Future<void> delete(Iterable<String> paths) => Future.wait([
    for (final p in paths)
      _storage.ref(p).delete().catchError((Object e) {
        if (e is FirebaseException && e.code == 'object-not-found') return;
        throw e;
      }),
  ]);

  Future<Uint8List> download(ChatAttachment attachment) async {
    final data = await _storage
        .ref(attachment.path)
        .getData(maxAttachmentBytes);
    if (data == null) throw Exception('Attachment not found.');
    return data;
  }

  /// Keeps names readable while dropping characters that would add path
  /// segments or trip up storage URLs.
  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
    final short = cleaned.length > 80
        ? cleaned.substring(cleaned.length - 80)
        : cleaned;
    return short.isEmpty ? 'file' : short;
  }
}

/// Storage paths of attachments in raw message data.
Iterable<String> attachmentPaths(Map<String, dynamic> message) sync* {
  for (final a in (message['attachments'] as List?) ?? const []) {
    if (a is Map && a['path'] is String) yield a['path'] as String;
  }
}

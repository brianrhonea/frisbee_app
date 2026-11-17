import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/chat.dart';
import '../../domain/models/outbox.dart';

/// Where queued items and their attachments are kept until they go out.
abstract class OutboxStore {
  Future<List<OutboxJob>> load();
  Future<void> save(List<OutboxJob> jobs);

  /// Keeps [file] (attachment [index] of [jobId]) until the job is done.
  Future<OutboxFile> putFile(String jobId, int index, NewAttachment file);
  Future<Uint8List> readFile(OutboxFile file);
  Future<void> deleteFiles(String jobId);
}

/// [OutboxStore] in the app's support folder: `outbox/jobs.json` and
/// `outbox/<job id>/<n>`. The folder is the app's own (not backed up to
/// iCloud by default on iOS, not shared with other apps), but items aren't
/// encrypted: they're what the user wrote, waiting to go out.
class FileOutboxStore implements OutboxStore {
  FileOutboxStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;
  Directory? _dir;

  Future<Directory> get _folder async => _dir ??= await Directory(
    '${(await _root()).path}/outbox',
  ).create(recursive: true);

  Future<File> get _jobs async => File('${(await _folder).path}/jobs.json');

  @override
  Future<List<OutboxJob>> load() async {
    try {
      final f = await _jobs;
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString());
      if (list is! List) return [];
      return [
        for (final j in list)
          if (j is Map) ?OutboxJob.fromJson(Map<String, Object?>.from(j)),
      ];
    } on Exception {
      // A damaged file loses the queue, not the app.
      return [];
    }
  }

  @override
  Future<void> save(List<OutboxJob> jobs) async {
    final f = await _jobs;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final j in jobs) j.toJson()]));
    // Replaced in one step, so a crash mid-write keeps the old list.
    await tmp.rename(f.path);
  }

  @override
  Future<OutboxFile> putFile(
    String jobId,
    int index,
    NewAttachment file,
  ) async {
    final dir = await Directory('${(await _folder).path}/$jobId').create();
    final path = '$jobId/$index';
    await File('${dir.path}/$index').writeAsBytes(file.bytes, flush: true);
    return OutboxFile(name: file.name, path: path, size: file.size);
  }

  @override
  Future<Uint8List> readFile(OutboxFile file) async =>
      File('${(await _folder).path}/${file.path}').readAsBytes();

  @override
  Future<void> deleteFiles(String jobId) async {
    final dir = Directory('${(await _folder).path}/$jobId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

import 'dart:typed_data';

import 'package:frisbee_app/data/services/outbox_store.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/outbox.dart';

/// Keeps the queue in memory; [saved] is what a restart would read.
class MemoryOutboxStore implements OutboxStore {
  List<Map<String, Object?>> saved = [];
  final files = <String, Uint8List>{};

  @override
  Future<List<OutboxJob>> load() async => [
    for (final j in saved) ?OutboxJob.fromJson(j),
  ];

  @override
  Future<void> save(List<OutboxJob> jobs) async =>
      saved = [for (final j in jobs) j.toJson()];

  @override
  Future<OutboxFile> putFile(String jobId, int index, NewAttachment f) async {
    files['$jobId/$index'] = f.bytes;
    return OutboxFile(name: f.name, path: '$jobId/$index', size: f.size);
  }

  @override
  Future<Uint8List> readFile(OutboxFile f) async => files[f.path]!;

  @override
  Future<void> deleteFiles(String jobId) async =>
      files.removeWhere((k, _) => k.startsWith('$jobId/'));
}

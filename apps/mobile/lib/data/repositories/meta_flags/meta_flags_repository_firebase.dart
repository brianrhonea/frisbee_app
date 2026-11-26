import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/meta_flags.dart';
import 'meta_flags_repository.dart';

/// [MetaFlagsRepository] over the Firestore document `meta/flags`. The rules
/// let anyone read it, signed out too; nobody can write it from a client.
class MetaFlagsRepositoryFirebase implements MetaFlagsRepository {
  MetaFlagsRepositoryFirebase({FirebaseFirestore? firestore}) : _db = firestore;

  final FirebaseFirestore? _db;

  DocumentReference<Map<String, dynamic>> get _doc =>
      (_db ?? FirebaseFirestore.instance).doc('meta/flags');

  @override
  Future<MetaFlags?> read({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final snap = await _doc.get().timeout(timeout);
      return snap.exists ? MetaFlags.parse(snap.data()) : null;
    } on Object {
      return null;
    }
  }

  @override
  Stream<MetaFlags?> watch() async* {
    try {
      await for (final snap in _doc.snapshots()) {
        yield snap.exists ? MetaFlags.parse(snap.data()) : null;
      }
    } on Object {
      // A failed listener ends the stream; say "unreadable" once and let
      // the caller listen again on its next check.
      yield null;
    }
  }
}

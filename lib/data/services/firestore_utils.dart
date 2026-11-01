import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Counts the document reads Firestore bills listeners for, by query
/// label, and in debug builds logs the totals every minute. Reads served
/// from the local cache aren't billed and aren't counted.
abstract final class FirestoreReads {
  static final _log = Logger('FirestoreReads');
  static final _counts = <String, int>{};
  static Timer? _timer;

  /// Reads so far per label.
  static Map<String, int> get counts => Map.unmodifiable(_counts);

  static int get total => _counts.values.fold(0, (a, b) => a + b);

  static void add(String label, int reads) {
    if (reads <= 0) return;
    _counts.update(label, (n) => n + reads, ifAbsent: () => reads);
    if (kDebugMode) {
      _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _report());
    }
  }

  static void _report() {
    final top = _counts.entries.toList()..sort((a, b) => b.value - a.value);
    _log.info(
      'Firestore reads: $total total; '
      '${top.take(12).map((e) => '${e.key}=${e.value}').join(', ')}',
    );
  }

  static void reset() => _counts.clear();
}

/// [query]'s snapshots, counting the documents each server snapshot is
/// billed for under [label]: every document the first time, then each
/// changed one.
Stream<QuerySnapshot<Map<String, dynamic>>> countedSnapshots(
  Query<Map<String, dynamic>> query,
  String label,
) => query.snapshots().map((s) {
  // An empty result still costs one read.
  if (!s.metadata.isFromCache) {
    FirestoreReads.add(label, s.docChanges.isEmpty ? 1 : s.docChanges.length);
  }
  return s;
});

/// [ref]'s snapshots, counting one read per server snapshot under [label].
Stream<DocumentSnapshot<Map<String, dynamic>>> countedDocSnapshots(
  DocumentReference<Map<String, dynamic>> ref,
  String label,
) => ref.snapshots().map((s) {
  if (!s.metadata.isFromCache) FirestoreReads.add(label, 1);
  return s;
});

/// Converts Firestore-specific values (e.g. [Timestamp]) into plain Dart
/// types so domain models never depend on Firebase.
Map<String, dynamic> plainData(Map<String, dynamic>? data) =>
    (data ?? const {}).map((k, v) => MapEntry(k, _plain(v)));

Object? _plain(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  Map m => m.map((k, v) => MapEntry('$k', _plain(v))),
  List l => l.map(_plain).toList(),
  _ => value,
};

/// Deletes [refs] in batches (a batch holds at most 500 writes).
Future<void> deleteDocs(
  FirebaseFirestore db,
  Iterable<DocumentReference<Object?>> refs,
) async {
  final all = refs.toList();
  for (var i = 0; i < all.length; i += 450) {
    final batch = db.batch();
    for (final r in all.skip(i).take(450)) {
      batch.delete(r);
    }
    await batch.commit();
  }
}

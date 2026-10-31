import 'package:cloud_firestore/cloud_firestore.dart';

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

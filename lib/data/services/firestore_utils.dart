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

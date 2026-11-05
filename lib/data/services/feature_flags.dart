import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Kill switches for newer behaviour, read live from the `meta/flags`
/// document. Editing that document in the Firebase console turns a feature
/// off (or on) in every running app at once, with no new build: the
/// one-click rollback for the app side (docs/rollback.md).
///
/// Until the document loads (or when a key is missing) [defaults] apply.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore,
      _auth = auth;

  /// Values used until `meta/flags` says otherwise.
  static const defaults = <String, bool>{
    // Search through the rate-limited `api-search` Cloud Function. Off
    // until the `api` functions are deployed to the project.
    'use_api_search': false,
    // Shrink photos before upload (ImageCompressor).
    'compress_images': true,
  };

  /// Flags fixed in code, for tests.
  FeatureFlags.fixed(Map<String, bool> values) : _db = null, _auth = null {
    _values.addAll(values);
  }

  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;
  final _values = <String, bool>{};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _flagsSub;

  bool get useApiSearch => _flag('use_api_search');
  bool get compressImages => _flag('compress_images');

  bool _flag(String key) => _values[key] ?? defaults[key] ?? false;

  /// Follows `meta/flags` while someone is signed in (the rules only let
  /// signed-in users read it).
  void start() {
    _authSub ??= (_auth ?? FirebaseAuth.instance).authStateChanges().listen((
      user,
    ) {
      _flagsSub?.cancel();
      _flagsSub = null;
      if (user == null) return;
      _flagsSub = (_db ?? FirebaseFirestore.instance)
          .doc('meta/flags')
          .snapshots()
          .listen(_apply, onError: (Object _) {});
    });
  }

  void _apply(DocumentSnapshot<Map<String, dynamic>> snap) {
    final next = <String, bool>{
      for (final MapEntry(:key, :value) in (snap.data() ?? const {}).entries)
        if (value is bool) key: value,
    };
    if (mapEquals(next, _values)) return;
    _values
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _flagsSub?.cancel();
    super.dispose();
  }
}

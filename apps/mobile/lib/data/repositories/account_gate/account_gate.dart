import 'package:flutter/foundation.dart';

import '../auth/auth_repository.dart';

/// What the account gate (docs/specifications/contracts/account-gate.md)
/// says is still missing for the signed-in account: the fields of the
/// API's 403 `account_incomplete`, in the contract's order. The router
/// sends the person to the matching step; the steps clear their field
/// when they succeed. Also holds the adults-only dead end.
///
/// Reset whenever the signed-in account changes.
class AccountGate extends ChangeNotifier {
  AccountGate({AuthRepository? auth}) : _auth = auth {
    _uid = auth?.currentUser?.uid;
    auth?.addListener(_onAuth);
  }

  static const emailUnverified = 'email_unverified';
  static const age = 'age';
  static const terms = 'terms';

  /// The order the API reports them in.
  static const order = [emailUnverified, age, terms];

  final AuthRepository? _auth;
  String? _uid;
  final _missing = <String>{};
  bool _underAge = false;

  void _onAuth() {
    final uid = _auth?.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    reset();
  }

  /// The first thing missing, or null.
  String? get first {
    for (final f in order) {
      if (_missing.contains(f)) return f;
    }
    return null;
  }

  bool has(String field) => _missing.contains(field);

  /// Someone under 18 gave a birth date: a dead end, not a form.
  bool get underAge => _underAge;

  /// The API refused a write for [fields] (unknown names are ignored).
  void report(Iterable<String> fields) {
    final known = fields.where(order.contains).toSet();
    if (known.isEmpty ||
        (known.length == _missing.length && _missing.containsAll(known))) {
      return;
    }
    _missing
      ..clear()
      ..addAll(known);
    notifyListeners();
  }

  /// A step finished: [field] is no longer missing.
  void clear(String field) {
    if (_missing.remove(field)) notifyListeners();
  }

  void markUnderAge() {
    if (_underAge) return;
    _underAge = true;
    notifyListeners();
  }

  void reset() {
    if (_missing.isEmpty && !_underAge) return;
    _missing.clear();
    _underAge = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';

/// The "Complete your details" card on Home, for accounts made before
/// personal details were asked at sign-up. Dismissed per account.
class PersonalPromptViewModel extends ChangeNotifier {
  PersonalPromptViewModel({
    required PersonalDetailsRepository personalRepository,
    required AuthRepository authRepository,
  }) : _personal = personalRepository,
       _auth = authRepository {
    _personal.addListener(notifyListeners);
    _loadDismissed();
  }

  final PersonalDetailsRepository _personal;
  final AuthRepository _auth;
  bool _dismissed = true;

  String get _key => 'personalPrompt.${_auth.currentUser?.uid}';

  bool get visible => !_dismissed && _personal.shouldPrompt;

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissed = prefs.getBool(_key) ?? false;
    } on Exception {
      _dismissed = false;
    }
    notifyListeners();
  }

  Future<void> dismiss() async {
    _dismissed = true;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } on Exception {
      // Shown again next launch; fine.
    }
  }

  @override
  void dispose() {
    _personal.removeListener(notifyListeners);
    super.dispose();
  }
}

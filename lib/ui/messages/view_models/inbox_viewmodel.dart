import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';

/// The user's direct-message conversations, newest first.
class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
  }) : uid = authRepository.currentUser?.uid ?? '' {
    _sub = directMessageRepository
        .watchConversations(uid)
        .listen(
          (c) {
            _conversations = c;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _conversations ??= const [];
            notifyListeners();
          },
        );
  }

  final String uid;
  late final StreamSubscription<List<Conversation>> _sub;
  List<Conversation>? _conversations;
  Object? _error;

  bool get loaded => _conversations != null;
  List<Conversation> get conversations => _conversations ?? const [];
  Object? get error => _error;

  bool isUnread(Conversation c) => c.isUnread(uid);

  String? _selectedId;

  /// The conversation open beside the list on wide screens: the one
  /// picked, else the newest.
  String? get selectedId {
    final picked = _selectedId;
    if (picked != null && conversations.any((c) => c.id == picked)) {
      return picked;
    }
    return conversations.firstOrNull?.id;
  }

  void select(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

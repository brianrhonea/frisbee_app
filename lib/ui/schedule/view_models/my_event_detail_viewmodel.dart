import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// One event on the user's personal schedule.
class MyEventDetailViewModel extends ChangeNotifier {
  MyEventDetailViewModel({
    required this.eventId,
    required EventRepository eventRepository,
    required AuthRepository authRepository,
  }) : _events = eventRepository,
       _uid = authRepository.currentUser?.uid ?? '' {
    deleteEvent = Command0<void>(_delete);
    _sub = _events
        .watchMyEvent(_uid, eventId)
        .listen(
          (e) {
            _event = e;
            _loaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String eventId;
  final EventRepository _events;
  final String _uid;
  late final StreamSubscription<TeamEvent?> _sub;

  TeamEvent? _event;
  TeamEvent? get event => _event;

  bool _loaded = false;
  bool get loaded => _loaded;

  Object? _error;
  Object? get error => _error;

  late final Command0<void> deleteEvent;

  Future<Result<void>> _delete() => _events.deleteMyEvent(_uid, eventId);

  @override
  void dispose() {
    _sub.cancel();
    deleteEvent.dispose();
    super.dispose();
  }
}

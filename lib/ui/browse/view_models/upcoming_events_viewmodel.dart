import 'package:flutter/foundation.dart';

import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/browse.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Public team events and group tournaments still to come, for everyone.
class UpcomingEventsViewModel extends ChangeNotifier {
  UpcomingEventsViewModel({required BrowseRepository browseRepository})
    : _browse = browseRepository {
    load = Command0<void>(_load)..execute();
  }

  final BrowseRepository _browse;

  late final Command0<void> load;

  UpcomingEvents _upcoming = const UpcomingEvents();
  UpcomingEvents get upcoming => _upcoming;

  bool get isEmpty => _upcoming.events.isEmpty && _upcoming.tournaments.isEmpty;

  Future<Result<void>> _load() async {
    switch (await _browse.upcoming()) {
      case Ok(:final value):
        _upcoming = value;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  @override
  void dispose() {
    load.dispose();
    super.dispose();
  }
}

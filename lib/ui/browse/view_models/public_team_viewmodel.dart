import 'package:flutter/foundation.dart';

import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/browse.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'post_images.dart';

/// A team or group's public page for signed-out visitors.
class PublicTeamViewModel extends ChangeNotifier with PostImages {
  PublicTeamViewModel({
    required this.teamId,
    required BrowseRepository browseRepository,
  }) : browse = browseRepository {
    load = Command0<void>(_load)..execute();
  }

  final String teamId;

  @override
  final BrowseRepository browse;

  late final Command0<void> load;

  PublicTeamPage? _page;

  /// Null until loaded.
  PublicTeamPage? get page => _page;

  Future<Result<void>> _load() async {
    switch (await browse.team(teamId)) {
      case Ok(:final value):
        _page = value;
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

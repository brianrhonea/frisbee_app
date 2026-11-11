import 'package:flutter/foundation.dart';

import '../../../data/services/geocoding_service.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Picks where a group plays: search an address, choose a match, then
/// nudge the pin by tapping the map.
class LocationPickerViewModel extends ChangeNotifier {
  LocationPickerViewModel({
    required GeocodingService geocoding,
    GroupLocation? initial,
  }) : _geocoding = geocoding,
       _picked = initial {
    search = Command1<List<GroupLocation>, String>(_search);
  }

  final GeocodingService _geocoding;

  late final Command1<List<GroupLocation>, String> search;

  GroupLocation? _picked;

  /// The chosen spot; null until one is picked.
  GroupLocation? get picked => _picked;

  List<GroupLocation> get results => switch (search.result) {
    Ok(:final value) => value,
    _ => const [],
  };

  bool get noMatches => search.completed && results.isEmpty;

  Future<Result<List<GroupLocation>>> _search(String query) async {
    try {
      return Result.ok(await _geocoding.search(query));
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  void pick(GroupLocation location) {
    _picked = location;
    notifyListeners();
  }

  /// Moves the pin, keeping the address the organizer chose or typed.
  void movePin(double latitude, double longitude) {
    _picked = GroupLocation(
      address: _picked?.address ?? '',
      latitude: latitude,
      longitude: longitude,
    );
    notifyListeners();
  }

  void setAddress(String address) {
    final p = _picked;
    if (p == null) return;
    _picked = GroupLocation(
      address: address.trim(),
      latitude: p.latitude,
      longitude: p.longitude,
    );
    notifyListeners();
  }
}

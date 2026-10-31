import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/team.dart';

/// Turns an address into map coordinates with OpenStreetMap's Nominatim
/// service (no API key). Its usage policy asks for an identifying
/// User-Agent and at most one request a second, so lookups only run when
/// an organizer searches, never as they type.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _userAgent = 'FrisbeeApp/1.0 (community group locations)';
  static const _limit = 5;

  /// Places matching [query], best first. Network errors are thrown.
  Future<List<GroupLocation>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final response = await _client.get(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'limit': '$_limit',
      }),
      headers: {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw GeocodingException(response.statusCode);
    }
    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    return [
      for (final place in body)
        if (place is Map)
          if ((
                double.tryParse('${place['lat']}'),
                double.tryParse('${place['lon']}'),
              )
              case (final double lat, final double lng))
            GroupLocation(
              address: _trim('${place['display_name'] ?? q}'),
              latitude: lat,
              longitude: lng,
            ),
    ];
  }

  /// Addresses are stored with a 200-character cap (firestore.rules).
  static String _trim(String address) =>
      address.length <= 200 ? address : address.substring(0, 200);
}

class GeocodingException implements Exception {
  const GeocodingException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Address search failed ($statusCode). Try again.';
}

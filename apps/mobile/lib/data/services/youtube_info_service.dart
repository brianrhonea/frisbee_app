import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/team_video.dart';

/// What YouTube says about a video that can be embedded.
typedef YouTubeInfo = ({String title, String channel});

/// Looks videos up with YouTube's public oEmbed endpoint (no API key).
/// It answers for public and unlisted videos that allow embedding, and
/// fails for private, deleted or embed-blocked ones.
class YouTubeInfoService {
  YouTubeInfoService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The video's title and channel, or null if it can't be embedded.
  /// Network errors are thrown.
  Future<YouTubeInfo?> lookUp(String youtubeId) async {
    final response = await _client.get(
      Uri.https('www.youtube.com', '/oembed', {
        'url': TeamVideo.watchUrlOf(youtubeId),
        'format': 'json',
      }),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map) return null;
    return (
      title: '${body['title'] ?? ''}',
      channel: '${body['author_name'] ?? ''}',
    );
  }
}

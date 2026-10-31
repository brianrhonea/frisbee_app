import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/youtube_info_service.dart';
import 'package:frisbee_app/domain/models/team_video.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('youtubeIdFrom', () {
    const id = 'dQw4w9WgXcQ';

    test('reads every common YouTube link shape', () {
      for (final link in [
        id,
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&t=42s&list=PL1',
        'youtube.com/watch?v=$id',
        'https://m.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'https://youtu.be/$id?si=abc&t=10',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id?feature=share',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube-nocookie.com/embed/$id',
        'https://music.youtube.com/watch?v=$id',
        '  https://youtu.be/$id  ',
      ]) {
        expect(TeamVideo.youtubeIdFrom(link), id, reason: link);
      }
    });

    test('rejects other sites, channels and broken ids', () {
      for (final link in [
        '',
        'not a link',
        'https://vimeo.com/123456789',
        'https://evil.example/watch?v=$id',
        'https://www.youtube.com/@ultiup',
        'https://www.youtube.com/playlist?list=PL1234567890',
        'https://www.youtube.com/watch?v=short',
        'https://youtu.be/',
        'javascript:alert(1)',
        'ftp://youtu.be/$id',
      ]) {
        expect(TeamVideo.youtubeIdFrom(link), isNull, reason: link);
      }
    });
  });

  test('stores only the id, folder, title and description', () {
    final v = TeamVideo.fromMap('v1', {
      'youtubeId': 'dQw4w9WgXcQ',
      'title': 'Film',
      'description': 'Zone O',
      'authorName': 'Casey',
      'createdAt': DateTime(2026, 11, 1),
    });
    expect(v.watchUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(v.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(v.folderId, '');
    expect(v.copyWith(title: '  Film 2  ', folderId: 'f1').toEditableMap(), {
      'youtubeId': 'dQw4w9WgXcQ',
      'folderId': 'f1',
      'title': 'Film 2',
      'description': 'Zone O',
    });
  });

  group('YouTubeInfoService', () {
    test('asks oEmbed for the title and channel', () async {
      late Uri asked;
      final service = YouTubeInfoService(
        client: MockClient((req) async {
          asked = req.url;
          return http.Response(
            jsonEncode({'title': 'Film review', 'author_name': 'Flyers'}),
            200,
          );
        }),
      );
      final info = await service.lookUp('dQw4w9WgXcQ');
      expect(info, (title: 'Film review', channel: 'Flyers'));
      expect(asked.host, 'www.youtube.com');
      expect(asked.path, '/oembed');
      expect(
        asked.queryParameters['url'],
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('private, deleted or embed-blocked videos come back null', () async {
      for (final code in [401, 403, 404]) {
        final service = YouTubeInfoService(
          client: MockClient((_) async => http.Response('Unauthorized', code)),
        );
        expect(await service.lookUp('dQw4w9WgXcQ'), isNull);
      }
    });
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../../domain/models/ranking.dart';
import '../../../domain/models/tournament.dart';
import '../../../domain/models/usau_team.dart';
import 'usau_parser.dart';

/// Fetches and parses pages from play.usaultimate.org directly from the app.
///
/// Stand-in for the `functions/src/usau` Cloud Functions until Firebase is
/// set up. Requests are sequential and spaced out to stay polite.
class UsauClient {
  UsauClient({
    http.Client? client,
    this.requestDelay = const Duration(seconds: 1),
  }) : _client = client ?? http.Client();

  static const _userAgent = 'FrisbeeApp/1.0 (team management app)';

  /// Safety cap on pages per ranking list (20 teams each).
  static const maxRankingPages = 50;

  /// Cap on extra tab requests per team page.
  static const maxTeamTabs = 3;

  static final _log = Logger('UsauClient');

  final http.Client _client;
  final Duration requestDelay;

  Future<String> _get(String url, {Map<String, String>? cookies}) async =>
      _send(http.Request('GET', Uri.parse(url)), cookies);

  Future<String> _post(
    String url,
    Map<String, String> fields, {
    Map<String, String>? cookies,
  }) async =>
      _send(http.Request('POST', Uri.parse(url))..bodyFields = fields, cookies);

  /// Sends [req]. When [cookies] is given, it is sent and updated from the
  /// response, since ASP.NET postbacks may depend on the session cookie.
  Future<String> _send(http.Request req, Map<String, String>? cookies) async {
    req.headers.addAll({'User-Agent': _userAgent, 'Accept': 'text/html'});
    if (cookies != null && cookies.isNotEmpty) {
      req.headers['Cookie'] = cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    final res = await http.Response.fromStream(
      await _client.send(req).timeout(const Duration(seconds: 30)),
    );
    if (res.statusCode != 200) {
      throw Exception('USA Ultimate returned ${res.statusCode} for ${req.url}');
    }
    final setCookie = res.headers['set-cookie'];
    if (cookies != null && setCookie != null) {
      // package:http joins multiple Set-Cookie headers with commas.
      for (final c in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
        final pair = c.split(';').first.trim();
        final eq = pair.indexOf('=');
        if (eq > 0) cookies[pair.substring(0, eq)] = pair.substring(eq + 1);
      }
    }
    // USAU pages are UTF-8; don't rely on the Content-Type charset, since
    // `res.body` falls back to Latin-1 without one.
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  Future<List<Tournament>> fetchTournaments() async {
    final tournaments = parseTournaments(
      await _get('$usauBase/events/tournament/'),
    );
    if (tournaments.isEmpty) {
      throw Exception(
        'No tournaments found; the USA Ultimate page may have changed.',
      );
    }
    return tournaments;
  }

  Future<List<RankSet>> fetchRankSets() async {
    final sets = parseRankSets(await _get('$usauBase/teams/events/rankings/'));
    if (sets.isEmpty) {
      throw Exception(
        'No rankings found; the USA Ultimate page may have changed.',
      );
    }
    return sets;
  }

  /// Fetches a team page plus its separately loaded "Events" / "Schedule"
  /// tabs, merged into one [UsauTeam]. A tab that fails to load is skipped
  /// so the roster still shows.
  Future<UsauTeam> fetchTeam(String url) async {
    final cookies = <String, String>{};
    final source = await _get(url, cookies: cookies);
    var team = parseUsauTeam(source, url: url);
    for (final tab in parseTeamTabs(source, pageUrl: url).take(maxTeamTabs)) {
      await Future<void>.delayed(requestDelay);
      try {
        final fields = tab.fields;
        final page = fields == null
            ? await _get(tab.url, cookies: cookies)
            : await _post(tab.url, fields, cookies: cookies);
        team = team.merge(parseUsauTeam(page, url: url));
      } on Exception catch (e) {
        _log.warning('Failed to load team tab ${tab.url}', e);
      }
    }
    return team;
  }

  /// Fetches every page of [set]'s rankings. The list is paged 20 teams at a
  /// time behind ASP.NET postbacks, so each "Next" link is replayed as a form
  /// post carrying the previous page's view state.
  Future<RankingDivision> fetchDivision(RankSet set) async {
    final cookies = <String, String>{};
    final entries = <RankingEntry>[];
    final seen = <String>{};
    var pageUrl = set.url;
    await Future<void>.delayed(requestDelay);
    var page = parseRankingsPage(await _get(pageUrl, cookies: cookies));
    for (var n = 1; ; n++) {
      final fresh = page.entries
          .where((e) => seen.add('${e.rank}|${e.teamName}'))
          .toList();
      entries.addAll(fresh);
      final next = page.next;
      // Stop if the server ignored the postback and re-sent the same page.
      if (next == null || fresh.isEmpty || n >= maxRankingPages) break;
      pageUrl = Uri.parse(pageUrl).resolve(next.action).toString();
      await Future<void>.delayed(requestDelay);
      page = parseRankingsPage(
        await _post(pageUrl, next.fields, cookies: cookies),
        rankOffset: entries.length,
      );
    }
    return RankingDivision(
      key: set.key,
      label: set.label,
      sourceUrl: set.url,
      updatedAt: DateTime.now(),
      entries: entries,
    );
  }
}

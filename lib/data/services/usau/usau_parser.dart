import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../../domain/models/ranking.dart';
import '../../../domain/models/tournament.dart';
import '../../../domain/models/usau_team.dart';

/// Dart port of `functions/src/usau/parse.ts`. Keep the two in sync until the
/// Cloud Functions take over scraping again.
const usauBase = 'https://play.usaultimate.org';

/// A published ranking list on USA Ultimate, e.g. "Club Men".
typedef RankSet = ({String key, String label, String title, String url});

String _clean(String? s) => (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

String _absolute(String? href) {
  if (href == null || href.isEmpty) return '';
  try {
    return Uri.parse(usauBase).resolve(href).toString();
  } on FormatException {
    return '';
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses "Nov 07, 2026" as UTC noon, so it shows as the same date in US
/// time zones.
DateTime? parseUsauDate(String text) {
  final m = RegExp(
    r'([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),\s*(\d{4})',
  ).firstMatch(text);
  if (m == null) return null;
  final month = _months[m[1]!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(int.parse(m[3]!), month, int.parse(m[2]!), 12);
}

/// Parses "Nov 07, 2026 - Nov 08, 2026" (end optional).
(DateTime?, DateTime?) parseDateRange(String text) {
  final parts = _clean(text).split(RegExp(r'\s+-\s+'));
  final start = parseUsauDate(parts.first);
  final end = parts.length > 1 ? parseUsauDate(parts[1]) : start;
  return (start, end);
}

String _titleCase(String s) => s.toLowerCase().replaceAllMapped(
  RegExp(r'\b[a-z]'),
  (m) => m[0]!.toUpperCase(),
);

const _divisionWords = ['Mixed', 'Women', 'Men', 'Girls', 'Boys', 'Open'];

/// Splits "College - Women" or "High School - Mixed DI" into
/// level ("College") and division ("Women").
({String level, String division}) parseCompetitionGroup(String group) {
  final g = _clean(group);
  final dash = g.indexOf(' - ');
  final level = dash >= 0 ? _titleCase(g.substring(0, dash)) : '';
  final rest = dash >= 0 ? g.substring(dash + 3) : g;
  final division =
      _divisionWords
          .where((w) => RegExp('\\b$w\\b', caseSensitive: false).hasMatch(rest))
          .firstOrNull ??
      '';
  return (level: level, division: division);
}

String _slugFromHref(String href) {
  final slug = href
      .replaceFirst(RegExp(r'^.*/events/', caseSensitive: false), '')
      .replaceFirst(RegExp(r'[/?#].*$'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
  return slug.length > 200 ? slug.substring(0, 200) : slug;
}

List<Element> _cells(Element tr) =>
    tr.children.where((e) => e.localName == 'td').toList();

/// Parses the "Current/Upcoming Events" and "Past Events" tables on
/// play.usaultimate.org/events/tournament/.
List<Tournament> parseTournaments(String source) {
  final doc = html.parse(source);
  final out = <String, Tournament>{};
  final tables = doc
      .querySelectorAll('table')
      .where(
        (t) =>
            (t.id).endsWith('gvCurrentUpcomingEvents') ||
            (t.id).endsWith('gvPastEvents'),
      );
  for (final table in tables) {
    for (final tr in table.querySelectorAll('tr')) {
      final cells = _cells(tr);
      if (cells.length < 6) continue;
      final link = cells[1].querySelector("a[href*='/events/']");
      final href = link?.attributes['href'];
      if (link == null || href == null) continue;
      final id = _slugFromHref(href);
      if (id.isEmpty) continue;

      final levels = <String, int>{};
      final divisions = <String>{};
      for (final li in cells[4].querySelectorAll('li')) {
        // Strip the "[24]" team count.
        final copy = li.clone(true);
        for (final span in copy.querySelectorAll('span')) {
          span.remove();
        }
        final (:level, :division) = parseCompetitionGroup(copy.text);
        if (level.isNotEmpty) levels[level] = (levels[level] ?? 0) + 1;
        if (division.isNotEmpty) divisions.add(division);
      }
      final topLevel = levels.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final (start, end) = parseDateRange(cells[5].text);

      out[id] = Tournament(
        id: id,
        name: _clean(link.text),
        url: _absolute(href),
        startDate: start,
        endDate: end,
        city: _clean(cells[2].text),
        state: _clean(cells[3].text),
        competitionLevel: topLevel.firstOrNull?.key ?? '',
        divisions: divisions.toList()..sort(),
      );
    }
  }
  return out.values.toList();
}

/// Parses the published rank sets on
/// play.usaultimate.org/teams/events/rankings/, keeping the first (newest)
/// entry per rank set.
List<RankSet> parseRankSets(String source) {
  final doc = html.parse(source);
  final out = <String, RankSet>{};
  final tables = doc
      .querySelectorAll('table')
      .where((t) => t.id.endsWith('gvRankSetList'));
  for (final table in tables) {
    for (final tr in table.querySelectorAll('tr')) {
      final cells = _cells(tr);
      if (cells.length < 5) continue;
      if (!RegExp(
        'published',
        caseSensitive: false,
      ).hasMatch(_clean(cells[1].text))) {
        continue;
      }
      final href = cells[4]
          .querySelector("a[href*='RankSet=']")
          ?.attributes['href'];
      if (href == null) continue;
      final url = _absolute(href);
      final raw = Uri.parse(url).queryParameters['RankSet'];
      if (raw == null || raw.isEmpty) continue;
      final key = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
      if (out.containsKey(key)) continue;
      final label = _clean(cells[2].text);
      out[key] = (
        key: key,
        label: label.isNotEmpty ? label : raw.replaceAll('-', ' '),
        title: _clean(cells[0].text),
        url: url,
      );
    }
  }
  return out.values.toList();
}

int? _toInt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^\d-]'), ''));

double? _toDouble(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^\d.-]'), ''));

enum _Column { rank, team, rating, wins, losses, record, region }

final _columnPatterns = <(_Column, RegExp)>[
  (_Column.rank, RegExp(r'^rank$|^#$|^place$', caseSensitive: false)),
  (_Column.team, RegExp(r'^team', caseSensitive: false)),
  (_Column.rating, RegExp(r'rating|power', caseSensitive: false)),
  (_Column.wins, RegExp(r'^wins?$|^w$', caseSensitive: false)),
  (_Column.losses, RegExp(r'^loss(es)?$|^l$', caseSensitive: false)),
  (_Column.record, RegExp(r'record|w\s*-\s*l', caseSensitive: false)),
  (_Column.region, RegExp(r'region|section|conference', caseSensitive: false)),
];

/// The fields an ASP.NET WebForms postback needs: every named input and
/// select in the page's form, plus `__EVENTTARGET`.
typedef UsauPostBack = ({String action, Map<String, String> fields});

/// One page of a paged team rankings list.
typedef RankingsPage = ({List<RankingEntry> entries, UsauPostBack? next});

Element? _closestTable(Element e) {
  for (var p = e.parent; p != null; p = p.parent) {
    if (p.localName == 'table') return p;
  }
  return null;
}

/// Rows that belong to [table] itself, not to tables nested in it (such as
/// the GridView pager).
Iterable<Element> _ownRows(Element table) =>
    table.querySelectorAll('tr').where((tr) => _closestTable(tr) == table);

final _postBackTarget = RegExp(r"""__doPostBack\(\s*['"]([^'"]+)['"]""");

/// Builds the form post that a `javascript:__doPostBack(...)` link inside
/// [scope] whose text matches [linkText] would send, or null if none exists.
UsauPostBack? _postBack(Document doc, Element scope, RegExp linkText) {
  final link = scope
      .querySelectorAll('a[href*="__doPostBack"]')
      .where((a) => linkText.hasMatch(_clean(a.text)))
      .firstOrNull;
  return link == null ? null : _postBackFor(doc, link);
}

/// Builds the form post that clicking the `__doPostBack` [link] would send.
UsauPostBack? _postBackFor(Document doc, Element link) {
  final target = _postBackTarget.firstMatch(link.attributes['href'] ?? '');
  final form = doc.querySelector('form');
  if (target == null || form == null) return null;

  final fields = <String, String>{};
  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name'];
    final type = (input.attributes['type'] ?? 'text').toLowerCase();
    if (name == null || name.isEmpty) continue;
    if (const {'submit', 'button', 'image', 'reset', 'file'}.contains(type)) {
      continue;
    }
    if ((type == 'checkbox' || type == 'radio') &&
        !input.attributes.containsKey('checked')) {
      continue;
    }
    fields[name] = input.attributes['value'] ?? '';
  }
  for (final select in form.querySelectorAll('select')) {
    final name = select.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final options = select.querySelectorAll('option');
    final selected =
        options
            .where((o) => o.attributes.containsKey('selected'))
            .firstOrNull ??
        options.firstOrNull;
    if (selected != null) {
      fields[name] = selected.attributes['value'] ?? _clean(selected.text);
    }
  }
  fields['__EVENTTARGET'] = target[1]!;
  fields['__EVENTARGUMENT'] = '';
  return (action: form.attributes['action'] ?? '', fields: fields);
}

/// Maps each column in [patterns] to the index of the first matching header
/// cell, using whichever of [table]'s own header rows matches the most
/// columns (a table may start with a one-cell title row).
Map<C, int> _matchHeaders<C>(Element table, List<(C, RegExp)> patterns) {
  var best = <C, int>{};
  for (final tr in _ownRows(table)) {
    final headers = tr.children.where((c) => c.localName == 'th').toList();
    if (headers.isEmpty) continue;
    final columns = <C, int>{};
    for (var i = 0; i < headers.length; i++) {
      final text = _clean(headers[i].text);
      for (final (col, re) in patterns) {
        if (!columns.containsKey(col) && re.hasMatch(text)) {
          columns[col] = i;
          break;
        }
      }
    }
    if (columns.length > best.length) best = columns;
  }
  return best;
}

/// Parses a team rankings page (team_rankings/?RankSet=...).
///
/// Columns are matched by header name, not position. Rows without a rank
/// column are ranked by order, starting after [rankOffset].
List<RankingEntry> parseRankings(String source, {int rankOffset = 0}) =>
    parseRankingsPage(source, rankOffset: rankOffset).entries;

/// Like [parseRankings], plus the postback for the "Next" pager link when
/// the list continues on another page.
RankingsPage parseRankingsPage(String source, {int rankOffset = 0}) {
  final doc = html.parse(source);

  Element? bestTable;
  var bestColumns = <_Column, int>{};
  for (final table in doc.querySelectorAll('table')) {
    final columns = _matchHeaders(table, _columnPatterns);
    final usable =
        columns.containsKey(_Column.team) &&
        (columns.containsKey(_Column.rank) ||
            columns.containsKey(_Column.rating));
    if (usable && columns.length > bestColumns.length) {
      bestTable = table;
      bestColumns = columns;
    }
  }
  if (bestTable == null) return (entries: const <RankingEntry>[], next: null);

  final teamIdx = bestColumns[_Column.team]!;
  final out = <RankingEntry>[];
  for (final tr in _ownRows(bestTable)) {
    final cells = _cells(tr);
    if (cells.length <= teamIdx) continue;
    // The pager row ("Rows: 1 - 20 of 80 ... 1 2 3 4") wraps a nested table.
    if (cells.any((c) => c.querySelector('table') != null)) continue;
    String cell(_Column c) {
      final i = bestColumns[c];
      return i == null || i >= cells.length ? '' : _clean(cells[i].text);
    }

    final teamCell = cells[teamIdx];
    final teamName = _clean(teamCell.text);
    if (teamName.isEmpty) continue;

    var wins = _toInt(cell(_Column.wins));
    var losses = _toInt(cell(_Column.losses));
    final record = RegExp(
      r'(\d+)\s*-\s*(\d+)',
    ).firstMatch(cell(_Column.record));
    if (record != null && wins == null && losses == null) {
      wins = int.parse(record[1]!);
      losses = int.parse(record[2]!);
    }

    out.add(
      RankingEntry(
        rank: _toInt(cell(_Column.rank)) ?? rankOffset + out.length + 1,
        teamName: teamName,
        rating: _toDouble(cell(_Column.rating)),
        wins: wins,
        losses: losses,
        region: cell(_Column.region),
        teamUrl: _absolute(teamCell.querySelector('a')?.attributes['href']),
      ),
    );
  }
  return (
    entries: out,
    next: _postBack(doc, bestTable, RegExp(r'^next', caseSensitive: false)),
  );
}

enum _RosterColumn { number, name, position, height, pronouns }

final _rosterPatterns = <(_RosterColumn, RegExp)>[
  (
    _RosterColumn.number,
    RegExp(r'^(#|no\.?|num(ber)?|jersey)$', caseSensitive: false),
  ),
  (
    _RosterColumn.name,
    RegExp(r'^(player|name|full name)', caseSensitive: false),
  ),
  (_RosterColumn.position, RegExp(r'^pos(ition)?', caseSensitive: false)),
  (_RosterColumn.height, RegExp(r'^h(eigh)?t', caseSensitive: false)),
  (_RosterColumn.pronouns, RegExp(r'pronoun', caseSensitive: false)),
];

enum _GameColumn { date, score, opponent }

final _gamePatterns = <(_GameColumn, RegExp)>[
  (_GameColumn.date, RegExp(r'^date', caseSensitive: false)),
  (_GameColumn.score, RegExp(r'score|result', caseSensitive: false)),
  (
    _GameColumn.opponent,
    RegExp(r'^(opponent|vs\.?|versus)', caseSensitive: false),
  ),
];

/// Parses a team page (teams/events/Eventteam/?TeamId=...).
///
/// Profile details come from `<dl>` term/description pairs. The roster and
/// schedule tables are found by header names; a one-cell row (or caption) in
/// a schedule table starts a new tournament.
UsauTeam parseUsauTeam(String source, {required String url}) {
  final doc = html.parse(source);
  final tables = doc.querySelectorAll('table');

  final info = <({String label, String value})>[];
  for (final dl in doc.querySelectorAll('dl')) {
    String? label;
    for (final child in dl.children) {
      if (child.localName == 'dt') {
        label = _clean(child.text).replaceFirst(RegExp(r':$'), '');
      } else if (child.localName == 'dd' && label != null) {
        final value = _clean(child.text);
        if (label.isNotEmpty && value.isNotEmpty) {
          info.add((label: label, value: value));
        }
        label = null;
      }
    }
  }

  // Real pages put the city in a paragraph rather than a <dl>.
  final city = _clean(doc.querySelector('.team_city')?.text);
  if (city.isNotEmpty && !info.any((i) => i.label == 'City')) {
    info.add((label: 'City', value: city));
  }

  final roster = <UsauPlayer>[];
  for (final table in tables) {
    final cols = _matchHeaders(table, _rosterPatterns);
    final nameIdx = cols[_RosterColumn.name];
    if (nameIdx == null || _matchHeaders(table, _gamePatterns).isNotEmpty) {
      continue;
    }
    for (final tr in _ownRows(table)) {
      final cells = _cells(tr);
      if (cells.length <= nameIdx) continue;
      if (cells.any((c) => c.querySelector('table') != null)) continue;
      String cell(_RosterColumn c) {
        final i = cols[c];
        return i == null || i >= cells.length ? '' : _clean(cells[i].text);
      }

      final name = cell(_RosterColumn.name);
      if (name.isEmpty) continue;
      roster.add(
        UsauPlayer(
          name: name,
          number: cell(_RosterColumn.number),
          position: cell(_RosterColumn.position),
          height: cell(_RosterColumn.height),
          pronouns: cell(_RosterColumn.pronouns),
        ),
      );
    }
  }

  final games = <UsauGame>[];
  for (final table in tables) {
    var cols = _matchHeaders(table, _gamePatterns);
    // The real right-rail schedule has no header row: date, score, opponent.
    if (cols.isEmpty && table.classes.contains('schedule_table')) {
      cols = {
        _GameColumn.date: 0,
        _GameColumn.score: 1,
        _GameColumn.opponent: 2,
      };
    }
    final opponentIdx = cols[_GameColumn.opponent];
    if (opponentIdx == null) continue;
    var tournament = _clean(table.querySelector('caption')?.text);
    for (final tr in _ownRows(table)) {
      final all = tr.children
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .toList();
      if (all.length == 1) {
        final text = _clean(all.single.text);
        if (text.isNotEmpty) tournament = text;
        continue;
      }
      final cells = _cells(tr);
      if (cells.length <= opponentIdx) continue;
      String cell(_GameColumn c) {
        final i = cols[c];
        return i == null || i >= cells.length ? '' : _clean(cells[i].text);
      }

      final opponentCell = cells[opponentIdx];
      final opponent = _clean(opponentCell.text);
      if (opponent.isEmpty) continue;
      games.add(
        UsauGame(
          opponent: opponent,
          tournament: tournament,
          date: cell(_GameColumn.date),
          score: cell(_GameColumn.score),
          opponentUrl: _absolute(
            opponentCell.querySelector('a')?.attributes['href'],
          ),
        ),
      );
    }
  }

  final events = <UsauEvent>[];
  for (final table in tables) {
    final cols = _matchHeaders(table, _eventPatterns);
    final nameIdx = cols[_EventColumn.name];
    if (nameIdx == null ||
        !cols.containsKey(_EventColumn.date) ||
        _matchHeaders(table, _gamePatterns).containsKey(_GameColumn.opponent)) {
      continue;
    }
    for (final tr in _ownRows(table)) {
      final cells = _cells(tr);
      if (cells.length <= nameIdx) continue;
      if (cells.any((c) => c.querySelector('table') != null)) continue;
      String cell(_EventColumn c) {
        final i = cols[c];
        return i == null || i >= cells.length ? '' : _clean(cells[i].text);
      }

      final nameCell = cells[nameIdx];
      final name = _clean(nameCell.text);
      if (name.isEmpty) continue;
      final dates = cell(_EventColumn.date);
      final (start, end) = parseDateRange(dates);
      events.add(
        UsauEvent(
          name: name,
          url: _absolute(nameCell.querySelector('a')?.attributes['href']),
          dates: dates,
          startDate: start,
          endDate: end,
          location: cell(_EventColumn.location),
          placement: cell(_EventColumn.placement),
        ),
      );
    }
  }

  final profileName = _clean(doc.querySelector('.profile_info h4')?.text);
  final heading = profileName.isNotEmpty
      ? profileName
      : doc
            .querySelectorAll('h1, h2, h3')
            .map((h) => _clean(h.text))
            .where((t) => t.isNotEmpty)
            .firstOrNull;
  return UsauTeam(
    name: heading ?? '',
    url: url,
    info: info,
    roster: roster,
    games: games,
    events: events,
  );
}

enum _EventColumn { name, date, location, placement }

final _eventPatterns = <(_EventColumn, RegExp)>[
  (_EventColumn.name, RegExp(r'^(event|tournament)', caseSensitive: false)),
  (_EventColumn.date, RegExp(r'date', caseSensitive: false)),
  (
    _EventColumn.location,
    RegExp(r'location|city|site|venue', caseSensitive: false),
  ),
  (
    _EventColumn.placement,
    RegExp(r'^(place|placement|finish|final|standing)', caseSensitive: false),
  ),
];

/// A follow-up request for another tab of a page: a GET of [url], or a POST
/// of [fields] to it for ASP.NET postback tabs.
typedef UsauRequest = ({String url, Map<String, String>? fields});

final _scheduleTab = RegExp(r'\b(events?|schedule)\b', caseSensitive: false);

/// Finds the team page's "Events" / "Schedule" tabs that load separately,
/// so their tournaments and games can be merged in. In-page anchors (#...)
/// are skipped since their content is already on [pageUrl], and plain links
/// count only if they stay on this team (so site navigation such as the
/// "Events" menu is ignored).
List<UsauRequest> parseTeamTabs(String source, {required String pageUrl}) {
  final doc = html.parse(source);
  final page = Uri.parse(pageUrl);
  final teamId = page.queryParameters['TeamId'];
  final out = <UsauRequest>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a[href]')) {
    final text = _clean(a.text);
    if (text.isEmpty || text.length > 30 || !_scheduleTab.hasMatch(text)) {
      continue;
    }
    final href = a.attributes['href']!.trim();
    if (href.startsWith('#')) continue;
    if (href.contains('__doPostBack')) {
      final postBack = _postBackFor(doc, a);
      if (postBack == null || !seen.add(postBack.fields['__EVENTTARGET']!)) {
        continue;
      }
      out.add((
        url: page.resolve(postBack.action).toString(),
        fields: postBack.fields,
      ));
      continue;
    }
    final Uri target;
    try {
      target = page.resolve(href);
    } on FormatException {
      continue;
    }
    final sameTeam =
        teamId != null &&
        target.host == page.host &&
        target.queryParameters['TeamId'] == teamId;
    final url = target.removeFragment().toString();
    if (!sameTeam || url == page.toString() || !seen.add(url)) continue;
    out.add((url: url, fields: null));
  }
  return out;
}

import 'dart:async';

import 'package:logging/logging.dart';

import '../../../domain/models/ranking.dart';
import '../../services/usau/usau_client.dart';
import 'ranking_repository.dart';

/// Scrapes every published USA Ultimate ranking list on first use and keeps
/// them in memory. Divisions are emitted as they load, so the first list
/// shows up after one request instead of after all of them.
class RankingRepositoryUsau implements RankingRepository {
  RankingRepositoryUsau({required UsauClient client}) : _client = client;

  final UsauClient _client;
  final _log = Logger('RankingRepositoryUsau');

  List<RankingDivision> _divisions = const [];
  bool _complete = false;
  Future<void>? _loading;
  final _listeners = <StreamController<List<RankingDivision>>>{};

  @override
  Stream<List<RankingDivision>> watchDivisions() {
    late final StreamController<List<RankingDivision>> controller;
    controller = StreamController(
      onListen: () {
        if (_divisions.isNotEmpty) controller.add(_divisions);
        if (_complete) {
          controller.close();
          return;
        }
        _listeners.add(controller);
        (_loading ??= _load()).then(
          (_) {
            _listeners.remove(controller);
            controller.close();
          },
          onError: (Object e, StackTrace s) {
            _listeners.remove(controller);
            controller
              ..addError(e, s)
              ..close();
          },
        );
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  Future<void> _load() async {
    try {
      final sets = await _client.fetchRankSets();
      var failures = 0;
      for (final set in sets) {
        try {
          final division = await _client.fetchDivision(set);
          if (division.entries.isEmpty) {
            _log.warning('No ranking rows parsed for ${set.key}');
            continue;
          }
          _divisions = [..._divisions, division]
            ..sort((a, b) => a.label.compareTo(b.label));
          for (final l in _listeners) {
            l.add(_divisions);
          }
        } on Exception catch (e) {
          failures++;
          _log.warning('Failed to load rankings for ${set.key}', e);
        }
      }
      if (_divisions.isEmpty) {
        throw Exception(
          'Could not load any rankings from USA Ultimate'
          '${failures > 0 ? ' ($failures requests failed)' : ''}.',
        );
      }
      _complete = true;
    } catch (_) {
      // Allow a retry to fetch again.
      _loading = null;
      rethrow;
    }
  }
}

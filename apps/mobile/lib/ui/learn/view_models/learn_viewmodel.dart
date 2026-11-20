import 'package:flutter/foundation.dart';

import '../../../data/repositories/learn/learn_progress_repository.dart';
import '../../../domain/models/discover.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../learn_content.dart';

/// Learn to play's reading progress: which lessons ([learnSections]) are
/// read, "N of M read", and Mark all unread. A lesson is read once the end
/// of it has stayed on screen for [learnReadAfter] (the screen calls
/// [markRead]), the same rule as the website's.
class LearnViewModel extends ChangeNotifier {
  LearnViewModel({required LearnProgressRepository repository})
    : _repo = repository {
    load = Command0(_load)..execute();
    markAllUnread = Command0(_markAllUnread);
  }

  final LearnProgressRepository _repo;

  late final Command0<void> load;

  /// Back to nothing read (neutral: nothing is lost but the ticks).
  late final Command0<void> markAllUnread;

  Set<String> _read = {};
  bool _loaded = false;

  /// Whether the saved progress is in (until then nothing shows as read).
  bool get loaded => _loaded;

  bool isRead(String id) => _read.contains(id);

  /// Lessons read that are still in the guide.
  int get readCount => learnSections.where((s) => _read.contains(s.id)).length;

  int get total => learnSections.length;

  /// "3 of 12 read".
  String get progressLabel => learnProgressLabel(readCount, total);

  Future<Result<void>> _load() async {
    final saved = await _repo.readLessons();
    // Anything marked while it loaded stays.
    _read = {..._read, ...saved};
    _loaded = true;
    notifyListeners();
    return const Result.ok(null);
  }

  /// Marks lesson [id] read (and saves it), once.
  void markRead(String id) {
    if (_read.contains(id) || !learnSections.any((s) => s.id == id)) return;
    _read = {..._read, id};
    notifyListeners();
    _repo.saveReadLessons(_read);
  }

  Future<Result<void>> _markAllUnread() async {
    _read = {};
    notifyListeners();
    await _repo.saveReadLessons(const {});
    return const Result.ok(null);
  }
}

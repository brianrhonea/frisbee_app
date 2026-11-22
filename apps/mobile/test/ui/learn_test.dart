// Learn to play's reading progress (F9): a lesson is read once the end of
// it has stayed on screen for learnReadAfter, as on the website.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/learn/learn_progress_repository.dart';
import 'package:frisbee_app/data/services/shared_preferences_service.dart';
import 'package:frisbee_app/domain/models/discover.dart';
import 'package:frisbee_app/ui/learn/learn_content.dart';
import 'package:frisbee_app/ui/learn/view_models/learn_viewmodel.dart';
import 'package:frisbee_app/ui/learn/widgets/learn_screen.dart';

class _MapPrefs implements SharedPreferencesService {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  test('lessons have the website ids, in its order', () {
    expect(learnSections.map((s) => s.id), [
      'basics',
      'field',
      'pull',
      'moving',
      'stall',
      'scoring',
      'turnovers',
      'defense',
      'spirit',
      'divisions',
      'words',
      'start',
    ]);
  });

  group('LearnViewModel', () {
    test('loads what was read, counts only lessons in the guide', () async {
      final repo = LearnProgressRepositoryMemory({'basics', 'stall', 'gone'});
      final vm = LearnViewModel(repository: repo);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.isRead('basics'), isTrue);
      expect(vm.readCount, 2);
      expect(vm.progressLabel, '2 of 12 read');
    });

    test('marks a lesson read once and saves it; Mark all unread clears '
        'them', () async {
      final repo = LearnProgressRepositoryMemory();
      final vm = LearnViewModel(repository: repo);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm
        ..markRead('field')
        ..markRead('field')
        ..markRead('not-a-lesson');
      expect(vm.readCount, 1);
      expect(await repo.readLessons(), {'field'});

      await vm.markAllUnread.execute();
      expect(vm.readCount, 0);
      expect(vm.progressLabel, '0 of 12 read');
      expect(await repo.readLessons(), isEmpty);
    });
  });

  test('progress is kept in shared preferences, as a JSON list', () async {
    final prefs = _MapPrefs();
    final repo = LearnProgressRepositoryPrefs(() => prefs);
    await repo.saveReadLessons({'stall', 'basics'});
    expect(prefs.values['learn.read'], '["basics","stall"]');
    expect(await repo.readLessons(), {'basics', 'stall'});
    await repo.saveReadLessons({});
    expect(prefs.values, isEmpty);
    prefs.values['learn.read'] = 'not json';
    expect(await repo.readLessons(), isEmpty);
  });

  testWidgets('a lesson whose end stays on screen is ticked, and the count '
      'goes up; scrolling past is not enough', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = LearnProgressRepositoryMemory();
    final vm = LearnViewModel(repository: repo);
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: LearnScreen(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('0 of 12 read'), findsOneWidget);
    expect(find.text('Mark all unread'), findsNothing);

    // Jump to Turnovers and stay there.
    await tester.tap(find.text('Turnovers').first);
    await tester.pumpAndSettle();
    await tester.pump(learnReadAfter + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(vm.isRead('turnovers'), isTrue);
    expect(vm.isRead('basics'), isFalse, reason: 'scrolled past');
    final read = vm.readCount;
    expect(read, greaterThan(0));

    // Back to the top: the count and ticks show, with Mark all unread.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(find.text('${vm.readCount} of 12 read'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(vm.readCount));
    await tester.ensureVisible(find.text('Mark all unread'));
    await tester.tap(find.text('Mark all unread'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 12 read'), findsOneWidget);
    expect(await repo.readLessons(), isEmpty);
    // Leave no timers running.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(learnReadAfter);
  });
}

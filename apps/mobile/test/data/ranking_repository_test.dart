import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository_firebase.dart';

Map<String, dynamic> _doc(String level, String division) => {
  'level': level,
  'division': division,
  'minGames': 5,
  'teams': [
    {'rank': 1, 'teamId': 't1', 'name': 'Alpha', 'rating': 1200},
  ],
};

void main() {
  test('leaves out youth, unknown and mismatched rankings', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('rankings/club-mixed').set(_doc('club', 'mixed'));
    await db.doc('rankings/college-women').set(_doc('college', 'women'));
    // Left from before youth stopped being ranked.
    await db.doc('rankings/youth-mixed').set(_doc('youth', 'mixed'));
    await db.doc('rankings/elite-mixed').set(_doc('elite', 'mixed'));
    // Says youth inside an adult key.
    await db.doc('rankings/club-open').set(_doc('youth', 'open'));

    final repo = RankingRepositoryFirebase(firestore: db);
    final list = await repo.watchRankings().first;
    expect(list.map((r) => r.key).toList()..sort(), [
      'club-mixed',
      'college-women',
    ]);
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/utils/result.dart';

/// H1: the rules refuse a `profiles` list query that doesn't ask for
/// `adult == true`, so the app's people and player searches ask for it, and
/// a profile without the marker never comes back.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Future<void> profile(String id, String name, {bool? adult}) =>
        db.collection('profiles').doc(id).set({
          'name': name,
          'keywords': ['sam', name.toLowerCase()],
          'tags': ['sam'],
          'adult': ?adult,
        });
    await profile('a1', 'Sam', adult: true);
    await profile('a2', 'Samantha');
    await profile('a3', 'Samir', adult: false);
  });

  test('people search leaves out a profile without the adult marker', () async {
    final repo = DirectMessageRepositoryFirebase(
      attachments: AttachmentStorage(),
      firestore: db,
    );
    final r = await repo.searchPeople('sam', excludeUid: 'me');
    expect(r, isA<Ok>());
    expect([for (final p in (r as Ok).value) p.uid], ['a1']);
  });

  test('player search leaves out a profile without the adult marker', () async {
    final repo = ProfileRepositoryFirebase(firestore: db);
    final r = await repo.searchPlayers('sam');
    expect(r, isA<Ok>());
    expect([for (final p in (r as Ok).value) p.uid], ['a1']);
  });
}

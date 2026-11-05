import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/discord_import.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/callable_client.dart';
import '../chat/chat_repository_firebase.dart';
import 'discord_import_repository.dart';

/// Previews through the `discord-previewTemplate` Cloud Function
/// (functions/src/discord), which reads the template from Discord; writes
/// the import from the app, so firestore.rules checks it like any other
/// edit by the owner.
class DiscordImportRepositoryFirebase implements DiscordImportRepository {
  DiscordImportRepositoryFirebase({
    required CallableClient functions,
    FirebaseFirestore? firestore,
  }) : _functions = functions,
       _db = firestore ?? FirebaseFirestore.instance;

  final CallableClient _functions;
  final FirebaseFirestore _db;

  @override
  Future<Result<DiscordImportPlan>> preview(String teamId, String link) =>
      guard(() async {
        final result = await _functions.call('discord-previewTemplate', {
          'teamId': teamId,
          'link': link,
        });
        if (result is! Map) {
          throw const CallableException("Discord's answer made no sense.");
        }
        return DiscordImportPlan.fromMap(Map<String, dynamic>.from(result));
      });

  @override
  Future<Result<void>> apply(Team team, DiscordImport import, String uid) =>
      guard(() async {
        final batch = _db.batch()
          ..update(
            _db.collection('teams').doc(team.id),
            rolesData(
              import.roles,
              cleanMemberRoles(
                team.memberRoles,
                import.roles,
                team.members.keys,
              ),
            ),
          );
        final folders = chatFolders(_db, team.id);
        for (final f in import.folders) {
          batch.set(folders.doc(f.id), {
            ...f.toMap(),
            'createdBy': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        final rooms = chatRooms(_db, team.id);
        for (final r in import.rooms) {
          batch.set(rooms.doc(), newRoomData(r, uid));
        }
        await batch.commit();
      });
}

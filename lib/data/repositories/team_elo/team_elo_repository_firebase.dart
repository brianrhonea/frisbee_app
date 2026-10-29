import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/models/team_elo.dart';
import '../../services/firestore_utils.dart';
import 'team_elo_repository.dart';

/// Reads the ratings the `computeUsauTeamElo` Cloud Function writes to
/// `usau_team_elo` (one document per ranking list).
class TeamEloRepositoryFirebase implements TeamEloRepository {
  TeamEloRepositoryFirebase({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<TeamEloDivision>> watchDivisions() => _db
      .collection('usau_team_elo')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => TeamEloDivision.fromMap(d.id, plainData(d.data())))
            .toList(),
      );
}

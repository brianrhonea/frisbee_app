import '../../../domain/models/discord_import.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';

/// Imports a Discord server's roles and channels from a server template
/// link (https://discord.new/...).
abstract class DiscordImportRepository {
  /// Reads the template behind [link] and returns what it holds. Only
  /// [teamId]'s owner may ask.
  Future<Result<DiscordImportPlan>> preview(String teamId, String link);

  /// Adds [import]'s roles, folders and rooms to [team] in one write, as
  /// [uid] (the owner).
  Future<Result<void>> apply(Team team, DiscordImport import, String uid);

  /// Adds a community team's share of an import ([TeamChatImport]): its
  /// copies of community roles (with [Team.orgRoles]), folders and rooms,
  /// in one write, as [uid] (the team's owner).
  Future<Result<void>> applyToTeam(TeamChatImport import, String uid);
}

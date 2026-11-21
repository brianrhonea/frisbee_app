import 'package:flutter/foundation.dart';

import '../../../domain/models/moderation.dart';
import '../../../utils/result.dart';

/// Reports and blocks (App Store guideline 1.2). Writes go through the API
/// (`/v1/reports`, `/v1/me/blocks/*`, `/v1/teams/:id/reports`); the block
/// list is read live from `users/{uid}/blocks`, which only the API writes.
/// The [current] list is kept for the signed-in user, so feeds, comments,
/// messages and profiles can hide people at once.
abstract class ModerationRepository extends ChangeNotifier {
  /// Whether this build can reach Stall 10's server (reports and blocks need it).
  bool get enabled;

  /// The signed-in user's blocks, live; [BlockList.empty] when signed out.
  BlockList get current;

  /// Reports [target] for [reason]; with [block], blocks its author
  /// ([authorId], hidden at once) too. Ok(true) when the author was blocked.
  Future<Result<bool>> report(
    ReportTarget target,
    ReportReason reason, {
    String? details,
    bool block = false,
    String? authorId,
  });

  Future<Result<void>> block(String uid);
  Future<Result<void>> unblock(String uid);

  /// Open reports on [teamId]'s chat, posts and comments, for its admins.
  Future<Result<List<ReportInfo>>> teamReports(String teamId);

  /// An admin removes the reported content ([remove]) or dismisses the report.
  Future<Result<void>> resolveTeamReport(
    String teamId,
    String reportId, {
    required bool remove,
  });
}

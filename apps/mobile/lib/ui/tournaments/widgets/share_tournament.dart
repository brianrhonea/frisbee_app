import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../utils/invite_links.dart';

/// Hands a tournament's link to the share sheet. Tests pass their own.
typedef ShareTournament =
    Future<void> Function(BuildContext context, String text, Uri link);

/// What sharing [t] sends: its name, when and where, then its public page
/// on the website ([InviteLinks.tournament]), which anyone can open. The
/// website's Share sends the same link.
({String text, Uri link}) tournamentShare(HostedTournament t) {
  final link = InviteLinks.tournament(t.id);
  final f = DateFormat('EEE, MMM d');
  final end = t.endsOn;
  final when = end == null || DateUtils.isSameDay(end, t.startsOn)
      ? f.format(t.startsOn)
      : '${f.format(t.startsOn)} – ${f.format(end)}';
  final details = [when, if (t.location.trim().isNotEmpty) t.location.trim()];
  return (text: '${t.name}\n${details.join(' · ')}\n$link', link: link);
}

/// The platform share sheet with [text] (which ends with [link]).
Future<void> shareTournament(
  BuildContext context,
  String text,
  Uri link,
) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: text.split('\n').first,
      // iPad anchors the sheet here.
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

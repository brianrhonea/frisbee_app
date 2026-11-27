// D9: tournament-status tags are neutral (zinc/indigo); red only for live,
// green only for success. Team-kind tags use Tone.grey (neutral).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/ui/core/ui/status_pill.dart';
import 'package:frisbee_app/ui/core/ui/tone.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_status_badge.dart';

import '../../ui_harness/harness.dart';

void main() {
  test(
    'only registration is green, only live is red; amber is never a status',
    () {
      for (final s in HostedStatus.values) {
        final expected = switch (s) {
          HostedStatus.registration => Tone.green,
          HostedStatus.live => Tone.red,
          _ => Tone.grey,
        };
        expect(s.tone, expected, reason: s.name);
        expect(s.tone, isNot(Tone.amber), reason: s.name);
      }
    },
  );

  testWidgets('the badge renders neutral, success or live pills only', (
    t,
  ) async {
    for (final s in HostedStatus.values) {
      await pumpInApp(t, HostedStatusBadge(status: s));
      final pill = t.widget<StatusPill>(find.byType(StatusPill));
      final expected = switch (s) {
        HostedStatus.registration => PillTone.success,
        HostedStatus.live => PillTone.live,
        _ => PillTone.neutral,
      };
      expect(pill.tone, expected, reason: s.name);
      expect(find.text(s.label), findsOneWidget);
    }
  });

  test('Tone.grey is the neutral pill (the team-kind tag tone)', () {
    expect(Tone.grey.pill, PillTone.neutral);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/agreement.dart';
import 'package:frisbee_app/ui/auth/view_models/agree_terms_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/agree_terms_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/auth_layout.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

import '../testing/fakes.dart';

void main() {
  setUp(AuthLayout.debugReset);

  testWidgets('Continue waits for the box, then records the agreement', (
    tester,
  ) async {
    final agreements = FakeAgreementRepository(agreed: false);
    final vm = AgreeTermsViewModel(
      agreementRepository: agreements,
      authRepository: FakeAuthRepository(user: testUser),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AgreeTermsScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(agreementPoints.first), findsOneWidget);
    expect(find.text('Read the Community Guidelines'), findsOneWidget);
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueButton);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(find.byKey(const Key('agree-terms')));
    await tester.pump();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(agreements.agreeCalls, 1);
    expect(agreements.agreed, isTrue);
  });
}

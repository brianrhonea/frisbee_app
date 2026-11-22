// The agreement step's version and summary (domain/models/agreement.dart),
// checked by packages/shared/test/agreement_fixtures.test.ts against
// agreements.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/agreement.dart';

import 'fixture_file.dart';

void main() {
  test('the guidelines and terms agreement (agreements/terms.json)', () {
    checkFixture(
      'agreements/terms.json',
      'The Community Guidelines and Terms members agree to: the current '
          'version and the summary both platforms show.',
      [
        {'version': termsVersion, 'points': agreementPoints},
      ],
    );
  });
}

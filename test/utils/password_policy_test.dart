import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/utils/password_policy.dart';

void main() {
  test('needs 8+ characters with a letter and a number', () {
    expect(PasswordPolicy.problem('abc123'), 'At least 8 characters');
    expect(PasswordPolicy.problem('abcdefgh'), isNotNull);
    expect(PasswordPolicy.problem('12345678'), isNotNull);
    expect(PasswordPolicy.problem(' abcd1234'), isNotNull);
    expect(PasswordPolicy.problem('a1' * 65), 'At most 128 characters');
    expect(PasswordPolicy.problem('pull1234'), isNull);
    expect(PasswordPolicy.problem('Huck it deep 7!'), isNull);
  });
}

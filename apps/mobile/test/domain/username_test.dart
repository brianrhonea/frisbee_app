import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/model_utils.dart';
import 'package:frisbee_app/domain/models/username.dart';
import 'package:frisbee_app/utils/password_policy.dart';

void main() {
  test('usernames: 3-20 lowercase letters, numbers, _ and .', () {
    expect(Username.normalize('  @Pat.Lee '), 'pat.lee');
    expect(Username.problem('pat.lee'), isNull);
    expect(Username.problem('Pat_Lee7'), isNull, reason: 'stored lowercase');
    expect(Username.problem('pa'), isNotNull);
    expect(Username.problem('a' * 21), isNotNull);
    expect(Username.problem('pat lee'), isNotNull);
    expect(Username.problem('pat!'), isNotNull);
    expect(Username.problem('.pat'), isNotNull);
    expect(Username.problem('pat.'), isNotNull);
    expect(Username.problem('pa..t'), isNotNull);
    expect(Username.problem('admin'), 'That username is reserved');
  });

  test('people are found by username as well as name', () {
    final keys = profileKeywords('Brian Honea', 'bhonea_7');
    expect(keys, containsAll(['bri', 'hon', 'bho', 'bhonea_7']));
    const p = UserProfile(uid: 'u', name: 'Brian Honea', username: 'bhonea_7');
    expect(p.matches('@bhon'), isTrue);
    expect(p.matches('brian'), isTrue);
    expect(p.matches('@someone'), isFalse);
  });

  test('password strength climbs with length and variety', () {
    expect(PasswordPolicy.strength('abc'), PasswordStrength.weak);
    expect(PasswordPolicy.strength('password1'), PasswordStrength.weak);
    expect(PasswordPolicy.problem('Password1'), contains('common'));
    expect(PasswordPolicy.strength('pull1234'), PasswordStrength.fair);
    expect(PasswordPolicy.strength('Pull1234hammer'), PasswordStrength.good);
    expect(
      PasswordPolicy.strength('Huck it deep, 7 times!'),
      PasswordStrength.strong,
    );
    expect(PasswordPolicy.checklist('abc').map((r) => r.met), [
      false,
      true,
      false,
    ]);
  });
}

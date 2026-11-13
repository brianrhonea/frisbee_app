/// How strong a password is, for the meter on sign-up.
enum PasswordStrength {
  weak('Weak'),
  fair('Fair'),
  good('Good'),
  strong('Strong');

  const PasswordStrength(this.label);
  final String label;
}

/// Rules for new passwords, checked on sign-up before Firebase sees them.
abstract final class PasswordPolicy {
  static const minLength = 8;

  /// Long enough for a passphrase; Firebase allows more, but nobody types it.
  static const maxLength = 128;

  static final _letter = RegExp('[A-Za-z]');
  static final _lower = RegExp('[a-z]');
  static final _upper = RegExp('[A-Z]');
  static final _digit = RegExp('[0-9]');
  static final _symbol = RegExp('[^A-Za-z0-9]');

  /// Passwords people pick first; never more than weak.
  static const _common = {
    'password',
    'password1',
    'password123',
    'passw0rd',
    'qwerty123',
    'abc12345',
    'abcd1234',
    'iloveyou1',
    'letmein1',
    'welcome1',
    'frisbee1',
    'ultimate1',
    '12345678a',
    'a12345678',
  };

  /// The requirements, each with whether [password] meets it, for the
  /// checklist under the field.
  static List<({String label, bool met})> checklist(String password) => [
    (label: '$minLength+ characters', met: password.length >= minLength),
    (label: 'A letter', met: _letter.hasMatch(password)),
    (label: 'A number', met: _digit.hasMatch(password)),
  ];

  /// What's wrong with [password], or null when it's acceptable.
  static String? problem(String password) {
    if (password.length < minLength) {
      return 'At least $minLength characters';
    }
    if (password.length > maxLength) {
      return 'At most $maxLength characters';
    }
    if (password.trim() != password) {
      return "Can't start or end with a space";
    }
    if (!_letter.hasMatch(password) || !_digit.hasMatch(password)) {
      return 'Use at least one letter and one number';
    }
    if (_common.contains(password.toLowerCase())) {
      return 'Too common. Pick something harder to guess';
    }
    return null;
  }

  /// A rough strength from length and variety. Anything that fails
  /// [problem] is weak.
  static PasswordStrength strength(String password) {
    if (problem(password) != null) return PasswordStrength.weak;
    var score = 0;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (_lower.hasMatch(password) && _upper.hasMatch(password)) score++;
    if (_symbol.hasMatch(password)) score++;
    // The same character over and over adds little.
    if (password.split('').toSet().length < password.length / 2) score--;
    return switch (score) {
      <= 0 => PasswordStrength.fair,
      1 || 2 => PasswordStrength.good,
      _ => PasswordStrength.strong,
    };
  }
}

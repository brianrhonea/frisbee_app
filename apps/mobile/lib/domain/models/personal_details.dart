/// A player's personal details: legal name, birthday, phone, gender,
/// address and, under 18, a parent or guardian. Only the player sees them;
/// the API keeps them encrypted (`/v1/me/personal`). Mirrors
/// packages/shared/src/personal.ts: keep the rules and limits in step.
library;

/// Too young to have an account (COPPA): sign-up stops.
const minimumAge = 13;

/// Under this, a parent or guardian's details are asked too.
const adultAge = 18;

const tooYoungMessage = 'You must be $minimumAge or older to use Stall 10.';

enum Gender {
  woman('Woman'),
  man('Man'),
  nonbinary('Non-binary'),
  unspecified('Prefer not to say');

  const Gender(this.label);
  final String label;

  static Gender? fromName(Object? name) =>
      Gender.values.where((g) => g.name == name).firstOrNull;
}

abstract final class PersonalLimits {
  static const name = 60;
  static const phone = 30;
  static const email = 254;
  static const line = 100;
  static const city = 60;
  static const region = 60;
  static const postalCode = 20;
  static const relationship = 40;
}

/// [date] as YYYY-MM-DD.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// [s] (YYYY-MM-DD) as a date, or null if it isn't a real one.
DateTime? parseIsoDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final date = DateTime.utc(y, mo, d);
  return date.year == y && date.month == mo && date.day == d ? date : null;
}

/// Whole years from [birth] to [today] (calendar dates; times ignored).
int ageOn(DateTime birth, DateTime today) {
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age--;
  }
  return age;
}

/// What's wrong with [birth] on [today], or null; under 13 gives
/// [tooYoungMessage].
String? birthDateProblem(DateTime? birth, DateTime today) {
  if (birth == null) return 'Enter your date of birth.';
  final age = ageOn(birth, today);
  if (age < 0) return 'That date is in the future.';
  if (age > 120) return 'Check the year of your date of birth.';
  if (age < minimumAge) return tooYoungMessage;
  return null;
}

/// 7 to 15 digits, with an optional leading + and the usual separators.
String? phoneProblem(String input) {
  final s = input.trim();
  if (s.isEmpty) return 'Enter a phone number.';
  if (!RegExp(r'^\+?[0-9 ().-]+$').hasMatch(s)) {
    return 'Use only digits, spaces, +, -, ( and ).';
  }
  final digits = s.replaceAll(RegExp(r'\D'), '').length;
  if (digits < 7 || digits > 15) return 'Enter a full phone number.';
  return null;
}

String? emailProblem(String input) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input.trim())
    ? null
    : 'Enter a valid email.';

class Address {
  const Address({
    required this.line1,
    this.line2 = '',
    required this.city,
    required this.region,
    required this.postalCode,
    this.country = 'US',
  });

  final String line1;
  final String line2;
  final String city;
  final String region;
  final String postalCode;

  /// ISO 3166-1 alpha-2, e.g. US.
  final String country;

  factory Address.fromMap(Map<String, Object?> m) => Address(
    line1: '${m['line1'] ?? ''}',
    line2: '${m['line2'] ?? ''}',
    city: '${m['city'] ?? ''}',
    region: '${m['region'] ?? ''}',
    postalCode: '${m['postalCode'] ?? ''}',
    country: '${m['country'] ?? 'US'}',
  );

  Map<String, Object?> toMap() => {
    'line1': line1.trim(),
    'line2': line2.trim(),
    'city': city.trim(),
    'region': region.trim(),
    'postalCode': postalCode.trim(),
    'country': country.trim().toUpperCase(),
  };
}

class Guardian {
  const Guardian({
    required this.name,
    this.relationship = '',
    required this.email,
    required this.phone,
  });

  final String name;
  final String relationship;
  final String email;
  final String phone;

  factory Guardian.fromMap(Map<String, Object?> m) => Guardian(
    name: '${m['name'] ?? ''}',
    relationship: '${m['relationship'] ?? ''}',
    email: '${m['email'] ?? ''}',
    phone: '${m['phone'] ?? ''}',
  );

  Map<String, Object?> toMap() => {
    'name': name.trim(),
    'relationship': relationship.trim(),
    'email': email.trim(),
    'phone': phone.trim(),
  };
}

class PersonalDetails {
  const PersonalDetails({
    required this.legalFirstName,
    required this.legalLastName,
    required this.birthDate,
    required this.phone,
    required this.gender,
    required this.address,
    this.guardian,
  });

  final String legalFirstName;
  final String legalLastName;
  final DateTime birthDate;
  final String phone;
  final Gender gender;
  final Address address;

  /// Required under 18; not kept at 18 and over.
  final Guardian? guardian;

  static PersonalDetails? fromMap(Map<String, Object?>? m) {
    if (m == null) return null;
    final birth = parseIsoDate('${m['birthDate']}');
    final gender = Gender.fromName(m['gender']);
    final address = m['address'];
    if (birth == null || gender == null || address is! Map) return null;
    final guardian = m['guardian'];
    return PersonalDetails(
      legalFirstName: '${m['legalFirstName'] ?? ''}',
      legalLastName: '${m['legalLastName'] ?? ''}',
      birthDate: birth,
      phone: '${m['phone'] ?? ''}',
      gender: gender,
      address: Address.fromMap(address.cast<String, Object?>()),
      guardian: guardian is Map
          ? Guardian.fromMap(guardian.cast<String, Object?>())
          : null,
    );
  }

  /// The `PUT /v1/me/personal` body.
  Map<String, Object?> toMap() => {
    'legalFirstName': legalFirstName.trim(),
    'legalLastName': legalLastName.trim(),
    'birthDate': isoDate(birthDate),
    'phone': phone.trim(),
    'gender': gender.name,
    'address': address.toMap(),
    'guardian': ?guardian?.toMap(),
  };
}

/// `GET /v1/me/personal/status`.
class PersonalDetailsStatus {
  const PersonalDetailsStatus({required this.complete, required this.required});

  final bool complete;

  /// The account is new enough that the app asks before anything else.
  final bool required;

  factory PersonalDetailsStatus.fromMap(Map<String, Object?> m) =>
      PersonalDetailsStatus(
        complete: m['complete'] == true,
        required: m['required'] == true,
      );
}

/// Thrown when the API refuses details for being under [minimumAge].
class TooYoungException implements Exception {
  const TooYoungException();

  @override
  String toString() => tooYoungMessage;
}

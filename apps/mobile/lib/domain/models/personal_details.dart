/// A player's personal details: legal name, birthday, phone, gender and
/// address. Launch is adults only (18+). Only the player sees them;
/// the API keeps them encrypted (`/v1/me/personal`). Mirrors
/// packages/shared/src/personal.ts: keep the rules and limits in step.
library;

/// Launch is adults only: under this, sign-up stops (account gate, Q6).
const adultAge = 18;

/// The server's own text (`adultOnlyMessage` in
/// packages/shared/src/account_gate.ts); the website shows the same.
const adultOnlyMessage = 'You must be $adultAge or older to use Stall 10.';

/// Kept for callers that still name it: the same message.
const tooYoungMessage = adultOnlyMessage;

/// The birth date is saved once (`birthDateLockedMessage` in
/// packages/shared/src/account_gate.ts).
const birthDateLockedMessage =
    "Your date of birth can't be changed. Contact support if it's wrong.";

/// Where to write when a saved birth date is wrong.
const supportEmail = 'support@stall10.app';

/// [birthDateLockedMessage] with where to go, for showing.
const birthDateLockedHint = '$birthDateLockedMessage Email $supportEmail.';

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

/// What's wrong with [birth] on [today], or null; under 18 gives
/// [adultOnlyMessage].
String? birthDateProblem(DateTime? birth, DateTime today) {
  if (birth == null) return 'Enter your date of birth.';
  final age = ageOn(birth, today);
  if (age < 0) return 'That date is in the future.';
  if (age > 120) return 'Check the year of your date of birth.';
  if (age < adultAge) return adultOnlyMessage;
  return null;
}

/// Club teams ([Team.isClubTeam]) take players this age and over.
const clubMinimumAge = 16;

/// Why someone too young can't join a club team; also shown up front.
const clubTooYoungMessage =
    'Club teams are for players $clubMinimumAge and over.';

/// Why someone with no date of birth on file can't join a club team yet.
const clubNeedsBirthDateMessage =
    'Add your date of birth in About you to join a club team.';

/// What an admin sees when the person they're adding can't join a club
/// team.
String clubCantJoinMessage(String name) =>
    "$name can't join a club team: club teams are for players "
    '$clubMinimumAge and over.';

/// Why someone born on [birth] can't join a club team on [today], or null:
/// [clubMinimumAge] or over that day, counted as [ageOn] counts. The API
/// checks this when anyone joins; the app only explains it.
String? clubJoinProblem(DateTime? birth, DateTime today) {
  if (birth == null) return clubNeedsBirthDateMessage;
  return ageOn(birth, today) >= clubMinimumAge ? null : clubTooYoungMessage;
}

/// Community roles add their holders to the community's teams, but not to
/// club teams: nothing but the API can check an age, so players join those
/// with an invite.
const clubRolesNotice =
    "Club teams (16 and over) don't take anyone from roles: invite their "
    'players instead.';

/// Whether someone born on [birth] may join a club team on [today].
bool canJoinClubTeam(DateTime? birth, DateTime today) =>
    clubJoinProblem(birth, today) == null;

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

class PersonalDetails {
  const PersonalDetails({
    required this.legalFirstName,
    required this.legalLastName,
    required this.birthDate,
    required this.phone,
    required this.gender,
    required this.address,
  });

  final String legalFirstName;
  final String legalLastName;
  final DateTime birthDate;
  final String phone;
  final Gender gender;
  final Address address;

  static PersonalDetails? fromMap(Map<String, Object?>? m) {
    if (m == null) return null;
    final birth = parseIsoDate('${m['birthDate']}');
    final gender = Gender.fromName(m['gender']);
    final address = m['address'];
    if (birth == null || gender == null || address is! Map) return null;
    return PersonalDetails(
      legalFirstName: '${m['legalFirstName'] ?? ''}',
      legalLastName: '${m['legalLastName'] ?? ''}',
      birthDate: birth,
      phone: '${m['phone'] ?? ''}',
      gender: gender,
      address: Address.fromMap(address.cast<String, Object?>()),
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
  };
}

/// `GET /v1/me/personal/status`.
class PersonalDetailsStatus {
  const PersonalDetailsStatus({required this.complete, required this.required});

  final bool complete;

  /// The account is new enough that the app asks before anything else.
  final bool required;

  /// Throws a [FormatException] unless both fields are plain booleans, so
  /// an unreadable answer is an error rather than "nothing required".
  factory PersonalDetailsStatus.fromMap(Map<String, Object?> m) {
    final complete = m['complete'], required = m['required'];
    if (complete is! bool || required is! bool) {
      throw const FormatException('The status answer is not true/false');
    }
    return PersonalDetailsStatus(complete: complete, required: required);
  }
}

/// Thrown when the API refuses a birth date for being under [adultAge]
/// (412, [adultOnlyMessage]). The app then shows the adults-only screen.
class TooYoungException implements Exception {
  const TooYoungException([this.message = adultOnlyMessage]);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the API refuses a different birth date than the saved one
/// (412, [birthDateLockedMessage]).
class BirthDateLockedException implements Exception {
  const BirthDateLockedException();

  @override
  String toString() => birthDateLockedHint;
}

/// The exception for a 412 on a birth date, or null if [message] and
/// [fields] aren't one. [message] is the API's own text.
Exception? birthDateRefusal(
  String code,
  Map<String, String> fields,
  String message,
) {
  if (code != 'failed_precondition' || !fields.containsKey('birthDate')) {
    return null;
  }
  return message == birthDateLockedMessage
      ? const BirthDateLockedException()
      : TooYoungException(message);
}

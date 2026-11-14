import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';

void main() {
  final today = DateTime(2026, 11, 20);

  test('age counts whole years, birthdays included', () {
    expect(ageOn(DateTime(2013, 11, 20), today), 13);
    expect(ageOn(DateTime(2013, 11, 21), today), 12);
    expect(ageOn(DateTime(2008, 2, 29), DateTime(2026, 2, 28)), 17);
    expect(ageOn(DateTime(2008, 2, 29), DateTime(2026, 3, 1)), 18);
  });

  test('birthday rules match the API', () {
    expect(birthDateProblem(null, today), 'Enter your date of birth.');
    expect(
      birthDateProblem(DateTime(2027), today),
      'That date is in the future.',
    );
    expect(birthDateProblem(DateTime(2014), today), tooYoungMessage);
    expect(birthDateProblem(DateTime(2013, 11, 20), today), isNull);
    expect(birthDateProblem(DateTime(1890), today), isNotNull);
  });

  test('phone numbers', () {
    expect(phoneProblem('+1 (555) 010-2030'), isNull);
    expect(phoneProblem('555 0102'), isNull);
    expect(phoneProblem('call me'), isNotNull);
    expect(phoneProblem('12345'), isNotNull);
    expect(phoneProblem(''), isNotNull);
  });

  test('dates round-trip as YYYY-MM-DD', () {
    expect(isoDate(DateTime(2001, 2, 3)), '2001-02-03');
    expect(parseIsoDate('2001-02-03'), DateTime.utc(2001, 2, 3));
    expect(parseIsoDate('2001-02-30'), isNull);
  });

  test('toMap is the API body; a missing guardian is left out', () {
    final d = PersonalDetails(
      legalFirstName: ' Pat ',
      legalLastName: 'Lee',
      birthDate: DateTime(1995, 4, 2),
      phone: '555-010-2030',
      gender: Gender.unspecified,
      address: const Address(
        line1: '1 Main St',
        city: 'Boston',
        region: 'MA',
        postalCode: '02110',
        country: 'us',
      ),
    );
    final m = d.toMap();
    expect(m['legalFirstName'], 'Pat');
    expect(m['birthDate'], '1995-04-02');
    expect(m['gender'], 'unspecified');
    expect((m['address'] as Map)['country'], 'US');
    expect(m.containsKey('guardian'), isFalse);
    final back = PersonalDetails.fromMap(m)!;
    expect(back.birthDate, DateTime.utc(1995, 4, 2));
    expect(back.address.city, 'Boston');
  });
}

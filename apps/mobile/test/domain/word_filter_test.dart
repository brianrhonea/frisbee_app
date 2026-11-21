import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/word_filter.dart';

/// The app's word filter against packages/shared/fixtures/word_filter/, the
/// same cases and lists the API's word_filter.ts is tested against.
void main() {
  const dir = '../../packages/shared/fixtures/word_filter';

  test('the lists match the API', () {
    final lists =
        jsonDecode(File('$dir/lists.json').readAsStringSync())
            as Map<String, Object?>;
    expect(lists['blockedTerms'], blockedTerms);
    expect(lists['blockedPhrases'], blockedPhrases);
    expect(lists['maskedTerms'], maskedTerms);
    expect(lists['blockedEndings'], blockedEndings);
    expect(lists['maskedEndings'], maskedEndings);
  });

  final cases =
      (jsonDecode(File('$dir/cases.json').readAsStringSync())
              as Map<String, Object?>)['cases']!
          as List;
  for (final c in cases.cast<Map<String, Object?>>()) {
    test(c['name']! as String, () {
      final f = filterText(c['input']! as String);
      expect(f.text, c['text']);
      expect(f.blocked, c['blocked']);
    });
  }

  test('cleanText masks, and refuses blocked words', () {
    expect(cleanText('oh shit'), 'oh s***');
    expect(() => cleanText('kys'), throwsA(isA<BlockedWordsException>()));
  });
}

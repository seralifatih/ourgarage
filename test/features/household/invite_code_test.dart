import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourgarage/features/household/invite_code.dart';

void main() {
  group('alphabet', () {
    test('excludes every ambiguous character', () {
      // The whole point: these are the pairs people get wrong reading a code
      // off a screen or hearing it over the phone.
      for (final char in ['0', 'O', '1', 'I', 'L']) {
        expect(
          InviteCode.alphabet.contains(char),
          isFalse,
          reason: '$char is ambiguous and must not appear in a code',
        );
      }
    });

    test('is otherwise digits and uppercase letters', () {
      expect(InviteCode.alphabet, matches(RegExp(r'^[2-9A-Z]+$')));
      expect(InviteCode.alphabet.length, 31);
    });
  });

  group('generate', () {
    test('produces a six-character code from the alphabet', () {
      for (var i = 0; i < 200; i++) {
        final code = InviteCode.generate();
        expect(code, hasLength(InviteCode.length));
        expect(InviteCode.isWellFormed(code), isTrue);
      }
    });

    test('does not repeat itself in any meaningful way', () {
      final codes = {for (var i = 0; i < 500; i++) InviteCode.generate()};
      // Collisions are possible in principle, but 500 draws from ~887M should
      // never produce one; a duplicate here means the source is not random.
      expect(codes, hasLength(500));
    });

    test('a seeded generator is reproducible, for tests only', () {
      expect(InviteCode.generate(Random(7)), InviteCode.generate(Random(7)));
    });
  });

  group('normalise', () {
    test('uppercases and strips the separators people add', () {
      expect(InviteCode.normalise('mk7 npq'), 'MK7NPQ');
      expect(InviteCode.normalise('MK7-NPQ'), 'MK7NPQ');
      expect(InviteCode.normalise('  MK7NPQ  '), 'MK7NPQ');
    });

    test('repairs the predictable misreadings', () {
      // Someone typing O for a Q, or L for a J, made the mistake the alphabet
      // was designed to avoid. Rejecting them would blame the user.
      expect(InviteCode.normalise('0'), 'Q');
      expect(InviteCode.normalise('O'), 'Q');
      expect(InviteCode.normalise('1'), 'J');
      expect(InviteCode.normalise('I'), 'J');
      expect(InviteCode.normalise('l'), 'J');
    });

    test('a repaired code is well formed', () {
      expect(InviteCode.isWellFormed(InviteCode.normalise('mk7-np0')), isTrue);
    });

    test('leaves an already-clean code alone', () {
      final code = InviteCode.generate();
      expect(InviteCode.normalise(code), code);
    });
  });

  group('isWellFormed', () {
    test('rejects the wrong length', () {
      expect(InviteCode.isWellFormed('MK7NP'), isFalse);
      expect(InviteCode.isWellFormed('MK7NPQR'), isFalse);
      expect(InviteCode.isWellFormed(''), isFalse);
    });

    test('rejects characters outside the alphabet', () {
      expect(InviteCode.isWellFormed('MK7NP!'), isFalse);
      expect(InviteCode.isWellFormed('mk7npq'), isFalse, reason: 'lowercase');
      expect(InviteCode.isWellFormed('MK7NPO'), isFalse, reason: 'O excluded');
    });
  });
}

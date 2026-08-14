import 'dart:math';

/// Generation and normalisation of the 6-character invite code.
///
/// The code is read aloud, texted, and typed in by hand, so the alphabet
/// deliberately omits every character people confuse when doing that:
/// `0`/`O`, `1`/`I`/`L`. What is left is unambiguous in every font a phone is
/// likely to render it in.
///
/// 6 characters from 31 symbols is ~887 million combinations. Codes are
/// single-use and expire in 7 days, and the only thing guessing one gets you
/// is membership of a stranger's garage — so this is comfortable, though it is
/// worth noting the real protection is the unique constraint and the
/// expiry, not the entropy.
class InviteCode {
  const InviteCode._();

  /// Digits and uppercase letters, minus `0 O 1 I L`.
  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static const int length = 6;

  /// Excluded characters mapped to the one they were most likely mistyped for.
  ///
  /// The alphabet contains `O`, `I` and `L` nowhere, so a user who typed one
  /// of them was looking at something else. `O` is almost always a zero
  /// misread — but zero is excluded too, so both collapse onto `Q`, the only
  /// round glyph in the alphabet. Same reasoning for the vertical strokes.
  ///
  /// Substituting rather than rejecting is deliberate: someone reading a code
  /// off a cracked screen and typing `L` for `J` made a predictable mistake,
  /// and answering "invalid code" would make it look like the app's problem.
  static const Map<String, String> lookalikes = {
    '0': 'Q',
    'O': 'Q',
    '1': 'J',
    'I': 'J',
    'L': 'J',
  };

  /// A fresh random code.
  ///
  /// [Random.secure] rather than [Random]: a predictable sequence would let
  /// someone who redeemed one invite derive the next household's code.
  static String generate([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Cleans up a hand-typed code: uppercases, strips separators, and repairs
  /// the predictable misreadings in [lookalikes].
  ///
  /// Spaces and dashes go because people insert them when reading a code in
  /// groups, and rejecting `MK7 NPQ` would be pedantry.
  static String normalise(String input) {
    final cleaned = input.trim().toUpperCase().replaceAll(
      RegExp(r'[\s\-_]'),
      '',
    );

    return cleaned.split('').map((char) => lookalikes[char] ?? char).join();
  }

  /// Whether [code] could be a real code. Cheap client-side guard only — the
  /// server decides whether it actually exists.
  static bool isWellFormed(String code) {
    if (code.length != length) return false;
    return code.split('').every(alphabet.contains);
  }
}

// test/core/markdown/wikilink_extractor_test.dart — WikilinkExtractor unit tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/markdown/wikilink_extractor.dart';

void main() {
  group('extractReferences', () {
    test('parses a bare title', () {
      final matches = WikilinkExtractor.extractReferences('See [[Auth Notes]] for details.');

      expect(matches, hasLength(1));
      expect(matches.single.raw, '[[Auth Notes]]');
      expect(matches.single.target, 'Auth Notes');
      expect(matches.single.alias, isNull);
    });

    test('parses a bare ticketId', () {
      final matches = WikilinkExtractor.extractReferences('See [[AIO-42]] for details.');

      expect(matches.single.target, 'AIO-42');
      expect(matches.single.alias, isNull);
    });

    test('parses Target|Alias for a title target', () {
      final matches = WikilinkExtractor.extractReferences('[[Auth Notes|the auth docs]]');

      expect(matches.single.target, 'Auth Notes');
      expect(matches.single.alias, 'the auth docs');
    });

    test('parses Target|Alias for a ticketId target', () {
      final matches = WikilinkExtractor.extractReferences('[[AIO-42|Auth]]');

      expect(matches.single.target, 'AIO-42');
      expect(matches.single.alias, 'Auth');
    });

    test('trims whitespace around target and alias', () {
      final matches = WikilinkExtractor.extractReferences('[[ Auth Notes | the docs ]]');

      expect(matches.single.target, 'Auth Notes');
      expect(matches.single.alias, 'the docs');
    });

    test('finds multiple distinct occurrences', () {
      final matches = WikilinkExtractor.extractReferences(
        '[[Auth Notes]] and [[AIO-42]] and [[Billing]]',
      );

      expect(matches, hasLength(3));
      expect(matches.map((m) => m.target), ['Auth Notes', 'AIO-42', 'Billing']);
    });

    test('deduplicates case-insensitively by (target, alias), keeping first-seen casing', () {
      final matches = WikilinkExtractor.extractReferences(
        '[[Auth Notes]] ... [[auth notes]] ... [[AUTH NOTES]]',
      );

      expect(matches, hasLength(1));
      expect(matches.single.target, 'Auth Notes');
    });

    test('does not deduplicate the same target with a different alias', () {
      final matches = WikilinkExtractor.extractReferences(
        '[[Auth Notes|one]] [[Auth Notes|two]]',
      );

      expect(matches, hasLength(2));
      expect(matches.map((m) => m.alias), ['one', 'two']);
    });

    test('returns empty for content with no wikilink', () {
      final matches = WikilinkExtractor.extractReferences('Plain text, no brackets here.');

      expect(matches, isEmpty);
    });

    test('ignores malformed brackets', () {
      final matches = WikilinkExtractor.extractReferences('[Auth Notes] and [[unterminated');

      expect(matches, isEmpty);
    });

    test('ignores an empty double-bracket pair', () {
      final matches = WikilinkExtractor.extractReferences('[[]]');

      expect(matches, isEmpty);
    });
  });

  group('looksLikeTicketId', () {
    test('matches an AIO-42-shaped string', () {
      expect(WikilinkExtractor.looksLikeTicketId('AIO-42'), isTrue);
    });

    test('matches a multi-letter prefix', () {
      expect(WikilinkExtractor.looksLikeTicketId('PROJ-1'), isTrue);
    });

    test('rejects a plain title', () {
      expect(WikilinkExtractor.looksLikeTicketId('Auth Notes'), isFalse);
    });

    test('rejects an empty string', () {
      expect(WikilinkExtractor.looksLikeTicketId(''), isFalse);
    });

    test('rejects a partial pattern missing the numeric suffix', () {
      expect(WikilinkExtractor.looksLikeTicketId('AIO-'), isFalse);
    });

    test('rejects a partial pattern missing the hyphen', () {
      expect(WikilinkExtractor.looksLikeTicketId('AIO42'), isFalse);
    });

    test('rejects lowercase letters', () {
      expect(WikilinkExtractor.looksLikeTicketId('aio-42'), isFalse);
    });
  });

  group('rewriteTitle', () {
    test('rewrites a bare title-anchored occurrence', () {
      final result = WikilinkExtractor.rewriteTitle(
        'See [[Old Title]] for details.',
        'Old Title',
        'New Title',
      );

      expect(result, 'See [[New Title]] for details.');
    });

    test('rewrites an aliased title-anchored occurrence, keeping the alias', () {
      final result = WikilinkExtractor.rewriteTitle(
        '[[Old Title|see here]]',
        'Old Title',
        'New Title',
      );

      expect(result, '[[New Title|see here]]');
    });

    test('is case-insensitive on the old title', () {
      final result = WikilinkExtractor.rewriteTitle('[[OLD TITLE]]', 'Old Title', 'New Title');

      expect(result, '[[New Title]]');
    });

    test('leaves an id-anchored occurrence untouched, even if its alias contains the old title', () {
      final result = WikilinkExtractor.rewriteTitle(
        '[[AIO-42|Old Title]]',
        'Old Title',
        'New Title',
      );

      expect(result, '[[AIO-42|Old Title]]');
    });

    test('rewrites every matching occurrence in the content', () {
      final result = WikilinkExtractor.rewriteTitle(
        '[[Old Title]] appears twice: [[Old Title]]',
        'Old Title',
        'New Title',
      );

      expect(result, '[[New Title]] appears twice: [[New Title]]');
    });

    test('returns content unchanged when no occurrence matches', () {
      const content = '[[Some Other Title]]';
      final result = WikilinkExtractor.rewriteTitle(content, 'Old Title', 'New Title');

      expect(result, content);
    });
  });
}

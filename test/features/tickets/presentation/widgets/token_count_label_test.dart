// test/features/tickets/presentation/widgets/token_count_label_test.dart — formatTokenCount + TokenCountLabel widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/widgets/token_count_label.dart';

/// Wraps [child] in a bare [ThemeScope] — `TokenCountLabel` needs no
/// localization/routing/cubit scaffolding, unlike `TicketBoardCard`.
Widget _wrap(Widget child) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    builder: (context, _) =>
        ThemeScope(theme: aionThemeArctic, child: Center(child: child)),
  );
}

void main() {
  group('formatTokenCount', () {
    test('a negative input clamps to 0', () {
      expect(formatTokenCount(-5), '0');
    });

    test('exactly 0 renders as the exact integer', () {
      expect(formatTokenCount(0), '0');
    });

    test('under 1000 renders as the exact integer, no suffix', () {
      expect(formatTokenCount(842), '842');
      expect(formatTokenCount(999), '999');
    });

    test('exactly 1000 renders as "1K"', () {
      expect(formatTokenCount(1000), '1K');
    });

    test('a whole-thousand value drops the trailing ".0"', () {
      expect(formatTokenCount(12000), '12K');
      expect(formatTokenCount(34000), '34K');
    });

    test('a fractional-thousand value keeps one decimal', () {
      expect(formatTokenCount(12300), '12.3K');
      expect(formatTokenCount(18400), '18.4K');
    });

    test('just under 1,000,000 stays in the K range', () {
      expect(formatTokenCount(999000), '999K');
    });

    test('exactly 1,000,000 renders as "1M"', () {
      expect(formatTokenCount(1000000), '1M');
    });

    test('a fractional-million value keeps one decimal', () {
      expect(formatTokenCount(1200000), '1.2M');
    });
  });

  group('TokenCountLabel.range', () {
    testWidgets('detail variant composes "~{lo}–{hi} tokens"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.range(
            low: 28000,
            high: 61000,
            variant: TokenCountVariant.detail,
          ),
        ),
      );

      expect(find.text('~28K–61K tokens'), findsOneWidget);
    });

    testWidgets('compact variant omits the unit word', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.range(
            low: 28000,
            high: 61000,
            variant: TokenCountVariant.compact,
          ),
        ),
      );

      expect(find.text('~28K–61K'), findsOneWidget);
      expect(find.textContaining('tokens'), findsNothing);
    });
  });

  group('TokenCountLabel.total', () {
    testWidgets('an abbreviated total is "~"-prefixed (detail)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.total(
            total: 18400,
            variant: TokenCountVariant.detail,
          ),
        ),
      );

      expect(find.text('~18.4K tokens'), findsOneWidget);
    });

    testWidgets('an exact total under 1000 carries no "~" (detail)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.total(
            total: 842,
            variant: TokenCountVariant.detail,
          ),
        ),
      );

      expect(find.text('842 tokens'), findsOneWidget);
    });

    testWidgets('compact variant omits the unit word', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.total(
            total: 18400,
            variant: TokenCountVariant.compact,
          ),
        ),
      );

      expect(find.text('~18.4K'), findsOneWidget);
      expect(find.textContaining('tokens'), findsNothing);
    });

    testWidgets('live: true renders identically to live: false (no accent '
        'recoloring)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TokenCountLabel.total(
            total: 18400,
            variant: TokenCountVariant.detail,
            live: true,
          ),
        ),
      );

      expect(find.text('~18.4K tokens'), findsOneWidget);
    });
  });
}

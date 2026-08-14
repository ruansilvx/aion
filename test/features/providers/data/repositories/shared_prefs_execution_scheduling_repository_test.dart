// test/features/providers/data/repositories/shared_prefs_execution_scheduling_repository_test.dart — SharedPrefsExecutionSchedulingRepository tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/data/repositories/shared_prefs_execution_scheduling_repository.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsExecutionSchedulingRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getMode defaults to strictFifo when unset', () async {
      final repository = SharedPrefsExecutionSchedulingRepository();

      expect(await repository.getMode(), ExecutionSchedulingMode.strictFifo);
    });

    test('setMode then getMode round-trips', () async {
      final repository = SharedPrefsExecutionSchedulingRepository();

      await repository.setMode(ExecutionSchedulingMode.hybrid);

      expect(await repository.getMode(), ExecutionSchedulingMode.hybrid);
    });

    test('getConcurrencyCeiling defaults to 2 when unset', () async {
      final repository = SharedPrefsExecutionSchedulingRepository();

      expect(await repository.getConcurrencyCeiling(), 2);
    });

    test('setConcurrencyCeiling then getConcurrencyCeiling round-trips', () async {
      final repository = SharedPrefsExecutionSchedulingRepository();

      await repository.setConcurrencyCeiling(5);

      expect(await repository.getConcurrencyCeiling(), 5);
    });

    test('mode and concurrency ceiling persist under independent keys', () async {
      final repository = SharedPrefsExecutionSchedulingRepository();

      await repository.setMode(ExecutionSchedulingMode.parallel);
      await repository.setConcurrencyCeiling(4);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('execution_scheduling.mode'), 'parallel');
      expect(prefs.getInt('execution_scheduling.concurrency_ceiling'), 4);
    });
  });
}

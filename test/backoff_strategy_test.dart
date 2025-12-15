import 'dart:math';

import 'package:okws_client/src/backoff_strategy.dart';
import 'package:test/test.dart';

void main() {
  group('BackoffStrategy Tests', () {
    group('LinearBackoff', () {
      test('should return constant interval', () {
        final strategy = LinearBackoff(Duration(seconds: 2));
        expect(strategy.next(1), equals(Duration(seconds: 2)));
        expect(strategy.next(2), equals(Duration(seconds: 2)));
        expect(strategy.next(10), equals(Duration(seconds: 2)));
      });
    });

    group('ExponentialBackoff', () {
      test('should increase exponentially', () {
        // Disable jitter for deterministic testing
        final strategy = ExponentialBackoff(
          initial: Duration(seconds: 1),
          multiplier: 2.0,
          jitter: 0.0,
        );

        // attempt 1: 1 * 2^0 = 1s
        expect(strategy.next(1).inMilliseconds, equals(1000));

        // attempt 2: 1 * 2^1 = 2s
        expect(strategy.next(2).inMilliseconds, equals(2000));

        // attempt 3: 1 * 2^2 = 4s
        expect(strategy.next(3).inMilliseconds, equals(4000));
      });

      test('should respect max duration', () {
        final strategy = ExponentialBackoff(
          initial: Duration(seconds: 1),
          max: Duration(seconds: 5),
          multiplier: 2.0,
          jitter: 0.0,
        );

        expect(strategy.next(1).inMilliseconds, equals(1000)); // 1s
        expect(strategy.next(2).inMilliseconds, equals(2000)); // 2s
        expect(strategy.next(3).inMilliseconds, equals(4000)); // 4s
        expect(strategy.next(4).inMilliseconds,
            equals(5000)); // 8s -> clamped to 5s
        expect(strategy.next(5).inMilliseconds,
            equals(5000)); // 16s -> clamped to 5s
      });

      test('should apply jitter', () {
        final strategy = ExponentialBackoff(
          initial: Duration(milliseconds: 1000),
          multiplier: 1.0, // constant base to isolate jitter
          jitter: 0.1, // +/- 10%
        );

        // Run multiple times to verify range
        for (int i = 0; i < 100; i++) {
          final duration = strategy.next(1).inMilliseconds;
          // 1000ms +/- 10% => 900ms to 1100ms
          expect(duration, greaterThanOrEqualTo(900));
          expect(duration, lessThanOrEqualTo(1100));
        }
      });

      test('should not return negative duration', () {
        // Edge case where jitter might cause negative values if not handled
        final strategy = ExponentialBackoff(
          initial: Duration(milliseconds: 10),
          jitter: 2.0, // Massive jitter
        );

        for (int i = 0; i < 100; i++) {
          final duration = strategy.next(1).inMilliseconds;
          expect(duration, greaterThanOrEqualTo(0));
        }
      });
    });
  });
}

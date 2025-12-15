import 'dart:math';

/// Strategy for calculating backoff duration.
abstract class BackoffStrategy {
  /// Calculate the delay for the next attempt.
  /// [attempt] is the number of consecutive failures (starts at 1).
  Duration next(int attempt);

  /// Reset any internal state if needed.
  void reset();
}

/// Linear backoff strategy: fixed interval.
class LinearBackoff implements BackoffStrategy {
  final Duration interval;

  LinearBackoff(this.interval);

  @override
  Duration next(int attempt) => interval;

  @override
  void reset() {}
}

/// Exponential backoff strategy with optional jitter.
class ExponentialBackoff implements BackoffStrategy {
  final Duration initial;
  final Duration max;
  final double multiplier;
  final double jitter;
  final Random _random = Random();

  ExponentialBackoff({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.multiplier = 1.5,
    this.jitter = 0.2,
  });

  @override
  Duration next(int attempt) {
    double nextMs =
        (initial.inMilliseconds * pow(multiplier, attempt - 1)).toDouble();

    // Apply jitter
    if (jitter > 0) {
      final double jitterRange = nextMs * jitter;
      final double jitterValue =
          _random.nextDouble() * jitterRange * 2 - jitterRange;
      nextMs += jitterValue;
    }

    // Clamp to max
    if (nextMs > max.inMilliseconds) {
      nextMs = max.inMilliseconds.toDouble();
    }

    // Ensure at least initial duration (or 0)
    if (nextMs < 0) nextMs = 0;

    return Duration(milliseconds: nextMs.round());
  }

  @override
  void reset() {}
}

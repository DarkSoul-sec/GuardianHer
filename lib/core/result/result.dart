import '../error/failures.dart';

/// A lightweight Result type used across feature boundaries.
///
/// Operations return `Result<T>` instead of throwing; success is represented
/// by [Ok], failure by [Err] wrapping a [Failure].
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Transforms the result into a single value of type [R].
  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) {
    return switch (this) {
      Ok(:final value) => onOk(value),
      Err(:final failure) => onErr(failure),
    };
  }

  /// Returns the value on success, or `null` on failure.
  T? getOrNull() => switch (this) {
        Ok(:final value) => value,
        _ => null,
      };
}

/// Successful result carrying a [value].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

/// Failed result carrying a [failure].
final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
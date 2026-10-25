import 'package:equatable/equatable.dart';

/// Typed failure for user-facing error handling.
class AppFailure extends Equatable implements Exception {
  const AppFailure({
    required this.message,
    this.code,
    this.cause,
  });

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppFailure($code): $message';

  @override
  List<Object?> get props => [message, code];
}

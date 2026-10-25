import 'package:flutter_test/flutter_test.dart';
import 'package:pathable/data/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('web auth redirect uses the open browser origin', () {
    expect(
      webAuthRedirect(
        base: Uri.parse('http://127.0.0.1:8081/account?next=%2F'),
        isWeb: true,
      ),
      'http://127.0.0.1:8081',
    );
    expect(
      webAuthRedirect(
        base: Uri.parse('http://localhost:8081/'),
        isWeb: true,
      ),
      'http://localhost:8081',
    );
    expect(
      webAuthRedirect(
        base: Uri.parse('http://127.0.0.1:8081/'),
        isWeb: false,
      ),
      isNull,
    );
  });

  test('redirect rejection names the local origins to allow', () {
    final message = describeAuthFailure(
      const AuthException('redirect url is not allowed'),
      base: Uri.parse('http://127.0.0.1:8081/account'),
      isWeb: true,
    );
    expect(message, contains('http://127.0.0.1:8081'));
    expect(message, contains('http://localhost:8081'));
  });
}

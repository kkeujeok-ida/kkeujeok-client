import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/google_auth_gateway.dart';

void main() {
  group('account chooser failures', () {
    test('only the user backing out is silent', () {
      expect(
        signInFailure(GoogleSignInExceptionCode.canceled),
        AuthOutcome.cancelled,
      );
    });
    test('an interrupted flow or missing UI shows the retry notice', () {
      expect(
        signInFailure(GoogleSignInExceptionCode.interrupted),
        AuthOutcome.networkError,
      );
      expect(
        signInFailure(GoogleSignInExceptionCode.uiUnavailable),
        AuthOutcome.networkError,
      );
    });
  });

  group('Drive permission failures', () {
    test('a cancel code or cancel text is a refusal', () {
      expect(
        accessFailure(GoogleSignInExceptionCode.canceled, ''),
        AuthOutcome.denied,
      );
      expect(
        accessFailure(GoogleSignInExceptionCode.unknownError, 'User Canceled'),
        AuthOutcome.denied,
      );
    });
    test('anything else is a connection problem', () {
      expect(
        accessFailure(GoogleSignInExceptionCode.unknownError, 'timeout'),
        AuthOutcome.networkError,
      );
    });
  });

  test('the only scope requested is drive.file', () {
    expect(driveFileScope, 'https://www.googleapis.com/auth/drive.file');
  });
}

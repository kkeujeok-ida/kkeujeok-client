import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/google_auth_gateway.dart';
import 'package:kkeujeok/storage/session_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SessionHint> hint([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SessionHint(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('session hint', () {
    test('is signed out until it is set, and can be cleared', () async {
      final h = await hint();
      expect(h.signedIn, isFalse);
      await h.set(true);
      expect(h.signedIn, isTrue);
      await h.set(false);
      expect(h.signedIn, isFalse);
    });

    test('a value of the wrong type is signed out, not an error', () async {
      final h = await hint({'signedIn': 'yes'});
      expect(h.signedIn, isFalse);
    });

    test('without preferences nothing is remembered', () async {
      final h = SessionHint(null);
      await h.set(true);
      expect(h.signedIn, isFalse);
    });

    test('stores a flag only, no token or account', () async {
      final prefs = await (() async {
        SharedPreferences.setMockInitialValues({});
        return SharedPreferences.getInstance();
      })();
      await SessionHint(prefs).set(true);
      expect(prefs.getKeys(), {'signedIn'});
      expect(prefs.get('signedIn'), true);
    });
  });

  group('account', () {
    test('is remembered with the flag and forgotten with it', () async {
      final h = await hint();
      expect(h.account, isNull);
      await h.set(true);
      await h.setAccount('sub-1', 'a@example.com');
      expect(h.account, (sub: 'sub-1', email: 'a@example.com'));
      await h.set(false);
      expect(h.account, isNull);
    });

    test('restore brings the account back, not a token', () async {
      final h = await hint({
        'signedIn': true,
        'accountSub': 'sub-1',
        'accountEmail': 'a@example.com',
      });
      final g = GoogleAuthGateway(hint: h);
      expect(g.account, isNull);
      expect(await g.restore(), isTrue);
      expect(g.account!.sub, 'sub-1');
      expect(g.account!.email, 'a@example.com');
    });

    test('a signed-out hint restores no account', () async {
      final h = await hint({'accountSub': 's', 'accountEmail': 'e'});
      final g = GoogleAuthGateway(hint: h);
      expect(await g.restore(), isFalse);
      expect(g.account, isNull);
    });
  });

  group('launch asks Google nothing', () {
    test('restore follows the hint and never touches the plugin', () async {
      // The plugin is not available in tests: any call to it would throw.
      expect(await GoogleAuthGateway(hint: await hint()).restore(), isFalse);
      expect(
        await GoogleAuthGateway(hint: await hint({'signedIn': true})).restore(),
        isTrue,
      );
    });

    test('sign out forgets the hint even when Google fails', () async {
      final h = await hint({'signedIn': true});
      final gateway = GoogleAuthGateway(hint: h);
      await expectLater(gateway.signOut(), throwsA(anything));
      expect(h.signedIn, isFalse);
    });
  });
}

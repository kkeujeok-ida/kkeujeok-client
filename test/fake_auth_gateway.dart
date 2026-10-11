import 'dart:async';

import 'package:kkeujeok/drive/auth_gateway.dart';

/// Scripted gateway: each call pops the next outcome (the last one repeats).
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    this.restored = false,
    List<AuthOutcome> signIns = const [AuthOutcome.granted],
    List<AuthOutcome> requests = const [AuthOutcome.granted],
    this.signOutFails = false,
    this.signOutHangs = false,
    List<bool> disconnects = const [true],
    this.disconnectHangs = false,
    this.signInAccount,
  }) : _signIns = [...signIns],
       _requests = [...requests],
       _disconnects = [...disconnects];

  final bool restored;
  final List<AuthOutcome> _signIns;
  final List<AuthOutcome> _requests;
  int restoreCalls = 0;
  int signInCalls = 0;
  final List<bool> _disconnects; // true = revoked, false = throws
  final bool signOutFails;
  final bool signOutHangs;
  final bool disconnectHangs;

  /// What [account] becomes when a sign-in is granted.
  final AuthAccount? signInAccount;

  @override
  AuthAccount? account;
  int requestCalls = 0;
  int signOutCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<bool> restore() async {
    restoreCalls++;
    return restored;
  }

  @override
  Future<AuthOutcome> signIn() async {
    signInCalls++;
    final o = _signIns.length > 1 ? _signIns.removeAt(0) : _signIns.first;
    if (o == AuthOutcome.granted) account = signInAccount;
    return o;
  }

  @override
  Future<AuthOutcome> requestAccess() async {
    requestCalls++;
    return _requests.length > 1 ? _requests.removeAt(0) : _requests.first;
  }

  /// What [accessToken] answers; null = no token.
  String? token = 'test-token';

  @override
  Future<String?> accessToken() async =>
      tokenError ? throw StateError('plugin failed') : token;

  /// [accessToken] throws (a transient failure) instead of answering.
  bool tokenError = false;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    account = null;
    if (signOutHangs) return Completer<void>().future;
    if (signOutFails) throw StateError('signOut failed');
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    account = null;
    if (disconnectHangs) return Completer<void>().future;
    final ok = _disconnects.length > 1
        ? _disconnects.removeAt(0)
        : _disconnects.first;
    if (!ok) throw StateError('disconnect failed');
  }
}

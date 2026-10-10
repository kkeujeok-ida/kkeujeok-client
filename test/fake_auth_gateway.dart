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
    return _signIns.length > 1 ? _signIns.removeAt(0) : _signIns.first;
  }

  @override
  Future<AuthOutcome> requestAccess() async {
    requestCalls++;
    return _requests.length > 1 ? _requests.removeAt(0) : _requests.first;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutHangs) return Completer<void>().future;
    if (signOutFails) throw StateError('signOut failed');
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (disconnectHangs) return Completer<void>().future;
    final ok = _disconnects.length > 1
        ? _disconnects.removeAt(0)
        : _disconnects.first;
    if (!ok) throw StateError('disconnect failed');
  }
}

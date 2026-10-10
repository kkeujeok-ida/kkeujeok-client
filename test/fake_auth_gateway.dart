import 'package:kkeujeok/drive/auth_gateway.dart';

/// Scripted gateway: each call pops the next outcome (the last one repeats).
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    this.restored = false,
    List<AuthOutcome> signIns = const [AuthOutcome.granted],
    List<AuthOutcome> requests = const [AuthOutcome.granted],
  }) : _signIns = [...signIns],
       _requests = [...requests];

  final bool restored;
  final List<AuthOutcome> _signIns;
  final List<AuthOutcome> _requests;
  int restoreCalls = 0;
  int signInCalls = 0;
  int requestCalls = 0;

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
}

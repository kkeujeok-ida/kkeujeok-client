import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/has_unsent.dart';

Map<String, Object?> _s({
  Object? orderRev = 'o',
  Object? metaRev = 'm',
  Object? pages = const [
    {'id': 'p1', 'rev': 'a'},
  ],
}) => {'orderRev': orderRev, 'metaRev': metaRev, 'pages': pages};

void main() {
  group('SyncInfo.fromJson', () {
    test('the defaults and a full record', () {
      expect(SyncInfo.fromJson(<String, Object?>{})!.state, SyncState.pending);
      final i = SyncInfo.fromJson({
        'fileId': 'F',
        'baseHeadRevisionId': 'R1',
        'state': 'conflict',
        'pendingVerify': {
          'parentRevisionId': null,
          'oursRevisionId': 'R2',
          'round': 3,
        },
        'resumableSession': {'uri': 'u', 'size': 0},
        'createIntent': {'kkeujeokId': 'k', 'parentId': 'p'},
        'conflicts': [
          {'pageId': 'p', 'rev': 'r', 'resolvedAt': null, 'more': 1},
        ],
        'unsentSidecars': [
          {'pageId': 'p', 'rev': 'r'},
        ],
        'lastError': {'class': 'quota', 'status': 403, 'reason': 'x'},
        'future': 7,
      })!;
      expect(i.state, SyncState.conflict);
      expect(i.toJson()['future'], 7);
      expect(i.conflicts.single['more'], 1);
    });

    final bad = <String, Object?>{
      'not an object': [1],
      'path-like base id': {'baseHeadRevisionId': '../x'},
      'base id with a space': {'baseHeadRevisionId': 'a b'},
      'base id of 201 chars': {'baseHeadRevisionId': 'a' * 201},
      'fileId a number': {'fileId': 5},
      'unknown state': {'state': 'dirty'},
      'round 0': {
        'pendingVerify': {'round': 0},
      },
      'round 4': {
        'pendingVerify': {'round': 4},
      },
      'pendingVerify not an object': {'pendingVerify': true},
      'session size negative': {
        'resumableSession': {'uri': 'u', 'size': -1},
      },
      'session without uri': {
        'resumableSession': {'size': 1},
      },
      'intent incomplete': {
        'createIntent': {'kkeujeokId': 'k'},
      },
      'conflicts not a list': {'conflicts': {}},
      'conflict without rev': {
        'conflicts': [
          {'pageId': 'p'},
        ],
      },
      'conflict that is a string': {
        'conflicts': ['p'],
      },
      'sidecar with a number rev': {
        'unsentSidecars': [
          {'pageId': 'p', 'rev': 1},
        ],
      },
      'error status 99': {
        'lastError': {'class': 'fatal', 'status': 99},
      },
      'error status 600': {
        'lastError': {'class': 'fatal', 'status': 600},
      },
      'error without class': {
        'lastError': {'status': 500},
      },
    };
    bad.forEach((name, json) {
      test('rejects: $name', () => expect(SyncInfo.fromJson(json), isNull));
    });
  });

  group('hasUnsentRule input checks', () {
    Map<String, Object?> run(Object? base, Object? working) => hasUnsentRule({
      'base': base,
      'working': working,
      'pendingVerify': null,
      'unsentSidecars': <Object?>[],
    });
    const invalid = {'error': 'invalidInput'};

    test('a good pair is judged', () {
      expect(run(_s(), _s()), {'hasUnsent': false});
    });

    final bad = <String, Map<String, Object?>>{
      'page without id': _s(
        pages: [
          {'rev': 'a'},
        ],
      ),
      'page without rev': _s(
        pages: [
          {'id': 'p1'},
        ],
      ),
      'page id a number': _s(
        pages: [
          {'id': 1, 'rev': 'a'},
        ],
      ),
      'page that is a string': _s(pages: ['p1']),
      'duplicate page ids': _s(
        pages: [
          {'id': 'p', 'rev': 'a'},
          {'id': 'p', 'rev': 'b'},
        ],
      ),
      'orderRev missing': _s(orderRev: null),
      'metaRev a number': _s(metaRev: 1),
    };
    bad.forEach((name, s) {
      test('working with $name', () => expect(run(null, s), invalid));
      test('base with $name', () => expect(run(s, _s()), invalid));
    });
  });
}

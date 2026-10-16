import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A new UUIDv7 for notes, pages, strokes and revs.
String newId() => _uuid.v7();

/// `YYYY-MM-DDTHH:mm:ss.sssZ`, always 3 millisecond digits.
String canonicalNow(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

// ponytail: the Android model name needs a device-info plugin; one constant
// until a story adds it.
/// `editedBy` of what this device writes.
const deviceEditedBy = 'Android';

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// UUIDv5 (spec `merge.resolve`): SHA-1 over the 16 bytes of [namespace]
/// then the UTF-8 bytes of [name]; the first 16 bytes, version 5, variant
/// `10`; 32 lowercase hex digits in 8-4-4-4-12 groups.
String uuidV5(String name, String namespace) {
  final hex = namespace.replaceAll('-', '');
  final ns = [
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final d = crypto.sha1.convert([...ns, ...utf8.encode(name)]).bytes;
  final b = d.sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  final x = [for (final v in b) v.toRadixString(16).padLeft(2, '0')].join();
  return '${x.substring(0, 8)}-${x.substring(8, 12)}-${x.substring(12, 16)}'
      '-${x.substring(16, 20)}-${x.substring(20)}';
}

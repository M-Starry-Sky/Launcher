import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingqiong_launcher/core/game/version_installer.dart';

void main() {
  test('installVanilla repairs existing 1.20.1 under C:/xingqiong/game',
      () async {
    final root = Directory(r'C:\xingqiong\game');
    expect(root.existsSync(), isTrue, reason: 'expected launcher game root');
    final logs = <String>[];
    final installer = VersionInstaller(onProgress: (m) {
      logs.add(m);
      // ignore: avoid_print
      print(m);
    });
    try {
      await installer
          .installVanilla('1.20.1', root)
          .timeout(const Duration(minutes: 5));
      final jar = File(r'C:\xingqiong\game\versions\1.20.1\1.20.1.jar');
      expect(jar.existsSync(), isTrue);
      expect(jar.lengthSync(), greaterThan(10 * 1024 * 1024));
      expect(
        logs.any((e) => e.contains('安装完成')),
        isTrue,
        reason: 'logs=${logs.join(" | ")}',
      );
    } finally {
      installer.close();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}

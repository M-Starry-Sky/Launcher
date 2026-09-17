import 'dart:io';

/// 合并写入 Minecraft `options.txt`，保留玩家其它设置。
class JavaOptionsWriter {
  /// [entries] 覆盖指定键；其余行原样保留。
  static Future<void> merge(Directory gameDir, Map<String, String> entries) async {
    if (entries.isEmpty) return;
    final file = File('${gameDir.path}/options.txt');
    final map = <String, String>{};
    final order = <String>[];

    if (file.existsSync()) {
      for (final raw in await file.readAsLines()) {
        final line = raw.trimRight();
        if (line.isEmpty) continue;
        final idx = line.indexOf(':');
        if (idx <= 0) {
          order.add(line);
          continue;
        }
        final key = line.substring(0, idx);
        final value = line.substring(idx + 1);
        if (!map.containsKey(key)) order.add(key);
        map[key] = value;
      }
    }

    for (final e in entries.entries) {
      if (!map.containsKey(e.key) && !order.contains(e.key)) {
        order.add(e.key);
      }
      map[e.key] = e.value;
    }

    final buf = StringBuffer();
    for (final key in order) {
      if (map.containsKey(key)) {
        buf.writeln('$key:${map[key]}');
      } else {
        buf.writeln(key);
      }
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(buf.toString());
  }
}

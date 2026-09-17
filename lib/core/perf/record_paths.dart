import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 录像默认目录：设置优先，否则「视频/XingqiongRecordings」。
Future<String> resolveRecordSaveDir(String configured) async {
  final c = configured.trim();
  if (c.isNotEmpty) return c;
  try {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final videos = Directory(p.join(userProfile, 'Videos'));
        if (videos.existsSync()) {
          return p.join(videos.path, 'XingqiongRecordings');
        }
      }
    }
    final movies = await getApplicationDocumentsDirectory();
    return p.join(movies.path, 'XingqiongRecordings');
  } catch (_) {
    return p.join(Directory.systemTemp.path, 'XingqiongRecordings');
  }
}

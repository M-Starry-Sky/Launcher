import 'package:flutter/material.dart';

import '../core/config/app_config.dart';

/// 「兼容联机」启用前的用户须知（面向玩家）。
class CompatMultiplayerGuard {
  static const warningTitle = '开启前请阅读';

  static const warningBody = '''
「兼容联机」会关闭服务器的正版登录校验，方便离线昵称和正版账号在私人房间一起玩，并可能安装跨版本相关模组。

请你知悉：

1. 这不等于官方联机方式。关闭正版校验后，房间更像私人试验环境，不适合当成正规公开服来用。
2. 请只在家人、好友的私人房间里使用；不要用于公开招人、收费进服，或任何可能被看作规避正版授权的场合。
3. 请遵守微软 / Mojang 的游戏服务条款与当地法规。若条款不允许此类玩法，请保持关闭，改用正版登录的正常联机。
4. 因开启本模式产生的账号、联机或合规问题，由使用者自行负责。

点「我知道了，继续开启」即表示你已阅读并同意以上说明。''';

  /// 返回 true 表示用户确认启用。
  static Future<bool> confirmEnable(
    BuildContext context,
    AppConfig config,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE6A23C)),
              SizedBox(width: 8),
              Expanded(child: Text(warningTitle)),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Text(
                warningBody,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('保持关闭'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE6A23C),
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('我知道了，继续开启'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await config.setBool(AppConfig.keyRoomCompatWhitelistAck, true);
      await config.setBool(AppConfig.keyRoomCompatMode, true);
      return true;
    }
    return false;
  }
}

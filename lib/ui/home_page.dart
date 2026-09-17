import 'package:flutter/material.dart';

import 'launcher_shell.dart';

/// 兼容旧入口：主页即主流启动器壳。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const LauncherShell();
}

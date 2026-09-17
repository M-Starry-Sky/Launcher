import 'package:flutter/material.dart';

/// 防止同一入口在弹窗未关闭时被连点，叠出无限层 Dialog / BottomSheet。
class DialogGuard {
  bool _locked = false;

  bool get isLocked => _locked;

  /// 已有弹窗进行中则直接返回 null，不执行 [action]。
  Future<T?> run<T>(Future<T?> Function() action) async {
    if (_locked) return null;
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
    }
  }

  /// 同步抢锁：适合「先 setState 再 await」的按钮。
  bool tryLock() {
    if (_locked) return false;
    _locked = true;
    return true;
  }

  void unlock() {
    _locked = false;
  }
}

/// 带互斥的 showDialog。
Future<T?> showGuardedDialog<T>({
  required BuildContext context,
  required DialogGuard guard,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return guard.run(
    () => showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: builder,
    ),
  );
}

/// 带互斥的 showModalBottomSheet。
Future<T?> showGuardedModalBottomSheet<T>({
  required BuildContext context,
  required DialogGuard guard,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool isScrollControlled = false,
}) {
  return guard.run(
    () => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      builder: builder,
    ),
  );
}

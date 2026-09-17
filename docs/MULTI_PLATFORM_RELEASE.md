# 多端发布说明（星穹次元启动器）

## Android 注意

- **正式包必须带 `INTERNET` 权限**（已写在 `android/app/src/main/AndroidManifest.xml`）。仅 debug/profile 有权限会导致 release 拉不到 BMCL/Mojang 镜像。
- 手机默认关闭局域网 P2P；UI 在宽度 &lt; 960 用底栏，&lt; 720 用窄屏布局。
- 桌面显示名：`@string/app_name` → **星穹次元**。
- 实验室 → 模组开发工作台可下载星穹优化源码（GitHub `tool/xingqiong_hud_bridge` / `tool/xingqiong_hud_bridge_26`，Apache-2.0）。
  - `xingqiong-perf.jar`：MC 1.20–1.21.x（Yarn）
  - `xingqiong-perf-26.jar`：MC 26.1+（去混淆）

## 本机（Windows）当前可产出

| 产物 | 说明 |
|------|------|
| `XingqiongLauncher-*-Windows-x64-Setup.exe` | **企业式图形安装向导**：欢迎页 → 许可协议 → 选择目录 → 附加任务 → 就绪确认 → 安装进度 → 完成页；Setup 图标与向导侧栏均为官方 Logo |
| `XingqiongLauncher-*-windows-x64-portable.zip` | Windows 便携版（免安装，内含 `logo.png`） |

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_release.ps1
```

输出目录：`frontend/dist/`

## 其他端（工程已脚手架，需对应机器/SDK）

| 平台 | 条件 | 命令 |
|------|------|------|
| Android APK/AAB | Android Studio / SDK | `flutter build apk --release` |
| Linux | Linux 或 WSL + GTK | `flutter build linux --release` |
| macOS | Apple Mac | `flutter build macos --release` |
| iOS | Apple Mac + Xcode | `flutter build ipa` |
| Web | 暂不正式分发（桌面插件依赖 `dart:ffi`） | — |

已启用目录：`android/` `ios/` `macos/` `linux/` `windows/` `web/`，Launcher 图标由 `assets/images/logo.png` 写入各端。

## 品牌资源

- 源 Logo：`assets/images/logo.png`
- 安装向导：`installer/branding/wizard_image.bmp`、`wizard_small.bmp`、`setup.ico`
- 生成：`tool/gen_branding_assets.py`、`tool/fix_branding_assets.py`

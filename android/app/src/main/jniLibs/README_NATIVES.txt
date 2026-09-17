将 Pojav / FCL 兼容的 native 库放入对应 ABI 目录后重新编译 APK：

必需（完整进游）：
  libxingqiong_je.so   — JNI：nativeStartGameImpl
  libpojavexec.so      — JVM 启动 / 输入桥（或等价实现）
  libgl4es.so          — OpenGL→GLES（可选 Zink）

可选：
  libopenxr_loader.so

虚拟按键层在 Kotlin（JeGameActivity / VirtualControlsView）已内置，
不依赖 so；缺少 so 时仍可打开横屏触控页并看到按键反馈。

ABI 目录示例：
  jniLibs/arm64-v8a/
  jniLibs/armeabi-v7a/
  jniLibs/x86_64/

/// 本地应用版本与 GitHub 更新源（与 pubspec.yaml / version.json 保持一致）。
class AppVersion {
  static const String displayName = '星穹次元启动器';
  static const String version = '0.2.5';

  static const String githubOwner = 'M-Starry-Sky';
  static const String githubRepo = 'Launcher';

  static String get githubRepoUrl =>
      'https://github.com/$githubOwner/$githubRepo';

  static String get versionManifestUrl =>
      'https://raw.githubusercontent.com/$githubOwner/$githubRepo/main/version.json';

  static String get releasesApiUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static String get releasesPageUrl =>
      'https://github.com/$githubOwner/$githubRepo/releases';
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../download/accelerated_downloader.dart';
import '../download/download_sources.dart';
import '../download/network_env.dart';

/// 游戏版本安装器：全部从 Mojang / Fabric 官方元数据源下载，平台不托管游戏文件。
/// - 原版：piston-meta 官方版本清单 → 客户端 jar / libraries / assets
/// - Fabric：meta.fabricmc.net 官方 profile → 保存为继承原版的版本 JSON
/// 实际字节下载经 [AcceleratedDownloader]（多源 / 可选节点互传）。
class VersionInstaller {
  static const String versionManifestUrl =
      'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
  static const String fabricProfileTemplate =
      'https://meta.fabricmc.net/v2/versions/loader/{game}/{loader}/profile/json';
  static const String userAgent = DownloadSources.userAgent;

  final void Function(String message)? onProgress;
  final AppConfig? config;
  late final AcceleratedDownloader _downloader;

  VersionInstaller({this.onProgress, this.config}) {
    _downloader = AcceleratedDownloader(config: config, onLog: onProgress);
  }

  void close() => _downloader.close();

  void _log(String message) {
    onProgress?.call(message);
    // 落盘便于排查「下载失败」；失败时用户可打开此文件。
    try {
      final f = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}xingqiong_download.log',
      );
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {}
  }

  /// 列出游戏目录下已下载的版本文件夹。
  static List<LocalGameVersion> listLocalVersions(Directory gameDir) {
    final versionsDir = Directory(p.join(gameDir.path, 'versions'));
    if (!versionsDir.existsSync()) return const [];
    final out = <LocalGameVersion>[];
    try {
      for (final e in versionsDir.listSync().whereType<Directory>()) {
        final id = p.basename(e.path);
        if (id.isEmpty || id.startsWith('.')) continue;
        final jsonFile = File(p.join(e.path, '$id.json'));
        final hasJson = jsonFile.existsSync();

        String? inheritsFrom;
        if (hasJson) {
          try {
            final raw = jsonFile.readAsStringSync();
            final map = jsonDecode(raw);
            if (map is Map && map['inheritsFrom'] != null) {
              inheritsFrom = '${map['inheritsFrom']}'.trim();
              if (inheritsFrom.isEmpty) inheritsFrom = null;
            }
          } catch (_) {}
        }

        // 1) 本目录 $id.jar  2) 目录内任意客户端 jar  3) inheritsFrom 父版本 jar
        var jarFile = File(p.join(e.path, '$id.jar'));
        var jarBytes = jarFile.existsSync() ? jarFile.lengthSync() : 0;
        var hasOwnJar = jarFile.existsSync() && jarBytes > 1024 * 100;

        if (!hasOwnJar) {
          try {
            final any = e
                .listSync()
                .whereType<File>()
                .where((f) {
                  final n = p.basename(f.path).toLowerCase();
                  return n.endsWith('.jar') &&
                      !n.contains('sources') &&
                      !n.contains('javadoc');
                })
                .toList();
            if (any.isNotEmpty) {
              any.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
              jarFile = any.first;
              jarBytes = jarFile.lengthSync();
              hasOwnJar = jarBytes > 1024 * 100;
            }
          } catch (_) {}
        }

        var hasJar = hasOwnJar;
        String? jarSourceId;
        if (!hasJar && inheritsFrom != null) {
          final parentJar = File(
            p.join(versionsDir.path, inheritsFrom, '$inheritsFrom.jar'),
          );
          if (parentJar.existsSync() && parentJar.lengthSync() > 1024 * 100) {
            hasJar = true;
            jarBytes = parentJar.lengthSync();
            jarSourceId = inheritsFrom;
          }
        }

        var nativeCount = _countNativesInVersionDir(e);
        // Fabric/Forge profile 常无自带 natives，沿用父版本
        if (nativeCount == 0 && inheritsFrom != null) {
          final parentDir =
              Directory(p.join(versionsDir.path, inheritsFrom));
          if (parentDir.existsSync()) {
            nativeCount = _countNativesInVersionDir(parentDir);
          }
        }

        out.add(LocalGameVersion(
          id: id,
          path: e.path,
          hasJar: hasJar,
          hasJson: hasJson,
          jarBytes: jarBytes,
          nativeLibCount: nativeCount,
          inheritsFrom: inheritsFrom,
          jarFromParent: jarSourceId != null,
        ));
      }
    } catch (_) {
      return const [];
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  static int _countNativesInVersionDir(Directory versionDir) {
    var nativeCount = 0;
    final nativeDirs = <Directory>[
      Directory(p.join(versionDir.path, 'natives-${_staticOsName()}')),
      Directory(p.join(versionDir.path, 'natives')),
    ];
    try {
      for (final sub in versionDir.listSync().whereType<Directory>()) {
        final bn = p.basename(sub.path).toLowerCase();
        if (bn.startsWith('natives')) nativeDirs.add(sub);
      }
    } catch (_) {}
    final seen = <String>{};
    for (final nd in nativeDirs) {
      if (!nd.existsSync()) continue;
      final key = p.normalize(nd.path);
      if (!seen.add(key)) continue;
      try {
        nativeCount += nd
            .listSync()
            .whereType<File>()
            .where((f) {
              final n = f.path.toLowerCase();
              return n.endsWith('.dll') ||
                  n.endsWith('.so') ||
                  n.endsWith('.dylib');
            })
            .length;
      } catch (_) {}
    }
    return nativeCount;
  }

  /// 删除已下载版本目录（真删除磁盘；含同游戏版本的 Fabric profile）。
  /// 成功后写入 [.need_reinstall_<id>]，下次启动强制完整重装。
  static Future<void> deleteLocalVersion(
    Directory gameDir,
    String versionId, {
    bool includeRelatedLoaders = true,
  }) async {
    final id = versionId.trim();
    if (id.isEmpty ||
        id.contains('..') ||
        id.contains('/') ||
        id.contains(r'\')) {
      throw InstallException('非法版本 id');
    }
    final versionsRoot = Directory(p.join(gameDir.path, 'versions'));
    final targets = <Directory>[
      Directory(p.join(versionsRoot.path, id)),
    ];
    if (includeRelatedLoaders && versionsRoot.existsSync()) {
      for (final e in versionsRoot.listSync().whereType<Directory>()) {
        final name = p.basename(e.path);
        if (name == id) continue;
        if (name.endsWith('-$id')) {
          targets.add(e);
        }
      }
    }

    final failed = <String>[];
    for (final dir in targets) {
      try {
        await _deleteDirectoryVerified(dir);
      } catch (e) {
        failed.add('${p.basename(dir.path)}: $e');
      }
    }
    final primary = Directory(p.join(versionsRoot.path, id));
    if (primary.existsSync()) {
      throw InstallException(
        '删除未完成，目录仍在：${primary.path}\n'
        '请先完全退出游戏/Java 进程后重试。'
        '${failed.isEmpty ? '' : '\n详情: ${failed.join('; ')}'}',
      );
    }
    if (failed.isNotEmpty) {
      throw InstallException('部分关联目录删除失败: ${failed.join('; ')}');
    }
    await versionsRoot.create(recursive: true);
    await reinstallStamp(gameDir, id).writeAsString(
      '${DateTime.now().toIso8601String()}\n',
      flush: true,
    );
  }

  static File reinstallStamp(Directory gameDir, String versionId) =>
      File(p.join(gameDir.path, 'versions', '.need_reinstall_$versionId'));

  static bool needsForcedReinstall(Directory gameDir, String versionId) =>
      reinstallStamp(gameDir, versionId).existsSync();

  /// 本机是否已有某游戏版本的 Fabric profile；有则返回 loader 版本号。
  static String? findLocalFabricLoader(Directory gameDir, String gameVersion) {
    final versions = Directory(p.join(gameDir.path, 'versions'));
    if (!versions.existsSync()) return null;
    final prefix = 'fabric-loader-';
    final suffix = '-$gameVersion';
    String? best;
    try {
      for (final e in versions.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (!name.startsWith(prefix) || !name.endsWith(suffix)) continue;
        final mid = name.substring(prefix.length, name.length - suffix.length);
        if (mid.isEmpty) continue;
        final json = File(p.join(e.path, '$name.json'));
        if (!json.existsSync()) continue;
        best = mid;
        break;
      }
    } catch (_) {}
    return best;
  }

  /// 本地是否已可直接启动（免安装检查）。对齐主流启动器的「已安装即秒启」。
  static bool isWarmReady({
    required Directory gameDir,
    required String gameVersion,
    required String loaderType,
    String loaderVersion = '',
  }) {
    if (needsForcedReinstall(gameDir, gameVersion)) return false;
    final versionDir = Directory(p.join(gameDir.path, 'versions', gameVersion));
    final jsonFile = File(p.join(versionDir.path, '$gameVersion.json'));
    final jar = File(p.join(versionDir.path, '$gameVersion.jar'));
    if (!jsonFile.existsSync() || !jar.existsSync()) return false;
    try {
      if (jar.lengthSync() < 1024 * 100) return false;
    } catch (_) {
      return false;
    }

    try {
      final versionJson =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final assetIndex = (versionJson['assetIndex'] as Map?) ?? {};
      final indexName = '${assetIndex['id'] ?? gameVersion}';
      final stamp = File(
        p.join(gameDir.path, 'assets', 'objects', '.xq_assets_ok_$indexName'),
      );
      if (!stamp.existsSync()) return false;
      final libsStamp = File(
        p.join(versionDir.path, '.xq_libs_ok'),
      );
      // 无库戳时仍允许：旧安装靠 jar+资产即可；首次完整装后会写戳
      if (libsStamp.existsSync()) {
        final n = int.tryParse(libsStamp.readAsStringSync().trim()) ?? 0;
        if (n <= 0) return false;
      }
    } catch (_) {
      return false;
    }

    final loader = loaderType.toLowerCase();
    if (loader == 'fabric' || loader == 'quilt') {
      if (loaderVersion.isEmpty) return false;
      final profileId = 'fabric-loader-$loaderVersion-$gameVersion';
      final profile = File(
        p.join(gameDir.path, 'versions', profileId, '$profileId.json'),
      );
      if (!profile.existsSync()) return false;
    }
    return true;
  }

  /// 缺资产戳但本地文件看起来齐全时，抽样校验后补写戳。
  ///
  /// 对齐 PCL/HMCL「已安装即信任」：避免每次启动对 `assets/objects` 全量扫盘
  ///（缺戳时常见 2–3 分钟慢启）。抽样失败则返回 false，由安装流程完整补齐。
  static Future<bool> healAssetsStampIfPossible(
    Directory gameDir,
    String gameVersion, {
    void Function(String message)? onLog,
  }) async {
    if (needsForcedReinstall(gameDir, gameVersion)) return false;
    final versionDir = Directory(p.join(gameDir.path, 'versions', gameVersion));
    final jsonFile = File(p.join(versionDir.path, '$gameVersion.json'));
    final jar = File(p.join(versionDir.path, '$gameVersion.jar'));
    if (!jsonFile.existsSync() || !jar.existsSync()) return false;
    try {
      if (jar.lengthSync() < 1024 * 100) return false;
    } catch (_) {
      return false;
    }

    try {
      final versionJson =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final assetIndex = (versionJson['assetIndex'] as Map?) ?? {};
      final indexName = '${assetIndex['id'] ?? gameVersion}';
      final indexesDir = Directory(p.join(gameDir.path, 'assets', 'indexes'));
      final objectsDir = Directory(p.join(gameDir.path, 'assets', 'objects'));
      final stamp = File(p.join(objectsDir.path, '.xq_assets_ok_$indexName'));
      final indexFile = File(p.join(indexesDir.path, '$indexName.json'));
      if (!indexFile.existsSync() || !objectsDir.existsSync()) return false;

      final indexJson = jsonDecode(indexFile.readAsStringSync()) as Map;
      final objects = (indexJson['objects'] as Map?) ?? {};
      final total = objects.length;
      if (total <= 0) return false;

      if (stamp.existsSync()) {
        final stamped = int.tryParse(stamp.readAsStringSync().trim());
        if (stamped == total) return true;
      }

      // 抽样若干 hash：毫秒级 exists，避免全树 list
      const sampleCap = 12;
      var checked = 0;
      var ok = 0;
      for (final entry in objects.entries) {
        if (checked >= sampleCap) break;
        final info = entry.value;
        if (info is! Map) continue;
        final hash = info['hash']?.toString();
        if (hash == null || hash.length < 3) continue;
        checked++;
        final f = File(p.join(objectsDir.path, hash.substring(0, 2), hash));
        if (f.existsSync()) ok++;
      }
      if (checked == 0 || ok < checked) {
        onLog?.call('资产抽样未通过（$ok/$checked），将走完整检查');
        return false;
      }

      await stamp.writeAsString('$total');
      onLog?.call('已补写资产就绪戳（$total，抽样 $ok/$checked），跳过全量扫盘');
      return true;
    } catch (e) {
      onLog?.call('补写资产戳失败: $e');
      return false;
    }
  }

  static Future<void> clearReinstallStamp(
    Directory gameDir,
    String versionId,
  ) async {
    final f = reinstallStamp(gameDir, versionId);
    if (f.existsSync()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Windows 下文件占用常见：重试 + 改名后再删 + rd /s /q，并校验。
  static Future<void> _deleteDirectoryVerified(Directory dir) async {
    if (!dir.existsSync()) return;
    Object? lastError;
    for (var i = 0; i < 6; i++) {
      try {
        if (!dir.existsSync()) return;
        await dir.delete(recursive: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!dir.existsSync()) return;
      } catch (e) {
        lastError = e;
      }
      try {
        if (!dir.existsSync()) return;
        final tomb = Directory(
          '${dir.path}.trash_${DateTime.now().microsecondsSinceEpoch}',
        );
        await dir.rename(tomb.path);
        await tomb.delete(recursive: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!dir.existsSync() && !tomb.existsSync()) return;
      } catch (e) {
        lastError = e;
      }
      if (Platform.isWindows && dir.existsSync()) {
        try {
          final r = await Process.run(
            'cmd',
            ['/c', 'rd', '/s', '/q', dir.path],
            runInShell: false,
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
          if (!dir.existsSync()) return;
          lastError = 'rd exit=${r.exitCode} ${r.stderr}';
        } catch (e) {
          lastError = e;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
    }
    if (dir.existsSync()) {
      throw InstallException(
        '无法删除 ${dir.path}${lastError == null ? '' : ' ($lastError)'}',
      );
    }
  }

  static String _staticOsName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'osx';
    return 'linux';
  }

  // 桌面对齐 HMCL；手机压并发，减轻限流。
  static int get _assetConcurrency {
    final n = Platform.numberOfProcessors;
    if (Platform.isAndroid || Platform.isIOS) {
      return n.clamp(4, 8);
    }
    return (n * 2).clamp(6, 24);
  }

  static int get _libConcurrency {
    final n = Platform.numberOfProcessors;
    if (Platform.isAndroid || Platform.isIOS) {
      return n.clamp(3, 6);
    }
    return n.clamp(4, 12);
  }

  /// 有界并发执行任务列表。
  Future<void> _runPool(
    List<Future<void> Function()> tasks, {
    required int concurrency,
  }) async {
    if (tasks.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tasks.length) return;
        await tasks[i]();
      }
    }

    final n = concurrency.clamp(1, tasks.length);
    await Future.wait(List.generate(n, (_) => worker()));
  }

  /// 安装原版（含资产）。[gameDir] 为游戏根目录（.minecraft 风格布局）。
  /// [force] 为 true 时先清空该版本目录再完整下载（删除后重装）。
  Future<void> installVanilla(
    String versionId,
    Directory gameDir, {
    bool force = false,
  }) async {
    _downloader.versionId = versionId;
    final versionDir = Directory('${gameDir.path}/versions/$versionId');

    // 暖启动：已装齐则整段跳过（房间路径等未走 LaunchService 时同样受益）
    if (!force) {
      if (!isWarmReady(
        gameDir: gameDir,
        gameVersion: versionId,
        loaderType: 'none',
      )) {
        await healAssetsStampIfPossible(gameDir, versionId, onLog: _log);
      }
      if (isWarmReady(
        gameDir: gameDir,
        gameVersion: versionId,
        loaderType: 'none',
      )) {
        _log('原版 $versionId 本地已就绪，跳过安装检查');
        return;
      }
    }

    if (force || needsForcedReinstall(gameDir, versionId)) {
      _log('强制重装 $versionId：清空本机版本目录后重新下载…');
      if (versionDir.existsSync()) {
        await _deleteDirectoryVerified(versionDir);
      }
      await clearReinstallStamp(gameDir, versionId);
    }

    await versionDir.create(recursive: true);
    final jsonFile = File('${versionDir.path}/$versionId.json');
    final clientJar = File('${versionDir.path}/$versionId.jar');

    late final Map<String, dynamic> versionJson;
    final jarOk = clientJar.existsSync() && clientJar.lengthSync() > 1024 * 100;
    final localReady = jsonFile.existsSync() && jarOk;
    // 本地已齐时跳过镜像探测，避免每次启动白白等网络探活
    if (!localReady) {
      await NetworkEnv.instance.ensureProbed(onLog: onProgress);
    }
    if (localReady) {
      _log('原版 $versionId 本地已就绪，跳过清单下载');
      versionJson =
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      // 校验体积：过小视为损坏，强制重下
      final downloads = (versionJson['downloads'] as Map?) ?? {};
      final client = (downloads['client'] as Map?) ?? {};
      final expectedSize = (client['size'] as num?)?.toInt();
      if (expectedSize != null &&
          expectedSize > 0 &&
          clientJar.lengthSync() != expectedSize) {
        _log(
          '客户端 jar 体积异常（${clientJar.lengthSync()} ≠ $expectedSize），重新下载…',
        );
        await clientJar.delete();
        final clientUrl = client['url'] as String?;
        final clientSha1 = client['sha1'] as String?;
        if (clientUrl == null) {
          throw InstallException('版本元数据缺少 client.url');
        }
        await NetworkEnv.instance.ensureProbed(onLog: onProgress);
        await _downloadTo(
          Uri.parse(clientUrl),
          clientJar,
          expectedSha1: clientSha1,
          expectedSize: expectedSize,
        );
      }
    } else {
      if (clientJar.existsSync() && !jarOk) {
        _log('本地 jar 过小或不完整，将重新下载');
        try {
          await clientJar.delete();
        } catch (_) {}
      }
      _log('获取版本清单…');
      final manifest = await _getJson(Uri.parse(versionManifestUrl));
      final versions = (manifest['versions'] as List? ?? [])
          .whereType<Map>()
          .where((v) => v['id'] == versionId)
          .toList();
      if (versions.isEmpty) {
        throw InstallException('官方源中不存在版本 $versionId');
      }

      _log('获取 $versionId 版本元数据…');
      versionJson =
          await _getJson(Uri.parse(versions.first['url'] as String));
      await jsonFile.writeAsString(jsonEncode(versionJson));

      final downloads = (versionJson['downloads'] as Map?) ?? {};
      final client = (downloads['client'] as Map?) ?? {};
      final clientUrl = client['url'] as String?;
      final clientSha1 = client['sha1'] as String?;
      final clientSize = (client['size'] as num?)?.toInt();
      if (clientUrl != null) {
        if (clientJar.existsSync() &&
            clientSize != null &&
            clientJar.lengthSync() != clientSize) {
          _log('本地 jar 大小不符，重新下载');
          try {
            await clientJar.delete();
          } catch (_) {}
        }
        if (!clientJar.existsSync()) {
          _log('下载客户端 jar…');
          await _downloadTo(
            Uri.parse(clientUrl),
            clientJar,
            expectedSha1: clientSha1,
            expectedSize: clientSize,
          );
        }
      }
    }

    // libraries（并发）
    final libraryDir = Directory('${gameDir.path}/libraries');
    await libraryDir.create(recursive: true);
    final nativesDir = Directory('${versionDir.path}/natives-${_osName()}');
    await nativesDir.create(recursive: true);

    final libraries = (versionJson['libraries'] as List? ?? [])
        .whereType<Map>()
        .where((lib) => _rulesAllow(lib['rules']))
        .toList();

    final libJobs = <Future<void> Function()>[];
    final nativeFiles = <File>[];
    final nativeClassifier = _nativeClassifier();
    for (final lib in libraries) {
      final libName = lib['name'] as String? ?? '';
      final libDownloads = (lib['downloads'] as Map?) ?? {};
      final artifact = libDownloads['artifact'] as Map?;
      if (artifact != null) {
        final path = artifact['path'] as String?;
        final url = artifact['url'] as String?;
        final sha1 = artifact['sha1'] as String?;
        final size = (artifact['size'] as num?)?.toInt();
        if (path != null && url != null) {
          final target = File('${libraryDir.path}/$path');
          // 1.19+：natives 是独立 artifact（如 …:natives-windows），需解压出 dll
          if (_isNativeClassifierName(libName, nativeClassifier)) {
            nativeFiles.add(target);
          }
          if (!target.existsSync()) {
            final name = path.split('/').last;
            libJobs.add(() async {
              await _downloadTo(
                Uri.parse(url),
                target,
                expectedSha1: sha1,
                expectedSize: size,
              );
              _log('库 $name');
            });
          }
        }
      }
      // 旧格式：downloads.classifiers.natives-windows
      final classifiers = (libDownloads['classifiers'] as Map?) ?? {};
      final native = classifiers[nativeClassifier] as Map?;
      if (native != null) {
        final nativeUrl = native['url'] as String?;
        final nativePath = native['path'] as String?;
        final nativeSha1 = native['sha1'] as String?;
        if (nativeUrl != null && nativePath != null) {
          final nativeFile = File('${libraryDir.path}/$nativePath');
          nativeFiles.add(nativeFile);
          if (!nativeFile.existsSync()) {
            libJobs.add(() async {
              await _downloadTo(
                Uri.parse(nativeUrl),
                nativeFile,
                expectedSha1: nativeSha1,
              );
            });
          }
        }
      }
    }
    if (libJobs.isNotEmpty) {
      _log('下载依赖库 ${libJobs.length} 个（并发 $_libConcurrency）…');
      await _runPool(libJobs, concurrency: _libConcurrency);
    }
    try {
      await File(p.join(versionDir.path, '.xq_libs_ok'))
          .writeAsString('${libraries.length}');
    } catch (_) {}

    final nativeDlls = nativesDir.existsSync()
        ? nativesDir
            .listSync()
            .whereType<File>()
            .where((f) {
              final n = f.path.toLowerCase();
              return n.endsWith('.dll') ||
                  n.endsWith('.so') ||
                  n.endsWith('.dylib');
            })
            .length
        : 0;
    final hasOpenAl = nativesDir.existsSync() &&
        nativesDir.listSync().whereType<File>().any((f) {
          final n = f.uri.pathSegments.last.toLowerCase();
          return n == 'openal.dll' || n.startsWith('libopenal');
        });
    // Windows 缺 OpenAL / 库过少 → 强制重解压
    final nativesBad = nativeFiles.isNotEmpty &&
        (nativeDlls < 3 || (Platform.isWindows && !hasOpenAl));
    if (nativesBad) {
      if (nativesDir.existsSync()) {
        _log('natives 不完整（dll=$nativeDlls openal=$hasOpenAl），重新解压…');
        try {
          await nativesDir.delete(recursive: true);
        } catch (_) {}
      } else {
        _log('解压 natives（${nativeFiles.length} 个）…');
      }
      await nativesDir.create(recursive: true);
      for (final nativeFile in nativeFiles) {
        if (!nativeFile.existsSync()) {
          _log('缺少 natives 包 ${nativeFile.uri.pathSegments.last}');
          continue;
        }
        await extractZipTo(nativeFile, nativesDir);
      }
      final after = nativesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.dll') ||
              f.path.toLowerCase().endsWith('.so') ||
              f.path.toLowerCase().endsWith('.dylib'))
          .length;
      _log('natives 已就绪（$after 个本地库）');
      if (after == 0) {
        throw InstallException(
          'natives 解压后仍为空，游戏无法启动。请删除该版本后重装。',
        );
      }
    } else if (nativeDlls > 0) {
      // 清掉历史错误解压留下的 windows/ 杂质目录
      final junk = Directory('${nativesDir.path}/windows');
      if (junk.existsSync()) {
        try {
          await junk.delete(recursive: true);
          _log('已清理 natives 杂质目录');
        } catch (_) {}
      }
      _log('natives 已就绪（$nativeDlls 个本地库）');
    } else if (nativeFiles.isEmpty) {
      _log('警告：未找到 $nativeClassifier 包，若启动闪退请删除版本后重装');
    }

    // assets（高并发；小文件走镜像快速路径）
    final assetIndex = (versionJson['assetIndex'] as Map?) ?? {};
    final assetIndexUrl = assetIndex['url'] as String?;
    if (assetIndexUrl != null) {
      final assetsDir = Directory('${gameDir.path}/assets');
      final indexesDir = Directory('${assetsDir.path}/indexes');
      final objectsDir = Directory('${assetsDir.path}/objects');
      await indexesDir.create(recursive: true);
      await objectsDir.create(recursive: true);

      final indexName = assetIndex['id'] as String? ?? versionId;
      final indexFile = File('${indexesDir.path}/$indexName.json');
      final String indexJson;
      if (indexFile.existsSync()) {
        indexJson = indexFile.readAsStringSync();
      } else {
        _log('下载资产索引…');
        indexJson = await _getString(Uri.parse(assetIndexUrl));
        await indexFile.writeAsString(indexJson);
      }
      final objects =
          ((jsonDecode(indexJson) as Map)['objects'] as Map?) ?? {};

      final stamp = File('${objectsDir.path}/.xq_assets_ok_$indexName');
      final total = objects.length;
      if (stamp.existsSync()) {
        final stamped = int.tryParse(stamp.readAsStringSync().trim());
        if (stamped == total && total > 0) {
          _log('资产已齐全 ($total，跳过扫描)');
        } else {
          await _scanAndFetchAssets(
            objects: objects,
            objectsDir: objectsDir,
            stamp: stamp,
            total: total,
          );
        }
      } else {
        await _scanAndFetchAssets(
          objects: objects,
          objectsDir: objectsDir,
          stamp: stamp,
          total: total,
        );
      }
    }

    _log('原版 $versionId 安装完成');
  }

  Future<void> _scanAndFetchAssets({
    required Map objects,
    required Directory objectsDir,
    required File stamp,
    required int total,
  }) async {
    // 一次递归列举远快于对每个 hash 调 existsSync（缺戳时常见数分钟）
    final existing = <String>{};
    if (objectsDir.existsSync()) {
      try {
        await for (final e
            in objectsDir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            final name = p.basename(e.path);
            if (name.length == 40 && !name.startsWith('.')) {
              existing.add(name);
            }
          }
        }
      } catch (_) {}
    }

    final pending = <({String hash, File file, int? size})>[];
    for (final entry in objects.entries) {
      final info = entry.value as Map;
      final hash = info['hash'] as String;
      if (existing.contains(hash)) continue;
      pending.add((
        hash: hash,
        file: File('${objectsDir.path}/${hash.substring(0, 2)}/$hash'),
        size: (info['size'] as num?)?.toInt(),
      ));
    }

    final already = total - pending.length;
    if (pending.isEmpty) {
      _log('资产已齐全 ($total)');
      await stamp.writeAsString('$total');
      return;
    }

    _log('待下载资产 ${pending.length}/$total（并发 $_assetConcurrency）…');
    var finished = already;
    var failed = 0;
    var lastBeat = DateTime.now();
    await _runPool(
      [
        for (final p in pending)
          () async {
            try {
              await _downloadTo(
                Uri.parse(
                  'https://resources.download.minecraft.net/'
                  '${p.hash.substring(0, 2)}/${p.hash}',
                ),
                p.file,
                expectedSha1: p.hash,
                expectedSize: p.size,
              );
            } catch (e) {
              failed++;
              if (failed <= 5) {
                _log('资产失败 ${p.hash.substring(0, 8)}…: $e');
              }
            } finally {
              finished++;
              final now = DateTime.now();
              final dueBeat = now.difference(lastBeat).inSeconds >= 2;
              if (finished % 20 == 0 || finished == total || dueBeat) {
                lastBeat = now;
                _log('资产进度 $finished/$total'
                    '${failed > 0 ? '（失败 $failed）' : ''}');
              }
            }
          },
      ],
      concurrency: _assetConcurrency,
    );
    if (failed > 5) {
      _log('另有 ${failed - 5} 个资产失败未逐条列出');
    }
    _log('资产下载完成（成功 ${pending.length - failed}，失败 $failed）');
    if (failed > 0) {
      final retry = <({String hash, File file, int? size})>[];
      for (final p in pending) {
        if (!p.file.existsSync()) retry.add(p);
      }
      if (retry.isNotEmpty) {
        _log('补下失败资产 ${retry.length} 个…');
        var still = 0;
        await _runPool(
          [
            for (final p in retry)
              () async {
                try {
                  await _downloadTo(
                    Uri.parse(
                      'https://resources.download.minecraft.net/'
                      '${p.hash.substring(0, 2)}/${p.hash}',
                    ),
                    p.file,
                    expectedSha1: p.hash,
                    expectedSize: p.size,
                  );
                } catch (_) {
                  still++;
                }
              },
          ],
          concurrency: (_assetConcurrency / 2).ceil().clamp(2, 8),
        );
        failed = still;
        _log('补下后仍失败 $failed');
      }
    }
    final failRatio = pending.isEmpty ? 0.0 : failed / pending.length;
    if (failed >= 50 || failRatio >= 0.1) {
      throw InstallException(
        '资产下载失败过多（$failed/${pending.length}），请检查网络后重试下载',
      );
    }
    // 可接受失败阈值内也写戳，避免下次启动再全量扫盘/补下（常见 2–3 分钟慢启根因）
    await stamp.writeAsString('$total');
  }

  /// 安装 Fabric（官方 profile JSON，继承原版）。需先安装原版。
  Future<void> installFabric(
      String gameVersion, String loaderVersion, Directory gameDir) async {
    _downloader.versionId = gameVersion;
    final profileId = 'fabric-loader-$loaderVersion-$gameVersion';
    final versionDir = Directory('${gameDir.path}/versions/$profileId');
    final profileFile = File('${versionDir.path}/$profileId.json');

    late final Map<String, dynamic> profile;
    if (profileFile.existsSync()) {
      _log('Fabric profile 本地已就绪，跳过网络拉取');
      profile =
          jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
    } else {
      final url = fabricProfileTemplate
          .replaceAll('{game}', gameVersion)
          .replaceAll('{loader}', loaderVersion);
      _log('获取 Fabric 官方 profile…');
      profile = await _getJson(Uri.parse(url));
      await versionDir.create(recursive: true);
      await profileFile.writeAsString(jsonEncode(profile));
    }
    await versionDir.create(recursive: true);

    // Fabric profile 的 libraries 自带官方仓库 URL
    final libraryDir = Directory('${gameDir.path}/libraries');
    await libraryDir.create(recursive: true);
    final fabricJobs = <Future<void> Function()>[];
    for (final lib in (profile['libraries'] as List? ?? []).whereType<Map>()) {
      final libUrl = (lib['url'] as String?) ?? 'https://libraries.minecraft.net/';
      final name = lib['name'] as String;
      final path = _mavenPath(name);
      if (path == null) continue;
      final target = File('${libraryDir.path}/$path');
      if (target.existsSync()) continue;
      fabricJobs.add(() async {
        await _downloadTo(Uri.parse('$libUrl$path'), target);
        _log('Fabric 库 ${path.split('/').last}');
      });
    }
    if (fabricJobs.isNotEmpty) {
      _log('下载 Fabric 库 ${fabricJobs.length} 个…');
      await _runPool(fabricJobs, concurrency: _libConcurrency);
    } else {
      _log('Fabric 库已齐全');
    }
    _log('Fabric $loaderVersion（游戏 $gameVersion）安装完成');
  }

  /// 解析版本继承链（fabric profile → 原版）为启动所需结构。
  ///
  /// [trustClasspath]：暖启动时信任本地库已齐全，跳过数百次 existsSync
  ///（对齐主流启动器「已装即拉起」）。
  Future<ResolvedVersion> resolveVersionChain(
    String profileId,
    Directory gameDir, {
    bool trustClasspath = false,
  }) async {
    var json = await _readVersionJson(profileId, gameDir);
    final chain = <Map<String, dynamic>>[json];
    while (json['inheritsFrom'] != null) {
      final parent = await _readVersionJson(json['inheritsFrom'] as String,
          gameDir);
      chain.insert(0, parent);
      json = parent;
    }

    // 任一版本目录有库戳即可信任 classpath（完整装过）
    var trust = trustClasspath;
    if (!trust) {
      for (final layer in chain) {
        final id = layer['id'] as String?;
        if (id == null) continue;
        final stamp = File(p.join(gameDir.path, 'versions', id, '.xq_libs_ok'));
        if (stamp.existsSync()) {
          final n = int.tryParse(stamp.readAsStringSync().trim()) ?? 0;
          if (n > 0) {
            trust = true;
            break;
          }
        }
      }
    }

    final libraryDir = '${gameDir.path}/libraries';
    final classpath = <String>[];
    final seen = <String>{};
    String? mainClass;
    List<String>? gameArgs;
    String? assetsIndexName;
    String? mainJarId;
    String? nativesDirPath;

    // 先收集候选路径再批量探测，并去重
    final candidatePaths = <String>[];
    final nativeDirs = <String>[];

    for (final layer in chain) {
      final id = layer['id'] as String;
      final libs = (layer['libraries'] as List? ?? []).whereType<Map>();
      for (final lib in libs) {
        if (!_rulesAllow(lib['rules'])) continue;
        final name = lib['name'] as String;
        final path = _mavenPath(name);
        if (path != null) {
          final full =
              '$libraryDir/$path'.replaceAll('/', Platform.pathSeparator);
          if (seen.add(full)) candidatePaths.add(full);
        }
        final native = ((lib['natives'] as Map?)?[_osName()]) as String?;
        if (native != null) {
          nativeDirs.add(
              '${gameDir.path}/versions/$id/natives-${_osName()}');
        }
      }
      if (layer['inheritsFrom'] == null) {
        mainJarId = id;
      }
      mainClass = (layer['mainClass'] as String?) ?? mainClass;
      gameArgs ??= _gameArgsOf(layer);
      assetsIndexName ??=
          ((layer['assetIndex'] as Map?)?['id']) as String? ?? assetsIndexName;
    }

    if (trust) {
      classpath.addAll(candidatePaths);
    } else {
      final existFlags = List<bool>.generate(
        candidatePaths.length,
        (i) => File(candidatePaths[i]).existsSync(),
        growable: false,
      );
      for (var i = 0; i < candidatePaths.length; i++) {
        if (existFlags[i]) classpath.add(candidatePaths[i]);
      }
    }

    for (final nd in nativeDirs) {
      if (nativesDirPath != null) break;
      if (Directory(nd).existsSync()) nativesDirPath = nd;
    }

    final jarId = mainJarId ?? profileId;
    final vanillaNatives =
        Directory('${gameDir.path}/versions/$jarId/natives-${_osName()}');
    if (vanillaNatives.existsSync()) {
      nativesDirPath = vanillaNatives.path;
    } else if (nativesDirPath == null) {
      nativesDirPath = vanillaNatives.path;
    }

    final clientJar =
        '${gameDir.path}/versions/$mainJarId/$mainJarId.jar';
    if (mainJarId != null && File(clientJar).existsSync()) {
      classpath.insert(0, clientJar);
    }

    return ResolvedVersion(
      id: profileId,
      mainClass: mainClass,
      classpath: classpath,
      gameArgs: gameArgs ?? const [],
      assetsIndexName: assetsIndexName ?? '',
      nativesDir: nativesDirPath ?? '',
    );
  }

  List<String>? _gameArgsOf(Map<String, dynamic> layer) {
    final arguments = layer['arguments'] as Map?;
    if (arguments != null) {
      final game = (arguments['game'] as List? ?? [])
          .where((e) => e is String)
          .cast<String>()
          .toList();
      if (game.isNotEmpty) return game;
    }
    final legacy = layer['minecraftArguments'] as String?;
    if (legacy != null) return legacy.split(' ');
    return null;
  }

  Future<Map<String, dynamic>> _readVersionJson(
      String id, Directory gameDir) async {
    final file = File('${gameDir.path}/versions/$id/$id.json');
    if (!await file.exists()) {
      throw InstallException('缺少版本元数据 $id，请先安装该版本');
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  /// 读取版本 JSON（含 inheritsFrom 链）声明的 Java 主版本。
  /// 用于启动前选对隔离 JDK；无元数据时返回 null。
  static Future<int?> peekDeclaredJavaMajor(
    Directory gameDir,
    String versionId,
  ) async {
    try {
      var id = versionId;
      for (var depth = 0; depth < 8; depth++) {
        final file = File('${gameDir.path}/versions/$id/$id.json');
        if (!await file.exists()) return null;
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final jv = json['javaVersion'];
        if (jv is Map) {
          final major = (jv['majorVersion'] as num?)?.toInt();
          if (major != null && major > 0) return major;
        }
        final parent = json['inheritsFrom'] as String?;
        if (parent == null || parent.isEmpty) return null;
        id = parent;
      }
    } catch (_) {}
    return null;
  }

  String? _mavenPath(String name) {
    final parts = name.split(':');
    if (parts.length < 3) return null;
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    final version = parts[2];
    final classifier = parts.length > 3 ? '-${parts[3]}' : '';
    return '$group/$artifact/$version/$artifact-$version$classifier.jar';
  }

  /// 当前平台对应的 natives classifier（1.19+ 独立库名后缀）。
  String _nativeClassifier() {
    if (Platform.isWindows) return 'natives-windows';
    if (Platform.isMacOS) {
      final ver = Platform.version.toLowerCase();
      if (ver.contains('arm') || ver.contains('aarch64')) {
        return 'natives-macos-arm64';
      }
      return 'natives-macos';
    }
    return 'natives-linux';
  }

  bool _isNativeClassifierName(String mavenName, String classifier) {
    final parts = mavenName.split(':');
    return parts.length >= 4 && parts[3] == classifier;
  }

  bool _rulesAllow(dynamic rules) {
    if (rules is! List || rules.isEmpty) return true;
    var allowed = false;
    for (final rule in rules.whereType<Map>()) {
      final action = rule['action'] as String?;
      final os = (rule['os'] as Map?)?['name'] as String?;
      if (os == null) {
        if (action == 'allow') allowed = true;
      } else if (os == _osName()) {
        allowed = action == 'allow';
      }
    }
    return allowed;
  }

  String _osName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'osx';
    return 'linux';
  }

  // ---- HTTP 工具 ----

  List<String>? _rankedMirrorBases;

  Future<List<String>> _mirrorBasesAsync() async {
    if (_rankedMirrorBases != null) return _rankedMirrorBases!;
    final list = config?.downloadMirrorBases ?? const <String>[];
    _rankedMirrorBases = await NetworkEnv.instance.rankedMirrorBases(
      list,
      onLog: onProgress,
    );
    return _rankedMirrorBases!;
  }

  Future<http.Response> _httpGet(Uri official) async {
    final uris = (config?.downloadAccelEnabled ?? true)
        ? DownloadSources.candidates(
            official,
            mirrorBases: await _mirrorBasesAsync(),
          )
        : [official];
    if (NetworkEnv.instance.preferMirrors && uris.length > 1) {
      final mirrorFirst = [
        ...uris.where((u) => !_isOfficialMetaHost(u.host)),
        ...uris.where((u) => _isOfficialMetaHost(u.host)),
      ];
      uris
        ..clear()
        ..addAll(mirrorFirst);
    }
    Object? last;
    for (final uri in uris) {
      try {
        final response = await http
            .get(uri, headers: {'User-Agent': userAgent})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) return response;
        last = 'HTTP ${response.statusCode}';
      } catch (e) {
        last = e;
      }
    }
    throw InstallException('请求失败 ($official → $last)');
  }

  static bool _isOfficialMetaHost(String host) {
    final h = host.toLowerCase();
    return h.endsWith('mojang.com') ||
        h.endsWith('minecraft.net') ||
        h.endsWith('fabricmc.net');
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _httpGet(uri);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String> _getString(Uri uri) async {
    final response = await _httpGet(uri);
    return utf8.decode(response.bodyBytes);
  }

  Future<void> _downloadTo(
    Uri uri,
    File target, {
    String? expectedSha1,
    int? expectedSize,
  }) async {
    try {
      final result = await _downloader.downloadTo(
        uri,
        target,
        expectedSha1: expectedSha1,
        expectedSize: expectedSize,
      );
      // 资产海量，避免刷屏；仅对大文件或非单源通道提示
      final notable = (expectedSize ?? 0) >= 256 * 1024 ||
          result.channel == DownloadChannel.peer ||
          result.channel == DownloadChannel.multiSource;
      if (!notable) return;
      final name = target.uri.pathSegments.isNotEmpty
          ? target.uri.pathSegments.last
          : target.path;
      switch (result.channel) {
        case DownloadChannel.peer:
          _log('节点互传 $name');
        case DownloadChannel.multiSource:
          _log('多源加速 $name');
        case DownloadChannel.fallback:
          _log('回落官方 $name');
        case DownloadChannel.single:
          break;
      }
    } catch (e) {
      throw InstallException('下载失败 ($uri): $e');
    }
  }

  /// 解压 zip（natives jar）到目录：只落本地库到根目录。
  static Future<void> extractZipTo(File zipFile, Directory targetDir) async {
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
    await targetDir.create(recursive: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (entry.name.startsWith('META-INF')) continue;
      final normalized = entry.name.replaceAll('\\', '/');
      final lower = normalized.toLowerCase();
      final isNativeLib = lower.endsWith('.dll') ||
          lower.endsWith('.so') ||
          lower.endsWith('.dylib') ||
          lower.endsWith('.jnilib');
      // 非本地库（.sha1 / .git / 目录占位）一律跳过，避免污染 java.library.path
      if (!isNativeLib) continue;
      final baseName = normalized.split('/').last;
      if (baseName.isEmpty) continue;
      final file = File('${targetDir.path}/$baseName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>);
    }
  }
}

/// 解析后的启动所需版本信息。
class ResolvedVersion {
  final String id;
  final String? mainClass;
  final List<String> classpath;
  final List<String> gameArgs;
  final String assetsIndexName;
  /// 本地库目录（java.library.path）；Fabric 时仍指向原版 natives。
  final String nativesDir;

  const ResolvedVersion({
    required this.id,
    required this.mainClass,
    required this.classpath,
    required this.gameArgs,
    required this.assetsIndexName,
    this.nativesDir = '',
  });
}

class InstallException implements Exception {
  final String message;
  const InstallException(this.message);

  @override
  String toString() => message;
}

/// 本地已下载的游戏版本目录摘要。
class LocalGameVersion {
  final String id;
  final String path;
  final bool hasJar;
  final bool hasJson;
  final int jarBytes;
  final int nativeLibCount;
  /// Fabric/Forge profile 继承的原版 id（如 1.20.1）。
  final String? inheritsFrom;
  /// jar 实际来自父版本（本目录无 $id.jar 属正常）。
  final bool jarFromParent;

  const LocalGameVersion({
    required this.id,
    required this.path,
    required this.hasJar,
    required this.hasJson,
    required this.jarBytes,
    required this.nativeLibCount,
    this.inheritsFrom,
    this.jarFromParent = false,
  });

  bool get looksComplete => hasJar && hasJson;

  String get statusLabel {
    if (!hasJson) return '缺少元数据';
    if (!hasJar) {
      if (inheritsFrom != null) {
        return '缺少原版 $inheritsFrom jar';
      }
      return '缺少 jar';
    }
    if (jarFromParent && inheritsFrom != null) {
      return '已就绪（继承 $inheritsFrom）';
    }
    return '已就绪';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/platform_utils.dart';
import '../../core/config/app_config.dart';
import '../../core/perf/launcher_sleep.dart';
import '../../services/home_banner_service.dart';
import '../app_theme.dart';

/// 启动页左侧动态轮播图。远端不可达时回退本地图，不展示连服失败文案。
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({super.key});

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  static const _fallbackAssets = <String>[
    'assets/images/splash_background.png',
    'assets/images/default_background.png',
  ];

  List<HomeBanner> _banners = const [];
  bool _useLocalFallback = false;
  bool _loading = true;
  int _index = 0;
  PageController? _controller;
  Timer? _timer;

  int get _pageCount =>
      _useLocalFallback ? _fallbackAssets.length : _banners.length;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final list = await context
          .read<HomeBannerService>()
          .list()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _banners = const [];
          _useLocalFallback = true;
          _loading = false;
          _index = 0;
        });
      } else {
        setState(() {
          _banners = list;
          _useLocalFallback = false;
          _loading = false;
          _index = 0;
        });
      }
      _restartAutoPlay();
    } catch (_) {
      if (!mounted) return;
      // 后端超时/不可达：静默用本地图，不提示「连接服务器失败」
      setState(() {
        _banners = const [];
        _useLocalFallback = true;
        _loading = false;
        _index = 0;
      });
      _restartAutoPlay();
    }
  }

  void _restartAutoPlay() {
    _timer?.cancel();
    if (_pageCount < 2) return;
    final asleep = context.read<LauncherSleepController>().isAsleep;
    if (asleep) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _controller == null || !_controller!.hasClients) return;
      if (context.read<LauncherSleepController>().isAsleep) return;
      final next = (_index + 1) % _pageCount;
      _controller!.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openLink(String? link) async {
    final url = link?.trim() ?? '';
    if (url.isEmpty) return;
    try {
      await openUrlInBrowser(url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
    }
  }

  Widget _pageAt(int i, ThemeData theme, String base) {
    if (_useLocalFallback) {
      return Image.asset(
        _fallbackAssets[i],
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 40),
        ),
      );
    }
    final banner = _banners[i];
    final url = HomeBannerService.resolveImageUrl(base, banner.imageUrl);
    final image = Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        _fallbackAssets[i % _fallbackAssets.length],
        fit: BoxFit.cover,
      ),
    );
    final link = banner.linkUrl?.trim();
    if (link == null || link.isEmpty) return image;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openLink(link),
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.watch<AppConfig>().backendBaseUrl;
    final asleep = context.watch<LauncherSleepController>().isAsleep;
    if (asleep) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null && _pageCount >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restartAutoPlay();
      });
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            PageView.builder(
              controller: _controller,
              itemCount: _pageCount,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _pageAt(i, theme, base),
            ),
          if (_pageCount > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    Container(
                      width: i == _index ? 16 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              tooltip: '刷新',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

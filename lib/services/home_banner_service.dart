import '../core/network/api_client.dart';
import '../core/network/secure_endpoint.dart';

class HomeBanner {
  final String id;
  final String? title;
  final String imageUrl;
  final String? linkUrl;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    this.title,
    this.linkUrl,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> json) {
    return HomeBanner(
      id: '${json['banner_id'] ?? ''}',
      title: json['title']?.toString(),
      imageUrl: '${json['image_url'] ?? ''}',
      linkUrl: json['link_url']?.toString(),
    );
  }
}

/// 启动页轮播（公开）。
class HomeBannerService {
  final ApiClient api;

  HomeBannerService(this.api);

  Future<List<HomeBanner>> list() async {
    final json = await api.getPublic(SecureRoutes.homeBanners);
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => HomeBanner.fromJson(Map<String, dynamic>.from(e)))
        .where((b) => b.imageUrl.isNotEmpty)
        .toList();
  }

  /// 相对路径补全为后端绝对地址；外链与 data URL 原样返回。
  static String resolveImageUrl(String baseUrl, String imageUrl) {
    if (imageUrl.startsWith('http://') ||
        imageUrl.startsWith('https://') ||
        imageUrl.startsWith('data:')) {
      return imageUrl;
    }
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (imageUrl.startsWith('/')) return '$base$imageUrl';
    return '$base/$imageUrl';
  }
}

import '../core/network/api_client.dart';
import '../core/network/secure_endpoint.dart';

class HomeNotice {
  final String id;
  final String title;
  final String body;

  const HomeNotice({
    required this.id,
    required this.title,
    required this.body,
  });

  factory HomeNotice.fromJson(Map<String, dynamic> json) {
    return HomeNotice(
      id: '${json['notice_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
    );
  }
}

/// 启动页通知弹窗（公开）。
class HomeNoticeService {
  final ApiClient api;

  HomeNoticeService(this.api);

  Future<List<HomeNotice>> list() async {
    final json = await api.getPublic(SecureRoutes.homeNotices);
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => HomeNotice.fromJson(Map<String, dynamic>.from(e)))
        .where((n) => n.id.isNotEmpty && n.title.isNotEmpty)
        .toList();
  }
}

import '../core/network/api_client.dart';
import '../core/network/secure_endpoint.dart';
import '../models/community_post.dart';

/// 社区服务。
class CommunityService {
  final ApiClient api;

  CommunityService(this.api);

  Future<CommunityGuidelines> guidelines() async {
    final json = await api.getPublic(SecureRoutes.communityGuidelines);
    return CommunityGuidelines.fromJson(json);
  }

  Future<({List<CommunityPost> items, int page, int total})> listPosts({
    String? category,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'size': '$size',
      if (category != null && category.isNotEmpty && category != 'all')
        'category': category,
    };
    final json = await api.get(SecureRoutes.communityPosts, query);
    final raw = json['items'] as List? ?? const [];
    return (
      items: raw
          .map((e) =>
              CommunityPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      page: json['page'] as int? ?? page,
      total: (json['total'] as num?)?.toInt() ?? raw.length,
    );
  }

  Future<CommunityPost> createPost({
    required String category,
    required String title,
    required String body,
    String? linkUrl,
    required bool licenseAck,
  }) async {
    final json = await api.post(SecureRoutes.communityPosts, body: {
      'category': category,
      'title': title,
      'body': body,
      if (linkUrl != null && linkUrl.isNotEmpty) 'link_url': linkUrl,
      'license_ack': licenseAck,
    });
    return CommunityPost.fromJson(json);
  }

  Future<void> reportPost({
    required String postId,
    required String reason,
    String? detail,
  }) async {
    await api.post(SecureRoutes.communityReport(postId), body: {
      'reason': reason,
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    });
  }

  Future<void> deletePost(String postId) async {
    await api.delete(SecureRoutes.communityPost(postId));
  }
}

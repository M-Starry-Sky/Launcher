/// 社区帖子。
class CommunityPost {
  final String postId;
  final String category;
  final String title;
  final String body;
  final String? linkUrl;
  final String authorName;
  final bool pinned;
  final String? createdAt;

  const CommunityPost({
    required this.postId,
    required this.category,
    required this.title,
    required this.body,
    this.linkUrl,
    required this.authorName,
    required this.pinned,
    this.createdAt,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    return CommunityPost(
      postId: json['post_id'] as String,
      category: json['category'] as String? ?? 'tip',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      linkUrl: json['link_url'] as String?,
      authorName: json['author_name'] as String? ?? '玩家',
      pinned: json['pinned'] == true,
      createdAt: json['created_at'] as String?,
    );
  }

  String get categoryLabel => switch (category) {
        'tip' => '心得',
        'feedback' => '反馈',
        'share_link' => '合规分享',
        'notice' => '公告',
        _ => category,
      };
}

/// 社区公约。
class CommunityGuidelines {
  final String version;
  final String title;
  final List<String> rules;
  final List<String> allowedLinkHosts;

  const CommunityGuidelines({
    required this.version,
    required this.title,
    required this.rules,
    required this.allowedLinkHosts,
  });

  factory CommunityGuidelines.fromJson(Map<String, dynamic> json) {
    return CommunityGuidelines(
      version: json['version'] as String? ?? '1.0',
      title: json['title'] as String? ?? '社区公约',
      rules: (json['rules'] as List?)?.map((e) => '$e').toList() ?? const [],
      allowedLinkHosts:
          (json['allowed_link_hosts'] as List?)?.map((e) => '$e').toList() ??
              const [],
    );
  }
}

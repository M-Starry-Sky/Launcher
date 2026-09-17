/// 多套真实配置存档：切换时改写堆内存 / GC / 帧率档（可核对、可回滚）。
enum PerfProfileId {
  pvp,
  building,
  shadowLive,
  lowEnd,
}

extension PerfProfileIdX on PerfProfileId {
  String get storageKey => name;

  String get label => switch (this) {
        PerfProfileId.pvp => 'PVP 竞技',
        PerfProfileId.building => '建筑创造',
        PerfProfileId.shadowLive => '光影直播',
        PerfProfileId.lowEnd => '低配保帧',
      };

  String get hint => switch (this) {
        PerfProfileId.pvp => '竞技帧率档 + 高优先级 + 自动性能模组',
        PerfProfileId.building => '均衡帧率 + 稍高视距，方便建造',
        PerfProfileId.shadowLive => '画质优先；不强制关 VSync',
        PerfProfileId.lowEnd => '极低配帧率 + SerialGC 倾向',
      };

  static PerfProfileId? parse(String? raw) {
    for (final v in PerfProfileId.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

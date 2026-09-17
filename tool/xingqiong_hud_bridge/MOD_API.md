# 星穹优化模组 · 对外深度联动 API

模组 id：`xingqiong-perf`（0.4.x）  
入口类：`com.xingqiong.hud.api.XingqiongPerfApi`

```json
"depends": { "xingqiong-perf": ">=0.4.0" }
```

## 能力一览

| API | 说明 |
|-----|------|
| `getCurrentFps()` | 当前客户端 FPS |
| `setDamageNumbersEnabled` | 伤害跳字 |
| `setEntityHealthBarsEnabled` | 近距头顶心形血条（默认 ≤16 格） |
| `spawnDamageNumber` | 手动跳字 |
| `addPlayerMarker` / `remove` / `clear` | 纯坐标标记 |
| `setMinimapVisible` | 小地图开关 |

## 客户端体验（非 API）

- 圆形地形小地图（探索迷雾、实体点、标记、锁北、Z 临时放大）
- M 全屏大地图；B 加点；N 锁北；H 藏 HUD；C 洞穴层
- 生存信息：天数 / 时钟 / 天气 / 坐标 / 最近标记
- 头顶心：自己与 Boss 走原版；其余近距显示；队友绿心

设计终稿见：[`MINIMAP_DESIGN.md`](./MINIMAP_DESIGN.md)

## 示例

```java
XingqiongPerfApi.setDamageNumbersEnabled(true);
XingqiongPerfApi.setEntityHealthBarsEnabled(true);
XingqiongPerfApi.addPlayerMarker(null, "据点", MarkerKind.HOME, x, y, z, "minecraft:overworld");
```

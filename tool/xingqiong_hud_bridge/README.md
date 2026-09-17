# 星穹优化（Fabric 1.20.1）— 一体化模组

单一模组 `xingqiong-perf`，内含：

- 帧率 / 坐标桥接（`xingqiong_hud.json`）
- 迷你世界风格小地图（**仅玩家自标点**）
- 对外联动 API：`com.xingqiong.hud.api.XingqiongPerfApi`

不再拆成 HUD / 小地图 / API 多个 jar。

## 按键

| 键 | 作用 |
|----|------|
| M | 开关小地图 |
| N | 切换标记类型（复活点 → 村庄 → 标记） |
| B | 在脚下放置自标点 |

## 其他模组联动

```java
import com.xingqiong.hud.api.XingqiongPerfApi;
import com.xingqiong.hud.api.MarkerKind;

int fps = XingqiongPerfApi.getCurrentFps();
XingqiongPerfApi.addPlayerMarker(null, "我家", MarkerKind.RESPAWN, x, y, z, dim);
```

`fabric.mod.json`：

```json
"depends": { "xingqiong-perf": "*" }
```

## 构建

```bash
cd frontend/tool/xingqiong_hud_bridge
.\build_and_copy.ps1
```

产物：`frontend/assets/mods/xingqiong-perf.jar`（启动器自动安装）。

启动器侧会把渲染加速依赖（Sodium 等）作为**同一安装流程里的静默依赖**补齐，不作为多个「星穹产品模组」对外呈现。

package com.xingqiong.hud;

/**
 * 迷你世界风格 HUD 运行时配置（内存；后续可落盘）。
 */
public final class HudSettings {
    public static volatile boolean hudVisible = true;
    public static volatile boolean minimapEnabled = true;
    public static volatile boolean infoHudEnabled = true;
    public static volatile boolean rotateWithPlayer = true;
    /** 地图不绘制生物/玩家实体点（仅地形 + 自建标记）。 */
    public static volatile boolean showMobs = false;
    public static volatile boolean showAnimals = false;
    public static volatile boolean showPlayers = false;
    public static volatile boolean showWaypoints = true;
    public static volatile boolean caveMode = false;
    public static volatile boolean absoluteCoords = true;

    /** 小地图直径（像素）。 */
    public static volatile int minimapSize = 55;
    /** 基础可视半径（方块）；Z 键临时 ×2。 */
    public static volatile float minimapRange = 48f;
    public static volatile float maxWaypointDrawDistance = 500f;

    /** 头顶心形最大距离（方块）——刻意偏近。 */
    public static volatile float heartRenderDistance = 16f;
    public static volatile boolean heartsEnabled = true;
    public static volatile boolean hideHeartsWhenFull = false;
    public static volatile int heartDamageMemoryTicks = 100;

    public static volatile int deathPointSerial = 1;

    private HudSettings() {}
}

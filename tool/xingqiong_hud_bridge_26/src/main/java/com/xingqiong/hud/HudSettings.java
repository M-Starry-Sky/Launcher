package com.xingqiong.hud;

/**
 * 迷你世界风格 HUD 运行时配置。
 */
public final class HudSettings {
    public static volatile boolean hudVisible = true;
    public static volatile boolean minimapEnabled = true;
    public static volatile boolean infoHudEnabled = true;
    public static volatile boolean rotateWithPlayer = true;
    public static volatile boolean showWaypoints = true;
    public static volatile boolean caveMode = false;

    public static volatile int minimapSize = 55;
    public static volatile float minimapRange = 48f;
    public static volatile float maxWaypointDrawDistance = 500f;

    public static volatile float heartRenderDistance = 16f;
    public static volatile boolean heartsEnabled = true;
    public static volatile int deathPointSerial = 1;

    private HudSettings() {}
}

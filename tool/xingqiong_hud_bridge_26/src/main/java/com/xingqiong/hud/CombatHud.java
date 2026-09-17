package com.xingqiong.hud;

/** 26.x：战斗 HUD 世界渲染暂缓；保留开关供桥接/API。 */
public final class CombatHud {
    public static volatile boolean damageNumbers = true;
    public static volatile boolean healthBars = true;

    private CombatHud() {}

    public static void tick(net.minecraft.client.Minecraft client) {
        // no-op in 26.x bridge build (map/overlay first)
    }

    public static void spawn(double x, double y, double z, float amount, boolean heal) {
        // no-op
    }
}

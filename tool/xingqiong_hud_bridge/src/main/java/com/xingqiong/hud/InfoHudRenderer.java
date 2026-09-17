package com.xingqiong.hud;

import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.entity.player.PlayerEntity;

import java.util.List;

/**
 * 生存信息 HUD：天数 / 时间 / 天气 / 坐标 / 最近标记 / 状态。
 */
public final class InfoHudRenderer {
    private InfoHudRenderer() {}

    public static void render(DrawContext ctx, float tickDelta) {
        if (!HudSettings.hudVisible || !HudSettings.infoHudEnabled) return;
        MinecraftClient client = MinecraftClient.getInstance();
        if (client == null || client.player == null || client.world == null) return;
        if (client.options.hudHidden) return;
        if (client.currentScreen instanceof BigMapScreen) return;

        PlayerEntity p = client.player;
        ClientWorld w = client.world;
        var tr = client.textRenderer;

        long dayTime = w.getTimeOfDay();
        long day = dayTime / 24000L + 1;
        String clock = formatClock(dayTime);
        String period = periodIcon(dayTime);
        String weather = weatherText(w);

        int bx = p.getBlockX();
        int by = p.getBlockY();
        int bz = p.getBlockZ();

        String nearest = nearestWaypoint(w.getRegistryKey().getValue().toString(), bx, bz);

        int size = HudSettings.minimapSize;
        int sw = client.getWindow().getScaledWidth();
        int left = sw - size - 10;
        int top = 10 + size + 16;

        int y = top;
        y = line(ctx, tr, left, y, period + " 第 " + day + " 天");
        y = line(ctx, tr, left, y, clock + "  " + weather);
        y = line(ctx, tr, left, y, "X " + bx + " / Y " + by + " / Z " + bz);
        if (nearest != null) {
            y = line(ctx, tr, left, y, nearest);
        }
        String hp = String.format("❤ %.0f/%.0f  🍖 %d/20",
                p.getHealth(), p.getMaxHealth(), p.getHungerManager().getFoodLevel());
        line(ctx, tr, left, y, hp);
    }

    private static int line(DrawContext ctx, net.minecraft.client.font.TextRenderer tr, int x, int y, String s) {
        ctx.drawText(tr, s, x, y, 0xFFE8EEF5, true);
        return y + 11;
    }

    static String formatClock(long dayTime) {
        long t = Math.floorMod(dayTime, 24000L);
        // 0 → 06:00
        long minutesTotal = (t * 60L * 24L) / 24000L;
        long hours = (minutesTotal / 60L + 6L) % 24L;
        long mins = minutesTotal % 60L;
        return String.format("%02d:%02d", hours, mins);
    }

    static String periodIcon(long dayTime) {
        long t = Math.floorMod(dayTime, 24000L);
        if (t < 2000) return "黎明";
        if (t < 10000) return "白天";
        if (t < 13000) return "黄昏";
        return "夜晚";
    }

    static String weatherText(ClientWorld w) {
        if (w.isThundering()) return "雷暴";
        if (w.isRaining()) return "雨";
        return "晴朗";
    }

    private static String nearestWaypoint(String dim, int px, int pz) {
        List<PlayerMarker> list = PlayerMarkerStore.get().inDimension(dim);
        PlayerMarker best = null;
        double bestD = Double.MAX_VALUE;
        for (PlayerMarker m : list) {
            double d = Math.hypot(m.x - px, m.z - pz);
            if (d < bestD) {
                bestD = d;
                best = m;
            }
        }
        if (best == null) return null;
        String dir = compass(best.x - px, best.z - pz);
        return best.label + ": " + (int) bestD + "m " + dir;
    }

    private static String compass(double dx, double dz) {
        double ang = Math.toDegrees(Math.atan2(dx, -dz));
        if (ang < 0) ang += 360;
        if (ang < 22.5 || ang >= 337.5) return "↑";
        if (ang < 67.5) return "↗";
        if (ang < 112.5) return "→";
        if (ang < 157.5) return "↘";
        if (ang < 202.5) return "↓";
        if (ang < 247.5) return "↙";
        if (ang < 292.5) return "←";
        return "↖";
    }
}

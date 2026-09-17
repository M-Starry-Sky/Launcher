package com.xingqiong.hud;

import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.player.Player;

import java.util.List;

public final class InfoHudRenderer {
    private InfoHudRenderer() {}

    public static void render(GuiGraphicsExtractor gfx, float tickDelta) {
        if (!HudSettings.hudVisible || !HudSettings.infoHudEnabled) return;
        Minecraft client = Minecraft.getInstance();
        if (client == null || client.player == null || client.level == null) return;
        if (client.gui.hud.isHidden()) return;
        if (client.gui.screen() instanceof BigMapScreen) return;

        Player p = client.player;
        ClientLevel w = client.level;
        Font tr = client.font;

        long dayTime = w.getOverworldClockTime();
        long day = dayTime / 24000L + 1;
        String clock = formatClock(dayTime);
        String period = periodIcon(dayTime);
        String weather = weatherText(w);

        int bx = p.getBlockX();
        int by = p.getBlockY();
        int bz = p.getBlockZ();
        String nearest = nearestWaypoint(w.dimension().identifier().toString(), bx, bz);

        int size = HudSettings.minimapSize;
        int sw = gfx.guiWidth();
        int left = sw - size - 10;
        int top = 10 + size + 16;

        int y = top;
        y = line(gfx, tr, left, y, period + " 第 " + day + " 天");
        y = line(gfx, tr, left, y, clock + "  " + weather);
        y = line(gfx, tr, left, y, "X " + bx + " / Y " + by + " / Z " + bz);
        if (nearest != null) {
            y = line(gfx, tr, left, y, nearest);
        }
        String hp = String.format("❤ %.0f/%.0f  🍖 %d/20",
                p.getHealth(), p.getMaxHealth(), p.getFoodData().getFoodLevel());
        line(gfx, tr, left, y, hp);
    }

    private static int line(GuiGraphicsExtractor gfx, Font tr, int x, int y, String s) {
        gfx.text(tr, s, x, y, 0xFFE8EEF5, true);
        return y + 11;
    }

    static String formatClock(long dayTime) {
        long t = Math.floorMod(dayTime, 24000L);
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

    static String weatherText(ClientLevel w) {
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
        return best.label + ": " + (int) bestD + "m " + compass(best.x - px, best.z - pz);
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

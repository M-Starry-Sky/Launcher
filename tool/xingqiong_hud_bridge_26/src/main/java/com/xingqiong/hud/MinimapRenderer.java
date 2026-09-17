package com.xingqiong.hud;

import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import com.mojang.blaze3d.platform.InputConstants;

import java.util.List;

public final class MinimapRenderer {
    private MinimapRenderer() {}

    public static void render(GuiGraphicsExtractor gfx, float tickDelta) {
        if (!HudSettings.hudVisible || !HudSettings.minimapEnabled) return;
        if (!PlayerMarkerStore.minimapVisible) return;
        Minecraft client = Minecraft.getInstance();
        if (client == null || client.player == null || client.level == null) return;
        if (client.gui.hud.isHidden()) return;
        if (client.gui.screen() instanceof BigMapScreen) return;

        PlayerMarkerStore.get().ensureLoaded(client);
        ExploredTracker.get().ensureWorld(client);

        int size = HudSettings.minimapSize;
        boolean zoom = InputConstants.isKeyDown(InputConstants.KEY_Z);
        float range = HudSettings.minimapRange * (zoom ? 2f : 1f);

        int sw = gfx.guiWidth();
        int left = sw - size - 10;
        int top = 10;
        int cx = left + size / 2;
        int cy = top + size / 2;
        int r = size / 2 - 2;

        fillCircle(gfx, cx, cy, r + 3, 0xEE05080C);

        double px = client.player.getX();
        double pz = client.player.getZ();
        float yaw = client.player.getYRot();
        boolean rotate = HudSettings.rotateWithPlayer;
        double rad = rotate ? Math.toRadians(-yaw) : 0;

        ClientLevel level = client.level;
        boolean cave = HudSettings.caveMode;
        int caveY = client.player.getBlockY();
        float blocksPerPixel = range / (r - 4f);

        int step = size > 140 ? 2 : 1;
        for (int dy = -r + 2; dy <= r - 2; dy += step) {
            for (int dx = -r + 2; dx <= r - 2; dx += step) {
                if (dx * dx + dy * dy > (r - 3) * (r - 3)) continue;
                double wx;
                double wz;
                if (rotate) {
                    double rx = dx * blocksPerPixel;
                    double rz = dy * blocksPerPixel;
                    double cos = Math.cos(-rad);
                    double sin = Math.sin(-rad);
                    wx = px + rx * cos - rz * sin;
                    wz = pz + rx * sin + rz * cos;
                } else {
                    wx = px + dx * blocksPerPixel;
                    wz = pz + dy * blocksPerPixel;
                }
                int bx = Mth.floor(wx);
                int bz = Mth.floor(wz);
                int argb;
                if (!ExploredTracker.get().isExplored(bx >> 4, bz >> 4)) {
                    argb = 0xFF0A0C10;
                } else {
                    argb = ChunkColorCache.get().colorAt(level, bx, bz, cave, caveY);
                }
                gfx.fill(cx + dx, cy + dy, cx + dx + step, cy + dy + step, argb);
            }
        }

        if (HudSettings.showWaypoints) {
            String dim = level.dimension().identifier().toString();
            List<PlayerMarker> marks = PlayerMarkerStore.get().inDimension(dim);
            for (PlayerMarker m : marks) {
                double dist = Math.hypot(m.x - px, m.z - pz);
                if (dist > HudSettings.maxWaypointDrawDistance) continue;
                int[] scr = project(cx, cy, r, rad, rotate, px, pz, range, m.x, m.z);
                if (scr == null) continue;
                WaypointIcons.draw(gfx, m.kind, scr[0], scr[1], 8, m.colorArgb | 0xFF000000);
            }
        }

        gfx.fill(cx - 1, cy - 5, cx + 2, cy + 4, 0xFFFFFFFF);
        gfx.fill(cx - 4, cy - 1, cx + 5, cy + 2, 0xFF4DB6FF);
        if (!rotate) {
            double a = Math.toRadians(yaw);
            int ax = cx + (int) Math.round(Math.sin(a) * 6);
            int az = cy - (int) Math.round(Math.cos(a) * 6);
            gfx.fill(ax - 1, az - 1, ax + 2, az + 2, 0xFF7EB6FF);
        }

        gfx.text(client.font, "N", cx - 3, top + 2, 0xFFFF6666, true);
        drawCircle(gfx, cx, cy, r, 0xFF7EB6FF);

        int bx = client.player.getBlockX();
        int by = client.player.getBlockY();
        int bz = client.player.getBlockZ();
        String tip = "X " + bx + "  Y " + by + "  Z " + bz
                + (zoom ? "  ×2" : "")
                + (cave ? "  洞穴" : "");
        gfx.text(client.font, tip, left, top + size + 2, 0xFFE0E6EE, true);
    }

    private static int[] project(
            int cx, int cy, int r,
            double rad, boolean rotate,
            double px, double pz, float range,
            double x, double z
    ) {
        double dx = x - px;
        double dz = z - pz;
        double rx, rz;
        if (rotate) {
            rx = dx * Math.cos(rad) - dz * Math.sin(rad);
            rz = dx * Math.sin(rad) + dz * Math.cos(rad);
        } else {
            rx = dx;
            rz = dz;
        }
        float scale = (r - 6) / range;
        int mx, mz;
        double dist = Math.sqrt(dx * dx + dz * dz);
        if (dist > range) {
            double ang = Math.atan2(rz, rx);
            mx = cx + (int) Math.round(Math.cos(ang) * (r - 6));
            mz = cy + (int) Math.round(Math.sin(ang) * (r - 6));
        } else {
            mx = cx + Mth.clamp((int) Math.round(rx * scale), -r + 5, r - 5);
            mz = cy + Mth.clamp((int) Math.round(rz * scale), -r + 5, r - 5);
        }
        if ((mx - cx) * (mx - cx) + (mz - cy) * (mz - cy) > (r - 2) * (r - 2)) return null;
        return new int[]{mx, mz};
    }

    private static void fillCircle(GuiGraphicsExtractor gfx, int cx, int cy, int radius, int argb) {
        int r2 = radius * radius;
        for (int y = -radius; y <= radius; y++) {
            int xSpan = (int) Math.sqrt(r2 - y * y);
            gfx.fill(cx - xSpan, cy + y, cx + xSpan + 1, cy + y + 1, argb);
        }
    }

    private static void drawCircle(GuiGraphicsExtractor gfx, int cx, int cy, int radius, int argb) {
        int r2 = radius * radius;
        int inner = (radius - 1) * (radius - 1);
        for (int y = -radius; y <= radius; y++) {
            for (int x = -radius; x <= radius; x++) {
                int d = x * x + y * y;
                if (d <= r2 && d >= inner) {
                    gfx.fill(cx + x, cy + y, cx + x + 1, cy + y + 1, argb);
                }
            }
        }
    }
}

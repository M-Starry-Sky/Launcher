package com.xingqiong.hud;

import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.MathHelper;
import org.lwjgl.glfw.GLFW;

import java.util.List;

/**
 * 迷你世界风格圆形小地图：地形色块 + 迷雾 + 标记图标 + 玩家箭头。
 * 不显示生物/玩家实体点。
 */
public final class MinimapRenderer {
    private MinimapRenderer() {}

    public static void render(DrawContext ctx, float tickDelta) {
        if (!HudSettings.hudVisible || !HudSettings.minimapEnabled) return;
        if (!PlayerMarkerStore.minimapVisible) return;
        MinecraftClient client = MinecraftClient.getInstance();
        if (client == null || client.player == null || client.world == null) return;
        if (client.options.hudHidden) return;
        if (client.currentScreen instanceof BigMapScreen) return;

        PlayerMarkerStore.get().ensureLoaded(client);
        ExploredTracker.get().ensureWorld(client);

        int size = HudSettings.minimapSize;
        boolean zoom = isKeyDown(client, GLFW.GLFW_KEY_Z);
        float range = HudSettings.minimapRange * (zoom ? 2f : 1f);

        int sw = client.getWindow().getScaledWidth();
        int left = sw - size - 10;
        int top = 10;
        int cx = left + size / 2;
        int cy = top + size / 2;
        int r = size / 2 - 2;

        fillCircle(ctx, cx, cy, r + 3, 0xEE05080C);

        double px = client.player.getX();
        double pz = client.player.getZ();
        float yaw = client.player.getYaw();
        boolean rotate = HudSettings.rotateWithPlayer;
        double rad = rotate ? Math.toRadians(-yaw) : 0;

        ClientWorld world = client.world;
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
                int bx = MathHelper.floor(wx);
                int bz = MathHelper.floor(wz);
                int chunkX = bx >> 4;
                int chunkZ = bz >> 4;
                int argb;
                if (!ExploredTracker.get().isExplored(chunkX, chunkZ)) {
                    argb = 0xFF0A0C10;
                } else {
                    argb = ChunkColorCache.get().colorAt(world, bx, bz, cave, caveY);
                }
                ctx.fill(cx + dx, cy + dy, cx + dx + step, cy + dy + step, argb);
            }
        }

        if (HudSettings.showWaypoints) {
            String dim = world.getRegistryKey().getValue().toString();
            List<PlayerMarker> marks = PlayerMarkerStore.get().inDimension(dim);
            for (PlayerMarker m : marks) {
                double dist = Math.hypot(m.x - px, m.z - pz);
                if (dist > HudSettings.maxWaypointDrawDistance) continue;
                int[] scr = project(cx, cy, r, rad, rotate, px, pz, range, m.x, m.z);
                if (scr == null) continue;
                WaypointIcons.draw(ctx, m.kind, scr[0], scr[1], 8, m.colorArgb | 0xFF000000);
            }
        }

        ctx.fill(cx - 1, cy - 5, cx + 2, cy + 4, 0xFFFFFFFF);
        ctx.fill(cx - 4, cy - 1, cx + 5, cy + 2, 0xFF4DB6FF);
        if (!rotate) {
            double a = Math.toRadians(yaw);
            int ax = cx + (int) Math.round(Math.sin(a) * 6);
            int az = cy - (int) Math.round(Math.cos(a) * 6);
            ctx.fill(ax - 1, az - 1, ax + 2, az + 2, 0xFF7EB6FF);
        }

        ctx.drawText(client.textRenderer, "N", cx - 3, top + 2, 0xFFFF6666, true);
        drawCircle(ctx, cx, cy, r, 0xFF7EB6FF);

        int bx = client.player.getBlockX();
        int by = client.player.getBlockY();
        int bz = client.player.getBlockZ();
        String tip = "X " + bx + "  Y " + by + "  Z " + bz
                + (zoom ? "  ×2" : "")
                + (cave ? "  洞穴" : "");
        ctx.drawText(client.textRenderer, tip, left, top + size + 2, 0xFFE0E6EE, true);
    }

    private static boolean isKeyDown(MinecraftClient client, int key) {
        long win = client.getWindow().getHandle();
        return GLFW.glfwGetKey(win, key) == GLFW.GLFW_PRESS;
    }

    /** @return screen [x,y] or null if outside circle */
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
            mx = cx + MathHelper.clamp((int) Math.round(rx * scale), -r + 5, r - 5);
            mz = cy + MathHelper.clamp((int) Math.round(rz * scale), -r + 5, r - 5);
        }
        if ((mx - cx) * (mx - cx) + (mz - cy) * (mz - cy) > (r - 2) * (r - 2)) return null;
        return new int[]{mx, mz};
    }

    private static void fillCircle(DrawContext ctx, int cx, int cy, int radius, int argb) {
        int r2 = radius * radius;
        for (int y = -radius; y <= radius; y++) {
            int xSpan = (int) Math.sqrt(r2 - y * y);
            ctx.fill(cx - xSpan, cy + y, cx + xSpan + 1, cy + y + 1, argb);
        }
    }

    private static void drawCircle(DrawContext ctx, int cx, int cy, int radius, int argb) {
        int r2 = radius * radius;
        int inner = (radius - 1) * (radius - 1);
        for (int y = -radius; y <= radius; y++) {
            for (int x = -radius; x <= radius; x++) {
                int d = x * x + y * y;
                if (d <= r2 && d >= inner) {
                    ctx.fill(cx + x, cy + y, cx + x + 1, cy + y + 1, argb);
                }
            }
        }
    }
}

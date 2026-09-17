package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.input.KeyEvent;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import com.mojang.blaze3d.platform.InputConstants;

import java.util.List;
import java.util.UUID;

public class BigMapScreen extends Screen {
    private double centerX;
    private double centerZ;
    private float zoom = 1f;
    private boolean dragging;
    private int listScroll;

    public BigMapScreen() {
        super(Component.literal("大地图"));
        Minecraft c = Minecraft.getInstance();
        if (c.player != null) {
            centerX = c.player.getX();
            centerZ = c.player.getZ();
        }
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void extractRenderState(GuiGraphicsExtractor gfx, int mouseX, int mouseY, float delta) {
        Minecraft client = this.minecraft;
        if (client == null || client.player == null || client.level == null) {
            onClose();
            return;
        }
        ClientLevel level = client.level;
        PlayerMarkerStore.get().ensureLoaded(client);
        ExploredTracker.get().ensureWorld(client);

        gfx.fill(0, 0, width, height, 0xCC0A0E14);

        long dayTime = level.getOverworldClockTime();
        long day = dayTime / 24000L + 1;
        String header = InfoHudRenderer.periodIcon(dayTime)
                + " 第" + day + "天  "
                + InfoHudRenderer.formatClock(dayTime) + "  "
                + InfoHudRenderer.weatherText(level);
        gfx.text(font, header, 12, 10, 0xFFE8EEF5, true);
        gfx.text(font,
                "X " + client.player.getBlockX()
                        + " / Y " + client.player.getBlockY()
                        + " / Z " + client.player.getBlockZ(),
                12, 22, 0xFFB0BEC5, true);

        int mapLeft = 12;
        int mapTop = 40;
        int mapRight = width - 220;
        int mapBottom = height - 40;
        if (mapRight < mapLeft + 80) mapRight = width - 12;
        int mapW = mapRight - mapLeft;
        int mapH = mapBottom - mapTop;

        gfx.fill(mapLeft - 1, mapTop - 1, mapRight + 1, mapBottom + 1, 0xFF7EB6FF);
        gfx.fill(mapLeft, mapTop, mapRight, mapBottom, 0xFF05080C);

        float blocksPerPixel = 2f / zoom;
        boolean cave = HudSettings.caveMode;
        int caveY = client.player.getBlockY();
        int step = zoom < 0.5f ? 3 : (zoom < 1.2f ? 2 : 1);

        for (int py = 0; py < mapH; py += step) {
            for (int px = 0; px < mapW; px += step) {
                double wx = centerX + (px - mapW / 2.0) * blocksPerPixel;
                double wz = centerZ + (py - mapH / 2.0) * blocksPerPixel;
                int bx = Mth.floor(wx);
                int bz = Mth.floor(wz);
                int argb;
                if (!ExploredTracker.get().isExplored(bx >> 4, bz >> 4)) {
                    argb = 0xFF0A0C10;
                } else {
                    argb = ChunkColorCache.get().colorAt(level, bx, bz, cave, caveY);
                }
                gfx.fill(mapLeft + px, mapTop + py,
                        mapLeft + px + step, mapTop + py + step, argb);
            }
        }

        int ppx = mapLeft + mapW / 2 + (int) Math.round((client.player.getX() - centerX) / blocksPerPixel);
        int ppz = mapTop + mapH / 2 + (int) Math.round((client.player.getZ() - centerZ) / blocksPerPixel);
        if (ppx >= mapLeft && ppx < mapRight && ppz >= mapTop && ppz < mapBottom) {
            gfx.fill(ppx - 2, ppz - 2, ppx + 3, ppz + 3, 0xFFFFFFFF);
            gfx.fill(ppx - 1, ppz - 4, ppx + 2, ppz - 1, 0xFF4DB6FF);
        }

        String dim = level.dimension().identifier().toString();
        List<PlayerMarker> marks = PlayerMarkerStore.get().inDimension(dim);
        for (PlayerMarker m : marks) {
            int mx = mapLeft + mapW / 2 + (int) Math.round((m.x - centerX) / blocksPerPixel);
            int mz = mapTop + mapH / 2 + (int) Math.round((m.z - centerZ) / blocksPerPixel);
            if (mx < mapLeft || mx >= mapRight || mz < mapTop || mz >= mapBottom) continue;
            WaypointIcons.draw(gfx, m.kind, mx, mz, 12, m.colorArgb | 0xFF000000);
        }

        int listX = mapRight + 12;
        if (listX + 40 < width) {
            gfx.text(font, "标记", listX, 40, 0xFFFFD54F, true);
            int ly = 56 - listScroll;
            int idx = 0;
            for (PlayerMarker m : marks) {
                int rowY = ly + idx * 14;
                idx++;
                if (rowY < 50 || rowY > height - 50) continue;
                double dist = Math.hypot(m.x - client.player.getX(), m.z - client.player.getZ());
                WaypointIcons.draw(gfx, m.kind, listX + 6, rowY + 4, 10, m.colorArgb | 0xFF000000);
                gfx.text(font, m.label + "  " + (int) dist + "m", listX + 14, rowY, 0xFFE0E6EE, false);
            }
            if (marks.isEmpty()) {
                gfx.text(font, "（无标记）", listX, 56, 0xFF78909C, false);
            }
        }

        gfx.text(font,
                "拖拽平移 · 滚轮缩放 · 左键加点 · 中键回自己 · M/ESC 关闭 · 当前×"
                        + String.format("%.2f", zoom)
                        + (cave ? " · 洞穴" : " · 地表"),
                12, height - 18, 0xFF90A4AE, false);

        super.extractRenderState(gfx, mouseX, mouseY, delta);
    }

    @Override
    public boolean mouseClicked(MouseButtonEvent event, boolean doubled) {
        int mapLeft = 12;
        int mapTop = 40;
        int mapRight = Math.max(width - 220, width - 12);
        int mapBottom = height - 40;
        double mouseX = event.x();
        double mouseY = event.y();
        int button = event.button();
        if (mouseX >= mapLeft && mouseX < mapRight && mouseY >= mapTop && mouseY < mapBottom) {
            if (button == 0) {
                float blocksPerPixel = 2f / zoom;
                int mapW = mapRight - mapLeft;
                int mapH = mapBottom - mapTop;
                double wx = centerX + (mouseX - mapLeft - mapW / 2.0) * blocksPerPixel;
                double wz = centerZ + (mouseY - mapTop - mapH / 2.0) * blocksPerPixel;
                placeMarker(wx, wz);
                return true;
            }
            if (button == 2 && minecraft != null && minecraft.player != null) {
                centerX = minecraft.player.getX();
                centerZ = minecraft.player.getZ();
                return true;
            }
            if (button == 1) {
                dragging = true;
                return true;
            }
        }
        dragging = button == 0;
        return super.mouseClicked(event, doubled);
    }

    @Override
    public boolean mouseReleased(MouseButtonEvent event) {
        dragging = false;
        return super.mouseReleased(event);
    }

    @Override
    public boolean mouseDragged(MouseButtonEvent event, double dx, double dy) {
        if (dragging || event.button() == 0 || event.button() == 1) {
            float blocksPerPixel = 2f / zoom;
            centerX -= dx * blocksPerPixel;
            centerZ -= dy * blocksPerPixel;
            return true;
        }
        return super.mouseDragged(event, dx, dy);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double horizontal, double vertical) {
        zoom = Mth.clamp(zoom * (vertical > 0 ? 1.15f : 0.87f), 0.25f, 4f);
        return true;
    }

    @Override
    public boolean keyPressed(KeyEvent event) {
        int keyCode = event.key();
        if (keyCode == InputConstants.KEY_M) {
            onClose();
            return true;
        }
        if (keyCode == InputConstants.KEY_C) {
            HudSettings.caveMode = !HudSettings.caveMode;
            ChunkColorCache.get().invalidateAll();
            return true;
        }
        if (keyCode == InputConstants.KEY_N) {
            HudSettings.rotateWithPlayer = !HudSettings.rotateWithPlayer;
            return true;
        }
        return super.keyPressed(event);
    }

    private void placeMarker(double wx, double wz) {
        Minecraft c = minecraft;
        if (c == null || c.player == null || c.level == null) return;
        String dim = c.level.dimension().identifier().toString();
        long day = c.level.getOverworldClockTime() / 24000L + 1;
        String id = "wp_" + UUID.randomUUID().toString().substring(0, 6);
        PlayerMarkerStore.get().upsert(new PlayerMarker(
                id, "标记", MarkerKind.FLAG,
                Math.floor(wx), c.player.getY(), Math.floor(wz),
                dim, true, MarkerKind.FLAG.argb, (int) day
        ));
        c.player.sendSystemMessage(Component.literal("已添加标记 @" + (int) wx + "," + (int) wz));
    }
}

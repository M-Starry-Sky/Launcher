package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.text.Text;
import net.minecraft.util.math.MathHelper;
import org.lwjgl.glfw.GLFW;

import java.util.List;
import java.util.UUID;

/**
 * 全屏大地图：拖拽平移、滚轮缩放、左键加点、中键回玩家。
 */
public class BigMapScreen extends Screen {
    private double centerX;
    private double centerZ;
    private float zoom = 1f; // 1 = 每像素约 2 格
    private boolean dragging;
    private double lastMx, lastMy;
    private int listScroll;

    public BigMapScreen() {
        super(Text.literal("大地图"));
        MinecraftClient c = MinecraftClient.getInstance();
        if (c.player != null) {
            centerX = c.player.getX();
            centerZ = c.player.getZ();
        }
    }

    @Override
    protected void init() {
        super.init();
    }

    @Override
    public boolean shouldPause() {
        return false;
    }

    @Override
    public void render(DrawContext ctx, int mouseX, int mouseY, float delta) {
        MinecraftClient client = this.client;
        if (client == null || client.player == null || client.world == null) {
            close();
            return;
        }
        ClientWorld world = client.world;
        PlayerMarkerStore.get().ensureLoaded(client);
        ExploredTracker.get().ensureWorld(client);

        ctx.fill(0, 0, width, height, 0xCC0A0E14);

        long dayTime = world.getTimeOfDay();
        long day = dayTime / 24000L + 1;
        String header = InfoHudRenderer.periodIcon(dayTime)
                + " 第" + day + "天  "
                + InfoHudRenderer.formatClock(dayTime) + "  "
                + InfoHudRenderer.weatherText(world);
        ctx.drawText(textRenderer, header, 12, 10, 0xFFE8EEF5, true);
        ctx.drawText(textRenderer,
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

        ctx.fill(mapLeft - 1, mapTop - 1, mapRight + 1, mapBottom + 1, 0xFF7EB6FF);
        ctx.fill(mapLeft, mapTop, mapRight, mapBottom, 0xFF05080C);

        float blocksPerPixel = 2f / zoom;
        boolean cave = HudSettings.caveMode;
        int caveY = client.player.getBlockY();
        int step = zoom < 0.5f ? 3 : (zoom < 1.2f ? 2 : 1);

        for (int py = 0; py < mapH; py += step) {
            for (int px = 0; px < mapW; px += step) {
                double wx = centerX + (px - mapW / 2.0) * blocksPerPixel;
                double wz = centerZ + (py - mapH / 2.0) * blocksPerPixel;
                int bx = MathHelper.floor(wx);
                int bz = MathHelper.floor(wz);
                int argb;
                if (!ExploredTracker.get().isExplored(bx >> 4, bz >> 4)) {
                    argb = 0xFF0A0C10;
                } else {
                    argb = ChunkColorCache.get().colorAt(world, bx, bz, cave, caveY);
                }
                ctx.fill(mapLeft + px, mapTop + py,
                        mapLeft + px + step, mapTop + py + step, argb);
            }
        }

        // 玩家
        int ppx = mapLeft + mapW / 2 + (int) Math.round((client.player.getX() - centerX) / blocksPerPixel);
        int ppz = mapTop + mapH / 2 + (int) Math.round((client.player.getZ() - centerZ) / blocksPerPixel);
        if (ppx >= mapLeft && ppx < mapRight && ppz >= mapTop && ppz < mapBottom) {
            ctx.fill(ppx - 2, ppz - 2, ppx + 3, ppz + 3, 0xFFFFFFFF);
            ctx.fill(ppx - 1, ppz - 4, ppx + 2, ppz - 1, 0xFF4DB6FF);
        }

        String dim = world.getRegistryKey().getValue().toString();
        List<PlayerMarker> marks = PlayerMarkerStore.get().inDimension(dim);
        for (PlayerMarker m : marks) {
            int mx = mapLeft + mapW / 2 + (int) Math.round((m.x - centerX) / blocksPerPixel);
            int mz = mapTop + mapH / 2 + (int) Math.round((m.z - centerZ) / blocksPerPixel);
            if (mx < mapLeft || mx >= mapRight || mz < mapTop || mz >= mapBottom) continue;
            WaypointIcons.draw(ctx, m.kind, mx, mz, 12, m.colorArgb | 0xFF000000);
        }

        // 侧栏标记列表
        int listX = mapRight + 12;
        if (listX + 40 < width) {
            ctx.drawText(textRenderer, "标记", listX, 40, 0xFFFFD54F, true);
            int ly = 56 - listScroll;
            int idx = 0;
            for (PlayerMarker m : marks) {
                int rowY = ly + idx * 14;
                idx++;
                if (rowY < 50 || rowY > height - 50) continue;
                double dist = Math.hypot(m.x - client.player.getX(), m.z - client.player.getZ());
                WaypointIcons.draw(ctx, m.kind, listX + 6, rowY + 4, 10, m.colorArgb | 0xFF000000);
                String line = m.label + "  " + (int) dist + "m";
                ctx.drawText(textRenderer, line, listX + 14, rowY, 0xFFE0E6EE, false);
            }
            if (marks.isEmpty()) {
                ctx.drawText(textRenderer, "（无标记）", listX, 56, 0xFF78909C, false);
            }
        }

        ctx.drawText(textRenderer,
                "拖拽平移 · 滚轮缩放 · 左键加点 · 中键回自己 · M/ESC 关闭 · 当前×"
                        + String.format("%.2f", zoom)
                        + (cave ? " · 洞穴" : " · 地表"),
                12, height - 18, 0xFF90A4AE, false);

        super.render(ctx, mouseX, mouseY, delta);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        int mapLeft = 12;
        int mapTop = 40;
        int mapRight = Math.max(width - 220, width - 12);
        int mapBottom = height - 40;
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
            if (button == 2 && client != null && client.player != null) {
                centerX = client.player.getX();
                centerZ = client.player.getZ();
                return true;
            }
            if (button == 1) {
                dragging = true;
                lastMx = mouseX;
                lastMy = mouseY;
                return true;
            }
        }
        dragging = button == 0;
        lastMx = mouseX;
        lastMy = mouseY;
        return super.mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        dragging = false;
        return super.mouseReleased(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dx, double dy) {
        if (dragging || button == 0 || button == 1) {
            float blocksPerPixel = 2f / zoom;
            centerX -= dx * blocksPerPixel;
            centerZ -= dy * blocksPerPixel;
            lastMx = mouseX;
            lastMy = mouseY;
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, dx, dy);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double amount) {
        zoom = MathHelper.clamp(zoom * (amount > 0 ? 1.15f : 0.87f), 0.25f, 4f);
        return true;
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (keyCode == GLFW.GLFW_KEY_M) {
            close();
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_C) {
            HudSettings.caveMode = !HudSettings.caveMode;
            ChunkColorCache.get().invalidateAll();
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_N) {
            HudSettings.rotateWithPlayer = !HudSettings.rotateWithPlayer;
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    private void placeMarker(double wx, double wz) {
        MinecraftClient c = client;
        if (c == null || c.player == null || c.world == null) return;
        String dim = c.world.getRegistryKey().getValue().toString();
        long day = c.world.getTimeOfDay() / 24000L + 1;
        String id = "wp_" + UUID.randomUUID().toString().substring(0, 6);
        PlayerMarkerStore.get().upsert(new PlayerMarker(
                id, "标记", MarkerKind.FLAG,
                Math.floor(wx), c.player.getY(), Math.floor(wz),
                dim, true, MarkerKind.FLAG.argb, (int) day
        ));
        c.player.sendMessage(Text.literal("已添加标记 @" + (int) wx + "," + (int) wz), true);
    }
}

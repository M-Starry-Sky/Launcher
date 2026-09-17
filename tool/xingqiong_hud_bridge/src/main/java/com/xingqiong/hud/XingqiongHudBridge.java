package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.PlayerMarker;
import com.xingqiong.hud.api.XingqiongPerfApi;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.WorldRenderEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.registry.RegistryKey;
import net.minecraft.text.Text;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.World;
import net.minecraft.world.biome.Biome;
import org.lwjgl.glfw.GLFW;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.UUID;

/**
 * 星穹 · 迷你世界风格小地图 / 大地图 / 信息 HUD / 近距心形血条。
 */
public class XingqiongHudBridge implements ClientModInitializer {
    private int tick;
    private int markerKindIndex;
    private boolean deathMarked;
    private int exploreFlush;

    private KeyBinding openBigMapKey;
    private KeyBinding placeMarkerKey;
    private KeyBinding toggleNorthKey;
    private KeyBinding hideHudKey;
    private KeyBinding cycleKindKey;
    private KeyBinding toggleCaveKey;

    @Override
    public void onInitializeClient() {
        openBigMapKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.open_bigmap",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_M,
                "category.xingqiong.hud"
        ));
        placeMarkerKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.place_marker",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_B,
                "category.xingqiong.hud"
        ));
        toggleNorthKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.toggle_north",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_N,
                "category.xingqiong.hud"
        ));
        hideHudKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.hide_hud",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_H,
                "category.xingqiong.hud"
        ));
        cycleKindKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.cycle_marker_kind",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_U,
                "category.xingqiong.hud"
        ));
        toggleCaveKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.xingqiong.toggle_cave",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_C,
                "category.xingqiong.hud"
        ));

        McCompat.registerHud((context, tickDelta) -> {
            MinimapRenderer.render(context, tickDelta);
            InfoHudRenderer.render(context, tickDelta);
        });

        WorldRenderEvents.AFTER_ENTITIES.register(ctx -> {
            MinecraftClient client = MinecraftClient.getInstance();
            if (client == null || client.textRenderer == null) return;
            var matrices = ctx.matrixStack();
            if (matrices == null) return;
            float td = McCompat.worldTickDelta(ctx);
            CombatHud.renderWorld(
                    matrices,
                    client.getBufferBuilders().getEntityVertexConsumers(),
                    td,
                    ctx.camera().getPos(),
                    ctx.camera().getRotation(),
                    client.textRenderer
            );
            client.getBufferBuilders().getEntityVertexConsumers().draw();
        });

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            CombatHud.tick(client);
            DevCmdChannel.tick(client);
            ChunkColorCache.get().tick(client);
            ExploredTracker.get().ensureWorld(client);

            if ((++exploreFlush) % 200 == 0) {
                ExploredTracker.get().flush(client);
            }

            handleDeathPoint(client);

            while (openBigMapKey.wasPressed()) {
                if (client.currentScreen instanceof BigMapScreen) {
                    client.setScreen(null);
                } else if (client.currentScreen == null && client.player != null) {
                    client.setScreen(new BigMapScreen());
                }
            }
            while (toggleNorthKey.wasPressed()) {
                HudSettings.rotateWithPlayer = !HudSettings.rotateWithPlayer;
                if (client.player != null) {
                    client.player.sendMessage(
                            Text.literal(HudSettings.rotateWithPlayer ? "小地图：随转向" : "小地图：锁北"),
                            true
                    );
                }
            }
            while (hideHudKey.wasPressed()) {
                HudSettings.hudVisible = !HudSettings.hudVisible;
                PlayerMarkerStore.minimapVisible = HudSettings.hudVisible;
                if (client.player != null) {
                    client.player.sendMessage(
                            Text.literal(HudSettings.hudVisible ? "HUD：显示" : "HUD：隐藏"),
                            true
                    );
                }
            }
            while (cycleKindKey.wasPressed()) {
                MarkerKind[] kinds = MarkerKind.placeable();
                markerKindIndex = (markerKindIndex + 1) % kinds.length;
                if (client.player != null) {
                    client.player.sendMessage(
                            Text.literal("标记类型 → " + kinds[markerKindIndex].displayZh()),
                            true
                    );
                }
            }
            while (toggleCaveKey.wasPressed()) {
                if (client.currentScreen != null) continue;
                HudSettings.caveMode = !HudSettings.caveMode;
                ChunkColorCache.get().invalidateAll();
                if (client.player != null) {
                    client.player.sendMessage(
                            Text.literal(HudSettings.caveMode ? "地图：洞穴层" : "地图：地表"),
                            true
                    );
                }
            }
            while (placeMarkerKey.wasPressed()) {
                placeAtPlayer(client);
            }

            if (client.player == null || client.world == null) return;
            // ~4Hz 写桥接，保证启动器小窗帧率/坐标与模组侧一致
            if ((++tick) % 5 != 0) return;
            write(client);
        });
    }

    private void handleDeathPoint(MinecraftClient client) {
        if (client.player == null || client.world == null) return;
        if (client.player.isDead()) {
            if (!deathMarked) {
                deathMarked = true;
                PlayerMarkerStore.get().ensureLoaded(client);
                String dim = client.world.getRegistryKey().getValue().toString();
                int n = HudSettings.deathPointSerial++;
                long day = client.world.getTimeOfDay() / 24000L + 1;
                String id = "death_" + n;
                PlayerMarkerStore.get().upsert(new PlayerMarker(
                        id, "死亡点 #" + n, MarkerKind.SKULL,
                        client.player.getX(), client.player.getY(), client.player.getZ(),
                        dim, true, MarkerKind.SKULL.argb, (int) day
                ));
            }
        } else {
            deathMarked = false;
        }
    }

    private MarkerKind currentKind() {
        MarkerKind[] kinds = MarkerKind.placeable();
        return kinds[Math.floorMod(markerKindIndex, kinds.length)];
    }

    private void placeAtPlayer(MinecraftClient client) {
        if (client.player == null || client.world == null) return;
        PlayerMarkerStore.get().ensureLoaded(client);
        MarkerKind kind = currentKind();
        String dim = client.world.getRegistryKey().getValue().toString();
        long day = client.world.getTimeOfDay() / 24000L + 1;
        String id = "wp_" + UUID.randomUUID().toString().substring(0, 6);
        String label = kind.displayZh();
        PlayerMarkerStore.get().upsert(new PlayerMarker(
                id, label, kind,
                client.player.getX(), client.player.getY(), client.player.getZ(),
                dim, true, kind.argb, (int) day
        ));
        client.player.sendMessage(
                Text.literal("已标记「" + label + "」@"
                        + client.player.getBlockX() + ","
                        + client.player.getBlockZ()),
                true
        );
    }

    private static void write(MinecraftClient client) {
        PlayerEntity p = client.player;
        if (p == null) return;
        World w = client.world;
        if (w == null) return;

        PlayerMarkerStore.get().ensureLoaded(client);

        BlockPos bp = p.getBlockPos();
        String dim = w.getRegistryKey().getValue().toString();
        String biome = "";
        try {
            RegistryKey<Biome> key = w.getBiome(bp).getKey().orElse(null);
            if (key != null) biome = key.getValue().toString();
        } catch (Exception ignored) {}

        int fps = McCompat.currentFps(client);
        XingqiongPerfApi._internalNotifyFps(fps);

        long day = w.getTimeOfDay() / 24000L + 1;

        // schema/bridge 字段供启动器小窗识别；坐标/帧率字段名保持兼容
        String json = String.format(Locale.US,
                "{\"schema\":1,\"bridge\":\"xingqiong-perf\",\"fps\":%d,"
                        + "\"x\":%.3f,\"y\":%.3f,\"z\":%.3f,\"yaw\":%.2f,\"pitch\":%.2f,"
                        + "\"dimension\":%s,\"biome\":%s,\"health\":%.1f,\"max_health\":%.1f,"
                        + "\"food\":%d,\"xp_level\":%d,\"game_mode\":%d,\"block_x\":%d,\"block_y\":%d,\"block_z\":%d,"
                        + "\"minimap\":%s,\"markers\":%d,\"damage_numbers\":%s,\"health_bars\":%s,"
                        + "\"day\":%d,\"cave\":%s,\"heart_range\":%.1f}",
                fps,
                p.getX(), p.getY(), p.getZ(),
                p.getYaw(), p.getPitch(),
                quote(dim), quote(biome),
                p.getHealth(), p.getMaxHealth(),
                p.getHungerManager().getFoodLevel(),
                p.experienceLevel,
                client.interactionManager != null
                        ? client.interactionManager.getCurrentGameMode().getId()
                        : -1,
                bp.getX(), bp.getY(), bp.getZ(),
                (HudSettings.hudVisible && PlayerMarkerStore.minimapVisible) ? "true" : "false",
                PlayerMarkerStore.get().inDimension(dim).size(),
                CombatHud.damageNumbers ? "true" : "false",
                CombatHud.healthBars ? "true" : "false",
                day,
                HudSettings.caveMode ? "true" : "false",
                HudSettings.heartRenderDistance
        );

        Path runDir = client.runDirectory.toPath();
        Path out = runDir.resolve("xingqiong_hud.json");
        try {
            Files.writeString(out, json, StandardCharsets.UTF_8);
        } catch (IOException ignored) {}
    }

    private static String quote(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}

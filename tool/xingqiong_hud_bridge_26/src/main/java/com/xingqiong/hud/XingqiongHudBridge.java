package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.PlayerMarker;
import com.xingqiong.hud.api.XingqiongPerfApi;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.biome.Biome;
import com.mojang.blaze3d.platform.InputConstants;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.UUID;

/**
 * 星穹 · 26.x：小地图 / 大地图 / 信息 HUD / 启动器桥接。
 */
public class XingqiongHudBridge implements ClientModInitializer {
    private static final KeyMapping.Category CATEGORY =
            KeyMapping.Category.register(Identifier.fromNamespaceAndPath("xingqiong-perf", "hud"));

    private int tick;
    private int markerKindIndex;
    private boolean deathMarked;
    private int exploreFlush;

    private KeyMapping openBigMapKey;
    private KeyMapping placeMarkerKey;
    private KeyMapping toggleNorthKey;
    private KeyMapping hideHudKey;
    private KeyMapping cycleKindKey;
    private KeyMapping toggleCaveKey;

    @Override
    public void onInitializeClient() {
        openBigMapKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.open_bigmap",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_M,
                CATEGORY
        ));
        placeMarkerKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.place_marker",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_B,
                CATEGORY
        ));
        toggleNorthKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.toggle_north",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_N,
                CATEGORY
        ));
        hideHudKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.hide_hud",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_H,
                CATEGORY
        ));
        cycleKindKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.cycle_marker_kind",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_U,
                CATEGORY
        ));
        toggleCaveKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.xingqiong.toggle_cave",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_C,
                CATEGORY
        ));

        HudElementRegistry.addLast(
                Identifier.fromNamespaceAndPath("xingqiong-perf", "hud"),
                (graphics, deltaTracker) -> {
                    float td = deltaTracker.getGameTimeDeltaPartialTick(false);
                    MinimapRenderer.render(graphics, td);
                    InfoHudRenderer.render(graphics, td);
                    CombatHud.renderHud(graphics, td);
                }
        );

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            CombatHud.tick(client);
            DevCmdChannel.tick(client);
            ChunkColorCache.get().tick(client);
            ExploredTracker.get().ensureWorld(client);

            if ((++exploreFlush) % 200 == 0) {
                ExploredTracker.get().flush(client);
            }

            handleDeathPoint(client);

            while (openBigMapKey.consumeClick()) {
                if (client.gui.screen() instanceof BigMapScreen) {
                    client.gui.setScreen(null);
                } else if (client.gui.screen() == null && client.player != null) {
                    client.gui.setScreen(new BigMapScreen());
                }
            }
            while (toggleNorthKey.consumeClick()) {
                HudSettings.rotateWithPlayer = !HudSettings.rotateWithPlayer;
                if (client.player != null) {
                    client.player.sendSystemMessage(Component.literal(
                            HudSettings.rotateWithPlayer ? "小地图：随转向" : "小地图：锁北"));
                }
            }
            while (hideHudKey.consumeClick()) {
                HudSettings.hudVisible = !HudSettings.hudVisible;
                PlayerMarkerStore.minimapVisible = HudSettings.hudVisible;
                if (client.player != null) {
                    client.player.sendSystemMessage(Component.literal(
                            HudSettings.hudVisible ? "HUD：显示" : "HUD：隐藏"));
                }
            }
            while (cycleKindKey.consumeClick()) {
                MarkerKind[] kinds = MarkerKind.placeable();
                markerKindIndex = (markerKindIndex + 1) % kinds.length;
                if (client.player != null) {
                    client.player.sendSystemMessage(Component.literal(
                            "标记类型 → " + kinds[markerKindIndex].displayZh()));
                }
            }
            while (toggleCaveKey.consumeClick()) {
                if (client.gui.screen() != null) continue;
                HudSettings.caveMode = !HudSettings.caveMode;
                ChunkColorCache.get().invalidateAll();
                if (client.player != null) {
                    client.player.sendSystemMessage(Component.literal(
                            HudSettings.caveMode ? "地图：洞穴层" : "地图：地表"));
                }
            }
            while (placeMarkerKey.consumeClick()) {
                placeAtPlayer(client);
            }

            if (client.player == null || client.level == null) return;
            if ((++tick) % 5 != 0) return;
            write(client);
        });
    }

    private void handleDeathPoint(Minecraft client) {
        if (client.player == null || client.level == null) return;
        if (client.player.isDeadOrDying()) {
            if (!deathMarked) {
                deathMarked = true;
                PlayerMarkerStore.get().ensureLoaded(client);
                String dim = client.level.dimension().identifier().toString();
                int n = HudSettings.deathPointSerial++;
                long day = client.level.getOverworldClockTime() / 24000L + 1;
                PlayerMarkerStore.get().upsert(new PlayerMarker(
                        "death_" + n, "死亡点 #" + n, MarkerKind.SKULL,
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

    private void placeAtPlayer(Minecraft client) {
        if (client.player == null || client.level == null) return;
        PlayerMarkerStore.get().ensureLoaded(client);
        MarkerKind kind = currentKind();
        String dim = client.level.dimension().identifier().toString();
        long day = client.level.getOverworldClockTime() / 24000L + 1;
        String id = "wp_" + UUID.randomUUID().toString().substring(0, 6);
        PlayerMarkerStore.get().upsert(new PlayerMarker(
                id, kind.displayZh(), kind,
                client.player.getX(), client.player.getY(), client.player.getZ(),
                dim, true, kind.argb, (int) day
        ));
        client.player.sendSystemMessage(Component.literal(
                "已标记「" + kind.displayZh() + "」@"
                        + client.player.getBlockX() + ","
                        + client.player.getBlockZ()));
    }

    private static void write(Minecraft client) {
        Player p = client.player;
        if (p == null) return;
        Level w = client.level;
        if (w == null) return;

        PlayerMarkerStore.get().ensureLoaded(client);

        BlockPos bp = p.blockPosition();
        String dim = w.dimension().identifier().toString();
        String biome = "";
        try {
            ResourceKey<Biome> key = w.getBiomeManager().getBiome(bp).unwrapKey().orElse(null);
            if (key != null) biome = key.identifier().toString();
        } catch (Exception ignored) {}

        int fps = client.getFps();
        XingqiongPerfApi._internalNotifyFps(fps);
        long day = w.getOverworldClockTime() / 24000L + 1;

        String json = String.format(Locale.US,
                "{\"schema\":1,\"bridge\":\"xingqiong-perf\",\"fps\":%d,"
                        + "\"x\":%.3f,\"y\":%.3f,\"z\":%.3f,\"yaw\":%.2f,\"pitch\":%.2f,"
                        + "\"dimension\":%s,\"biome\":%s,\"health\":%.1f,\"max_health\":%.1f,"
                        + "\"food\":%d,\"xp_level\":%d,\"game_mode\":%d,\"block_x\":%d,\"block_y\":%d,\"block_z\":%d,"
                        + "\"minimap\":%s,\"markers\":%d,\"damage_numbers\":%s,\"health_bars\":%s,"
                        + "\"day\":%d,\"cave\":%s,\"heart_range\":%.1f}",
                fps,
                p.getX(), p.getY(), p.getZ(),
                p.getYRot(), p.getXRot(),
                quote(dim), quote(biome),
                p.getHealth(), p.getMaxHealth(),
                p.getFoodData().getFoodLevel(),
                p.experienceLevel,
                client.gameMode != null ? client.gameMode.getPlayerMode().getId() : -1,
                bp.getX(), bp.getY(), bp.getZ(),
                (HudSettings.hudVisible && PlayerMarkerStore.minimapVisible) ? "true" : "false",
                PlayerMarkerStore.get().inDimension(dim).size(),
                CombatHud.damageNumbers ? "true" : "false",
                CombatHud.healthBars ? "true" : "false",
                day,
                HudSettings.caveMode ? "true" : "false",
                HudSettings.heartRenderDistance
        );

        Path out = client.gameDirectory.toPath().resolve("xingqiong_hud.json");
        try {
            Files.writeString(out, json, StandardCharsets.UTF_8);
        } catch (IOException ignored) {}
    }

    private static String quote(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}

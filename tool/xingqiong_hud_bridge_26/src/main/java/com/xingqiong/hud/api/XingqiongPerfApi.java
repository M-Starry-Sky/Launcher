package com.xingqiong.hud.api;

import com.xingqiong.hud.CombatHud;
import com.xingqiong.hud.PlayerMarkerStore;
import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.LivingEntity;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

public final class XingqiongPerfApi {
    private static volatile int lastFps;
    private static final List<Consumer<Integer>> FPS_LISTENERS =
            Collections.synchronizedList(new ArrayList<>());
    private static final List<BiConsumer<LivingEntity, Float>> DAMAGE_LISTENERS =
            Collections.synchronizedList(new ArrayList<>());

    private XingqiongPerfApi() {}

    public static int getCurrentFps() {
        Minecraft c = Minecraft.getInstance();
        if (c != null) {
            try {
                return c.getFps();
            } catch (Exception ignored) {}
        }
        return lastFps;
    }

    public static void _internalNotifyFps(int fps) {
        lastFps = fps;
        synchronized (FPS_LISTENERS) {
            for (Consumer<Integer> l : FPS_LISTENERS) {
                try { l.accept(fps); } catch (Exception ignored) {}
            }
        }
    }

    public static void addFpsListener(Consumer<Integer> listener) {
        if (listener != null) FPS_LISTENERS.add(listener);
    }

    public static void removeFpsListener(Consumer<Integer> listener) {
        FPS_LISTENERS.remove(listener);
    }

    public static boolean isDamageNumbersEnabled() { return CombatHud.damageNumbers; }
    public static void setDamageNumbersEnabled(boolean enabled) { CombatHud.damageNumbers = enabled; }
    public static boolean isEntityHealthBarsEnabled() { return CombatHud.healthBars; }
    public static void setEntityHealthBarsEnabled(boolean enabled) { CombatHud.healthBars = enabled; }

    public static void spawnDamageNumber(double x, double y, double z, float amount) {
        CombatHud.spawn(x, y, z, amount, amount < 0);
    }

    public static void addDamageListener(BiConsumer<LivingEntity, Float> listener) {
        if (listener != null) DAMAGE_LISTENERS.add(listener);
    }

    public static void removeDamageListener(BiConsumer<LivingEntity, Float> listener) {
        DAMAGE_LISTENERS.remove(listener);
    }

    public static void _internalNotifyDamage(LivingEntity entity, float delta) {
        synchronized (DAMAGE_LISTENERS) {
            for (BiConsumer<LivingEntity, Float> l : DAMAGE_LISTENERS) {
                try { l.accept(entity, delta); } catch (Exception ignored) {}
            }
        }
    }

    public static String addPlayerMarker(
            String id, String label, MarkerKind kind,
            double x, double y, double z, String dimension
    ) {
        String useId = (id == null || id.isBlank())
                ? UUID.randomUUID().toString().substring(0, 8) : id.trim();
        String useLabel = (label == null || label.isBlank())
                ? (kind == null ? MarkerKind.CUSTOM : kind).displayZh() : label.trim();
        PlayerMarkerStore.get().upsert(new PlayerMarker(useId, useLabel, kind, x, y, z, dimension));
        return useId;
    }

    public static boolean removePlayerMarker(String id) {
        return id != null && PlayerMarkerStore.get().remove(id);
    }

    public static int clearPlayerMarkers() {
        return PlayerMarkerStore.get().clearAll();
    }

    public static List<PlayerMarker> getPlayerMarkers() {
        return PlayerMarkerStore.get().snapshot();
    }

    public static List<PlayerMarker> getPlayerMarkersInDimension(String dimension) {
        Objects.requireNonNull(dimension);
        List<PlayerMarker> out = new ArrayList<>();
        for (PlayerMarker m : PlayerMarkerStore.get().snapshot()) {
            if (dimension.equals(m.dimension)) out.add(m);
        }
        return out;
    }

    public static boolean isMinimapVisible() {
        return PlayerMarkerStore.minimapVisible;
    }

    public static void setMinimapVisible(boolean visible) {
        PlayerMarkerStore.minimapVisible = visible;
    }
}

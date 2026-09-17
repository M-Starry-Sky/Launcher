package com.xingqiong.hud.api;

import com.xingqiong.hud.CombatHud;
import com.xingqiong.hud.PlayerMarkerStore;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.LivingEntity;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

/**
 * 星穹优化模组 · 对外深度联动 API（供其他模组调用）。
 * <p>
 * 能力：FPS、战斗 HUD（伤害数字/血条）、玩家自建小地图标记、开关项。
 * 不提供自动探索图 / 结构扫描。
 */
public final class XingqiongPerfApi {
    private static volatile int lastFps;
    private static final List<Consumer<Integer>> FPS_LISTENERS =
            Collections.synchronizedList(new ArrayList<>());
    private static final List<BiConsumer<LivingEntity, Float>> DAMAGE_LISTENERS =
            Collections.synchronizedList(new ArrayList<>());

    private XingqiongPerfApi() {}

    // ---- FPS ----

    public static int getCurrentFps() {
        MinecraftClient c = MinecraftClient.getInstance();
        if (c != null) {
            try {
                return c.getCurrentFps();
            } catch (Exception ignored) {}
        }
        return lastFps;
    }

    public static void _internalNotifyFps(int fps) {
        lastFps = fps;
        synchronized (FPS_LISTENERS) {
            for (Consumer<Integer> l : FPS_LISTENERS) {
                try {
                    l.accept(fps);
                } catch (Exception ignored) {}
            }
        }
    }

    public static void addFpsListener(Consumer<Integer> listener) {
        if (listener != null) FPS_LISTENERS.add(listener);
    }

    public static void removeFpsListener(Consumer<Integer> listener) {
        FPS_LISTENERS.remove(listener);
    }

    // ---- 战斗 HUD（伤害数字 / 生物血条）----

    public static boolean isDamageNumbersEnabled() {
        return CombatHud.damageNumbers;
    }

    public static void setDamageNumbersEnabled(boolean enabled) {
        CombatHud.damageNumbers = enabled;
    }

    public static boolean isEntityHealthBarsEnabled() {
        return CombatHud.healthBars;
    }

    public static void setEntityHealthBarsEnabled(boolean enabled) {
        CombatHud.healthBars = enabled;
    }

    /** 其他模组可手动生成跳字（正数=伤害，负数=治疗显示为绿字）。 */
    public static void spawnDamageNumber(double x, double y, double z, float amount) {
        CombatHud.spawn(x, y, z, amount, amount < 0);
    }

    public static void addDamageListener(BiConsumer<LivingEntity, Float> listener) {
        if (listener != null) DAMAGE_LISTENERS.add(listener);
    }

    public static void removeDamageListener(BiConsumer<LivingEntity, Float> listener) {
        DAMAGE_LISTENERS.remove(listener);
    }

    /** 内部：血量下降时回调（delta&gt;0 为受伤）。 */
    public static void _internalNotifyDamage(LivingEntity entity, float delta) {
        synchronized (DAMAGE_LISTENERS) {
            for (BiConsumer<LivingEntity, Float> l : DAMAGE_LISTENERS) {
                try {
                    l.accept(entity, delta);
                } catch (Exception ignored) {}
            }
        }
    }

    // ---- 玩家自建标记 ----

    public static String addPlayerMarker(
            String id,
            String label,
            MarkerKind kind,
            double x,
            double y,
            double z,
            String dimension
    ) {
        String useId = (id == null || id.isBlank())
                ? UUID.randomUUID().toString().substring(0, 8)
                : id.trim();
        String useLabel = (label == null || label.isBlank())
                ? (kind == null ? MarkerKind.CUSTOM : kind).displayZh()
                : label.trim();
        PlayerMarkerStore.get().upsert(new PlayerMarker(
                useId, useLabel, kind, x, y, z, dimension
        ));
        return useId;
    }

    public static boolean removePlayerMarker(String id) {
        if (id == null) return false;
        return PlayerMarkerStore.get().remove(id);
    }

    /** 清空全部玩家自建标记，返回清除数量。 */
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

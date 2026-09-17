package com.xingqiong.hud;

import com.xingqiong.hud.api.XingqiongPerfApi;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.boss.enderdragon.EnderDragon;
import net.minecraft.world.entity.boss.wither.WitherBoss;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.PlayerTeam;
import org.joml.Vector3fc;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 伤害跳字 + 近距头顶心形血条（自己/Boss 不画）。
 * 26.x：世界渲染事件已重构，改用 GameRenderer.projectPointToScreen 投到 HUD 层绘制。
 */
public final class CombatHud {
    private static final Map<Integer, Float> LAST_HP = new ConcurrentHashMap<>();
    private static final Map<Integer, Integer> LAST_HURT_TICK = new ConcurrentHashMap<>();
    private static final List<DmgFx> FX = new ArrayList<>();
    public static volatile boolean damageNumbers = true;
    public static volatile boolean healthBars = true;

    private CombatHud() {}

    public static void tick(Minecraft client) {
        if (client.level == null || client.player == null) {
            LAST_HP.clear();
            LAST_HURT_TICK.clear();
            synchronized (FX) {
                FX.clear();
            }
            return;
        }
        if (!damageNumbers && !healthBars) return;

        float scan = Math.max(HudSettings.heartRenderDistance + 8f, 32f);
        AABB box = client.player.getBoundingBox().inflate(scan);
        for (LivingEntity e : client.level.getEntitiesOfClass(LivingEntity.class, box, LivingEntity::isAlive)) {
            int id = e.getId();
            float now = e.getHealth();
            Float prev = LAST_HP.put(id, now);
            if (damageNumbers && prev != null) {
                float delta = prev - now;
                if (Math.abs(delta) >= 0.05f) {
                    spawn(
                            e.getX(),
                            e.getBoundingBox().getCenter().y + e.getBbHeight() * 0.35,
                            e.getZ(),
                            delta,
                            delta < 0
                    );
                    XingqiongPerfApi._internalNotifyDamage(e, delta);
                    if (delta > 0) {
                        LAST_HURT_TICK.put(id, e.tickCount);
                    }
                }
            }
        }
        LAST_HP.keySet().removeIf(id -> client.level.getEntity(id) == null);
        LAST_HURT_TICK.keySet().removeIf(id -> client.level.getEntity(id) == null);

        long nowMs = System.currentTimeMillis();
        synchronized (FX) {
            FX.removeIf(f -> nowMs - f.bornMs > 900);
            for (DmgFx f : FX) {
                f.y += 0.03;
            }
        }
    }

    public static void spawn(double x, double y, double z, float amount, boolean heal) {
        synchronized (FX) {
            if (FX.size() > 64) FX.remove(0);
            FX.add(new DmgFx(x, y, z, amount, heal, System.currentTimeMillis()));
        }
    }

    /** HUD 层绘制（屏幕投影）。 */
    public static void renderHud(GuiGraphicsExtractor gfx, float tickDelta) {
        Minecraft client = Minecraft.getInstance();
        if (client.level == null || client.player == null || client.font == null) return;
        if (client.gui.hud.isHidden() || !HudSettings.hudVisible) return;
        if (client.gui.screen() instanceof BigMapScreen) return;

        Font tr = client.font;
        int sw = gfx.guiWidth();
        int sh = gfx.guiHeight();

        if (healthBars && HudSettings.heartsEnabled) {
            float maxDist = HudSettings.heartRenderDistance;
            AABB box = client.player.getBoundingBox().inflate(maxDist);
            for (LivingEntity e : client.level.getEntitiesOfClass(
                    LivingEntity.class,
                    box,
                    ent -> ent.isAlive() && shouldShowHearts(client, ent)
            )) {
                double dist = e.distanceTo(client.player);
                if (dist > maxDist) continue;
                drawHearts(gfx, client, tr, sw, sh, e, tickDelta, dist);
            }
        }

        if (damageNumbers) {
            List<DmgFx> copy;
            synchronized (FX) {
                copy = new ArrayList<>(FX);
            }
            for (DmgFx f : copy) {
                String s = (f.heal ? "+" : "-") + trim(Math.abs(f.amount));
                int color = f.heal ? 0xFF55FF55 : 0xFFFF5555;
                drawWorldLabel(gfx, client, tr, sw, sh, f.x, f.y, f.z, s, color);
            }
        }
    }

    private static boolean shouldShowHearts(Minecraft client, LivingEntity e) {
        if (e == client.player) return false;
        if (e instanceof EnderDragon || e instanceof WitherBoss) return false;
        float max = e.getMaxHealth();
        if (max <= 0.01f) return false;
        float ratio = e.getHealth() / max;
        Integer hurt = LAST_HURT_TICK.get(e.getId());
        boolean recentHurt = hurt != null && (e.tickCount - hurt) < HudSettings.heartDamageMemoryTicks;
        if (HudSettings.hideHeartsWhenFull && ratio >= 0.999f && !recentHurt) {
            return false;
        }
        return true;
    }

    private static boolean isTeammate(Minecraft client, LivingEntity e) {
        if (!(e instanceof Player other) || client.player == null) return false;
        PlayerTeam selfTeam = client.player.getTeam();
        if (selfTeam == null) return false;
        PlayerTeam otherTeam = other.getTeam();
        return otherTeam != null && selfTeam.isAlliedTo(otherTeam);
    }

    private static void drawHearts(
            GuiGraphicsExtractor gfx,
            Minecraft client,
            Font tr,
            int sw,
            int sh,
            LivingEntity e,
            float tickDelta,
            double dist
    ) {
        float hp = e.getHealth();
        float max = e.getMaxHealth();
        int totalHearts = Mth.ceil(max / 2f);
        int filledHalves = Mth.ceil(hp);
        boolean compact = totalHearts > 30;

        int color = heartColor(e);
        boolean low = hp / max <= 0.2f;
        float shake = low ? (float) (Math.sin(e.tickCount * 1.2) * 2.5) : 0f;

        double x = Mth.lerp(tickDelta, e.xo, e.getX()) + shake * 0.01;
        double y = Mth.lerp(tickDelta, e.yo, e.getY()) + e.getBbHeight() + 0.45;
        double z = Mth.lerp(tickDelta, e.zo, e.getZ());

        String name = e.hasCustomName()
                ? e.getCustomName().getString()
                : e.getName().getString();

        int[] screen = project(client, x, y + 0.28, z, sw, sh);
        if (screen != null) {
            centered(gfx, tr, screen[0], screen[1], name, 0xFFFFFFFF);
        }

        if (compact) {
            drawWorldLabel(gfx, client, tr, sw, sh, x, y, z,
                    "❤×" + trim(hp) + "/" + trim(max), color);
            return;
        }

        StringBuilder row = new StringBuilder();
        int shown = Math.min(totalHearts, 30);
        double rowY = y;
        for (int i = 0; i < shown; i++) {
            int halfIndex = i * 2;
            if (filledHalves >= halfIndex + 2) row.append('❤');
            else if (filledHalves == halfIndex + 1) row.append('♥');
            else row.append('♡');
            if ((i + 1) % 10 == 0 && i + 1 < shown) {
                drawWorldLabel(gfx, client, tr, sw, sh, x, rowY, z, row.toString(), color);
                rowY -= 0.14;
                row.setLength(0);
            }
        }
        if (!row.isEmpty()) {
            drawWorldLabel(gfx, client, tr, sw, sh, x, rowY, z, row.toString(), color);
        }
    }

    private static int heartColor(LivingEntity e) {
        Minecraft client = Minecraft.getInstance();
        if (e.hasEffect(MobEffects.WITHER)) return 0xFF222222;
        if (e.hasEffect(MobEffects.POISON)) return 0xFF66BB6A;
        if (e.isInPowderSnow) return 0xFF80DEEA;
        if (e.getAbsorptionAmount() > 0.1f) return 0xFFFFD54F;
        if (client != null && isTeammate(client, e)) return 0xFF66BB6A;
        return 0xFFE53935;
    }

    private static String trim(float v) {
        if (v >= 10) return String.valueOf(Math.round(v));
        return String.format(java.util.Locale.US, "%.1f", v);
    }

    private static void drawWorldLabel(
            GuiGraphicsExtractor gfx,
            Minecraft client,
            Font tr,
            int sw,
            int sh,
            double x,
            double y,
            double z,
            String text,
            int argb
    ) {
        int[] screen = project(client, x, y, z, sw, sh);
        if (screen == null) return;
        centered(gfx, tr, screen[0], screen[1], text, argb);
    }

    private static void centered(GuiGraphicsExtractor gfx, Font tr, int sx, int sy, String text, int argb) {
        int w = tr.width(text);
        gfx.text(tr, text, sx - w / 2, sy, argb, true);
    }

    /**
     * @return {@code [sx, sy]} 像素坐标，或 null（在相机后方 / 屏外过远）
     */
    private static int[] project(Minecraft client, double x, double y, double z, int sw, int sh) {
        var cam = client.gameRenderer.mainCamera();
        Vec3 camPos = cam.position();
        double dx = x - camPos.x;
        double dy = y - camPos.y;
        double dz = z - camPos.z;
        Vector3fc fwd = cam.forwardVector();
        if (dx * fwd.x() + dy * fwd.y() + dz * fwd.z() <= 0.05) return null;

        Vec3 ndc = client.gameRenderer.projectPointToScreen(new Vec3(x, y, z));
        if (ndc == null || Double.isNaN(ndc.x) || Double.isNaN(ndc.y)) return null;
        // transformProject 后为 NDC；z 超出 [-1,1] 视为不可见
        if (ndc.z < -1.05 || ndc.z > 1.05) return null;

        int sx = (int) Math.round((ndc.x + 1.0) * 0.5 * sw);
        int sy = (int) Math.round((1.0 - ndc.y) * 0.5 * sh);
        if (sx < -80 || sy < -40 || sx > sw + 80 || sy > sh + 40) return null;
        return new int[]{sx, sy};
    }

    private static final class DmgFx {
        double x, y, z;
        final float amount;
        final boolean heal;
        final long bornMs;

        DmgFx(double x, double y, double z, float amount, boolean heal, long bornMs) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.amount = amount;
            this.heal = heal;
            this.bornMs = bornMs;
        }
    }
}

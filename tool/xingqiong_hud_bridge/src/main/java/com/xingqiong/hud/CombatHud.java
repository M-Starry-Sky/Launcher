package com.xingqiong.hud;

import com.xingqiong.hud.api.XingqiongPerfApi;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.font.TextRenderer;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.boss.WitherEntity;
import net.minecraft.entity.boss.dragon.EnderDragonEntity;
import net.minecraft.entity.effect.StatusEffects;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.scoreboard.AbstractTeam;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import org.joml.Quaternionf;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 伤害跳字 + 近距头顶心形血条（自己/Boss 不画）。
 */
public final class CombatHud {
    private static final Map<Integer, Float> LAST_HP = new ConcurrentHashMap<>();
    private static final Map<Integer, Integer> LAST_HURT_TICK = new ConcurrentHashMap<>();
    private static final List<DmgFx> FX = new ArrayList<>();
    public static volatile boolean damageNumbers = true;
    public static volatile boolean healthBars = true;

    private CombatHud() {}

    public static void tick(MinecraftClient client) {
        if (client.world == null || client.player == null) {
            LAST_HP.clear();
            LAST_HURT_TICK.clear();
            synchronized (FX) {
                FX.clear();
            }
            return;
        }
        if (!damageNumbers && !healthBars) return;

        float scan = Math.max(HudSettings.heartRenderDistance + 8f, 32f);
        for (LivingEntity e : client.world.getEntitiesByClass(
                LivingEntity.class,
                client.player.getBoundingBox().expand(scan),
                LivingEntity::isAlive
        )) {
            int id = e.getId();
            float now = e.getHealth();
            Float prev = LAST_HP.put(id, now);
            if (damageNumbers && prev != null) {
                float delta = prev - now;
                if (Math.abs(delta) >= 0.05f) {
                    spawn(e.getX(), e.getBodyY(0.85), e.getZ(), delta, delta < 0);
                    XingqiongPerfApi._internalNotifyDamage(e, delta);
                    if (delta > 0) {
                        LAST_HURT_TICK.put(id, e.age);
                    }
                }
            }
        }
        LAST_HP.keySet().removeIf(id -> client.world.getEntityById(id) == null);
        LAST_HURT_TICK.keySet().removeIf(id -> client.world.getEntityById(id) == null);

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

    public static void renderWorld(
            MatrixStack matrices,
            VertexConsumerProvider.Immediate immediate,
            float tickDelta,
            Vec3d camPos,
            Quaternionf camRot,
            TextRenderer textRenderer
    ) {
        MinecraftClient client = MinecraftClient.getInstance();
        if (client.world == null || client.player == null) return;
        if (client.options.hudHidden || !HudSettings.hudVisible) return;

        if (healthBars && HudSettings.heartsEnabled) {
            float maxDist = HudSettings.heartRenderDistance;
            for (LivingEntity e : client.world.getEntitiesByClass(
                    LivingEntity.class,
                    client.player.getBoundingBox().expand(maxDist),
                    ent -> ent.isAlive() && shouldShowHearts(client, ent)
            )) {
                double dist = e.distanceTo(client.player);
                if (dist > maxDist) continue;
                drawHearts(matrices, textRenderer, camPos, camRot, e, tickDelta, dist);
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
                drawLabel(matrices, textRenderer, camPos, camRot, f.x, f.y, f.z, s, color, 1f);
            }
        }
    }

    private static boolean shouldShowHearts(MinecraftClient client, LivingEntity e) {
        if (e == client.player) return false;
        if (e instanceof EnderDragonEntity || e instanceof WitherEntity) return false;
        float max = e.getMaxHealth();
        if (max <= 0.01f) return false;
        float ratio = e.getHealth() / max;
        Integer hurt = LAST_HURT_TICK.get(e.getId());
        boolean recentHurt = hurt != null && (e.age - hurt) < HudSettings.heartDamageMemoryTicks;
        if (HudSettings.hideHeartsWhenFull && ratio >= 0.999f && !recentHurt) {
            return false;
        }
        return true;
    }

    private static boolean isTeammate(MinecraftClient client, LivingEntity e) {
        if (!(e instanceof PlayerEntity other) || client.player == null) return false;
        AbstractTeam selfTeam = client.player.getScoreboardTeam();
        if (selfTeam == null) return false;
        AbstractTeam otherTeam = other.getScoreboardTeam();
        return selfTeam.isEqual(otherTeam);
    }

    private static void drawHearts(
            MatrixStack matrices,
            TextRenderer tr,
            Vec3d cam,
            Quaternionf rot,
            LivingEntity e,
            float tickDelta,
            double dist
    ) {
        float hp = e.getHealth();
        float max = e.getMaxHealth();
        int totalHearts = MathHelper.ceil(max / 2f);
        int filledHalves = MathHelper.ceil(hp);
        // 最多 3 行 × 10 = 30 心；再多显示文本
        boolean compact = totalHearts > 30;

        int color = heartColor(e);
        boolean low = hp / max <= 0.2f;
        float shake = low ? (float) (Math.sin(e.age * 1.2) * 2.5) : 0f;

        double x = MathHelper.lerp(tickDelta, e.prevX, e.getX()) + shake * 0.01;
        double y = MathHelper.lerp(tickDelta, e.prevY, e.getY()) + e.getHeight() + 0.45;
        double z = MathHelper.lerp(tickDelta, e.prevZ, e.getZ());

        String name = e.hasCustomName() ? e.getCustomName().getString() : e.getName().getString();
        float scale = dist < 6 ? 1f : 0.85f;
        drawLabel(matrices, tr, cam, rot, x, y + 0.28, z, name, 0xFFFFFFFF, scale);

        if (compact) {
            drawLabel(matrices, tr, cam, rot, x, y, z,
                    "❤×" + trim(hp) + "/" + trim(max), color, scale);
            return;
        }

        StringBuilder row = new StringBuilder();
        int shown = Math.min(totalHearts, 30);
        for (int i = 0; i < shown; i++) {
            int halfIndex = i * 2;
            if (filledHalves >= halfIndex + 2) row.append('❤');
            else if (filledHalves == halfIndex + 1) row.append('♥');
            else row.append('♡');
            if ((i + 1) % 10 == 0 && i + 1 < shown) {
                drawLabel(matrices, tr, cam, rot, x, y, z, row.toString(), color, scale);
                y -= 0.14;
                row.setLength(0);
            }
        }
        if (!row.isEmpty()) {
            drawLabel(matrices, tr, cam, rot, x, y, z, row.toString(), color, scale);
        }
    }

    private static int heartColor(LivingEntity e) {
        MinecraftClient client = MinecraftClient.getInstance();
        if (e.hasStatusEffect(StatusEffects.WITHER)) return 0xFF222222;
        if (e.hasStatusEffect(StatusEffects.POISON)) return 0xFF66BB6A;
        if (e.inPowderSnow) return 0xFF80DEEA;
        if (e.getAbsorptionAmount() > 0.1f) return 0xFFFFD54F;
        if (client != null && isTeammate(client, e)) return 0xFF66BB6A;
        return 0xFFE53935;
    }

    private static String trim(float v) {
        if (v >= 10) return String.valueOf(Math.round(v));
        return String.format(java.util.Locale.US, "%.1f", v);
    }

    private static void drawLabel(
            MatrixStack matrices,
            TextRenderer tr,
            Vec3d cam,
            Quaternionf rot,
            double x,
            double y,
            double z,
            String text,
            int argb,
            float scaleMul
    ) {
        matrices.push();
        matrices.translate(x - cam.x, y - cam.y, z - cam.z);
        matrices.multiply(rot);
        float s = -0.025f * scaleMul;
        matrices.scale(s, s, 0.025f);
        float w = tr.getWidth(text);
        tr.draw(
                text,
                -w / 2f,
                0,
                argb,
                false,
                matrices.peek().getPositionMatrix(),
                MinecraftClient.getInstance().getBufferBuilders().getEntityVertexConsumers(),
                TextRenderer.TextLayerType.SEE_THROUGH,
                0,
                0xF000F0
        );
        matrices.pop();
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

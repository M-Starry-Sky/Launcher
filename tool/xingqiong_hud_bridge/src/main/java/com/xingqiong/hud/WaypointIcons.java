package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.util.Identifier;

/**
 * 标记图标：Phosphor Icons（MIT）白色 PNG，绘制时乘标记颜色。
 */
public final class WaypointIcons {
    private static final Identifier FALLBACK = id("flag");

    private WaypointIcons() {}

    public static Identifier texture(MarkerKind kind) {
        if (kind == null) return FALLBACK;
        return id(kind.icon);
    }

    /** 在中心点绘制图标，colorArgb 含 alpha。 */
    public static void draw(
            DrawContext ctx,
            MarkerKind kind,
            int centerX,
            int centerY,
            int size,
            int colorArgb
    ) {
        Identifier tex = texture(kind);
        int half = Math.max(1, size / 2);
        int x = centerX - half;
        int y = centerY - half;
        float a = ((colorArgb >> 24) & 0xFF) / 255f;
        if (a <= 0f) a = 1f;
        float r = ((colorArgb >> 16) & 0xFF) / 255f;
        float g = ((colorArgb >> 8) & 0xFF) / 255f;
        float b = (colorArgb & 0xFF) / 255f;
        RenderSystem.enableBlend();
        RenderSystem.setShaderColor(r, g, b, a);
        try {
            // PNG 为 32×32，缩放到 size
            ctx.drawTexture(tex, x, y, 0, 0, size, size, 32, 32);
        } catch (Exception e) {
            RenderSystem.setShaderColor(1f, 1f, 1f, 1f);
            ctx.fill(x, y, x + size, y + size, colorArgb | 0xFF000000);
            return;
        }
        RenderSystem.setShaderColor(1f, 1f, 1f, 1f);
    }

    private static Identifier id(String icon) {
        String key = switch (icon) {
            case "house" -> "home";
            case "hammer" -> "mine";
            case "crown" -> "boss";
            case "warning" -> "danger";
            case "scroll" -> "quest";
            case "respawn" -> "bed";
            case "village" -> "home";
            case "custom" -> "flag";
            default -> icon;
        };
        return McCompat.id("xingqiong-perf", "textures/gui/icons/" + key + ".png");
    }
}

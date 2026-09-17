package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import net.minecraft.client.gui.GuiGraphicsExtractor;

public final class WaypointIcons {
    private WaypointIcons() {}

    public static void draw(
            GuiGraphicsExtractor gfx,
            MarkerKind kind,
            int centerX,
            int centerY,
            int size,
            int colorArgb
    ) {
        int half = Math.max(1, size / 2);
        int x = centerX - half;
        int y = centerY - half;
        int color = colorArgb | 0xFF000000;
        gfx.fill(x, y, x + size, y + size, color);
        gfx.fill(x + 1, y + 1, x + size - 1, y + size - 1, 0xFF101820);
        gfx.fill(centerX - 1, centerY - 1, centerX + 1, centerY + 1, color);
    }
}

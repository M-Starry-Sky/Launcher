package com.xingqiong.hud.api;

/**
 * 玩家自建标记（纯坐标快照）。创建后坐标固定。
 */
public final class PlayerMarker {
    public final String id;
    public final String label;
    public final MarkerKind kind;
    public final double x;
    public final double y;
    public final double z;
    public final String dimension;
    public final boolean visible;
    public final int colorArgb;
    public final int createdDay;

    public PlayerMarker(
            String id,
            String label,
            MarkerKind kind,
            double x,
            double y,
            double z,
            String dimension
    ) {
        this(id, label, kind, x, y, z, dimension, true, kind == null ? MarkerKind.CUSTOM.argb : kind.argb, 0);
    }

    public PlayerMarker(
            String id,
            String label,
            MarkerKind kind,
            double x,
            double y,
            double z,
            String dimension,
            boolean visible,
            int colorArgb,
            int createdDay
    ) {
        this.id = id;
        this.label = label;
        this.kind = kind == null ? MarkerKind.CUSTOM : kind;
        this.x = x;
        this.y = y;
        this.z = z;
        this.dimension = dimension == null ? "" : dimension;
        this.visible = visible;
        this.colorArgb = colorArgb == 0 ? this.kind.argb : colorArgb;
        this.createdDay = createdDay;
    }

    public PlayerMarker withMeta(String newLabel, boolean newVisible, int newColor) {
        return new PlayerMarker(id, newLabel, kind, x, y, z, dimension, newVisible, newColor, createdDay);
    }
}

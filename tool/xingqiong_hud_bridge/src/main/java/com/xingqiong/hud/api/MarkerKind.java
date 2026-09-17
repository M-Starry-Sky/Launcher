package com.xingqiong.hud.api;

/**
 * 标记图标预设（迷你世界风格）。
 */
public enum MarkerKind {
    HOME("home", "家", 0xFFFFD54F),
    MINE("mine", "矿洞", 0xFF90CAF9),
    BOSS("boss", "Boss", 0xFFE57373),
    DANGER("danger", "危险", 0xFFFF7043),
    QUEST("quest", "任务", 0xFFBA68C8),
    BED("bed", "床", 0xFFFF8A80),
    SKULL("skull", "死亡点", 0xFFB0BEC5),
    FLAG("flag", "旗帜", 0xFF81C784),
    /** @deprecated 兼容旧存档 */
    RESPAWN("bed", "复活点", 0xFFFF6B6B),
    /** @deprecated 兼容旧存档 */
    VILLAGE("home", "村庄", 0xFFFFD166),
    CUSTOM("flag", "标记", 0xFF7CF5C8);

    public final String icon;
    public final String labelZh;
    public final int argb;

    MarkerKind(String icon, String labelZh, int argb) {
        this.icon = icon;
        this.labelZh = labelZh;
        this.argb = argb;
    }

    public String displayZh() {
        return labelZh;
    }

    public static MarkerKind fromId(String id) {
        if (id == null || id.isBlank()) return CUSTOM;
        String t = id.trim().toUpperCase();
        try {
            return MarkerKind.valueOf(t);
        } catch (Exception e) {
            for (MarkerKind k : values()) {
                if (k.icon.equalsIgnoreCase(id.trim())) return k;
            }
            return CUSTOM;
        }
    }

    /** 供快捷键循环的「新建」类型（不含兼容别名）。 */
    public static MarkerKind[] placeable() {
        return new MarkerKind[]{HOME, MINE, BOSS, DANGER, QUEST, BED, FLAG, CUSTOM};
    }
}

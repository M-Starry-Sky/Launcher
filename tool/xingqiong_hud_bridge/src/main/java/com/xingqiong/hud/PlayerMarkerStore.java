package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.PlayerMarker;
import net.minecraft.client.MinecraftClient;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * 玩家自建标记（纯坐标）。兼容旧 JSON；新字段 visible/color/createdDay。
 */
public final class PlayerMarkerStore {
    private static final PlayerMarkerStore INSTANCE = new PlayerMarkerStore();
    public static volatile boolean minimapVisible = true;

    private final CopyOnWriteArrayList<PlayerMarker> markers = new CopyOnWriteArrayList<>();
    private boolean loaded;

    public static PlayerMarkerStore get() {
        return INSTANCE;
    }

    public synchronized void ensureLoaded(MinecraftClient client) {
        if (loaded || client == null || client.runDirectory == null) return;
        loaded = true;
        Path file = client.runDirectory.toPath().resolve("xingqiong_player_markers.json");
        if (!Files.isRegularFile(file)) return;
        try {
            String raw = Files.readString(file, StandardCharsets.UTF_8).trim();
            if (raw.isEmpty()) return;
            parseArray(raw);
        } catch (Exception ignored) {}
    }

    private void parseArray(String raw) {
        markers.clear();
        int i = 0;
        while (i < raw.length()) {
            int start = raw.indexOf('{', i);
            if (start < 0) break;
            int end = raw.indexOf('}', start);
            if (end < 0) break;
            String obj = raw.substring(start + 1, end);
            String id = field(obj, "id");
            String label = field(obj, "label");
            if (label == null || label.isEmpty()) label = field(obj, "name");
            String kind = field(obj, "kind");
            if (kind == null) kind = field(obj, "icon");
            String dim = field(obj, "dimension");
            double x = num(obj, "x");
            double y = num(obj, "y");
            double z = num(obj, "z");
            boolean visible = !obj.contains("\"visible\"") || bool(obj, "visible");
            int color = (int) num(obj, "colorArgb");
            String hex = field(obj, "color");
            if (color == 0 && hex != null) color = parseHex(hex);
            int day = (int) num(obj, "createdDay");
            if (id != null && !id.isEmpty()) {
                MarkerKind mk = MarkerKind.fromId(kind);
                markers.add(new PlayerMarker(
                        id, label == null ? "" : label, mk, x, y, z,
                        dim == null ? "" : dim, visible,
                        color == 0 ? mk.argb : color, day
                ));
            }
            i = end + 1;
        }
    }

    private static int parseHex(String hex) {
        try {
            String h = hex.trim();
            if (h.startsWith("#")) h = h.substring(1);
            if (h.length() == 6) return 0xFF000000 | Integer.parseInt(h, 16);
            if (h.length() == 8) return (int) Long.parseLong(h, 16);
        } catch (Exception ignored) {}
        return 0;
    }

    private static boolean bool(String obj, String key) {
        String needle = "\"" + key + "\"";
        int k = obj.indexOf(needle);
        if (k < 0) return true;
        int colon = obj.indexOf(':', k + needle.length());
        if (colon < 0) return true;
        int i = colon + 1;
        while (i < obj.length() && Character.isWhitespace(obj.charAt(i))) i++;
        return !obj.regionMatches(true, i, "false", 0, 5);
    }

    private static String field(String obj, String key) {
        String needle = "\"" + key + "\"";
        int k = obj.indexOf(needle);
        if (k < 0) return null;
        int colon = obj.indexOf(':', k + needle.length());
        if (colon < 0) return null;
        int q1 = obj.indexOf('"', colon + 1);
        if (q1 < 0) return null;
        int q2 = obj.indexOf('"', q1 + 1);
        if (q2 < 0) return null;
        return obj.substring(q1 + 1, q2)
                .replace("\\\"", "\"")
                .replace("\\\\", "\\");
    }

    private static double num(String obj, String key) {
        String needle = "\"" + key + "\"";
        int k = obj.indexOf(needle);
        if (k < 0) return 0;
        int colon = obj.indexOf(':', k + needle.length());
        if (colon < 0) return 0;
        int end = colon + 1;
        while (end < obj.length() && Character.isWhitespace(obj.charAt(end))) end++;
        int start = end;
        while (end < obj.length()) {
            char c = obj.charAt(end);
            if ((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') {
                end++;
            } else break;
        }
        try {
            return Double.parseDouble(obj.substring(start, end));
        } catch (Exception e) {
            return 0;
        }
    }

    public void upsert(PlayerMarker m) {
        remove(m.id);
        markers.add(m);
        saveAsync();
    }

    public boolean remove(String id) {
        boolean ok = markers.removeIf(m -> m.id.equals(id));
        if (ok) saveAsync();
        return ok;
    }

    public int clearAll() {
        int n = markers.size();
        if (n == 0) return 0;
        markers.clear();
        saveAsync();
        return n;
    }

    public List<PlayerMarker> snapshot() {
        return Collections.unmodifiableList(new ArrayList<>(markers));
    }

    public List<PlayerMarker> inDimension(String dim) {
        List<PlayerMarker> out = new ArrayList<>();
        for (PlayerMarker m : markers) {
            if (dim.equals(m.dimension) && m.visible) out.add(m);
        }
        return out;
    }

    private void saveAsync() {
        MinecraftClient client = MinecraftClient.getInstance();
        if (client == null || client.runDirectory == null) return;
        Path file = client.runDirectory.toPath().resolve("xingqiong_player_markers.json");
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        boolean first = true;
        for (PlayerMarker m : markers) {
            if (!first) sb.append(',');
            first = false;
            sb.append('{')
                    .append("\"id\":").append(q(m.id)).append(',')
                    .append("\"name\":").append(q(m.label)).append(',')
                    .append("\"label\":").append(q(m.label)).append(',')
                    .append("\"kind\":").append(q(m.kind.name())).append(',')
                    .append("\"icon\":").append(q(m.kind.icon)).append(',')
                    .append("\"x\":").append(String.format(Locale.US, "%.0f", m.x)).append(',')
                    .append("\"y\":").append(String.format(Locale.US, "%.0f", m.y)).append(',')
                    .append("\"z\":").append(String.format(Locale.US, "%.0f", m.z)).append(',')
                    .append("\"dimension\":").append(q(m.dimension)).append(',')
                    .append("\"color\":").append(q(String.format("#%06X", m.colorArgb & 0xFFFFFF))).append(',')
                    .append("\"visible\":").append(m.visible).append(',')
                    .append("\"createdDay\":").append(m.createdDay)
                    .append('}');
        }
        sb.append(']');
        try {
            Files.writeString(file, sb.toString(), StandardCharsets.UTF_8);
        } catch (IOException ignored) {}
    }

    private static String q(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}

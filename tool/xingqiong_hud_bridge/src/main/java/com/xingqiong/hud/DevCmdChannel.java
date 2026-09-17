package com.xingqiong.hud;

import com.xingqiong.hud.api.MarkerKind;
import com.xingqiong.hud.api.XingqiongPerfApi;
import net.minecraft.client.MinecraftClient;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.UUID;

/**
 * 启动器开发命令通道：读 gameDir/xingqiong_dev_cmd.json，执行后写 ack。
 */
public final class DevCmdChannel {
    private static long lastSeq = -1;

    private DevCmdChannel() {}

    public static void tick(MinecraftClient client) {
        if (client == null || client.runDirectory == null) return;
        Path runDir = client.runDirectory.toPath();
        Path cmdFile = runDir.resolve("xingqiong_dev_cmd.json");
        if (!Files.isRegularFile(cmdFile)) return;

        String raw;
        try {
            raw = Files.readString(cmdFile, StandardCharsets.UTF_8).trim();
        } catch (IOException e) {
            return;
        }
        if (raw.isEmpty()) return;

        long seq = (long) num(raw, "seq");
        if (seq <= lastSeq) return;
        if (bool(raw, "consumed")) return;

        String cmd = field(raw, "cmd");
        if (cmd == null || cmd.isEmpty()) {
            writeAck(runDir, seq, false, "missing cmd");
            markConsumed(cmdFile, raw, seq);
            lastSeq = seq;
            return;
        }

        boolean ok = true;
        String message = "ok";
        try {
            switch (cmd) {
                case "ping" -> message = "pong";
                case "set_damage_numbers" -> {
                    XingqiongPerfApi.setDamageNumbersEnabled(bool(raw, "enabled"));
                    message = "damage_numbers=" + XingqiongPerfApi.isDamageNumbersEnabled();
                }
                case "set_health_bars" -> {
                    XingqiongPerfApi.setEntityHealthBarsEnabled(bool(raw, "enabled"));
                    message = "health_bars=" + XingqiongPerfApi.isEntityHealthBarsEnabled();
                }
                case "set_minimap" -> {
                    XingqiongPerfApi.setMinimapVisible(bool(raw, "enabled"));
                    message = "minimap=" + XingqiongPerfApi.isMinimapVisible();
                }
                case "spawn_damage" -> {
                    if (client.player == null) {
                        ok = false;
                        message = "no player";
                        break;
                    }
                    float amount = (float) num(raw, "amount");
                    if (amount == 0) amount = 5f;
                    double x, y, z;
                    if (bool(raw, "relative") || hasField(raw, "dx") || hasField(raw, "dy") || hasField(raw, "dz")) {
                        x = client.player.getX() + num(raw, "dx");
                        y = client.player.getY() + (hasField(raw, "dy") ? num(raw, "dy") : 2.0);
                        z = client.player.getZ() + num(raw, "dz");
                    } else if (hasField(raw, "x") || hasField(raw, "y") || hasField(raw, "z")) {
                        x = num(raw, "x");
                        y = num(raw, "y");
                        z = num(raw, "z");
                    } else {
                        x = client.player.getX();
                        y = client.player.getY() + 2.0;
                        z = client.player.getZ();
                    }
                    XingqiongPerfApi.spawnDamageNumber(x, y, z, amount);
                    message = String.format(Locale.US, "spawned %.1f @ %.1f,%.1f,%.1f", amount, x, y, z);
                }
                case "add_marker" -> {
                    if (client.player == null || client.world == null) {
                        ok = false;
                        message = "no player";
                        break;
                    }
                    PlayerMarkerStore.get().ensureLoaded(client);
                    String id = field(raw, "id");
                    String label = field(raw, "label");
                    if (label == null || label.isEmpty()) label = "dev";
                    MarkerKind kind = MarkerKind.fromId(field(raw, "kind"));
                    double x, y, z;
                    if (bool(raw, "relative") || !(hasField(raw, "x") || hasField(raw, "y") || hasField(raw, "z"))) {
                        x = client.player.getX() + num(raw, "dx");
                        y = client.player.getY() + num(raw, "dy");
                        z = client.player.getZ() + num(raw, "dz");
                    } else {
                        x = num(raw, "x");
                        y = num(raw, "y");
                        z = num(raw, "z");
                    }
                    String dim = field(raw, "dimension");
                    if (dim == null || dim.isEmpty()) {
                        dim = client.world.getRegistryKey().getValue().toString();
                    }
                    if (id == null || id.isEmpty()) {
                        id = "dev-" + UUID.randomUUID().toString().substring(0, 6);
                    }
                    String used = XingqiongPerfApi.addPlayerMarker(id, label, kind, x, y, z, dim);
                    message = "marker=" + used;
                }
                case "clear_markers" -> {
                    PlayerMarkerStore.get().ensureLoaded(client);
                    int n = XingqiongPerfApi.clearPlayerMarkers();
                    message = "cleared=" + n;
                }
                default -> {
                    ok = false;
                    message = "unknown cmd: " + cmd;
                }
            }
        } catch (Exception e) {
            ok = false;
            message = e.getClass().getSimpleName() + ": " + e.getMessage();
        }

        writeAck(runDir, seq, ok, message);
        markConsumed(cmdFile, raw, seq);
        lastSeq = seq;
    }

    private static void writeAck(Path runDir, long seq, boolean ok, String message) {
        Path ack = runDir.resolve("xingqiong_dev_ack.json");
        String json = String.format(Locale.US,
                "{\"seq\":%d,\"ok\":%s,\"message\":%s,\"at\":%d}",
                seq,
                ok ? "true" : "false",
                quote(message == null ? "" : message),
                System.currentTimeMillis()
        );
        try {
            Files.writeString(ack, json, StandardCharsets.UTF_8);
        } catch (IOException ignored) {}
    }

    private static void markConsumed(Path cmdFile, String raw, long seq) {
        try {
            Files.deleteIfExists(cmdFile);
        } catch (IOException e) {
            try {
                Files.writeString(cmdFile,
                        String.format(Locale.US,
                                "{\"seq\":%d,\"consumed\":true}", seq),
                        StandardCharsets.UTF_8);
            } catch (IOException ignored) {}
        }
    }

    private static boolean hasField(String obj, String key) {
        return obj.contains("\"" + key + "\"");
    }

    private static String field(String obj, String key) {
        String needle = "\"" + key + "\"";
        int k = obj.indexOf(needle);
        if (k < 0) return null;
        int colon = obj.indexOf(':', k + needle.length());
        if (colon < 0) return null;
        int i = colon + 1;
        while (i < obj.length() && Character.isWhitespace(obj.charAt(i))) i++;
        if (i >= obj.length()) return null;
        if (obj.charAt(i) == '"') {
            int q1 = i;
            int q2 = obj.indexOf('"', q1 + 1);
            if (q2 < 0) return null;
            return obj.substring(q1 + 1, q2)
                    .replace("\\\"", "\"")
                    .replace("\\\\", "\\");
        }
        // bare true/false/null/number — not a string field
        return null;
    }

    private static boolean bool(String obj, String key) {
        String needle = "\"" + key + "\"";
        int k = obj.indexOf(needle);
        if (k < 0) return false;
        int colon = obj.indexOf(':', k + needle.length());
        if (colon < 0) return false;
        int i = colon + 1;
        while (i < obj.length() && Character.isWhitespace(obj.charAt(i))) i++;
        return obj.regionMatches(true, i, "true", 0, 4);
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

    private static String quote(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}

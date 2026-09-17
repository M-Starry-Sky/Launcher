package com.xingqiong.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.util.math.ChunkPos;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

/**
 * 已探索区块（玩家周围 1 圈）。
 */
public final class ExploredTracker {
    private static final ExploredTracker INSTANCE = new ExploredTracker();
    private final Set<Long> explored = new HashSet<>();
    private String worldKey = "";
    private boolean dirty;

    public static ExploredTracker get() {
        return INSTANCE;
    }

    public synchronized void ensureWorld(MinecraftClient client) {
        if (client == null || client.world == null) return;
        String key = client.world.getRegistryKey().getValue().toString();
        if (client.getServer() != null) {
            // 单人：用存档名区分
            try {
                key = key + "|" + client.getServer().getSaveProperties().getLevelName();
            } catch (Exception ignored) {}
        }
        if (!key.equals(worldKey)) {
            save(client);
            explored.clear();
            worldKey = key;
            load(client);
        }
    }

    public synchronized void markAround(ChunkPos center) {
        for (int dz = -1; dz <= 1; dz++) {
            for (int dx = -1; dx <= 1; dx++) {
                long k = ChunkPos.toLong(center.x + dx, center.z + dz);
                if (explored.add(k)) dirty = true;
            }
        }
    }

    public synchronized boolean isExplored(int chunkX, int chunkZ) {
        return explored.contains(ChunkPos.toLong(chunkX, chunkZ));
    }

    public synchronized void flush(MinecraftClient client) {
        if (dirty) save(client);
    }

    private void load(MinecraftClient client) {
        Path file = file(client);
        if (file == null || !Files.isRegularFile(file)) return;
        try {
            String raw = Files.readString(file, StandardCharsets.UTF_8).trim();
            if (raw.isEmpty()) return;
            // [cx,cz,cx,cz,...]
            raw = raw.replace("[", "").replace("]", "").replace(" ", "");
            if (raw.isEmpty()) return;
            String[] parts = raw.split(",");
            for (int i = 0; i + 1 < parts.length; i += 2) {
                try {
                    int cx = Integer.parseInt(parts[i]);
                    int cz = Integer.parseInt(parts[i + 1]);
                    explored.add(ChunkPos.toLong(cx, cz));
                } catch (NumberFormatException ignored) {}
            }
        } catch (IOException ignored) {}
        dirty = false;
    }

    private void save(MinecraftClient client) {
        Path file = file(client);
        if (file == null) return;
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        boolean first = true;
        for (long k : explored) {
            if (!first) sb.append(',');
            first = false;
            sb.append(ChunkPos.getPackedX(k)).append(',').append(ChunkPos.getPackedZ(k));
        }
        sb.append(']');
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, sb.toString(), StandardCharsets.UTF_8);
            dirty = false;
        } catch (IOException ignored) {}
    }

    private Path file(MinecraftClient client) {
        if (client == null || client.runDirectory == null || worldKey.isEmpty()) return null;
        String safe = worldKey.replace(':', '_').replace('|', '_').replace('/', '_');
        return client.runDirectory.toPath().resolve("xingqiong_map_cache")
                .resolve("explored_" + safe + ".json");
    }
}

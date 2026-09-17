package com.xingqiong.hud;

import net.minecraft.client.Minecraft;
import net.minecraft.world.level.ChunkPos;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

public final class ExploredTracker {
    private static final ExploredTracker INSTANCE = new ExploredTracker();
    private final Set<Long> explored = new HashSet<>();
    private String worldKey = "";
    private boolean dirty;

    public static ExploredTracker get() { return INSTANCE; }

    public synchronized void ensureWorld(Minecraft client) {
        if (client == null || client.level == null) return;
        String key = client.level.dimension().identifier().toString();
        if (client.getSingleplayerServer() != null) {
            try {
                key = key + "|" + client.getSingleplayerServer().getWorldData().getLevelName();
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
                long k = ChunkPos.pack(center.x() + dx, center.z() + dz);
                if (explored.add(k)) dirty = true;
            }
        }
    }

    public synchronized boolean isExplored(int chunkX, int chunkZ) {
        return explored.contains(ChunkPos.pack(chunkX, chunkZ));
    }

    public synchronized void flush(Minecraft client) {
        if (dirty) save(client);
    }

    private void load(Minecraft client) {
        Path file = file(client);
        if (file == null || !Files.isRegularFile(file)) return;
        try {
            String raw = Files.readString(file, StandardCharsets.UTF_8).trim()
                    .replace("[", "").replace("]", "").replace(" ", "");
            if (raw.isEmpty()) return;
            String[] parts = raw.split(",");
            for (int i = 0; i + 1 < parts.length; i += 2) {
                try {
                    explored.add(ChunkPos.pack(Integer.parseInt(parts[i]), Integer.parseInt(parts[i + 1])));
                } catch (NumberFormatException ignored) {}
            }
        } catch (IOException ignored) {}
        dirty = false;
    }

    private void save(Minecraft client) {
        Path file = file(client);
        if (file == null) return;
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        boolean first = true;
        for (long k : explored) {
            if (!first) sb.append(',');
            first = false;
            sb.append(ChunkPos.getX(k)).append(',').append(ChunkPos.getZ(k));
        }
        sb.append(']');
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, sb.toString(), StandardCharsets.UTF_8);
            dirty = false;
        } catch (IOException ignored) {}
    }

    private Path file(Minecraft client) {
        if (client == null || client.gameDirectory == null || worldKey.isEmpty()) return null;
        String safe = worldKey.replace(':', '_').replace('|', '_').replace('/', '_');
        return client.gameDirectory.toPath().resolve("xingqiong_map_cache")
                .resolve("explored_" + safe + ".json");
    }
}

package com.xingqiong.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.ChunkPos;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 区块地形色缓存（内存 + 可选 PNG 旁路二进制）。
 */
public final class ChunkColorCache {
    private static final ChunkColorCache INSTANCE = new ChunkColorCache();
    private static final int MAX_ENTRIES = 10000;

    private final Map<Long, int[]> cache = new ConcurrentHashMap<>();
    private String boundDim = "";
    private int tickBudget;

    public static ChunkColorCache get() {
        return INSTANCE;
    }

    public void tick(MinecraftClient client) {
        if (client.world == null || client.player == null) return;
        String dim = client.world.getRegistryKey().getValue().toString();
        if (!dim.equals(boundDim)) {
            cache.clear();
            boundDim = dim;
        }
        ClientWorld world = client.world;
        ChunkPos center = client.player.getChunkPos();
        boolean cave = HudSettings.caveMode;
        int caveY = client.player.getBlockY();
        int radius = 4;
        tickBudget = 3;
        for (int dz = -radius; dz <= radius && tickBudget > 0; dz++) {
            for (int dx = -radius; dx <= radius && tickBudget > 0; dx++) {
                ChunkPos cp = new ChunkPos(center.x + dx, center.z + dz);
                if (!world.isChunkLoaded(cp.x, cp.z)) continue;
                long key = key(cp, cave, caveY);
                if (cache.containsKey(key)) continue;
                cache.put(key, MapColorSampler.sampleChunk(world, cp, cave, caveY));
                tickBudget--;
                trim();
            }
        }
        ExploredTracker.get().markAround(center);
    }

    public int colorAt(ClientWorld world, int blockX, int blockZ, boolean cave, int caveY) {
        ChunkPos cp = new ChunkPos(blockX >> 4, blockZ >> 4);
        long key = key(cp, cave, caveY);
        int[] colors = cache.get(key);
        if (colors == null) {
            if (world.isChunkLoaded(cp.x, cp.z)) {
                colors = MapColorSampler.sampleChunk(world, cp, cave, caveY);
                cache.put(key, colors);
                trim();
            } else {
                return 0xFF05080C;
            }
        }
        int lx = blockX & 15;
        int lz = blockZ & 15;
        return colors[lz * 16 + lx];
    }

    public boolean hasChunk(ChunkPos cp, boolean cave, int caveY) {
        return cache.containsKey(key(cp, cave, caveY));
    }

    public void invalidateAll() {
        cache.clear();
    }

    private void trim() {
        if (cache.size() <= MAX_ENTRIES) return;
        Iterator<Long> it = cache.keySet().iterator();
        int remove = cache.size() - MAX_ENTRIES + 64;
        while (remove-- > 0 && it.hasNext()) {
            it.next();
            it.remove();
        }
    }

    private static long key(ChunkPos cp, boolean cave, int caveY) {
        long base = ChunkPos.toLong(cp.x, cp.z);
        if (!cave) return base;
        // 洞穴按 32 格 Y 分桶，避免每格一套缓存
        int band = caveY >> 5;
        return base ^ (((long) (band + 1024)) << 42);
    }

    /** 简易持久化目录（维度子目录），成功与否不影响运行。 */
    public Path cacheDir(MinecraftClient client) {
        if (client == null || client.runDirectory == null) return null;
        Path dir = client.runDirectory.toPath().resolve("xingqiong_map_cache").resolve(
                boundDim.replace(':', '_').replace('/', '_')
        );
        try {
            Files.createDirectories(dir);
        } catch (IOException ignored) {}
        return dir;
    }
}

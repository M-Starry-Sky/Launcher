package com.xingqiong.hud;

import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.level.ChunkPos;

import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class ChunkColorCache {
    private static final ChunkColorCache INSTANCE = new ChunkColorCache();
    private static final int MAX_ENTRIES = 10000;

    private final Map<Long, int[]> cache = new ConcurrentHashMap<>();
    private String boundDim = "";
    private int tickBudget;

    public static ChunkColorCache get() { return INSTANCE; }

    public void tick(Minecraft client) {
        if (client.level == null || client.player == null) return;
        String dim = client.level.dimension().identifier().toString();
        if (!dim.equals(boundDim)) {
            cache.clear();
            boundDim = dim;
        }
        ClientLevel level = client.level;
        ChunkPos center = client.player.chunkPosition();
        boolean cave = HudSettings.caveMode;
        int caveY = client.player.getBlockY();
        int radius = 4;
        tickBudget = 3;
        for (int dz = -radius; dz <= radius && tickBudget > 0; dz++) {
            for (int dx = -radius; dx <= radius && tickBudget > 0; dx++) {
                ChunkPos cp = new ChunkPos(center.x() + dx, center.z() + dz);
                if (!level.hasChunk(cp.x(), cp.z())) continue;
                long key = key(cp, cave, caveY);
                if (cache.containsKey(key)) continue;
                cache.put(key, MapColorSampler.sampleChunk(level, cp, cave, caveY));
                tickBudget--;
                trim();
            }
        }
        ExploredTracker.get().markAround(center);
    }

    public int colorAt(ClientLevel level, int blockX, int blockZ, boolean cave, int caveY) {
        ChunkPos cp = new ChunkPos(blockX >> 4, blockZ >> 4);
        long key = key(cp, cave, caveY);
        int[] colors = cache.get(key);
        if (colors == null) {
            if (level.hasChunk(cp.x(), cp.z())) {
                colors = MapColorSampler.sampleChunk(level, cp, cave, caveY);
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

    public void invalidateAll() { cache.clear(); }

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
        long base = ChunkPos.pack(cp.x(), cp.z());
        if (!cave) return base;
        int band = caveY >> 5;
        return base ^ (((long) (band + 1024)) << 42);
    }
}

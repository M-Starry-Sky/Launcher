package com.xingqiong.hud;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.material.MapColor;
import net.minecraft.client.multiplayer.ClientLevel;

public final class MapColorSampler {
    private MapColorSampler() {}

    public static int[] sampleChunk(ClientLevel level, ChunkPos pos, boolean cave, int caveY) {
        int[] colors = new int[256];
        int baseX = pos.getMinBlockX();
        int baseZ = pos.getMinBlockZ();
        BlockPos.MutableBlockPos mutable = new BlockPos.MutableBlockPos();
        for (int lz = 0; lz < 16; lz++) {
            for (int lx = 0; lx < 16; lx++) {
                int x = baseX + lx;
                int z = baseZ + lz;
                int y;
                if (cave) {
                    y = findCaveSurface(level, mutable, x, caveY, z);
                } else {
                    y = level.getHeight(Heightmap.Types.WORLD_SURFACE, x, z) - 1;
                    if (y < level.getMinY()) y = level.getMinY();
                }
                mutable.set(x, y, z);
                BlockState state = level.getBlockState(mutable);
                if (!cave && !state.getFluidState().isEmpty()) {
                    mutable.set(x, y - 1, z);
                    BlockState under = level.getBlockState(mutable);
                    if (!under.isAir()) state = under;
                }
                MapColor mapColor = state.getMapColor(level, mutable);
                int rgb = mapColor == null || mapColor == MapColor.NONE
                        ? 0x102030
                        : mapColor.col;
                int shade = cave ? 0 : Math.floorMod(y, 4);
                int r = Math.min(255, ((rgb >> 16) & 0xFF) + shade * 2);
                int g = Math.min(255, ((rgb >> 8) & 0xFF) + shade);
                int b = Math.min(255, (rgb & 0xFF) + shade);
                colors[lz * 16 + lx] = 0xFF000000 | (r << 16) | (g << 8) | b;
            }
        }
        return colors;
    }

    private static int findCaveSurface(
            ClientLevel level, BlockPos.MutableBlockPos m, int x, int centerY, int z
    ) {
        int bottom = level.getMinY();
        int top = level.getMaxY();
        int from = Math.max(bottom, centerY - 16);
        int to = Math.min(top - 1, centerY + 16);
        for (int y = to; y >= from; y--) {
            m.set(x, y, z);
            BlockState s = level.getBlockState(m);
            if (!s.isAir() && s.getFluidState().isEmpty() && s.getMapColor(level, m) != MapColor.NONE) {
                return y;
            }
        }
        return centerY;
    }
}

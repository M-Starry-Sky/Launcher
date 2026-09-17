package com.xingqiong.hud;

import net.minecraft.block.BlockState;
import net.minecraft.block.MapColor;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.ChunkPos;
import net.minecraft.world.Heightmap;

/**
 * 从已加载区块采样地表/洞穴层 MapColor，输出 16×16 ARGB。
 */
public final class MapColorSampler {
    private MapColorSampler() {}

    public static int[] sampleChunk(ClientWorld world, ChunkPos pos, boolean cave, int caveY) {
        int[] colors = new int[256];
        int baseX = pos.getStartX();
        int baseZ = pos.getStartZ();
        BlockPos.Mutable mutable = new BlockPos.Mutable();
        for (int lz = 0; lz < 16; lz++) {
            for (int lx = 0; lx < 16; lx++) {
                int x = baseX + lx;
                int z = baseZ + lz;
                int y;
                if (cave) {
                    y = findCaveSurface(world, mutable, x, caveY, z);
                } else {
                    y = world.getTopY(Heightmap.Type.WORLD_SURFACE, x, z) - 1;
                    if (y < world.getBottomY()) y = world.getBottomY();
                }
                mutable.set(x, y, z);
                BlockState state = world.getBlockState(mutable);
                // 水面略压暗，露出水下感
                if (!cave && !state.getFluidState().isEmpty()) {
                    mutable.set(x, y - 1, z);
                    BlockState under = world.getBlockState(mutable);
                    if (!under.isAir()) state = under;
                }
                MapColor mapColor = state.getMapColor(world, mutable);
                int rgb = mapColor == null || mapColor == MapColor.CLEAR
                        ? 0x102030
                        : McCompat.mapColorRgb(mapColor);
                // MapColor.color 为 0xRRGGBB；加不透明通道，并按高度轻微明暗
                int shade = cave ? 0 : Math.floorMod(y, 4);
                int r = Math.min(255, ((rgb >> 16) & 0xFF) + shade * 2);
                int g = Math.min(255, ((rgb >> 8) & 0xFF) + shade);
                int b = Math.min(255, (rgb & 0xFF) + shade);
                colors[lz * 16 + lx] = 0xFF000000 | (r << 16) | (g << 8) | b;
            }
        }
        return colors;
    }

    private static int findCaveSurface(ClientWorld world, BlockPos.Mutable m, int x, int centerY, int z) {
        int bottom = world.getBottomY();
        int top = world.getTopY();
        int from = Math.max(bottom, centerY - 16);
        int to = Math.min(top - 1, centerY + 16);
        for (int y = to; y >= from; y--) {
            m.set(x, y, z);
            BlockState s = world.getBlockState(m);
            if (!s.isAir() && s.getFluidState().isEmpty() && s.getMapColor(world, m) != MapColor.CLEAR) {
                return y;
            }
        }
        return centerY;
    }
}

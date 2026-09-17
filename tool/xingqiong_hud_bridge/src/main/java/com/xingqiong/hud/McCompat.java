package com.xingqiong.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.util.Identifier;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * 跨 MC 版本薄封装：Identifier / HUD 回调 / tickDelta / MapColor，避免为每个版本单独出包。
 */
public final class McCompat {
    private static final MethodHandles.Lookup LOOKUP = MethodHandles.lookup();

    private static final MethodHandle ID_OF;
    private static final Constructor<?> ID_CTOR;
    private static volatile Boolean HUD_REGISTRY_OK;

    static {
        MethodHandle of = null;
        Constructor<?> ctor = null;
        try {
            of = LOOKUP.findStatic(
                    Identifier.class,
                    "of",
                    MethodType.methodType(Identifier.class, String.class, String.class)
            );
        } catch (Throwable ignored) {
        }
        if (of == null) {
            try {
                ctor = Identifier.class.getDeclaredConstructor(String.class, String.class);
                ctor.setAccessible(true);
            } catch (Throwable ignored) {
            }
        }
        ID_OF = of;
        ID_CTOR = ctor;
    }

    private McCompat() {}

    public static Identifier id(String namespace, String path) {
        try {
            if (ID_OF != null) {
                return (Identifier) ID_OF.invoke(namespace, path);
            }
            if (ID_CTOR != null) {
                return (Identifier) ID_CTOR.newInstance(namespace, path);
            }
        } catch (Throwable t) {
            throw new IllegalStateException("Identifier 创建失败: " + namespace + ":" + path, t);
        }
        throw new IllegalStateException("当前运行时无法创建 Identifier");
    }

    /** 注册 HUD；优先新版 HudElementRegistry，回落 HudRenderCallback（反射适配签名）。 */
    public static void registerHud(HudDrawer drawer) {
        if (tryRegisterHudElement(drawer)) return;
        if (tryRegisterHudCallbackProxy(drawer)) return;
        // 最后：编译期 1.20.1 float 签名
        try {
            net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback.EVENT.register(
                    (context, tickDelta) -> drawer.draw(context, tickDelta)
            );
            return;
        } catch (Throwable t) {
            throw new IllegalStateException("无法注册 HUD 渲染回调", t);
        }
    }

    private static boolean tryRegisterHudElement(HudDrawer drawer) {
        try {
            Class<?> reg = Class.forName(
                    "net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry"
            );
            Method addLast = null;
            for (Method m : reg.getMethods()) {
                if (!m.getName().equals("addLast")) continue;
                Class<?>[] p = m.getParameterTypes();
                if (p.length == 2 && Identifier.class.isAssignableFrom(p[0])) {
                    addLast = m;
                    break;
                }
            }
            if (addLast == null) return false;
            Class<?> elementClz = Class.forName(
                    "net.fabricmc.fabric.api.client.rendering.v1.hud.HudElement"
            );
            Object element = java.lang.reflect.Proxy.newProxyInstance(
                    elementClz.getClassLoader(),
                    new Class<?>[]{elementClz},
                    (proxy, method, args) -> {
                        if (args != null && args.length >= 2 && args[0] instanceof DrawContext) {
                            drawer.draw((DrawContext) args[0], tickDeltaOf(args[1]));
                        }
                        return null;
                    }
            );
            addLast.invoke(null, id("xingqiong-perf", "hud"), element);
            HUD_REGISTRY_OK = true;
            return true;
        } catch (Throwable t) {
            HUD_REGISTRY_OK = false;
            return false;
        }
    }

    private static boolean tryRegisterHudCallbackProxy(HudDrawer drawer) {
        try {
            Class<?> cb = Class.forName(
                    "net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback"
            );
            Object event = cb.getField("EVENT").get(null);
            Method register = null;
            for (Method m : event.getClass().getMethods()) {
                if (!"register".equals(m.getName()) || m.getParameterCount() != 1) continue;
                register = m;
                break;
            }
            if (register == null) return false;
            Object listener = java.lang.reflect.Proxy.newProxyInstance(
                    cb.getClassLoader(),
                    new Class<?>[]{cb},
                    (proxy, method, args) -> {
                        if (args != null && args.length >= 2 && args[0] instanceof DrawContext) {
                            drawer.draw((DrawContext) args[0], tickDeltaOf(args[1]));
                        }
                        return null;
                    }
            );
            register.invoke(event, listener);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    public static float tickDeltaOf(Object tickCounterOrFloat) {
        if (tickCounterOrFloat == null) return 0f;
        if (tickCounterOrFloat instanceof Float f) return f;
        if (tickCounterOrFloat instanceof Double d) return d.floatValue();
        // RenderTickCounter / DeltaTracker
        for (String name : new String[]{
                "getTickDelta",
                "getDynamicDeltaTicks",
                "getLastFrameDuration"
        }) {
            try {
                Method m = tickCounterOrFloat.getClass().getMethod(name, boolean.class);
                Object v = m.invoke(tickCounterOrFloat, false);
                if (v instanceof Float f) return f;
                if (v instanceof Double d) return d.floatValue();
            } catch (Throwable ignored) {
            }
            try {
                Method m = tickCounterOrFloat.getClass().getMethod(name);
                Object v = m.invoke(tickCounterOrFloat);
                if (v instanceof Float f) return f;
                if (v instanceof Double d) return d.floatValue();
            } catch (Throwable ignored) {
            }
        }
        try {
            Method m = tickCounterOrFloat.getClass()
                    .getMethod("getGameTimeDeltaPartialTick", boolean.class);
            Object v = m.invoke(tickCounterOrFloat, false);
            if (v instanceof Float f) return f;
            if (v instanceof Double d) return d.floatValue();
        } catch (Throwable ignored) {
        }
        return 0f;
    }

    /** WorldRenderContext.tickDelta() 在新版本可能变为 tickCounter。 */
    public static float worldTickDelta(Object worldRenderContext) {
        try {
            Method m = worldRenderContext.getClass().getMethod("tickDelta");
            Object v = m.invoke(worldRenderContext);
            if (v instanceof Float f) return f;
            return tickDeltaOf(v);
        } catch (Throwable ignored) {
        }
        try {
            Method m = worldRenderContext.getClass().getMethod("tickCounter");
            return tickDeltaOf(m.invoke(worldRenderContext));
        } catch (Throwable ignored) {
        }
        return 0f;
    }

    public static int mapColorRgb(Object mapColor) {
        if (mapColor == null) return 0;
        // 1.20.x: public final int color
        try {
            Field f = mapColor.getClass().getField("color");
            Object v = f.get(mapColor);
            if (v instanceof Integer i) return i;
        } catch (Throwable ignored) {
        }
        for (String name : new String[]{"getColor", "getRenderColor", "getAverageColor"}) {
            try {
                Method m = mapColor.getClass().getMethod(name);
                Object v = m.invoke(mapColor);
                if (v instanceof Integer i) return i;
            } catch (Throwable ignored) {
            }
            try {
                Method m = mapColor.getClass().getMethod(name, int.class);
                Object v = m.invoke(mapColor, 0);
                if (v instanceof Integer i) return i;
            } catch (Throwable ignored) {
            }
        }
        return 0;
    }

    /** 兼容 getCurrentFps / 字段 currentFps（新版映射可能改名）。 */
    public static int currentFps(MinecraftClient client) {
        if (client == null) return 0;
        try {
            return client.getCurrentFps();
        } catch (Throwable ignored) {
        }
        for (String name : new String[]{"getCurrentFps", "getFps"}) {
            try {
                Method m = client.getClass().getMethod(name);
                Object v = m.invoke(client);
                if (v instanceof Integer i) return i;
                if (v instanceof Float f) return Math.round(f);
            } catch (Throwable ignored) {
            }
        }
        for (String name : new String[]{"currentFps", "fps"}) {
            try {
                Field f = client.getClass().getDeclaredField(name);
                f.setAccessible(true);
                Object v = f.get(client);
                if (v instanceof Integer i) return i;
                if (v instanceof Float fl) return Math.round(fl);
            } catch (Throwable ignored) {
            }
        }
        return 0;
    }

    @FunctionalInterface
    public interface HudDrawer {
        void draw(DrawContext context, float tickDelta);
    }
}

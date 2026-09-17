package com.xingqiong.launcher.je

import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.ActivityInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.min

/**
 * 内嵌 Java 版游戏页：全屏 Surface + 虚拟按键（对齐 FCL/Pojav 触控思路）。
 *
 * 按键事件写入控件队列，供后续 GLFW/LWJGL 桥消费；当前先保证触控层完整可用。
 */
class JeGameActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var controls: VirtualControlsView
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )

        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            setPadding(24, 24, 24, 24)
            text = "正在准备内嵌 Java 运行时…"
        }
        controls = VirtualControlsView(this)

        root.addView(
            status,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        root.addView(
            controls,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(root)

        val gameDir = intent.getStringExtra(EXTRA_GAME_DIR).orEmpty()
        val versionId = intent.getStringExtra(EXTRA_VERSION_ID).orEmpty()
        val jreHome = intent.getStringExtra(EXTRA_JRE_HOME).orEmpty()
        val username = intent.getStringExtra(EXTRA_USERNAME) ?: "Player"
        val javaMajor = intent.getIntExtra(EXTRA_JAVA_MAJOR, 17)

        status.text = buildString {
            appendLine("星穹次元 · 内嵌 Java 版")
            appendLine("版本: $versionId")
            appendLine("账号: $username")
            appendLine("Java: $javaMajor")
            appendLine("本体: $gameDir")
            appendLine("JRE: $jreHome")
            appendLine()
            appendLine("虚拟键：左摇杆移动 · 右键跳跃/潜行/攻击/使用 · 底栏快捷栏")
        }

        handler.postDelayed({
            bootstrapRuntime(jreHome, gameDir, versionId, username, javaMajor)
        }, 400)
    }

    private fun bootstrapRuntime(
        jreHome: String,
        gameDir: String,
        versionId: String,
        username: String,
        javaMajor: Int,
    ) {
        val jre = File(jreHome)
        val jvm = File(jre, "lib/server/libjvm.so").takeIf { it.exists() }
            ?: File(jre, "lib/libjvm.so").takeIf { it.exists() }
            ?: File(jre, "lib/aarch64/server/libjvm.so").takeIf { it.exists() }
            ?: File(jre, "lib/arm64/server/libjvm.so")

        if (!jre.isDirectory || !jvm.exists()) {
            status.append("\n\n未找到 Android OpenJDK（libjvm.so）。\n请先在启动器内下载手机 Java 运行时。")
            return
        }

        status.append("\n\n已定位 libjvm: ${jvm.absolutePath}")
        status.append("\n正在加载本地库（OpenJDK / 渲染桥）…")

        // 按 Pojav 思路预加载关键 so；缺文件时跳过，避免直接崩
        val preload = listOf(
            File(jre, "lib/server/libjvm.so"),
            File(jre, "lib/libjava.so"),
            File(jre, "lib/libjvm.so"),
            File(filesDir.parentFile, "lib/libgl4es.so"),
            File(applicationInfo.nativeLibraryDir, "libgl4es_32.so"),
            File(applicationInfo.nativeLibraryDir, "libpojavexec.so"),
            File(applicationInfo.nativeLibraryDir, "libopenxr_loader.so"),
        )
        for (f in preload) {
            if (!f.exists()) continue
            try {
                System.load(f.absolutePath)
                status.append("\nloaded ${f.name}")
            } catch (t: Throwable) {
                status.append("\nskip ${f.name}: ${t.message}")
            }
        }

        JeRuntimeBridge.lastControls = controls
        JeRuntimeBridge.lastStatus = status
        val ok = JeRuntimeBridge.nativeStartGame(
            jreHome,
            gameDir,
            versionId,
            username,
            javaMajor,
        )
        if (!ok) {
            status.append(
                "\n\n内嵌 JVM 桥尚未链接完整 natives（libpojavexec）。\n" +
                    "虚拟按键层已就绪；请将 Pojav/FCL 运行时 so 放入 jniLibs 后重编。\n" +
                    "也可暂时使用「外部 FCL/Zalith」启动已下载版本。",
            )
        } else {
            status.visibility = View.GONE
        }
    }

    override fun onBackPressed() {
        // 虚拟暂停键优先；返回键退出游戏页
        finish()
    }

    companion object {
        const val EXTRA_GAME_DIR = "game_dir"
        const val EXTRA_VERSION_ID = "version_id"
        const val EXTRA_JRE_HOME = "jre_home"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_JAVA_MAJOR = "java_major"
    }
}

/** 供 Dart / JNI 读取最近一次触控队列。 */
object JeRuntimeBridge {
    @JvmField
    var lastControls: VirtualControlsView? = null

    @JvmField
    var lastStatus: TextView? = null

    /** 由 libxingqiong_je.so 实现；未打包时返回 false。 */
    @JvmStatic
    fun nativeStartGame(
        jreHome: String,
        gameDir: String,
        versionId: String,
        username: String,
        javaMajor: Int,
    ): Boolean {
        return try {
            System.loadLibrary("xingqiong_je")
            nativeStartGameImpl(jreHome, gameDir, versionId, username, javaMajor)
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }

    @JvmStatic
    private external fun nativeStartGameImpl(
        jreHome: String,
        gameDir: String,
        versionId: String,
        username: String,
        javaMajor: Int,
    ): Boolean

    @JvmStatic
    fun pollControlEvent(): String? = lastControls?.pollEvent()
}

/**
 * 虚拟按键：左摇杆、右侧动作键、底部快捷栏、顶部菜单。
 * 事件格式：`KEY_DOWN:W` / `KEY_UP:SPACE` / `HOTBAR:3` / `LOOK:dx,dy`
 */
@SuppressLint("ViewConstructor")
class VirtualControlsView(activity: Activity) : View(activity) {
    private val paintBg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(90, 255, 255, 255)
        style = Paint.Style.FILL
    }
    private val paintFg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(180, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private val paintText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = 28f
    }
    private val paintActive = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(160, 91, 111, 232)
        style = Paint.Style.FILL
    }

    private val events = ConcurrentLinkedQueue<String>()
    private var stickCenter = PointF()
    private var stickKnob = PointF()
    private var stickPtr = -1
    private var lookPtr = -1
    private var lastLook = PointF()
    private val activeKeys = mutableSetOf<String>()

    private lateinit var jump: RectF
    private lateinit var sneak: RectF
    private lateinit var attack: RectF
    private lateinit var use: RectF
    private lateinit var inv: RectF
    private lateinit var pause: RectF
    private lateinit var chat: RectF
    private val hotbar = Array(9) { RectF() }

    fun pollEvent(): String? = events.poll()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val s = min(w, h) * 0.22f
        stickCenter.set(s * 1.2f, h - s * 1.3f)
        stickKnob.set(stickCenter.x, stickCenter.y)

        val r = min(w, h) * 0.08f
        val right = w - r * 1.4f
        val bottom = h - r * 1.4f
        jump = oval(right, bottom - r * 2.6f, r)
        sneak = oval(right - r * 2.4f, bottom, r * 0.85f)
        attack = oval(right, bottom, r)
        use = oval(right - r * 2.4f, bottom - r * 2.6f, r * 0.85f)

        inv = RectF(w * 0.42f, h * 0.04f, w * 0.52f, h * 0.12f)
        pause = RectF(w * 0.54f, h * 0.04f, w * 0.64f, h * 0.12f)
        chat = RectF(w * 0.30f, h * 0.04f, w * 0.40f, h * 0.12f)

        val barW = w * 0.62f
        val slot = barW / 9f
        val barL = (w - barW) / 2f
        val barT = h - slot * 1.15f
        for (i in 0 until 9) {
            hotbar[i] = RectF(barL + i * slot, barT, barL + (i + 1) * slot, barT + slot * 0.9f)
        }
    }

    private fun oval(cx: Float, cy: Float, r: Float) =
        RectF(cx - r, cy - r, cx + r, cy + r)

    override fun onDraw(canvas: Canvas) {
        // 左摇杆
        canvas.drawCircle(stickCenter.x, stickCenter.y, min(width, height) * 0.18f, paintBg)
        canvas.drawCircle(stickCenter.x, stickCenter.y, min(width, height) * 0.18f, paintFg)
        canvas.drawCircle(stickKnob.x, stickKnob.y, min(width, height) * 0.07f, paintActive)

        fun btn(rect: RectF, label: String, key: String) {
            val p = if (activeKeys.contains(key)) paintActive else paintBg
            canvas.drawRoundRect(rect, 18f, 18f, p)
            canvas.drawRoundRect(rect, 18f, 18f, paintFg)
            canvas.drawText(label, rect.centerX(), rect.centerY() + 10f, paintText)
        }
        btn(jump, "跳", "SPACE")
        btn(sneak, "潜", "SHIFT")
        btn(attack, "攻", "ATTACK")
        btn(use, "用", "USE")
        btn(inv, "包", "E")
        btn(pause, "停", "ESC")
        btn(chat, "聊", "T")

        for (i in 0 until 9) {
            val rect = hotbar[i]
            canvas.drawRoundRect(rect, 10f, 10f, paintBg)
            canvas.drawRoundRect(rect, 10f, 10f, paintFg)
            canvas.drawText("${i + 1}", rect.centerX(), rect.centerY() + 10f, paintText)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = event.actionIndex
                val id = event.getPointerId(idx)
                val x = event.getX(idx)
                val y = event.getY(idx)
                if (hypot(x - stickCenter.x, y - stickCenter.y) <= min(width, height) * 0.22f) {
                    stickPtr = id
                    moveStick(x, y)
                } else if (hit(jump, x, y)) press("SPACE")
                else if (hit(sneak, x, y)) press("SHIFT")
                else if (hit(attack, x, y)) press("ATTACK")
                else if (hit(use, x, y)) press("USE")
                else if (hit(inv, x, y)) tap("E")
                else if (hit(pause, x, y)) tap("ESC")
                else if (hit(chat, x, y)) tap("T")
                else {
                    var hb = false
                    for (i in 0 until 9) {
                        if (hit(hotbar[i], x, y)) {
                            events.offer("HOTBAR:${i + 1}")
                            hb = true
                            break
                        }
                    }
                    if (!hb && x > width * 0.45f) {
                        lookPtr = id
                        lastLook.set(x, y)
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    val id = event.getPointerId(i)
                    val x = event.getX(i)
                    val y = event.getY(i)
                    if (id == stickPtr) moveStick(x, y)
                    if (id == lookPtr) {
                        val dx = x - lastLook.x
                        val dy = y - lastLook.y
                        lastLook.set(x, y)
                        events.offer("LOOK:$dx,$dy")
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                val idx = event.actionIndex
                val id = event.getPointerId(idx)
                if (id == stickPtr) {
                    stickPtr = -1
                    stickKnob.set(stickCenter.x, stickCenter.y)
                    releaseMove()
                }
                if (id == lookPtr) lookPtr = -1
                release("SPACE")
                release("SHIFT")
                release("ATTACK")
                release("USE")
            }
        }
        invalidate()
        return true
    }

    private fun hit(r: RectF, x: Float, y: Float) = r.contains(x, y)

    private fun press(key: String) {
        if (activeKeys.add(key)) events.offer("KEY_DOWN:$key")
    }

    private fun release(key: String) {
        if (activeKeys.remove(key)) events.offer("KEY_UP:$key")
    }

    private fun tap(key: String) {
        events.offer("KEY_DOWN:$key")
        events.offer("KEY_UP:$key")
    }

    private fun moveStick(x: Float, y: Float) {
        val maxR = min(width, height) * 0.14f
        var dx = x - stickCenter.x
        var dy = y - stickCenter.y
        val len = hypot(dx, dy)
        if (len > maxR && len > 0) {
            dx = dx / len * maxR
            dy = dy / len * maxR
        }
        stickKnob.set(stickCenter.x + dx, stickCenter.y + dy)
        val nx = dx / maxR
        val ny = dy / maxR
        val dead = 0.25f
        val want = mutableSetOf<String>()
        if (ny < -dead) want.add("W")
        if (ny > dead) want.add("S")
        if (nx < -dead) want.add("A")
        if (nx > dead) want.add("D")
        for (k in listOf("W", "A", "S", "D")) {
            if (want.contains(k)) press(k) else release(k)
        }
        // 角度可供模拟冲刺等扩展
        if (want.isNotEmpty()) {
            val ang = atan2(dy, dx)
            events.offer("STICK:$nx,$ny,$ang")
        }
    }

    private fun releaseMove() {
        for (k in listOf("W", "A", "S", "D")) release(k)
        events.offer("STICK:0,0,0")
    }
}

package com.xingqiong.launcher

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.xingqiong.launcher.je.JeGameActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "xingqiong/android_launch"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPackageInstalled" -> {
                        val pkg = call.argument<String>("package")
                        result.success(!pkg.isNullOrBlank() && isPackageInstalled(pkg))
                    }
                    "launchPackage" -> {
                        val pkg = call.argument<String>("package")
                        result.success(!pkg.isNullOrBlank() && launchPackage(pkg))
                    }
                    "searchMarket" -> {
                        val query = call.argument<String>("query") ?: "Minecraft launcher"
                        result.success(searchMarket(query))
                    }
                    "startEmbeddedJe" -> {
                        val gameDir = call.argument<String>("gameDir") ?: ""
                        val versionId = call.argument<String>("versionId") ?: ""
                        val jreHome = call.argument<String>("jreHome") ?: ""
                        val username = call.argument<String>("username") ?: "Player"
                        val javaMajor = call.argument<Int>("javaMajor") ?: 17
                        result.success(
                            startEmbeddedJe(gameDir, versionId, jreHome, username, javaMajor),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startEmbeddedJe(
        gameDir: String,
        versionId: String,
        jreHome: String,
        username: String,
        javaMajor: Int,
    ): Boolean {
        return try {
            val intent = Intent(this, JeGameActivity::class.java).apply {
                putExtra(JeGameActivity.EXTRA_GAME_DIR, gameDir)
                putExtra(JeGameActivity.EXTRA_VERSION_ID, versionId)
                putExtra(JeGameActivity.EXTRA_JRE_HOME, jreHome)
                putExtra(JeGameActivity.EXTRA_USERNAME, username)
                putExtra(JeGameActivity.EXTRA_JAVA_MAJOR, javaMajor)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun launchPackage(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun searchMarket(query: String): Boolean {
        return try {
            val market = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://search?q=${Uri.encode(query)}"),
            )
            market.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(market)
            true
        } catch (_: Exception) {
            try {
                val web = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://www.coolapk.com/search?q=${Uri.encode(query)}"),
                )
                web.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(web)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}

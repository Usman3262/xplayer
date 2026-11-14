package com.player.tv

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** In-app update: Play-installed → Play Store; sideloaded (Downloader, Fire TV) → install the APK. */
object AppUpdateChannel {
  private const val NAME = "app/app_update"

  fun register(activity: Activity, engine: FlutterEngine) {
    MethodChannel(engine.dartExecutor.binaryMessenger, NAME).setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "installerPackage" -> result.success(installer(activity))
          "updatesDir" -> result.success(File(activity.cacheDir, "updates").apply { mkdirs() }.absolutePath)
          "hasPackage" -> result.success(hasPackage(activity, call.argument<String>("id") ?: ""))
          "canInstall" -> result.success(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
              activity.packageManager.canRequestPackageInstalls(),
          )
          "openInstallSettings" -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              start(activity, Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
            }
            result.success(true)
          }
          "installApk" -> {
            val file = File(call.argument<String>("path") ?: "")
            if (!file.exists()) { result.success(false); return@setMethodCallHandler }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.appupdate", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
              setDataAndType(uri, "application/vnd.android.package-archive")
              addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            result.success(start(activity, intent))
          }
          "openStore" -> {
            val id = activity.packageName
            // Name Google Play, not whichever store answers market:// links.
            val ok = start(activity, Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id"))
                .setPackage("com.android.vending")) ||
              start(activity, Intent(Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$id")))
            result.success(ok)
          }
          else -> result.notImplemented()
        }
      } catch (e: Exception) {
        result.error("app_update", e.message, null)
      }
    }
  }

  private fun start(activity: Activity, intent: Intent): Boolean = try {
    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
  } catch (_: ActivityNotFoundException) { false }

  private fun hasPackage(activity: Activity, id: String): Boolean = try {
    activity.packageManager.getPackageInfo(id, 0); true
  } catch (_: PackageManager.NameNotFoundException) { false }

  @Suppress("DEPRECATION")
  private fun installer(activity: Activity): String? = try {
    val pm = activity.packageManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      pm.getInstallSourceInfo(activity.packageName).let { it.installingPackageName ?: it.initiatingPackageName }
    } else {
      pm.getInstallerPackageName(activity.packageName)
    }
  } catch (_: Exception) { null }
}

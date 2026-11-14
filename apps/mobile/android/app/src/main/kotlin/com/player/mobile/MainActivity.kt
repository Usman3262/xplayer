package com.player.mobile

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.util.Rational
import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature

class MainActivity : FlutterActivity() {
  private val secureChannel = "app/screen_secure"
  private val bindingChannel = "app/device_binding"
  private val deviceChannel = "app/device"
  private val bindingAlias = "app.device.binding"
  private val popStoragePrefs = "app_pop_key"
  private val popStorageKey = "storage"
  private val pipChannelName = "app/pip"
  private var pipChannel: MethodChannel? = null
  /// Set by the player while a video plays (client 17 Oct #8: leaving the
  /// app during playback continues in a small window).
  private var autoPip = false
  private var pipAspect = Rational(16, 9)

  private fun pipParams(): PictureInPictureParams {
    val b = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      b.setAutoEnterEnabled(autoPip)
      b.setSeamlessResizeEnabled(true)
    }
    return b.build()
  }

  override fun onUserLeaveHint() {
    super.onUserLeaveHint()
    // Android 8-11: no auto-enter flag, enter on Home / app switch.
    if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      try { enterPictureInPictureMode(pipParams()) } catch (_: Exception) {}
    }
  }

  override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
    super.onPictureInPictureModeChanged(inPip, newConfig)
    pipChannel?.invokeMethod("onPipChanged", inPip)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    AppUpdateChannel.register(this, flutterEngine)
    TokenVault.register(flutterEngine.dartExecutor.binaryMessenger)

    pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName).also {
      it.setMethodCallHandler { call, result ->
        when (call.method) {
          "setAutoPip" -> {
            autoPip = call.argument<Boolean>("enabled") ?: false
            val w = call.argument<Number>("width")?.toInt() ?: 16
            val h = call.argument<Number>("height")?.toInt() ?: 9
            // Android allows 1:2.39 .. 2.39:1.
            val r = (w.toDouble() / h.coerceAtLeast(1)).coerceIn(0.42, 2.38)
            pipAspect = Rational((r * 1000).toInt(), 1000)
            try { setPictureInPictureParams(pipParams()) } catch (_: Exception) {}
            result.success(packageManager.hasSystemFeature("android.software.picture_in_picture"))
          }
          else -> result.notImplemented()
        }
      }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "setSecure" -> {
            val enabled = call.argument<Boolean>("enabled") ?: false
            runOnUiThread {
              if (enabled && isEmulator()) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                Log.i("ScreenSecure", "FLAG_SECURE ignored on emulator")
              } else if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
              } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
              }
            }
            result.success(null)
          }
          // C4: keep screen on during playback (TV screensaver / phone lock).
          "setKeepScreenOn" -> {
            val enabled = call.argument<Boolean>("enabled") ?: false
            runOnUiThread {
              if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              }
            }
            result.success(null)
          }
          "isRecording" -> result.success(false)
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bindingChannel)
      .setMethodCallHandler { call, result ->
        try {
          when (call.method) {
            "hasKey" -> {
              ensureKeyPair()
              result.success(true)
            }
            "getPopKeyStorage" -> {
              ensureKeyPair()
              result.success(readPopKeyStorage())
            }
            "getPublicKeySpkiBase64" -> {
              ensureKeyPair()
              result.success(publicKeySpkiBase64())
            }
            "getSigningCertSha256" -> result.success(signingCertSha256())
            "installerPackage" -> result.success(installerPackage())
            "playIntegrityToken" -> {
              // Google Play Integrity (security point 18), classic request with the
              // server challenge as nonce. Only asked for Play installs (Dart side).
              // Any failure (no Play services, Fire TV, quota, network) -> null.
              val nonce = call.argument<String>("nonce")
              val project = cloudProjectNumber()
              if (nonce.isNullOrEmpty() || project == null) {
                result.success(null)
                return@setMethodCallHandler
              }
              try {
                IntegrityManagerFactory.create(applicationContext)
                  .requestIntegrityToken(
                    IntegrityTokenRequest.builder()
                      .setNonce(nonce)
                      .setCloudProjectNumber(project)
                      .build(),
                  )
                  .addOnSuccessListener { r -> result.success(r.token()) }
                  .addOnFailureListener { e ->
                    Log.w("AppAttest", "playIntegrityToken failed: ${e.javaClass.simpleName}")
                    result.success(null)
                  }
              } catch (e: Throwable) {
                Log.w("AppAttest", "playIntegrityToken failed: ${e.javaClass.simpleName}")
                result.success(null)
              }
            }
            "attestKeyChain" -> {
              // Android Key Attestation (security point 18). Separate alias,
              // never the device-binding key. Off the main thread: StrongBox
              // key generation can take a second. Any failure -> null.
              val challenge = call.argument<String>("challenge")
              Thread {
                val chain = try {
                  attestKeyChain(challenge)
                } catch (e: Throwable) {
                  Log.w("AppAttest", "attestKeyChain failed: ${e.javaClass.simpleName}")
                  null
                }
                runOnUiThread { result.success(chain) }
              }.start()
            }
            "signRawNonce" -> {
              ensureKeyPair()
              val nonce = call.argument<ByteArray>("nonce")
              if (nonce == null || nonce.isEmpty()) {
                result.error("bad_args", "nonce required", null)
                return@setMethodCallHandler
              }
              // DER bytes — Dart converts to base64url no padding.
              result.success(signRawNonce(nonce))
            }
            else -> result.notImplemented()
          }
        } catch (e: Exception) {
          result.error("binding_error", e.message, null)
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          // System notification page for this app: the way out when the
          // permission prompt was missed or could not be pressed.
          // Background playback (client 23 Oct #7): foreground media service.
          "playbackServiceStart" -> {
            try {
              PlaybackService.start(this, call.argument<String>("title"))
              result.success(true)
            } catch (e: Exception) {
              result.success(false)
            }
          }
          "playbackServiceStop" -> {
            try { PlaybackService.stop(this) } catch (_: Exception) {}
            result.success(true)
          }
          "openNotificationSettings" -> {
            try {
              val i = android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
              startActivity(i)
              result.success(true)
            } catch (e: Exception) {
              result.success(false)
            }
          }
          "getDecoderDiagnostics" -> {
            val width = call.argument<Number>("width")?.toInt() ?: 0
            val height = call.argument<Number>("height")?.toInt() ?: 0
            val fps = call.argument<Number>("fps")?.toDouble() ?: 30.0
            Thread {
              try {
                val data = decoderDiagnostics(width, height, fps)
                runOnUiThread { result.success(data) }
              } catch (_: Exception) {
                runOnUiThread { result.error("decoder_diagnostics", "Unavailable", null) }
              }
            }.start()
          }
          "getStorage" -> {
            try {
              val st = android.os.StatFs(filesDir.path)
              result.success(mapOf("free" to st.availableBytes, "total" to st.totalBytes))
            } catch (e: Exception) {
              result.error("storage_error", e.message, null)
            }
          }
          "getCapabilities", "getDeviceInfo" -> {
            // Off the main thread (client 18 Oct #10, ANR): listing every
            // codec takes seconds on some TV chips and froze the app.
            Thread {
              try {
                val data = deviceCapabilities()
                runOnUiThread { result.success(data) }
              } catch (e: Exception) {
                runOnUiThread { result.error("device_error", e.message, null) }
              }
            }.start()
          }
          "getNetworkDiagnostics" -> {
            // Off the main thread (client 18 Oct #10, ANR): listing every
            // codec takes seconds on some TV chips and froze the app.
            Thread {
              try {
                val data = networkDiagnostics()
                runOnUiThread { result.success(data) }
              } catch (e: Exception) {
                runOnUiThread { result.error("network_error", e.message, null) }
              }
            }.start()
          }
          else -> result.notImplemented()
        }
      }
  }

  // Advertised support only: this does not instantiate a decoder or prove
  // that the exact stream's profile/configuration will decode successfully.
  private fun decoderDiagnostics(width: Int, height: Int, fps: Double): List<Map<String, Any?>> {
    return MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
      .filter { !it.isEncoder && it.supportedTypes.any { mime -> mime.equals("video/hevc", true) } }
      .map { info ->
        try {
          val caps = info.getCapabilitiesForType("video/hevc")
          val video = caps.videoCapabilities
          mapOf<String, Any?>(
            "name" to info.name,
            "hardware" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.isHardwareAccelerated else null,
            "software" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.isSoftwareOnly else null,
            "widthRange" to video.supportedWidths.toString(),
            "heightRange" to video.supportedHeights.toString(),
            "bitrateRange" to video.bitrateRange.toString(),
            "requestedSize" to "${width}x${height}",
            "sizeRateAdvertised" to if (width > 0 && height > 0 && fps > 0 && fps.isFinite())
              video.areSizeAndRateSupported(width, height, fps) else null,
            "profileLevels" to caps.profileLevels.map { pl -> mapOf("profile" to pl.profile, "level" to pl.level) }
          )
        } catch (_: Exception) {
          mapOf<String, Any?>("name" to info.name, "capabilities" to "unavailable")
        }
      }
  }

  private fun networkDiagnostics(): Map<String, Any?> {
    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val active = cm.activeNetwork
    val caps = active?.let { cm.getNetworkCapabilities(it) }
    val link = active?.let { cm.getLinkProperties(it) }

    var vpnActive = false
    val transports = mutableListOf<String>()
    if (caps != null) {
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
        vpnActive = true
        transports.add("vpn")
      }
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("wifi")
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("cellular")
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("ethernet")
    }

    val validated =
      caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    val captive =
      caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true
    val metered =
      caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true

    val dns = link?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList()

    val localeCountry = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      resources.configuration.locales[0]?.country ?: "?"
    } else {
      @Suppress("DEPRECATION")
      resources.configuration.locale.country
    }

    return mapOf(
      "vpnActive" to vpnActive,
      "transports" to transports,
      "validated" to validated,
      "captivePortal" to captive,
      "metered" to metered,
      "dnsServers" to dns,
      "timezone" to java.util.TimeZone.getDefault().id,
      "localeCountry" to localeCountry,
    )
  }

  private fun deviceCapabilities(): Map<String, Any?> {
    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val mem = ActivityManager.MemoryInfo()
    am.getMemoryInfo(mem)
    val totalRamMb = (mem.totalMem / (1024L * 1024L)).toInt()
    val metrics = resources.displayMetrics
    val refresh = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      display?.refreshRate?.toDouble() ?: 60.0
    } else {
      @Suppress("DEPRECATION")
      windowManager.defaultDisplay.refreshRate.toDouble()
    }
    val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      Build.SOC_MODEL
    } else {
      Build.HARDWARE
    }
    return mapOf(
      "model" to Build.MODEL,
      "brand" to Build.BRAND,
      "hardware" to Build.HARDWARE,
      "socModel" to soc,
      "sdkInt" to Build.VERSION.SDK_INT,
      "release" to Build.VERSION.RELEASE,
      "abis" to Build.SUPPORTED_ABIS.toList(),
      "totalRamMb" to totalRamMb,
      "isLowRamDevice" to am.isLowRamDevice,
      "screenWidthPx" to metrics.widthPixels,
      "screenHeightPx" to metrics.heightPixels,
      "density" to metrics.density.toDouble(),
      "refreshRate" to refresh,
      "hdr" to false,
      "codecs" to hwCodecCaps(),
    )
  }

  private fun hwCodecCaps(): Map<String, Map<String, Any>> {
    val wanted = listOf(
      "video/hevc",
      "video/avc",
      "video/x-vnd.on2.vp9",
      "video/av01",
    )
    val out = mutableMapOf<String, Map<String, Any>>()
    val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
    for (info in list.codecInfos) {
      if (info.isEncoder) continue
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        if (!info.isHardwareAccelerated) continue
      } else if (isSoftwareCodecName(info.name)) {
        // Pre-Q has no isHardwareAccelerated; skip known software decoders.
        continue
      }
      for (type in info.supportedTypes) {
        val mime = type.lowercase()
        if (!wanted.contains(mime)) continue
        try {
          val caps = info.getCapabilitiesForType(type).videoCapabilities ?: continue
          val w = caps.supportedWidths?.upper ?: 0
          val h = caps.supportedHeights?.upper ?: 0
          val fps = try {
            caps.getSupportedFrameRatesFor(w, h)?.upper ?: 30.0
          } catch (_: Exception) {
            30.0
          }
          // Width and height upper bounds are independent; measure the
          // standard sizes directly instead of trusting the corner size.
          val uhdFps = maxFpsAt(caps, 3840, 2160)
          val fhdFps = maxFpsAt(caps, 1920, 1080)
          val prev = out[mime]
          val better = prev == null ||
            uhdFps > (prev["uhdFps"] as Double) ||
            (uhdFps == (prev["uhdFps"] as Double) &&
              (w * h) > ((prev["width"] as Int) * (prev["height"] as Int)))
          if (better) {
            out[mime] = mapOf(
              "mime" to mime,
              "width" to w,
              "height" to h,
              "fps" to fps,
              "uhdFps" to uhdFps,
              "fhdFps" to fhdFps,
            )
          }
        } catch (_: Exception) {
          // skip broken codec entries
        }
      }
    }
    return out
  }

  private fun maxFpsAt(caps: MediaCodecInfo.VideoCapabilities, width: Int, height: Int): Double {
    return try {
      if (caps.isSizeSupported(width, height)) {
        caps.getSupportedFrameRatesFor(width, height)?.upper ?: 0.0
      } else {
        0.0
      }
    } catch (_: Exception) {
      0.0
    }
  }

  private fun isSoftwareCodecName(name: String): Boolean {
    val n = name.lowercase()
    return n.startsWith("omx.google.") || n.startsWith("c2.android.") ||
      n.contains(".sw.") || n.endsWith(".sw")
  }

  private fun isEmulator(): Boolean {
    val fingerprint = Build.FINGERPRINT.lowercase()
    val model = Build.MODEL.lowercase()
    val product = Build.PRODUCT.lowercase()
    val hardware = Build.HARDWARE.lowercase()
    val manufacturer = Build.MANUFACTURER.lowercase()
    return fingerprint.contains("generic")
      || fingerprint.contains("unknown")
      || model.contains("google_sdk")
      || model.contains("emulator")
      || model.contains("android sdk built for")
      || manufacturer.contains("genymotion")
      || product.contains("sdk")
      || product.contains("emulator")
      || hardware.contains("goldfish")
      || hardware.contains("ranchu")
      || (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
  }

  /** SHA-256 of the APK signing certificate (runtime integrity report, client 3.6). */
  private fun signingCertSha256(): String {
    val pm = packageManager
    val sig: android.content.pm.Signature? = if (Build.VERSION.SDK_INT >= 28) {
      pm.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES)
        .signingInfo?.apkContentsSigners?.firstOrNull()
    } else {
      @Suppress("DEPRECATION")
      pm.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNATURES)
        .signatures?.firstOrNull()
    }
    if (sig == null) return ""
    val d = java.security.MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
    return d.joinToString("") { "%02x".format(it) }
  }

  private fun ensureKeyPair() {
    val ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(null)
    if (ks.containsAlias(bindingAlias)) {
      if (readPopKeyStorage() == "none") {
        persistPopKeyStorage(detectPopKeyStorage(ks))
      }
      return
    }

    // StrongBox → TEE (default Keystore) → record what we got.
    var storage = "software"
    try {
      generateKeyPair(strongBox = true)
      storage = "strongbox"
    } catch (_: Exception) {
      generateKeyPair(strongBox = false)
      storage = detectPopKeyStorage(ks)
    }
    persistPopKeyStorage(storage)
  }

  private fun generateKeyPair(strongBox: Boolean) {
    val kpg = KeyPairGenerator.getInstance(
      KeyProperties.KEY_ALGORITHM_EC,
      "AndroidKeyStore",
    )
    val builder = KeyGenParameterSpec.Builder(
      bindingAlias,
      KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
    )
      .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
      .setDigests(KeyProperties.DIGEST_SHA256)
      .setUserAuthenticationRequired(false)
    if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      builder.setIsStrongBoxBacked(true)
    }
    kpg.initialize(builder.build())
    kpg.generateKeyPair()
  }

  private fun detectPopKeyStorage(ks: KeyStore): String {
    return try {
      ks.load(null)
      val entry = ks.getEntry(bindingAlias, null) as? KeyStore.PrivateKeyEntry
        ?: return "software"
      val factory = KeyFactory.getInstance(
        entry.privateKey.algorithm,
        "AndroidKeyStore",
      )
      val info = factory.getKeySpec(entry.privateKey, KeyInfo::class.java) as KeyInfo
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        when (info.securityLevel) {
          KeyProperties.SECURITY_LEVEL_STRONGBOX -> return "strongbox"
          KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> return "tee"
          else -> {}
        }
      }
      if (info.isInsideSecureHardware) "tee" else "software"
    } catch (_: Exception) {
      "software"
    }
  }

  private fun readPopKeyStorage(): String {
    return getSharedPreferences(popStoragePrefs, MODE_PRIVATE)
      .getString(popStorageKey, "none") ?: "none"
  }

  private fun persistPopKeyStorage(value: String) {
    getSharedPreferences(popStoragePrefs, MODE_PRIVATE)
      .edit()
      .putString(popStorageKey, value)
      .apply()
  }

  private fun publicKeySpkiBase64(): String {
    val ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(null)
    val entry = ks.getCertificate(bindingAlias)?.publicKey
      ?: throw IllegalStateException("missing public key")
    return Base64.encodeToString(entry.encoded, Base64.NO_WRAP)
  }

  /** DER signature bytes for Dart to base64url-encode. */
  private fun signRawNonce(nonce: ByteArray): ByteArray {
    val ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(null)
    val entry = ks.getEntry(bindingAlias, null) as KeyStore.PrivateKeyEntry
    val sig = Signature.getInstance("SHA256withECDSA")
    sig.initSign(entry.privateKey)
    sig.update(nonce)
    return sig.sign()
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
  }

  // --- Android Key Attestation (alias separate from app.device.binding) ---
  private val attestationAlias = "app.attestation"

  /** Fresh EC P-256 key with the server challenge; returns the cert chain
   *  (leaf first, standard Base64 DER) or null on API < 24 / any error. */
  /** Package that installed this app ("com.android.vending" = Google Play), or null. */
  private fun installerPackage(): String? = try {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      packageManager.getInstallSourceInfo(packageName).installingPackageName
    } else {
      @Suppress("DEPRECATION")
      packageManager.getInstallerPackageName(packageName)
    }
  } catch (e: Throwable) {
    null
  }

  /** Google Cloud project number (gcm_defaultSenderId string resource), or null when not set. */
  private fun cloudProjectNumber(): Long? = try {
    val id = resources.getIdentifier("gcm_defaultSenderId", "string", packageName)
    if (id == 0) null else getString(id).trim().toLongOrNull()
  } catch (e: Throwable) {
    null
  }

  private fun attestKeyChain(challenge: String?): List<String>? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
    if (challenge.isNullOrEmpty()) return null
    val challengeBytes = Base64.decode(challenge, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    if (challengeBytes.isEmpty()) return null
    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    fun generate(strongBox: Boolean) {
      try { ks.deleteEntry(attestationAlias) } catch (_: Exception) {}
      val builder = KeyGenParameterSpec.Builder(attestationAlias, KeyProperties.PURPOSE_SIGN)
        .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
        .setDigests(KeyProperties.DIGEST_SHA256)
        .setAttestationChallenge(challengeBytes)
      if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        builder.setIsStrongBoxBacked(true)
      }
      val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
      kpg.initialize(builder.build())
      kpg.generateKeyPair()
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      try {
        generate(true)
      } catch (_: Throwable) {
        generate(false)
      }
    } else {
      generate(false)
    }
    val chain = ks.getCertificateChain(attestationAlias) ?: return null
    if (chain.isEmpty()) return null
    return chain.map { Base64.encodeToString(it.encoded, Base64.NO_WRAP) }
  }
}

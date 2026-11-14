package com.player.mobile

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Seals login tokens with an AES-256-GCM key that lives in the Android
 * Keystore and cannot be exported (client security point 3). The sealed
 * bytes are stored by Dart in SharedPreferences; a copy of that file (backup,
 * root, adb) is useless without this device's key.
 *
 * Errors go back to Dart, which keeps the previous plain storage so a device
 * with a broken Keystore (seen with flutter_secure_storage, code 7) can still
 * sign in.
 */
object TokenVault {
  private const val CHANNEL = "app/token_vault"
  private const val ALIAS = "app.token.vault.v1"
  private const val IV_LEN = 12

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      try {
        val data = call.argument<ByteArray>("data")
        if (data == null) {
          result.error("bad_args", "data required", null)
          return@setMethodCallHandler
        }
        when (call.method) {
          "seal" -> result.success(seal(data))
          "open" -> result.success(open(data))
          else -> result.notImplemented()
        }
      } catch (e: Exception) {
        result.error("vault_error", e.javaClass.simpleName + ": " + (e.message ?: ""), null)
      }
    }
  }

  private fun key(): SecretKey {
    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
    val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    gen.init(
      KeyGenParameterSpec.Builder(
        ALIAS,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
      )
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build(),
    )
    return gen.generateKey()
  }

  private fun seal(plain: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key())
    val iv = cipher.iv
    return iv + cipher.doFinal(plain)
  }

  private fun open(sealed: ByteArray): ByteArray {
    require(sealed.size > IV_LEN + 16) { "sealed data too short" }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(
      Cipher.DECRYPT_MODE,
      key(),
      GCMParameterSpec(128, sealed.copyOfRange(0, IV_LEN)),
    )
    return cipher.doFinal(sealed.copyOfRange(IV_LEN, sealed.size))
  }
}

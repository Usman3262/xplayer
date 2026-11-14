import AVFoundation
import CryptoKit
import DeviceCheck
import Flutter
import Security
import UIKit

/// Seals login tokens with an AES-256-GCM key kept in the Keychain,
/// this-device-only (client security point 3). Dart stores the sealed bytes;
/// they cannot be opened from a backup or another device.
enum TokenVault {
  private static let service = "app.token.vault"
  private static let account = "v1"

  enum VaultError: Error { case keychain(OSStatus), seal }

  private static func key() throws -> SymmetricKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    if status == errSecSuccess, let data = out as? Data {
      return SymmetricKey(data: data)
    }
    guard status == errSecItemNotFound else { throw VaultError.keychain(status) }
    let key = SymmetricKey(size: .bits256)
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: key.withUnsafeBytes { Data($0) },
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let added = SecItemAdd(add as CFDictionary, nil)
    guard added == errSecSuccess else { throw VaultError.keychain(added) }
    return key
  }

  static func seal(_ plain: Data) throws -> Data {
    guard let combined = try AES.GCM.seal(plain, using: key()).combined else {
      throw VaultError.seal
    }
    return combined
  }

  static func open(_ sealed: Data) throws -> Data {
    try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key())
  }

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app/token_vault", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let data = (args["data"] as? FlutterStandardTypedData)?.data else {
        result(FlutterError(code: "bad_args", message: "data required", details: nil))
        return
      }
      do {
        switch call.method {
        case "seal": result(FlutterStandardTypedData(bytes: try seal(data)))
        case "open": result(FlutterStandardTypedData(bytes: try open(data)))
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "vault_error", message: "\(error)", details: nil))
      }
    }
  }
}

/// Device proof-of-possession key (client security area 5 / APK 3.4):
/// P-256 in the Secure Enclave, so the private key never leaves this phone.
/// Same channel and methods as Android (`DeviceBindingKey` in Dart): the
/// public key is sent as SPKI Base64; challenges are signed ECDSA-SHA256 DER.
/// Without a Secure Enclave (simulator) a software key, this-device-only.
enum DeviceBinding {
  private static let service = "app.device.binding"
  private static let account = "v1"

  enum BindingError: Error { case keychain(OSStatus) }

  private enum Key {
    case enclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    var publicKey: P256.Signing.PublicKey {
      switch self {
      case .enclave(let k): return k.publicKey
      case .software(let k): return k.publicKey
      }
    }

    func sign(_ data: Data) throws -> Data {
      switch self {
      case .enclave(let k): return try k.signature(for: data).derRepresentation
      case .software(let k): return try k.signature(for: data).derRepresentation
      }
    }
  }

  private static func stored() throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw BindingError.keychain(status) }
    return out as? Data
  }

  private static func store(_ data: Data) throws {
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else { throw BindingError.keychain(status) }
  }

  // First byte marks the kind: 1 = Secure Enclave blob, 2 = software key.
  private static func key() throws -> Key {
    if let blob = try stored(), let kind = blob.first {
      let body = blob.dropFirst()
      if kind == 1 { return .enclave(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: body)) }
      return .software(try P256.Signing.PrivateKey(rawRepresentation: body))
    }
    if SecureEnclave.isAvailable {
      let k = try SecureEnclave.P256.Signing.PrivateKey()
      try store(Data([1]) + k.dataRepresentation)
      return .enclave(k)
    }
    let k = P256.Signing.PrivateKey()
    try store(Data([2]) + k.rawRepresentation)
    return .software(k)
  }

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app/device_binding", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "getPublicKeySpkiBase64":
          result(try key().publicKey.derRepresentation.base64EncodedString())
        case "signRawNonce":
          guard let args = call.arguments as? [String: Any],
                let nonce = (args["nonce"] as? FlutterStandardTypedData)?.data, !nonce.isEmpty else {
            result(FlutterError(code: "bad_args", message: "nonce required", details: nil))
            return
          }
          result(try key().sign(nonce).base64EncodedString())
        case "isHardwareBacked":
          if case .enclave = try key() { result(true) } else { result(false) }
        case "hasKey":
          _ = try key()
          result(true)
        case "appAttest":
          // Apple App Attest (client security point 18). Invisible: nil on any
          // failure or unsupported device; the app behaves as before.
          guard let args = call.arguments as? [String: Any],
                let ch = args["challenge"] as? String,
                let raw = AppAttest.base64UrlDecode(ch), !raw.isEmpty else {
            result(nil)
            return
          }
          AppAttest.attest(challenge: raw) { out in
            DispatchQueue.main.async { result(out) }
          }
        case "getPopKeyStorage":
          // Reported to the backend before PoP enforcement (Usman, 20 Oct).
          if case .enclave = try key() { result("keychain-secure-enclave") } else { result("keychain") }
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "binding_error", message: "\(error)", details: nil))
      }
    }
  }
}

/// Apple App Attest: a fresh hardware key per attestation, attested by Apple
/// over SHA-256(challenge). The server checks the Apple chain, app id, nonce
/// and counter (backend Docs/FOR_APP_DEVICE_ATTESTATION_2026-11-02.md).
/// Needs the App Attest capability on the App ID (Apple developer portal).
enum AppAttest {
  static func base64UrlDecode(_ s: String) -> Data? {
    var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b.count % 4 != 0 { b += "=" }
    return Data(base64Encoded: b)
  }

  static func attest(challenge: Data, done: @escaping ([String: String]?) -> Void) {
    let service = DCAppAttestService.shared
    guard service.isSupported else { done(nil); return }
    service.generateKey { keyId, error in
      guard let keyId = keyId, error == nil else { done(nil); return }
      let clientDataHash = Data(SHA256.hash(data: challenge))
      service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
        guard let attestation = attestation, error == nil else { done(nil); return }
        done(["keyId": keyId, "attestation": attestation.base64EncodedString()])
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var secureEnabled = true
  private var captureObserver: NSObjectProtocol?
  private var methodChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background / lock-screen audio (client retest: background playback).
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try session.setActive(true)
    } catch {
      // Non-fatal: Flutter player still runs; OS may pause without session.
    }
    // A call, Siri or another app's sound deactivates the session; without
    // re-activating it the sound stayed off in the background (client 21 Oct
    // mobile #6). Also re-assert it each time the app leaves the screen.
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { note in
      guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
      try? AVAudioSession.sharedInstance().setActive(true)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { _ in
      try? AVAudioSession.sharedInstance().setActive(true)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppScreenSecure") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app/screen_secure",
      binaryMessenger: registrar.messenger()
    )
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "gone", message: nil, details: nil))
        return
      }
      switch call.method {
      case "setSecure":
        let args = call.arguments as? [String: Any]
        let enabled = (args?["enabled"] as? Bool) ?? true
        self.secureEnabled = enabled
        if enabled {
          self.startCaptureWatch()
        } else {
          self.stopCaptureWatch()
          self.hideCaptureOverlay()
        }
        result(nil)
      case "setKeepScreenOn":
        // C4: no auto-lock while the player holds the screen.
        let args = call.arguments as? [String: Any]
        let enabled = (args?["enabled"] as? Bool) ?? false
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(nil)
      case "isRecording":
        result(UIScreen.main.isCaptured)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    startCaptureWatch()

    TokenVault.register(registrar.messenger())
    DeviceBinding.register(registrar.messenger())

    // Free / total storage for the Downloads screen.
    let device = FlutterMethodChannel(
      name: "app/device",
      binaryMessenger: registrar.messenger()
    )
    device.setMethodCallHandler { call, result in
      guard call.method == "getStorage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        result(["free": free, "total": total])
      } catch {
        result(FlutterError(code: "storage_error", message: nil, details: nil))
      }
    }
  }

  private func startCaptureWatch() {
    stopCaptureWatch()
    captureObserver = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateCaptureOverlay()
    }
    updateCaptureOverlay()
  }

  private func stopCaptureWatch() {
    if let obs = captureObserver {
      NotificationCenter.default.removeObserver(obs)
      captureObserver = nil
    }
  }

  private func updateCaptureOverlay() {
    guard secureEnabled else {
      hideCaptureOverlay()
      return
    }
    if UIScreen.main.isCaptured {
      showCaptureOverlay()
      methodChannel?.invokeMethod("onRecordingChanged", arguments: true)
    } else {
      hideCaptureOverlay()
      methodChannel?.invokeMethod("onRecordingChanged", arguments: false)
    }
  }

  /// The app runs in a UIScene (SceneDelegate), so `self.window` is nil and
  /// the black cover was never added (17 Oct: recording still worked with
  /// Screen protection on). Use the scene's window.
  private var hostWindow: UIWindow? {
    if let w = self.window { return w }
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }

  private func showCaptureOverlay() {
    guard let window = hostWindow else { return }
    if let existing = window.viewWithTag(991177) {
      window.bringSubviewToFront(existing)
      return
    }
    let overlay = UIView(frame: window.bounds)
    overlay.tag = 991177
    overlay.backgroundColor = .black
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.isUserInteractionEnabled = true
    window.addSubview(overlay)
  }

  private func hideCaptureOverlay() {
    hostWindow?.viewWithTag(991177)?.removeFromSuperview()
  }
}

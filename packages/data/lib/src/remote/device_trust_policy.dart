/// Client rules for priority-device trust (Google / WhatsApp style).
///
/// Server must still enforce the same rules — UI alone is not enough.
class DeviceTrustPolicy {
  DeviceTrustPolicy._();

  /// This install is the account priority phone.
  static bool actorIsPriority({
    required bool anyDeviceIsPriority,
    required bool thisDeviceIsPriority,
  }) {
    if (!anyDeviceIsPriority) return false;
    return thisDeviceIsPriority;
  }

  /// Normal revoke must never clear the priority phone.
  /// Transfer priority first, or use lost-phone recovery / CP.
  static bool canRevokeDevice({required bool targetIsPriority}) =>
      !targetIsPriority;

  /// Revoke-all from a secondary would wipe primary — block when a priority exists.
  static bool canRevokeAll({
    required bool actorIsPriority,
    required bool accountHasPriority,
  }) {
    if (!accountHasPriority) return true;
    return actorIsPriority;
  }
}

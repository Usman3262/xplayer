"""Live checks for 8.3 user_devices. Run from apps/admin:
  PYTHONIOENCODING=utf-8 python supabase/tests/live_devices_check.py"""
import sys
sys.path.insert(0, "supabase/tests")
from _live import req, temp_admin, check, cleanup

try:
    a_id, A = temp_admin(None, mfa=False)
    b_id, B = temp_admin(None, mfa=False)
    s_id, S = temp_admin("support_agent")
    dev = {"id": "abc123def4567890", "platform": "android", "model": "OnePlus LE2115", "app": "6.0.36", "panel": "xtream",
           "password": "never-stored"}
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": dev})
    check("anon cannot check in", s in (401, 403, 404), (s, d))
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": dev, "p_signed_in": True}, tok=A)
    check("A checks in", s == 200 and d == {"revoked": False}, (s, d))
    s, d = req("GET", "/rest/v1/user_devices?select=*", tok=A)
    check("A sees the device, no extra fields stored", s == 200 and len(d) == 1 and d[0]["model"] == "OnePlus LE2115"
          and "password" not in str(d), (s, d))
    s, d = req("GET", "/rest/v1/user_devices?select=device_id", tok=B)
    check("B sees nothing of A", s == 200 and d == [], (s, d))
    s, d = req("POST", "/rest/v1/user_devices", {"user_id": b_id, "device_id": "zzzzzzzz11"}, tok=B)
    check("direct writes refused (RPC only)", s in (401, 403), (s, d))
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": {"id": "BAD ID!"}}, tok=A)
    check("bad device id refused", s == 400, (s, d))

    s, d = req("POST", "/rest/v1/rpc/device_revoke_mine", {"p_device": dev["id"]}, tok=A)
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": dev}, tok=A)
    check("removed device is told to sign out", s == 200 and d == {"revoked": True}, (s, d))
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": dev, "p_signed_in": True}, tok=A)
    check("signing in again on it brings it back", d == {"revoked": False}, (s, d))

    s, d = req("POST", "/rest/v1/rpc/admin_list_devices", {"p_search": dev["id"]}, tok=B)
    check("plain user cannot list all devices", s in (401, 403), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_devices", {"p_search": dev["id"]}, tok=S)
    check("support agent lists the device with the email", s == 200 and len(d) == 1 and d[0]["email"], (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_device_counts", {}, tok=S)
    check("support agent sees counts", s == 200 and d[0]["total"] >= 1, (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_revoke_device", {"p_user": a_id, "p_device": dev["id"], "p_reason": "test"}, tok=S)
    check("support agent revokes it", s in (200, 204), (s, d))
    s, d = req("POST", "/rest/v1/rpc/device_checkin", {"p_device": dev}, tok=A)
    check("…and the device is told to sign out", d == {"revoked": True}, (s, d))
    s, d = req("GET", f"/rest/v1/audit_logs?select=action&action=eq.device.revoke&entity_id=eq.{a_id}:{dev['id']}",
               key=__import__('_live').SEC)
    check("revoke written to the audit log", s == 200 and len(d) == 1, (s, d))
finally:
    cleanup()

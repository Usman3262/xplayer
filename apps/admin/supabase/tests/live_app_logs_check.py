# Live checks for remote app logs (migration 023). Run from apps/admin:
#   PYTHONIOENCODING=utf-8 python supabase/tests/live_app_logs_check.py
import secrets, sys
sys.path.insert(0, "supabase/tests")
from _live import req, temp_admin, check, cleanup, SEC

dev = "zzlive" + secrets.token_hex(6)
base = {"p_device": dev, "p_session": "s1abc", "p_platform": "android", "p_version": "1.0.0", "p_model": "Test"}
try:
    ev = [{"t": "2026-11-15T12:00:00Z", "tag": "PANEL", "msg": "GET http://h/player_api.php → HTTP 200"},
          {"t": "bad-date", "tag": "ACCOUNT", "msg": "sign in ok"},
          {"tag": "lower", "msg": "bad tag"}, {"tag": "ERR", "msg": ""}, "not an object"]
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=ev))
    check("anon app upload accepted; bad rows skipped (2 of 5 stored)", s == 200 and d == 2, (s, d))
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_device="BAD ID!", p_events=ev))
    check("bad device id → nothing stored", d == 0, (s, d))
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "x"}] * 101))
    check("more than 100 lines per batch → ignored", d == 0, (s, d))
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "y" * 5000}]))
    s2, rows = req("GET", f"/rest/v1/app_logs?select=message&device_id=eq.{dev}&message=like.yyy*", key=SEC)
    check("long message cut to 2000 chars", isinstance(rows, list) and rows and len(rows[0]["message"]) == 2000, rows and len(rows[0]["message"]))

    s, d = req("GET", f"/rest/v1/app_logs?select=id&device_id=eq.{dev}")
    check("anon cannot read logs", s in (401, 403) or d == [], (s, d))
    _, app_user = temp_admin(None)
    s, d = req("GET", f"/rest/v1/app_logs?select=id&device_id=eq.{dev}", tok=app_user)
    check("plain app user cannot read logs", d == [] or s >= 400, (s, d))
    s, d = req("POST", "/rest/v1/app_logs", {"device_id": dev, "session_id": "x1234", "platform": "android",
                                             "tag": "PANEL", "message": "direct", "logged_at": "2026-11-15T00:00:00Z"}, tok=app_user)
    check("direct insert refused (only the function writes)", s >= 400, (s, d))
    _, sup = temp_admin("support_agent")
    s, d = req("GET", f"/rest/v1/app_logs?select=tag,message,platform,app_version,device_model&device_id=eq.{dev}&order=id", tok=sup)
    check("support agent reads the device's lines", s == 200 and isinstance(d, list) and len(d) == 3 and d[0]["tag"] == "PANEL", (s, d))

    # Admin switch off → uploads ignored; then back on.
    req("PATCH", "/rest/v1/app_settings?key=eq.diagnostics.remote_logs", {"value": False}, key=SEC)
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "while off"}]))
    check("admin switch off → nothing stored", d == 0, (s, d))
    req("PATCH", "/rest/v1/app_settings?key=eq.diagnostics.remote_logs", {"value": True}, key=SEC)
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "back on"}]))
    check("switch back on → stored again", d == 1, (s, d))

    # Flood guard: 600 lines per device per 10 min.
    for _ in range(6):
        req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "flood"}] * 100))
    s, d = req("POST", "/rest/v1/rpc/log_app_events", dict(base, p_events=[{"tag": "PANEL", "msg": "over"}]))
    check("flood guard stops a runaway device", d == 0, (s, d))
finally:
    req("DELETE", f"/rest/v1/app_logs?device_id=eq.{dev}", key=SEC)
    req("PATCH", "/rest/v1/app_settings?key=eq.diagnostics.remote_logs", {"value": True}, key=SEC)
    cleanup()

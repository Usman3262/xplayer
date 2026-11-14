# Live: app versions, maintenance windows, player/cache settings (draft only — never published here).
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin
from datetime import datetime, timedelta, timezone
try:
    _, CM = temp_admin("content_manager")
    _, MM = temp_admin("marketing_manager")
    status = lambda: req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    st0 = status()
    s, orig = req("GET", "/rest/v1/app_versions?select=*&platform=eq.tv", tok=CM); orig = orig[0]
    s, d = req("PATCH", "/rest/v1/app_versions?platform=eq.tv", {"min_version": "1.2.0", "recommended_version": "1.3.0", "update_url": "https://example.com/tv"}, tok=CM, headers={"Prefer": "return=representation"})
    check("content manager sets TV versions", s == 200 and d and d[0]["min_version"] == "1.2.0", (s, d))
    check("draft dirty with 'versions'", "versions" in status()["changed"])
    s, d = req("PATCH", "/rest/v1/app_versions?platform=eq.tv", {"update_url": "http://insecure.example"}, tok=CM)
    check("non-https update link rejected by DB", s >= 400, (s, d))
    s, d = req("PATCH", "/rest/v1/app_versions?platform=eq.tv", {"min_version": "9.9.9"}, tok=MM, headers={"Prefer": "return=representation"})
    check("read-only role can't edit versions", s == 200 and d == [], (s, d))
    req("PATCH", "/rest/v1/app_versions?platform=eq.tv", {k: orig[k] for k in ["min_version", "recommended_version", "latest_version", "update_url", "release_notes"]}, tok=CM)

    now = datetime.now(timezone.utc)
    s, d = req("POST", "/rest/v1/maintenance_windows", {"title": "zz test", "message": "test", "starts_at": (now + timedelta(days=30)).isoformat(), "ends_at": (now + timedelta(days=30, hours=1)).isoformat()}, tok=CM, headers={"Prefer": "return=representation"})
    check("create future maintenance window", s == 201 and d, (s, d))
    mid = d[0]["id"]
    check("draft dirty with 'maintenance'", "maintenance" in status()["changed"])
    s, d = req("POST", "/rest/v1/maintenance_windows", {"title": "bad", "message": "x", "starts_at": now.isoformat(), "ends_at": (now - timedelta(hours=1)).isoformat()}, tok=CM)
    check("end before start rejected by DB", s >= 400, (s, d))
    req("DELETE", f"/rest/v1/maintenance_windows?id=eq.{mid}", tok=CM)

    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.player.retry_count", {"value": 99}, tok=CM)
    check("retry count above max (10) rejected", s >= 400, (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.player.live_format", {"value": "mp4"}, tok=CM)
    check("live format must be ts/m3u8", s >= 400, (s, d))
    if not st0["dirty"]:
        check("everything restored → clean", not status()["dirty"], status())
finally:
    cleanup()

# Live checks: login policy settings + "Choose your panel" types (migrations 002/019).
# Run from apps/admin:  PYTHONIOENCODING=utf-8 python supabase/tests/live_access_check.py
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin

P = "/rest/v1/onboarding_panel_types"
try:
    _, CM = temp_admin("content_manager")
    _, MM = temp_admin("marketing_manager")
    status = lambda: req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    st0 = status()
    s, orig = req("GET", f"{P}?select=key,is_enabled,sort_order,label,fields&order=sort_order", tok=CM)
    check("content manager reads panel types", s == 200 and len(orig) >= 3, (s, orig))

    s, d = req("PATCH", f"{P}?key=eq.m3u", {"is_enabled": False}, tok=CM, headers={"Prefer": "return=representation"})
    check("disable one panel type", s == 200 and d and d[0]["is_enabled"] is False, (s, d))
    check("draft dirty with 'onboarding'", "onboarding" in status()["changed"])
    s, d = req("PATCH", f"{P}?key=neq.zzz", {"is_enabled": False}, tok=CM)
    check("disabling ALL panel types is refused by the DB", s >= 400 and "at least one" in str(d), (s, d))
    s, d = req("PATCH", f"{P}?key=eq.m3u", {"is_enabled": True}, tok=MM, headers={"Prefer": "return=representation"})
    check("read-only role cannot edit panel types", s == 200 and d == [], (s, d))

    x = next(o for o in orig if o["key"] == "xtream")
    fields = [dict(f, label="Server address") if f["key"] == "host" else f for f in x["fields"]]
    s, d = req("PATCH", f"{P}?key=eq.xtream", {"label": "Xtream (test)", "fields": fields}, tok=CM, headers={"Prefer": "return=representation"})
    check("edit label + field label", s == 200 and d[0]["label"] == "Xtream (test)" and d[0]["fields"][0]["label"] == "Server address", (s, d))
    s, d = req("PATCH", f"{P}?key=eq.xtream", {"fields": {"not": "an array"}}, tok=CM)
    check("fields must be a list (DB check)", s >= 400, (s, d))

    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.auth.mode", {"value": "required"}, tok=CM, headers={"Prefer": "return=representation"})
    check("auth.mode = required accepted", s == 200 and d and d[0]["value"] == "required", (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.providers.max_connections", {"value": 99}, tok=CM)
    check("max panels above 50 rejected", s >= 400, (s, d))

    # restore everything
    for o in orig:
        req("PATCH", f"{P}?key=eq.{o['key']}", {"is_enabled": o["is_enabled"], "sort_order": o["sort_order"], "label": o["label"], "fields": o["fields"]}, tok=CM)
    req("PATCH", "/rest/v1/app_settings?key=eq.auth.mode", {"value": "optional"}, tok=CM)
    if not st0["dirty"]:
        check("all restored → clean", not status()["dirty"], status())
finally:
    cleanup()

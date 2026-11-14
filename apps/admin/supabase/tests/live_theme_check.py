# Live checks: theme + branding edits (migration 018), draft detection, permissions.
# Run from apps/admin:  PYTHONIOENCODING=utf-8 python supabase/tests/live_theme_check.py
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin

try:
    _, CM = temp_admin("content_manager")
    _, MM = temp_admin("marketing_manager")  # customization.read only
    status = lambda: req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    st0 = status()

    s, th = req("GET", "/rest/v1/app_themes?select=id,tokens&is_active=eq.true", tok=CM)
    check("content manager reads active theme", s == 200 and len(th) == 1 and th[0]["tokens"].get("primary"), th)
    orig = th[0]["tokens"]
    changed = {**orig, "primary": "#123456"}
    s, d = req("PATCH", "/rest/v1/app_themes?is_active=eq.true", {"tokens": changed}, tok=CM, headers={"Prefer": "return=representation"})
    check("content manager saves theme", s == 200 and d and d[0]["tokens"]["primary"] == "#123456", (s, d))
    st1 = status()
    check("draft dirty with 'theme'", "theme" in st1["changed"], st1)
    s, d = req("PATCH", "/rest/v1/app_themes?is_active=eq.true", {"tokens": orig}, tok=MM, headers={"Prefer": "return=representation"})
    check("marketing manager (read-only) cannot save theme", s == 200 and d == [], (s, d))
    req("PATCH", "/rest/v1/app_themes?is_active=eq.true", {"tokens": orig}, tok=CM)
    if not st0["dirty"]:
        check("theme restored → clean", not status()["dirty"], status())

    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.branding.logo_url", {"value": "javascript:alert(1)"}, tok=CM)
    check("non-http logo URL rejected by DB", s >= 400, (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.branding.display_name", {"value": 42}, tok=CM)
    check("wrong type rejected by DB", s >= 400, (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.branding.display_name", {"value": "Test Name"}, tok=CM, headers={"Prefer": "return=representation"})
    check("valid display name saved", s == 200 and d and d[0]["value"] == "Test Name", (s, d))
    st2 = status()
    check("draft dirty with 'settings'", "settings" in st2["changed"], st2)
    req("PATCH", "/rest/v1/app_settings?key=eq.branding.display_name", {"value": ""}, tok=CM)
    if not st0["dirty"]:
        check("branding restored → clean", not status()["dirty"], status())
finally:
    cleanup()

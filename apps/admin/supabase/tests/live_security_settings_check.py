# Live: security settings need settings.write (migration 020).
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin
K = "/rest/v1/app_settings?key=eq.admin.require_two_factor"
try:
    _, CM = temp_admin("content_manager")
    _, AD = temp_admin("admin")
    s, cur = req("GET", K + "&select=value", tok=AD); orig = cur[0]["value"]
    s, d = req("PATCH", K, {"value": not orig}, tok=CM, headers={"Prefer": "return=representation"})
    check("content manager CANNOT change require_two_factor", s == 200 and d == [], (s, d))
    s, d = req("PATCH", K, {"value": orig}, tok=AD, headers={"Prefer": "return=representation"})
    check("admin (settings.write) can write it", s == 200 and len(d) == 1, (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.search.min_chars", {"value": 2}, tok=CM, headers={"Prefer": "return=representation"})
    check("content manager can still edit normal settings", s == 200 and len(d) == 1, (s, d))
    s, d = req("PATCH", "/rest/v1/app_settings?key=eq.search.min_chars", {"category": "security"}, tok=AD)
    check("category can't be changed via API", s >= 400, (s, d))
    s, d = req("POST", "/rest/v1/app_settings", {"key": "x.y", "category": "app", "value_type": "bool", "value": True, "default_value": True, "description": "x"}, tok=CM)
    check("content manager can't add new settings", s >= 400, (s, d))
finally:
    cleanup()

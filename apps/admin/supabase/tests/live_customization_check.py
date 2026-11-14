# Live checks: publish status/draft detection, publish guard, flag edits, image storage.
# Run from apps/admin:  PYTHONIOENCODING=utf-8 python supabase/tests/live_customization_check.py
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import PUB, SEC, U, check, cleanup, req, temp_admin

try:
    _, CM = temp_admin("content_manager")
    _, AN = temp_admin("analyst")
    _, PLAIN = temp_admin(None)
    status = lambda t: req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=t)

    s, st0 = status(CM)
    check("status readable by content manager", s == 200 and "version" in st0, (s, st0))
    s, d = status(AN)
    check("analyst cannot read config status", s in (401, 403), (s, d))
    if st0.get("dirty"):
        print("NOTE: draft already had unpublished changes:", st0["changed"])

    # Toggle a harmless flag → draft dirty with 'flags'.
    s, cur = req("GET", "/rest/v1/feature_flags?select=enabled&key=eq.speed_test", tok=CM)
    orig = cur[0]["enabled"]
    s, d = req("PATCH", "/rest/v1/feature_flags?key=eq.speed_test", {"enabled": not orig}, tok=CM, headers={"Prefer": "return=representation"})
    check("content manager can toggle a flag", s == 200 and d and d[0]["enabled"] == (not orig), (s, d))
    s, st1 = status(CM)
    check("draft is dirty with 'flags'", st1["dirty"] and "flags" in st1["changed"], st1)
    s, d = req("PATCH", "/rest/v1/feature_flags?key=eq.speed_test", {"enabled": orig}, tok=AN, headers={"Prefer": "return=representation"})
    check("analyst cannot edit flags (0 rows)", s == 200 and d == [], (s, d))
    s, d = req("PATCH", "/rest/v1/feature_flags?key=eq.speed_test", {"platforms": ["web"]}, tok=CM)
    check("invalid platform rejected by DB", s >= 400, (s, d))

    # Toggle back → draft equals live again (if it was clean before).
    req("PATCH", "/rest/v1/feature_flags?key=eq.speed_test", {"enabled": orig}, tok=CM)
    s, st2 = status(CM)
    if not st0.get("dirty"):
        check("toggling back → not dirty", not st2["dirty"], st2)
        s, d = req("POST", "/rest/v1/rpc/publish_app_config", {"p_notes": "x"}, tok=CM)
        check("publish with no changes is refused", s >= 400 and "Nothing to publish" in str(d), (s, d))

    # Storage: upload as content manager, refused for analyst/plain/anon, type limits.
    png = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000" "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")
    import secrets as _s
    path = f"zz-test/live-{_s.token_hex(4)}.png"
    s, d = req("POST", f"/storage/v1/object/app-assets/{path}", tok=CM, raw=png, content_type="image/png")
    check("content manager can upload PNG", s == 200, (s, d))
    import urllib.request
    pub = f"{U}/storage/v1/object/public/app-assets/{path}"
    with urllib.request.urlopen(pub) as x:
        check("uploaded image is publicly readable", x.status == 200 and x.read()[:4] == png[:4])
    s, d = req("POST", f"/storage/v1/object/app-assets/zz-test/a.png", tok=AN, raw=png, content_type="image/png")
    check("analyst cannot upload", s >= 400, (s, d))
    s, d = req("POST", f"/storage/v1/object/app-assets/zz-test/b.png", tok=PLAIN, raw=png, content_type="image/png")
    check("plain user cannot upload", s >= 400, (s, d))
    s, d = req("POST", f"/storage/v1/object/app-assets/zz-test/c.png", raw=png, content_type="image/png")
    check("anonymous cannot upload", s >= 400, (s, d))
    s, d = req("POST", f"/storage/v1/object/app-assets/zz-test/x.svg", tok=CM, raw=b"<svg xmlns='http://www.w3.org/2000/svg'/>", content_type="image/svg+xml")
    check("SVG rejected by bucket", s >= 400, (s, d))
    s, d = req("POST", f"/storage/v1/object/app-assets/zz-test/big.png", tok=CM, raw=png + b"0" * (2 * 1024 * 1024 + 10), content_type="image/png")
    check("file over 2 MB rejected", s >= 400, (s, d))
    s, d = req("DELETE", "/storage/v1/object/app-assets", {"prefixes": [path]}, tok=CM)
    check("content manager can delete", s == 200 and isinstance(d, list) and len(d) == 1, (s, d))
finally:
    cleanup()

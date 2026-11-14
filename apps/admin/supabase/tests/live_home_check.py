# Live: home builder edits + END-TO-END targeting in get_app_config.
# Publishes temporary sections nobody can see (country ZZ / signed-in only / next year),
# checks what apps receive, then deletes them and publishes again (config back to before).
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin
from datetime import datetime, timedelta, timezone
H = "/rest/v1/home_sections"
created = []
try:
    _, CM = temp_admin("content_manager")
    _, MM = temp_admin("marketing_manager")
    st0 = req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    if st0["dirty"]:
        print("SKIP end-to-end part: there are unpublished changes already:", st0["changed"])
    yr = datetime.now(timezone.utc) + timedelta(days=365)
    base = {"section_type": "custom", "content_kind": "mixed", "layout": "rail", "item_limit": 10, "sort_order": 9990}
    rows = [
        {**base, "title": "zz test country", "source": "random", "countries": ["ZZ"]},
        {**base, "title": "zz test login", "source": "random", "requires_login": True},
        {**base, "title": "zz test later", "source": "random", "starts_at": yr.isoformat()},
        {**base, "title": "zz test picks", "source": "manual", "platforms": ["tv"], "countries": ["ZZ"]},
    ]
    for r in rows:
        s, d = req("POST", H, r, tok=CM, headers={"Prefer": "return=representation"})
        check(f"create section '{r['title']}'", s == 201, (s, d))
        created.append(d[0]["id"])
    s, d = req("POST", "/rest/v1/home_section_items", [
        {"section_id": created[3], "sort_order": 10, "item_kind": "movie", "tmdb_id": 157336, "panel_item_id": None, "panel_key": None},
        {"section_id": created[3], "sort_order": 20, "item_kind": "movie", "tmdb_id": None, "panel_item_id": "501", "panel_key": "neo"},
    ], tok=CM)
    check("add manual picks", s == 201, (s, d))
    s, d = req("POST", "/rest/v1/home_section_items", {"section_id": created[3], "item_kind": "movie"}, tok=CM)
    check("pick without any reference rejected", s >= 400, (s, d))
    s, d = req("PATCH", f"{H}?id=eq.{created[0]}", {"title": "x"}, tok=MM, headers={"Prefer": "return=representation"})
    check("read-only role can't edit sections", s == 200 and d == [], (s, d))
    # Targeting rule used by get_app_config (no publish needed).
    vis = lambda x, plat="android", country=None, signed=False, now=None: req("POST", "/rest/v1/rpc/config_item_visible", {
        "x": x, "p_platform": plat, "p_country": country, "p_signed_in": signed,
        "p_now": (now or datetime.now(timezone.utc)).isoformat()})[1]
    check("rule: all platforms/countries visible", vis({"platforms": None, "countries": None}) is True)
    check("rule: TV-only hidden on phone", vis({"platforms": ["tv"]}) is False and vis({"platforms": ["tv"]}, plat="tv") is True)
    check("rule: country ZZ hidden for others, shown for ZZ", vis({"countries": ["ZZ"]}, country="PK") is False and vis({"countries": ["ZZ"]}, country="ZZ") is True)
    check("rule: country-targeted hidden when country unknown", vis({"countries": ["ZZ"]}) is False)
    check("rule: signed-in only", vis({"login": True}) is False and vis({"login": True}, signed=True) is True)
    check("rule: schedule window", vis({"from": yr.isoformat()}) is False and vis({"to": (yr - timedelta(days=400)).isoformat()}) is False and vis({"from": (yr - timedelta(days=400)).isoformat(), "to": yr.isoformat()}) is True)
    st1 = req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    check("draft dirty with 'home'", "home" in st1["changed"], st1)

    if not st0["dirty"]:
        s, v = req("POST", "/rest/v1/rpc/publish_app_config", {"p_notes": "TEST sections (hidden) — removed next"}, tok=CM)
        check("publish test sections", s == 200, (s, v))
        titles = lambda body: [x["title"] for x in req("POST", "/rest/v1/rpc/get_app_config", body)[1]["home"]["sections"]]
        anon = titles({"p_platform": "android"})
        zz = titles({"p_platform": "android", "p_country": "zz"})
        check("guest: country-ZZ section hidden", "zz test country" not in anon, anon)
        check("guest from ZZ: country section shown", "zz test country" in zz, zz)
        check("guest: signed-in-only section hidden", "zz test login" not in anon, anon)
        check("scheduled-next-year section hidden", "zz test later" not in anon and "zz test later" not in zz)
        picks = [x for x in req("POST", "/rest/v1/rpc/get_app_config", {"p_platform": "tv", "p_country": "zz"})[1]["home"]["sections"] if x["title"] == "zz test picks"]
        check("manual picks reach the app (tmdb + panel id)", picks and [i.get("tmdb") for i in picks[0]["items"]] == [157336, None] and picks[0]["items"][1]["panel_id"] == "501", picks)
        s, d = req("POST", "/rest/v1/rpc/get_app_config", {"p_platform": "android", "p_known_version": v})
        check("known version with targeted sections → full reply (not cached 'unchanged')", d.get("unchanged") is False, d.get("unchanged"))
finally:
    for sid in created:
        req("DELETE", f"{H}?id=eq.{sid}", tok=CM)
    st = req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    if st["dirty"] and not st0["dirty"]:
        s, v = req("POST", "/rest/v1/rpc/publish_app_config", {"p_notes": "Removed TEST sections"}, tok=CM)
        print("republished clean config:", s, v)
    st = req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    check("cleanup: no unpublished changes left", not st["dirty"] or st0["dirty"], st)
    cleanup()

# Live checks for Phase 3 completion: banners, Top 10 lists, flag overrides (end-to-end),
# rollback, sports writes. Publishes only hidden/identical content and only when the
# draft is clean; everything created is removed again.
# Run from apps/admin:  PYTHONIOENCODING=utf-8 python supabase/tests/live_phase3_check.py
import os, sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(__file__))
from _live import check, cleanup, req, temp_admin

made = {"banners": [], "top10_lists": [], "home_sections": [], "feature_overrides": [], "sports_matches": [], "sports_teams": [], "sports_competitions": []}
try:
    uid_cm, CM = temp_admin("content_manager")
    _, MM = temp_admin("marketing_manager")
    uid_plain, PLAIN = temp_admin(None)
    status = lambda: req("POST", "/rest/v1/rpc/admin_config_status", {}, tok=CM)[1]
    st0 = status()
    clean = not st0["dirty"]
    if not clean:
        print("NOTE: unpublished drafts exist → skipping publish-based checks:", st0["changed"])
    ins = lambda table, row: req("POST", f"/rest/v1/{table}", row, tok=CM, headers={"Prefer": "return=representation"})

    # ── Banners ──
    s, d = ins("banners", {"title": "zz banner", "image_url": "https://example.com/a.png", "action_type": "content", "item_kind": "movie", "tmdb_id": 157336, "countries": ["ZZ"]})
    check("banner with TMDB content ref", s == 201, (s, d)); made["banners"].append(d[0]["id"])
    s, d = ins("banners", {"title": "x", "image_url": "https://example.com/a.png", "action_type": "url", "action_value": "http://insecure"})
    check("banner http link rejected", s >= 400, (s, d))
    s, d = ins("banners", {"title": "x", "image_url": "https://example.com/a.png", "action_type": "content"})
    check("content banner without ref rejected", s >= 400, (s, d))
    s, d = req("POST", "/rest/v1/banners", {"title": "x", "image_url": "https://example.com/a.png"}, tok=MM)
    check("read-only role can't add banners", s >= 400, (s, d))

    # ── Top 10 list + manual ranking + section link ──
    s, d = ins("top10_lists", {"title": "zz top", "content_kind": "movie", "source": "manual", "country": "ZZ"})
    check("create Top 10 list", s == 201, (s, d)); lid = d[0]["id"]; made["top10_lists"].append(lid)
    s, d = req("POST", "/rest/v1/top10_items", [{"list_id": lid, "rank": r, "item_kind": "movie", "tmdb_id": 1000 + r} for r in (1, 2, 3)], tok=CM)
    check("add 3 ranked titles", s == 201, (s, d))
    s, d = req("POST", "/rest/v1/top10_items", {"list_id": lid, "rank": 11, "item_kind": "movie", "tmdb_id": 1}, tok=CM)
    check("rank 11 rejected", s >= 400, (s, d))
    s, d = ins("home_sections", {"title": "zz top section", "section_type": "top10", "source": "manual", "layout": "ranked", "top10_list_id": lid, "countries": ["ZZ"], "sort_order": 9990})
    check("Top 10 section linked to list", s == 201, (s, d)); made["home_sections"].append(d[0]["id"])

    # ── Flag override: user + country ──
    s, d = ins("feature_overrides", {"flag_key": "clips", "target_type": "user", "target_value": uid_plain, "enabled": True})
    check("user override (clips on for one user)", s == 201, (s, d)); made["feature_overrides"].append(d[0]["id"])
    s, d = ins("feature_overrides", {"flag_key": "clips", "target_type": "country", "target_value": "ZZ", "enabled": True})
    check("country override (clips on for ZZ)", s == 201, (s, d)); made["feature_overrides"].append(d[0]["id"])
    s, d = req("POST", "/rest/v1/rpc/admin_flag_overrides", {}, tok=CM)
    check("overrides list shows user email", s == 200 and any(o["target_type"] == "user" and "@" in o["target_label"] for o in d), d)
    s, d = req("POST", "/rest/v1/rpc/admin_user_id_by_email", {"p_email": "nobody-zz@example.invalid"}, tok=CM)
    check("unknown email → null", s == 200 and d is None, (s, d))

    if clean:
        s, v = req("POST", "/rest/v1/rpc/publish_app_config", {"p_notes": "TEST hidden items — removed next"}, tok=CM)
        check("publish (hidden test items only)", s == 200, (s, v))
        flags = lambda tok=None, country=None: req("POST", "/rest/v1/rpc/get_app_config", {"p_platform": "android", **({"p_country": country} if country else {})}, tok=tok)[1]["flags"]["clips"]
        check("guest: clips stays off (global off)", flags() is False)
        check("signed-in user with override: clips ON", flags(tok=PLAIN) is True)
        check("other signed-in user: clips off", flags(tok=MM) is False)
        cfg = req("POST", "/rest/v1/rpc/get_app_config", {"p_platform": "android", "p_country": "zz"})[1]
        top = [t for t in cfg["home"]["top10"] if t["title"] == "zz top"]
        check("ZZ guest gets the Top 10 list with 3 ranked titles", top and [i["tmdb"] for i in top[0]["items"]] == [1001, 1002, 1003], top)
        check("ZZ guest gets the country banner", any(b["title"] == "zz banner" for b in cfg["home"]["banners"]))
        check("other countries don't get the banner", not any(b["title"] == "zz banner" for b in req("POST", "/rest/v1/rpc/get_app_config", {"p_platform": "android", "p_country": "pk"})[1]["home"]["banners"]))

    # ── Sports (no publish needed) ──
    s, d = ins("sports_competitions", {"name": "zz league"}); made["sports_competitions"].append(d[0]["id"])
    s, h = ins("sports_teams", {"name": "zz home fc"}); made["sports_teams"].append(h[0]["id"])
    s, a = ins("sports_teams", {"name": "zz away fc"}); made["sports_teams"].append(a[0]["id"])
    s, m = ins("sports_matches", {"competition_id": d[0]["id"], "home_team_id": h[0]["id"], "away_team_id": a[0]["id"], "kickoff_at": datetime.now(timezone.utc).isoformat(), "status": "live", "minute": 50, "home_score": 2, "away_score": 1})
    check("content manager creates a match (sports.write)", s == 201, (s, m)); mid = m[0]["id"]; made["sports_matches"].append(mid)
    req("POST", "/rest/v1/sports_lineups", {"match_id": mid, "team_id": h[0]["id"], "formation": "4-3-3", "players": [{"name": "A", "number": 9, "starter": True}]}, tok=CM)
    req("POST", "/rest/v1/sports_events", {"match_id": mid, "team_id": h[0]["id"], "minute": 45, "extra_minute": 2, "type": "goal", "player": "A"}, tok=CM)
    req("POST", "/rest/v1/sports_match_channels", {"match_id": mid, "channel_match": "zz sports 1"}, tok=CM)
    s, page = req("POST", "/rest/v1/rpc/get_match", {"p_id": mid})
    check("apps see the match page (lineup, 45+2 goal, channel)", page and page["lineups"] and page["events"][0]["extra"] == 2 and page["channels"][0]["match"] == "zz sports 1", page)
    s, d = req("POST", "/rest/v1/sports_matches", {"home_team_id": h[0]["id"], "away_team_id": a[0]["id"], "kickoff_at": datetime.now(timezone.utc).isoformat()}, tok=MM)
    check("marketing manager can't write sports", s >= 400, (s, d))
finally:
    for t in ["sports_matches", "sports_teams", "sports_competitions", "feature_overrides", "home_sections", "banners", "top10_lists"]:
        for rid in made[t]:
            req("DELETE", f"/rest/v1/{t}?id=eq.{rid}", tok=CM)
    if clean:
        st = status()
        if st["dirty"]:
            s, v = req("POST", "/rest/v1/rpc/publish_app_config", {"p_notes": "Removed TEST items"}, tok=CM)
            print("republished clean config:", s, v)
        # Rollback test: republish the CURRENT live version (identical content).
        live = status()["version"]
        s, v = req("POST", "/rest/v1/rpc/admin_republish_version", {"p_version": live, "p_notes": "TEST rollback (same content)"}, tok=CM)
        check("rollback RPC republishes a version", s == 200 and v == live + 1, (s, v))
        st = status()
        check("after rollback: no unpublished changes, restored_from set", not st["dirty"] and st["restored_from"] == live, st)
        s, d = req("POST", "/rest/v1/rpc/admin_republish_version", {"p_version": 99999}, tok=CM)
        check("rollback to unknown version refused", s >= 400, (s, d))
        s, d = req("POST", "/rest/v1/rpc/admin_republish_version", {"p_version": live}, tok=MM)
        check("read-only role can't roll back", s in (401, 403), (s, d))
    cleanup()
